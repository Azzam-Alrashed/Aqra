package com.azzamalrashed.aqra.recitation

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.util.zip.ZipInputStream
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The speech model a revision is followed with: Tarteel's Whisper fine-tuned on Quran recitation
 * (`tarteel-ai/whisper-base-ar-quran`, Apache-2.0), exported to ONNX and quantized to 8 bits, run by ONNX Runtime.
 *
 * It's downloaded once, as a zip of the model folder, kept on the device outside its backups, and run on the device:
 * the student's voice never leaves it and isn't kept.
 */
class RecitationModel(private val context: Context, private val scope: CoroutineScope) {
    sealed interface State {
        data object Absent : State
        data class Downloading(val fraction: Double) : State
        data object Installing : State
        data object Ready : State
        data object Failed : State
    }

    var state: State by mutableStateOf(if (isInstalled) State.Ready else State.Absent)
        private set

    /** filesDir's no-backup folder: recitation/<version>. */
    val folder: File get() = File(context.noBackupFilesDir, "recitation/$VERSION")

    val isInstalled: Boolean
        get() = listOf("encoder.onnx", "decoder.onnx", "mel_filters.bin", "tokens.txt").all { File(folder, it).exists() }

    /** Downloads and installs the model, reporting progress in [state]. */
    fun download() {
        if (isInstalled) {
            state = State.Ready
            return
        }
        if (state is State.Downloading || state == State.Installing) return
        state = State.Downloading(0.0)
        scope.launch {
            state = try {
                withContext(Dispatchers.IO) { fetchAndInstall() }
                State.Ready
            } catch (error: Exception) {
                android.util.Log.w("Aqra", "Recitation model download failed: $error", error)
                State.Failed
            }
        }
    }

    private suspend fun fetchAndInstall() {
        val parent = folder.parentFile!!.apply { mkdirs() }
        val archive = File(context.cacheDir, "$VERSION.zip")
        val connection = URL(DOWNLOAD_URL).openConnection() as HttpURLConnection
        try {
            if (connection.responseCode != 200) error("HTTP ${connection.responseCode}")
            val total = connection.contentLengthLong.takeIf { it > 0 } ?: DOWNLOAD_SIZE
            connection.inputStream.use { input ->
                archive.outputStream().use { output ->
                    val buffer = ByteArray(1 shl 16)
                    var written = 0L
                    var reported = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        written += count
                        if (written - reported > 512 * 1024) {
                            reported = written
                            val fraction = min(written.toDouble() / total, 1.0)
                            withContext(Dispatchers.Main) { state = State.Downloading(fraction) }
                        }
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
        withContext(Dispatchers.Main) { state = State.Installing }
        // Unpacked into a fresh folder, then put in place, so a half-installed model is never used.
        val staging = File(parent, "$VERSION.partial").apply { deleteRecursively(); mkdirs() }
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
            if (!staging.renameTo(folder)) error("Couldn't put the model in place")
        } finally {
            archive.delete()
            staging.deleteRecursively()
        }
    }

    companion object {
        /** The version installed; a new one goes in a folder of its own. */
        const val VERSION = "whisper-base-ar-quran-1-onnx"
        /** Where the archive is downloaded from: the project's storage bucket (backend/README.md). */
        const val DOWNLOAD_URL =
            "https://firebasestorage.googleapis.com/v0/b/aqra-quran.firebasestorage.app/o/models%2Frecitation%2F$VERSION.zip?alt=media"
        /** The archive's size, shown before downloading it. */
        const val DOWNLOAD_SIZE = 67_272_417L
    }
}

/**
 * Runs the model: 16 kHz mono audio in, the words it heard out, one stretch at a time. The log-mel features are
 * Whisper's own (30 s, a 400-sample Hann window every 160 samples, 80 mel bands), the decoding is greedy in Arabic
 * without timestamps, and the words come back from the model's byte-level tokens.
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
    private val filters: FloatArray = File(folder, "mel_filters.bin").readBytes().let { bytes ->
        val floats = FloatArray(bytes.size / 4)
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(floats)
        floats
    }
    private val tokens: List<String> = File(folder, "tokens.txt").readLines()

    fun transcribe(samples: FloatArray): String {
        val features = logMel(samples)
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(features), longArrayOf(1, MELS.toLong(), FRAMES.toLong())).use { input ->
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

    /** Whisper's log-mel features, [80][3000], for up to 30 s of audio (the rest is silence). */
    private fun logMel(samples: FloatArray): FloatArray {
        val length = min(samples.size, SAMPLES)
        // Centered frames: the audio padded by 200 samples at each end, the start mirrored.
        fun sample(index: Int): Float {
            val i = index - N_FFT / 2
            return when {
                i < 0 -> if (-i < length) samples[-i] else 0f
                i < length -> samples[i]
                else -> 0f
            }
        }
        // Frames past the audio are silent: their power is zero, so only the ones that reach the audio are computed.
        val heard = min(FRAMES, (length + N_FFT / 2) / HOP + 2)
        val mel = FloatArray(MELS * FRAMES) { LOG_FLOOR }
        val frame = FloatArray(N_FFT)
        val power = FloatArray(BINS)
        var top = LOG_FLOOR
        for (f in 0 until heard) {
            val start = f * HOP
            for (n in 0 until N_FFT) frame[n] = sample(start + n) * WINDOW[n]
            for (k in 0 until BINS) {
                var re = 0f
                var im = 0f
                val base = k * N_FFT
                for (n in 0 until N_FFT) {
                    re += frame[n] * COS[base + n]
                    im -= frame[n] * SIN[base + n]
                }
                power[k] = re * re + im * im
            }
            for (m in 0 until MELS) {
                var energy = 0f
                for (k in 0 until BINS) energy += power[k] * filters[k * MELS + m]
                val value = log10(max(energy, 1e-10f))
                mel[m * FRAMES + f] = value
                if (value > top) top = value
            }
        }
        val floor = top - 8f
        for (i in mel.indices) mel[i] = (max(mel[i], floor) + 4f) / 4f
        return mel
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
        const val SAMPLES = 480_000
        const val N_FFT = 400
        const val HOP = 160
        const val BINS = N_FFT / 2 + 1
        const val MELS = 80
        const val FRAMES = 3_000
        const val VOCABULARY = 51_865
        const val END_OF_TEXT = 50_257
        const val START_OF_TRANSCRIPT = 50_258L
        const val ARABIC = 50_272L
        const val TRANSCRIBE = 50_359L
        const val NO_TIMESTAMPS = 50_363L
        const val MAX_TOKENS = 200
        val LOG_FLOOR = log10(1e-10f)

        val WINDOW = FloatArray(N_FFT) { (0.5 - 0.5 * cos(2 * PI * it / N_FFT)).toFloat() }
        val COS = FloatArray(BINS * N_FFT) { cos(2 * PI * (it / N_FFT) * (it % N_FFT) / N_FFT).toFloat() }
        val SIN = FloatArray(BINS * N_FFT) { sin(2 * PI * (it / N_FFT) * (it % N_FFT) / N_FFT).toFloat() }

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
