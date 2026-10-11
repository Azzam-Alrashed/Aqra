package com.azzamalrashed.aqra.recitation

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.BuildConfig
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionSession
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Listens to the revision of a page and follows it: words are revealed as they're recited, stumbles are marked with what
 * kind they were, and a long pause inside an ayah brings the next word (the prompt, تلقين).
 *
 * The microphone's audio is split into stretches at the reciter's pauses, by its loudness against the room's own noise.
 * A stretch still being recited is heard every second or so, to reveal its words as they come; once the reciter pauses,
 * it's heard whole and settled. Nothing is recorded or kept. The same rules as the iOS app's listener.
 */
class RecitationListener internal constructor(
    session: RevisionSession,
    private val store: MushafStore,
    /** Where the audio comes from: the microphone, or a recording in the tests. */
    private val audio: () -> AudioSource,
    /** The model as the listener uses it; the tests give a fake. */
    private val hearing: Hearing,
) {
    /** The listener the app uses: the microphone, and the model on the device. */
    constructor(session: RevisionSession, store: MushafStore, model: RecitationModel) :
        this(session, store, { AudioSource.create() }, ModelHearing(model))

    enum class Phase { PREPARING, LISTENING, PAUSED, FAILED_MICROPHONE, FAILED_MODEL }

    /** The model as the listener uses it: loaded, then asked what a stretch of audio says. */
    interface Hearing {
        val isLoaded: Boolean
        suspend fun load()
        suspend fun transcribe(samples: FloatArray): String
    }

    var phase by mutableStateOf(Phase.PREPARING)
        private set
    /** How loud the voice is now, from 0 to 1, for the meter. */
    var level by mutableDoubleStateOf(0.0)
        private set
    var session by mutableStateOf(session)
        private set

    private var tracker = RecitationTracker.forPage(store.page(session.page), session.ayahs, store)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var source: AudioSource? = null
    private var loop: Job? = null
    /** Loading the model before the microphone goes on; cancelled by a pause or a stop in the meantime. */
    private var starting: Job? = null

    // Splitting the audio at pauses.
    private var leftover = FloatArray(0)
    private var noiseFloor = -60f
    private var voicedRun = 0
    private var silentRun = 0
    private val preroll = Samples()
    private var stretch: Samples? = null
    /** How loud each frame of the current stretch was, in dB, to cut a long stretch at its quietest moment. */
    private val levels = Samples()
    private var lastPartial = 0
    private var partial: FloatArray? = null
    // Hearing stretches, one at a time: settled ones in order, a stretch still being recited when there's time.
    private val settling = ArrayDeque<Stretch>()
    private var busy = false
    private var generation = 0
    /** How long the model took to hear the last stretch, in milliseconds. */
    private var lastHearing = 0L
    // Prompting after a pause: when the voice was last heard, and how long the pause before this stretch was.
    private var lastVoice = System.currentTimeMillis()
    private var promptsInARow = 0
    private var pauseBefore = 0L

    /** A stretch to settle, with the pause before it, unless a prompt broke that pause. */
    private class Stretch(val samples: FloatArray, val pauseBefore: Long)

    /**
     * Loads the model and starts listening; the microphone permission is asked for before. A pause or a stop while
     * the model loads leaves the microphone off.
     */
    fun start() {
        starting?.cancel()
        phase = Phase.PREPARING
        starting = scope.launch {
            try {
                hearing.load()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                android.util.Log.w("Aqra", "Recitation model couldn't load", error)
                phase = Phase.FAILED_MODEL
                return@launch
            }
            if (isActive) beginAudio()
        }
    }

    /** The microphone wasn't allowed: says so, with the way to Settings. */
    fun microphoneRefused() {
        phase = Phase.FAILED_MICROPHONE
    }

    fun pause() {
        starting?.cancel()
        starting = null
        if (phase != Phase.LISTENING && phase != Phase.PREPARING) return
        stopAudio()
        phase = Phase.PAUSED
    }

    fun resume() {
        if (source != null || starting?.isActive == true) return
        if (hearing.isLoaded) beginAudio() else start()
    }

    /** Turns the microphone on and follows what it hears. */
    private fun beginAudio() {
        if (source != null) return
        val audio = audio()
        try {
            audio.start()
        } catch (error: Exception) {
            android.util.Log.w("Aqra", "Microphone couldn't start", error)
            phase = Phase.FAILED_MICROPHONE
            return
        }
        source = audio
        phase = Phase.LISTENING
        lastVoice = System.currentTimeMillis()
        promptsInARow = 0
        loop = scope.launch {
            while (isActive) {
                delay(100)
                tick()
            }
        }
    }

    /** Turns the microphone off; what was being recited is heard all the same. */
    private fun stopAudio() {
        source?.stop()
        source = null
        loop?.cancel()
        loop = null
        closeStretch()
        level = 0.0
    }

    /** Follows another page's revision (the next of today's wird, or the same page again). */
    fun follow(session: RevisionSession) {
        this.session = session
        tracker = RecitationTracker.forPage(store.page(session.page), session.ayahs, store)
        generation += 1
        settling.clear()
        stretch = null
        partial = null
        preroll.clear()
        levels.clear()
        leftover = FloatArray(0)
        voicedRun = 0
        silentRun = 0
        lastVoice = System.currentTimeMillis()
        promptsInARow = 0
        source?.drain()
    }

    /** Stops for good: the screen is leaving. */
    fun close() {
        pause()
        scope.cancel()
    }

    // Every tenth of a second

    private fun tick() {
        val samples = source?.drain() ?: return
        if (session.isComplete) {
            level = 0.0
            return
        }
        catchUpWithTheSession()
        val all = leftover + samples
        var start = 0
        while (all.size - start >= FRAME) {
            frame(all, start)
            start += FRAME
        }
        leftover = all.copyOfRange(start, all.size)
        promptIfStuck()
        hearNext()
    }

    /**
     * The student revealed words by hand («الآية التالية», «أظهر الصفحة»): carry on from there. Words the tracker revealed
     * itself, from a stretch still being recited, aren't counted: that stretch is settled when the reciter pauses.
     */
    private fun catchUpWithTheSession() {
        var index = tracker.reached
        while (index < tracker.words.size && !session.isVeiled(tracker.words[index].ayah, tracker.words[index].position)) index += 1
        if (index > tracker.reached) tracker.skip(index)
    }

    /** One 30 ms frame: is it voice, against the room's noise, and does a stretch begin or end? */
    private fun frame(samples: FloatArray, from: Int) {
        var sum = 0f
        for (i in from until from + FRAME) sum += samples[i] * samples[i]
        val decibels = 20 * log10(sqrt(sum / FRAME) + 1e-9f)
        // The noise floor follows the quietest moments down at once and rises back slowly, about 1 dB a second.
        noiseFloor = if (decibels < noiseFloor) max(decibels, -90f) else noiseFloor + 0.03f
        val voiced = decibels > noiseFloor + 12 && decibels > -52
        if (voiced) {
            if (voicedRun == 0 && stretch == null) pauseBefore = if (promptsInARow > 0) 0 else System.currentTimeMillis() - lastVoice
            lastVoice = System.currentTimeMillis()
        }
        level = 0.7 * level + 0.3 * ((decibels - noiseFloor) / 30.0).coerceIn(0.0, 1.0)

        val current = stretch
        if (current != null) {
            current.add(samples, from, FRAME)
            levels.add(decibels)
            silentRun = if (voiced) 0 else silentRun + 1
            if (silentRun >= 17) {
                // Half a second of quiet ends a stretch.
                closeStretch()
            } else if (current.size >= RATE * LONGEST_STRETCH) {
                // The model hears 30 s at most: a long ayah is cut at the quietest moment of its last seconds.
                splitStretch()
            } else if (hearsWhileReciting && current.size - lastPartial >= RATE * 6 / 5 && current.size >= RATE * 4 / 5) {
                lastPartial = current.size
                partial = current.toArray()
            }
        } else {
            preroll.add(samples, from, FRAME)
            preroll.keepLast(FRAME * 8)
            voicedRun = if (voiced) voicedRun + 1 else 0
            if (voicedRun >= 3) {
                stretch = Samples().apply { add(preroll.toArray(), 0, preroll.size) }
                preroll.clear()
                silentRun = 0
                lastPartial = 0
                promptsInARow = 0
            }
        }
    }

    /**
     * Whether a stretch is heard while it's still being recited, to reveal its words as they come. Where the model is
     * slow, it isn't: hearing it would hold up settling the stretch, and the prompt after a pause.
     */
    private val hearsWhileReciting: Boolean get() = lastHearing < SLOW_HEARING

    private fun closeStretch() {
        val current = stretch ?: return
        stretch = null
        partial = null
        levels.clear()
        voicedRun = 0
        settling.addLast(Stretch(current.toArray(), pauseBefore))
        pauseBefore = 0
        hearNext()
    }

    /**
     * Cuts the stretch being recited at the quietest frame of its last [SPLIT_WINDOW] seconds — a breath between
     * words, so no word is cut in two — and settles what came before it. The rest carries on as the stretch being
     * recited, so an ayah longer than the model's window is heard in two parts and followed across them.
     */
    private fun splitStretch() {
        val current = stretch ?: return
        val frames = levels.size
        var quietest = max(1, frames - SPLIT_WINDOW * RATE / FRAME)
        for (frame in quietest + 1 until frames) if (levels[frame] < levels[quietest]) quietest = frame
        // The stretch began with a preroll before its first frame.
        val cut = current.size - frames * FRAME + quietest * FRAME
        settling.addLast(Stretch(current.take(cut), pauseBefore))
        current.dropFirst(cut)
        levels.dropFirst(quietest)
        pauseBefore = 0
        lastPartial = max(0, lastPartial - cut)
        partial = null
        hearNext()
    }

    private fun hearNext() {
        if (busy) return
        val final: Boolean
        val samples: FloatArray
        var pause = 0L
        if (settling.isNotEmpty()) {
            val next = settling.removeFirst()
            samples = next.samples
            pause = next.pauseBefore
            final = true
        } else {
            samples = partial ?: return
            partial = null
            final = false
        }
        busy = true
        val generation = generation
        scope.launch {
            val started = System.currentTimeMillis()
            val text = try {
                hearing.transcribe(samples)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                android.util.Log.w("Aqra", "The model couldn't hear a stretch", error)
                ""
            }
            lastHearing = System.currentTimeMillis() - started
            busy = false
            if (generation != this@RecitationListener.generation) return@launch
            if (BuildConfig.DEBUG) {
                android.util.Log.d("Recitation", "${if (final) "settled" else "partial"} ${samples.size / 16_000.0} s in ${System.currentTimeMillis() - started} ms: $text")
            }
            // A long pause inside an ayah that no prompt answered (the model was still hearing what came before).
            if (final && pause >= PROMPT_INSIDE_AYAH) tracker.hesitated()
            tracker.hear(text, final)
            apply()
            hearNext()
        }
    }

    /**
     * A long pause inside an ayah, or a longer one between two, brings the next word — twice at most in a row, since a
     * student who says nothing more may have stopped. The pause counts from the last sound of the voice, once what came
     * before it is heard.
     */
    private fun promptIfStuck() {
        if (stretch != null || settling.isNotEmpty() || busy || tracker.cursor == 0 || tracker.isComplete || promptsInARow >= 2) return
        val wait = if (tracker.isMidAyah) PROMPT_INSIDE_AYAH else PROMPT_BETWEEN_AYAT
        if (System.currentTimeMillis() - lastVoice < wait) return
        tracker.prompt()
        promptsInARow += 1
        lastVoice = System.currentTimeMillis()
        apply()
    }

    /** Shows the tracker's progress on the page. */
    private fun apply() {
        val words = tracker.words
        if (tracker.reached > 0) {
            val last = words[tracker.reached - 1]
            val endsAyah = tracker.reached == words.size || words[tracker.reached].ayah != last.ayah
            session.reveal(RevisionSession.WordRef(last.ayah, last.position), endsAyah)
        }
        if (tracker.isComplete) session.revealAll()
        for ((ayah, kinds) in tracker.stumbles) session.markStumble(ayah, kinds)
        for (index in tracker.prompted) session.prompt(RevisionSession.WordRef(words[index].ayah, words[index].position))
    }

    companion object {
        private const val RATE = 16_000
        private const val FRAME = 480 // 30 ms
        /** Milliseconds of silence inside an ayah before the next word is shown, and between two ayat. */
        const val PROMPT_INSIDE_AYAH = 4_000L
        const val PROMPT_BETWEEN_AYAT = 7_000L
        /** A model that takes longer than this to hear a stretch only hears it once it's settled. */
        private const val SLOW_HEARING = 1_500L
        /** Seconds of recitation a stretch grows to before it's cut; the model's window is 30 s. */
        const val LONGEST_STRETCH = 24
        /** The last seconds of a long stretch, searched for the quietest frame to cut at. */
        const val SPLIT_WINDOW = 6

        /** One transcriber for the app: the model is loaded once and kept while the app runs. */
        @Volatile private var transcriber: RecitationTranscriber? = null

        @Synchronized
        fun shared(model: RecitationModel): RecitationTranscriber =
            transcriber ?: RecitationTranscriber(model.folder).also { transcriber = it }
    }

    /** The real model, shared by every listener, loaded and run off the main thread. */
    private class ModelHearing(private val model: RecitationModel) : Hearing {
        override val isLoaded: Boolean get() = transcriber != null

        override suspend fun load() {
            withContext(Dispatchers.Default) { shared(model) }
        }

        override suspend fun transcribe(samples: FloatArray): String =
            withContext(Dispatchers.Default) { shared(model).transcribe(samples) }
    }
}

