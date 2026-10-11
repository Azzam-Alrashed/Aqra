package com.azzamalrashed.aqra.recitation

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.ByteArrayInputStream
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.security.MessageDigest
import java.util.zip.ZipInputStream
import kotlin.math.max
import kotlin.math.min
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The speech model a revision is followed with: Tarteel's Whisper fine-tuned on Quran recitation
 * (`tarteel-ai/whisper-base-ar-quran`, Apache-2.0), exported to ONNX and quantized to 8 bits, run by ONNX Runtime.
 *
 * It's downloaded once, as a zip of the model folder, kept on the device outside its backups, and run on the device:
 * the student's voice never leaves it and isn't kept. A download that stops carries on where it was; the archive is
 * checked against its checksum before it's unpacked; a model that isn't whole isn't installed.
 */
class RecitationModel(context: Context, private val scope: CoroutineScope) {
    sealed interface State {
        data object Absent : State
        data class Downloading(val fraction: Double) : State
        data object Installing : State
        data object Ready : State
        data class Failed(val reason: Failure) : State
    }

    /** Why the model isn't on the device. */
    enum class Failure {
        /** There isn't room for the archive and the unpacked model. */
        SPACE,
        /** The download didn't finish; it carries on next time. */
        DOWNLOAD,
        /** The archive didn't match its checksum, or didn't hold the model. */
        CORRUPT,
    }

    private val files = RecitationModelFiles(File(context.noBackupFilesDir, "recitation"), context.cacheDir)

    var state: State by mutableStateOf(if (files.isInstalled) State.Ready else State.Absent)
        private set

    /** filesDir's no-backup folder: recitation/<version>. */
    val folder: File get() = files.folder

    val isInstalled: Boolean get() = files.isInstalled

    init {
        // Old versions and the leftovers of an install that didn't finish go.
        scope.launch(Dispatchers.IO) { runCatching { files.cleanUp() } }
    }

    /** Downloads and installs the model, reporting progress in [state]. */
    fun download() {
        if (isInstalled) {
            state = State.Ready
            return
        }
        if (state is State.Downloading || state == State.Installing) return
        state = State.Downloading(files.fractionDownloaded())
        scope.launch {
            state = try {
                withContext(Dispatchers.IO) {
                    files.requireFreeSpace()
                    files.download(HttpFetcher(DOWNLOAD_URL)) { fraction ->
                        scope.launch(Dispatchers.Main.immediate) { if (state is State.Downloading) state = State.Downloading(fraction) }
                    }
                    withContext(Dispatchers.Main) { state = State.Installing }
                    files.install()
                }
                State.Ready
            } catch (problem: RecitationModelFiles.Problem) {
                android.util.Log.w("Aqra", "Recitation model: ${problem.message}")
                State.Failed(problem.failure)
            } catch (error: Exception) {
                android.util.Log.w("Aqra", "Recitation model download failed: $error", error)
                State.Failed(Failure.DOWNLOAD)
            }
        }
    }

    /** What the model, and anything a download left, take on the device. */
    fun usedSpace(): Long = files.usedSpace()

    /**
     * «نموذج الاستماع» in حسابي, «احذف»: the model goes from the device with anything a download left, and reciting aloud
     * downloads it again when it's next used. Not while a download or an install is under way; a listener holding the
     * model keeps its own copy in memory until it closes.
     */
    fun remove() {
        if (state is State.Downloading || state == State.Installing) return
        files.removeAll()
        state = State.Absent
    }

    companion object {
        /** The version installed; a new one goes in a folder of its own. */
        const val VERSION = "whisper-base-ar-quran-1-onnx"
        /** Where the archive is downloaded from: the project's storage bucket (backend/README.md). */
        const val DOWNLOAD_URL =
            "https://firebasestorage.googleapis.com/v0/b/aqra-quran.firebasestorage.app/o/models%2Frecitation%2F$VERSION.zip?alt=media"
        /** The archive's size, shown before downloading it. */
        const val DOWNLOAD_SIZE = 67_272_417L
        /** The archive's SHA-256 (backend/README.md): a download that doesn't match isn't installed. */
        const val CHECKSUM = "25f67e1ea6369c553db0319a0bdb02ecfed6c6ebe42c1accc20763e9cb33b3f1"
        /** What the unpacked model takes on the device (measured: 100,584 KiB), for the free-space check. */
        const val INSTALLED_SIZE = 103_000_000L
    }
}