/** Samples gathered as they come, without boxing each one. */
private class Samples {
    private var data = FloatArray(16_000)
    var size = 0
        private set

    fun add(source: FloatArray, from: Int, count: Int) {
        if (size + count > data.size) data = data.copyOf(max(data.size * 2, size + count))
        System.arraycopy(source, from, data, size, count)
        size += count
    }

    fun add(value: Float) {
        if (size == data.size) data = data.copyOf(data.size * 2)
        data[size] = value
        size += 1
    }

    operator fun get(index: Int): Float = data[index]

    /** Keeps only the last [count] samples. */
    fun keepLast(count: Int) {
        if (size <= count) return
        System.arraycopy(data, size - count, data, 0, count)
        size = count
    }

    /** The first [count] samples. */
    fun take(count: Int): FloatArray = data.copyOf(min(count, size))

    /** Removes the first [count] samples. */
    fun dropFirst(count: Int) {
        val kept = max(0, size - count)
        System.arraycopy(data, size - kept, data, 0, kept)
        size = kept
    }

    fun clear() {
        size = 0
    }

    fun toArray(): FloatArray = data.copyOf(size)
}

/** Where the recitation's audio comes from: 16 kHz mono samples, taken as they come. */
internal interface AudioSource {
    fun start()
    fun stop()
    /** The samples since the last call. */
    fun drain(): FloatArray