/**
 * The model's files on the device, and the steps that put them there: a download that carries on where it stopped,
 * the archive's checksum, and an install that's either whole or not there. Plain files, so the tests can run it.
 */
class RecitationModelFiles(
    /** The folder the versions live in (`recitation/` in the no-backup files). */
    private val root: File,
    /** Where the archive is downloaded (the cache; Android may clear it, and the download then starts over). */
    private val cache: File,
    private val version: String = RecitationModel.VERSION,
    private val checksum: String = RecitationModel.CHECKSUM,
    private val downloadSize: Long = RecitationModel.DOWNLOAD_SIZE,
    private val installedSize: Long = RecitationModel.INSTALLED_SIZE,
) {
    /** Why the model couldn't be had. */
    class Problem(val failure: RecitationModel.Failure, message: String) : IOException(message)

    /** What a download gives: the response's status, its length, and its body. */
    interface Fetcher {
        /** Opens the archive from byte [from] onwards (an HTTP Range request when it isn't 0). */
        fun open(from: Long): Response
    }

    class Response(
        val status: Int,
        val contentLength: Long,
        contentRange: String?,
        val stream: InputStream,
        private val onClose: () -> Unit = {},
    ) : Closeable {
        /** The whole file's length from `Content-Range: bytes a-b/total`, when the server says. */
        val totalLength: Long? = contentRange?.substringAfter('/', "")?.trim()?.toLongOrNull()

        override fun close() {
            stream.close()
            onClose()
        }
    }

    val folder: File get() = File(root, version)

    /** The archive, as far as it's downloaded. */
    val archive: File get() = File(cache, "recitation-$version.zip")

    /** How much of the archive is downloaded already, from 0 to 1: a download carries on from there. */
    fun fractionDownloaded(): Double = min(archive.length().toDouble() / downloadSize, 1.0)

    /** Whether the model is whole: every file it runs from is there, with something in it. */
    val isInstalled: Boolean
        get() = REQUIRED.all { File(folder, it).let { file -> file.isFile && file.length() > 0 } }

    /** What the model and the archive take, in bytes. */
    fun usedSpace(): Long = root.walkTopDown().filter { it.isFile }.sumOf { it.length() } + archive.length()

    /** Everything: every version, and the archive a download left. */
    fun removeAll() {
        root.deleteRecursively()
        archive.delete()
    }

    /** Removes other versions, installs that didn't finish, and other versions' archives. */
    fun cleanUp() {
        root.listFiles()?.forEach { if (it.name != version) it.deleteRecursively() }
        cache.listFiles()?.forEach {
            if (it.name.startsWith("recitation-") && it.name.endsWith(".zip") && it.name != archive.name) it.delete()
        }
    }

    /** Stops before a download that wouldn't fit: the rest of the archive, the unpacked model, and room to spare. */
    fun requireFreeSpace() {
        root.mkdirs()
        cache.mkdirs()
        val needed = max(0, downloadSize - archive.length()) + installedSize + MARGIN
        val free = min(root.usableSpace, cache.usableSpace)
        if (free < needed) throw Problem(RecitationModel.Failure.SPACE, "$free bytes free, $needed needed")
    }

    /**
     * Downloads the archive, carrying on from what's already here with a Range request; [progress] is given the
     * fraction downloaded as it goes. An archive that stops short is kept for next time.
     */
    fun download(fetch: Fetcher, progress: (Double) -> Unit = {}) {
        cache.mkdirs()
        var have = archive.length()
        // Whole, as far as its size says; the checksum has the last word.
        if (have >= downloadSize) return
        fetch.open(have).use { response ->
            val append: Boolean
            val total: Long
            when (response.status) {
                206 -> {
                    append = true
                    total = response.totalLength ?: downloadSize
                }
                200 -> {
                    // The server gave the whole file (it doesn't do ranges, or nothing was here): start over.
                    append = false
                    have = 0
                    total = response.contentLength.takeIf { it > 0 } ?: downloadSize
                }
                // Nothing past what's here: the archive is as long as the server's. Its checksum decides.
                416 -> if (have > 0) return else throw Problem(RecitationModel.Failure.DOWNLOAD, "HTTP 416")
                else -> throw Problem(RecitationModel.Failure.DOWNLOAD, "HTTP ${response.status}")
            }
            FileOutputStream(archive, append).use { output ->
                val buffer = ByteArray(1 shl 16)
                var written = have
                var reported = have
                while (true) {
                    val count = response.stream.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                    written += count
                    if (written - reported >= 512 * 1024) {
                        reported = written
                        progress(min(written.toDouble() / total, 1.0))
                    }
                }
            }
        }
    }

    /**
     * Checks the archive against its checksum and unpacks it into a fresh folder, then puts it in place, so a
     * half-installed model is never used; a model that isn't whole is removed again.
     */
    fun install() {
        if (sha256(archive) != checksum) {
            archive.delete()
            throw Problem(RecitationModel.Failure.CORRUPT, "The archive doesn't match its checksum")
        }
        root.mkdirs()
        val staging = File(root, "$version.partial").apply { deleteRecursively(); mkdirs() }
        try {
            ZipInputStream(archive.inputStream().buffered()).use { zip ->
                while (true) {
                    val entry = zip.nextEntry ?: break
                    val target = File(staging, entry.name)
                    // Only plain files in the folder itself.
                    if (entry.isDirectory || target.parentFile?.canonicalPath != staging.canonicalPath) continue
                    target.outputStream().use { zip.copyTo(it) }
                }
            }
            folder.deleteRecursively()
            if (!staging.renameTo(folder)) throw IOException("Couldn't put the model in place")
            if (!isInstalled) {
                folder.deleteRecursively()
                throw Problem(RecitationModel.Failure.CORRUPT, "The archive doesn't hold the model")
            }
        } finally {
            staging.deleteRecursively()
            archive.delete()
        }
    }

    companion object {
        private val REQUIRED = listOf("encoder.onnx", "decoder.onnx", "mel_filters.bin", "tokens.txt")
        /** Room to spare beyond the archive and the model. */
        private const val MARGIN = 50L shl 20

        /** The file's SHA-256, in lowercase hex. */
        fun sha256(file: File): String {
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buffer = ByteArray(1 shl 16)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            return digest.digest().joinToString("") { "%02x".format(it) }
        }
    }
}

/** The archive over HTTP, from a byte onwards when the download was begun before. */
class HttpFetcher(private val url: String) : RecitationModelFiles.Fetcher {
    override fun open(from: Long): RecitationModelFiles.Response {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        if (from > 0) connection.setRequestProperty("Range", "bytes=$from-")
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream ?: ByteArrayInputStream(ByteArray(0))
        return RecitationModelFiles.Response(status, connection.contentLengthLong, connection.getHeaderField("Content-Range"), stream) {
            connection.disconnect()
        }
    }
}

/**
 * Runs the model: 16 kHz mono audio in, the words it heard out, one stretch at a time. The log-mel features are
 * Whisper's own ([WhisperFeatures]), the decoding is greedy in Arabic without timestamps, and the words come back
 * from the model's byte-level tokens.
 */
class RecitationTranscriber(folder: File) : AutoCloseable {
    private val environment = OrtEnvironment.getEnvironment()
    private val options = OrtSession.SessionOptions().apply {
        setIntraOpNumThreads(max(2, min(4, Runtime.getRuntime().availableProcessors())))
        setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
    }
    private val encoder = environment.createSession(File(folder, "encoder.onnx").path, options)
    private val decoder = environment.createSession(File(folder, "decoder.onnx").path, options)
    private val pastNames = decoder.inputNames.filter { it.startsWith("past_key_values.") }
    /** The mel filter bank, [201][80] row by row. */
    private val features = WhisperFeatures(File(folder, "mel_filters.bin").readBytes().let { bytes ->
        val floats = FloatArray(bytes.size / 4)
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(floats)
        floats
    })
    private val tokens: List<String> = File(folder, "tokens.txt").readLines()