    companion object {
        /**
         * The microphone — or, in a debug build, a recording played in real time, when the file
         * `files/recitation-test.wav` (16 kHz mono 16-bit) is there.
         */
        fun create(): AudioSource {
            if (BuildConfig.DEBUG) testRecording?.takeIf { it.exists() }?.let { return RecordingSource(it) }
            return MicrophoneSource()
        }

        /** Set by the app with its files folder, for the debug recording. */
        @Volatile var testRecording: File? = null
    }
}

/** The microphone, at 16 kHz mono, read on a thread of its own. */
private class MicrophoneSource : AudioSource {
    private val lock = Any()
    private var samples = FloatArray(0)
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false

    @SuppressLint("MissingPermission") // Asked for before listening starts.
    override fun start() {
        val minimum = AudioRecord.getMinBufferSize(16_000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        val audio = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16_000, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_FLOAT, max(minimum, 16_000 * 4 / 5))
        if (audio.state != AudioRecord.STATE_INITIALIZED) {
            audio.release()
            error("The microphone couldn't start")
        }
        audio.startRecording()
        record = audio
        running = true
        thread = Thread {
            val buffer = FloatArray(1_600)
            while (running) {
                val count = audio.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                if (count > 0) synchronized(lock) { samples += buffer.copyOf(count) }
            }
        }.apply { name = "Recitation microphone"; start() }
    }

    override fun stop() {
        running = false
        thread?.join(500)
        record?.run { stop(); release() }
        record = null
    }

    override fun drain(): FloatArray = synchronized(lock) { samples.also { samples = FloatArray(0) } }
}

/** A recording played as if it were being recited now: its samples come out as time passes. */
private class RecordingSource(private val file: File) : AudioSource {
    private var samples = FloatArray(0)
    private var given = 0
    private var started = 0L

    override fun start() {
        RandomAccessFile(file, "r").use { input ->
            val bytes = ByteArray(input.length().toInt() - 44)
            input.seek(44)
            input.readFully(bytes)
            val shorts = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
            samples = FloatArray(shorts.remaining()) { shorts.get(it) / 32768f }
        }
        started = System.currentTimeMillis()
    }

    override fun stop() {}

    override fun drain(): FloatArray {
        val due = min(((System.currentTimeMillis() - started) * 16L).toInt(), samples.size)
        val out = if (due > given) samples.copyOfRange(given, due) else FloatArray(0)
        given = max(given, due)
        return out
    }
}