    fun transcribe(samples: FloatArray): String {
        val mel = features.logMel(samples)
        val shape = longArrayOf(1, WhisperFeatures.MELS.toLong(), WhisperFeatures.FRAMES.toLong())
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(mel), shape).use { input ->
            encoder.run(mapOf("input_features" to input)).use { encoded ->
                val hidden = encoded[0] as OnnxTensor
                return decode(hidden)
            }
        }
    }

    /** Greedy decoding from «<|startoftranscript|><|ar|><|transcribe|><|notimestamps|>», keeping the attention caches. */
    private fun decode(hidden: OnnxTensor): String {
        val out = ArrayList<Int>()
        val empty = pastNames.associateWith { OnnxTensor.createTensor(environment, FloatBuffer.allocate(0), longArrayOf(1, 8, 0, 64)) }
        var first: OrtSession.Result? = null
        var previous: OrtSession.Result? = null
        try {
            var ids = longArrayOf(START_OF_TRANSCRIPT, ARABIC, TRANSCRIBE, NO_TIMESTAMPS)
            for (step in 0 until MAX_TOKENS) {
                val past = HashMap<String, OnnxTensor>()
                for (name in pastNames) {
                    past[name] = when {
                        step == 0 -> empty.getValue(name)
                        // The cross-attention cache is the first step's; the decoder's own grows with every step.
                        ".encoder." in name -> first!!.get(name.replace("past_key_values", "present")).get() as OnnxTensor
                        else -> previous!!.get(name.replace("past_key_values", "present")).get() as OnnxTensor
                    }
                }
                val result = OnnxTensor.createTensor(environment, LongBuffer.wrap(ids), longArrayOf(1, ids.size.toLong())).use { input ->
                    OnnxTensor.createTensor(environment, booleanArrayOf(step > 0)).use { useCache ->
                        decoder.run(past + mapOf("input_ids" to input, "encoder_hidden_states" to hidden, "use_cache_branch" to useCache))
                    }
                }
                val logits = (result[0] as OnnxTensor).floatBuffer
                // The last position's logits; only text tokens or the end of the text.
                val offset = (ids.size - 1) * VOCABULARY
                var token = 0
                var best = Float.NEGATIVE_INFINITY
                for (candidate in 0..END_OF_TEXT) {
                    val value = logits.get(offset + candidate)
                    if (value > best) {
                        best = value
                        token = candidate
                    }
                }
                if (step == 0) first = result else if (previous !== first) previous?.close()
                previous = result
                if (token == END_OF_TEXT) break
                out += token
                ids = longArrayOf(token.toLong())
            }
        } finally {
            if (previous !== first) previous?.close()
            first?.close()
            empty.values.forEach { it.close() }
        }
        return detokenize(out)
    }

    /** The model's byte-level tokens back to text. */
    private fun detokenize(ids: List<Int>): String {
        val bytes = java.io.ByteArrayOutputStream()
        for (id in ids) {
            if (id >= tokens.size) continue
            for (char in tokens[id]) BYTE_OF[char]?.let { bytes.write(it) }
        }
        return bytes.toString(Charsets.UTF_8.name())
    }

    override fun close() {
        encoder.close()
        decoder.close()
        options.close()
    }

    private companion object {
        const val VOCABULARY = 51_865
        const val END_OF_TEXT = 50_257
        const val START_OF_TRANSCRIPT = 50_258L
        const val ARABIC = 50_272L
        const val TRANSCRIBE = 50_359L
        const val NO_TIMESTAMPS = 50_363L
        const val MAX_TOKENS = 200

        /** GPT-2's byte-to-character table, inverted: each printable stand-in back to its byte. */
        val BYTE_OF: Map<Char, Int> = run {
            val bytes = ((33..126) + (161..172) + (174..255)).toMutableList()
            val chars = bytes.toMutableList()
            var n = 0
            for (b in 0 until 256) if (b !in bytes) {
                bytes += b
                chars += 256 + n
                n += 1
            }
            chars.zip(bytes).associate { (c, b) -> c.toChar() to b }
        }
    }
}
