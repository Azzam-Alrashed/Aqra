package com.azzamalrashed.aqra.recitation

import com.azzamalrashed.aqra.TestQuran
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionSession
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * The listener around the tracker: the microphone, the model and the clock stand in, so these run in milliseconds.
 * The "recitation" is a recording whose words are flat tones of distinct loudness, which the fake model reads back
 * as the words of the page; the model itself isn't run here.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RecitationListenerTest {
    private val store get() = TestQuran.store
    private val dispatcher = StandardTestDispatcher()

    @Before
    fun main() = Dispatchers.setMain(dispatcher)

    @After
    fun reset() = Dispatchers.resetMain()

    private fun ayah(surah: Int, number: Int): Int = (0 until MushafStore.AYAH_COUNT).first { store.reference(it) == surah to number }

    /** Everything at once on the first drain, as if the whole recording had just been said. */
    private class AllAtOnce(private val samples: FloatArray) : AudioSource {
        var started = false
        var stopped = false
        private var drained = false

        override fun start() { started = true }
        override fun stop() { stopped = true }
        override fun drain(): FloatArray = if (drained) FloatArray(0) else { drained = true; samples }
    }

    /** A model that reads the words off the recording's tones; its loading can be held back. */
    private class FakeHearing(private val decode: (FloatArray) -> String) : RecitationListener.Hearing {
        override var isLoaded = false
        var gate: CompletableDeferred<Unit>? = null
        val heard = ArrayList<FloatArray>()

        override suspend fun load() {
            gate?.await()
            isLoaded = true
        }

        override suspend fun transcribe(samples: FloatArray): String {
            heard += samples
            return decode(samples)
        }
    }

    /**
     * Words as tones: word i is a square wave of amplitude 0.1 + 0.02·i for [secondsPerWord], then two frames of
     * silence; a second of silence closes the recording. [decode] reads the words a stretch holds, in order.
     */
    private class Tones(val words: List<String>, secondsPerWord: Double) {
        val samples: FloatArray

        init {
            val perWord = (secondsPerWord * 16_000).toInt()
            val gap = 2 * 480
            val out = FloatArray(words.size * (perWord + gap) + 16_000)
            var at = 0
            for (i in words.indices) {
                val amplitude = 0.1f + 0.02f * i
                for (n in 0 until perWord) out[at + n] = if (n % 2 == 0) amplitude else -amplitude
                at += perWord + gap
            }
            samples = out
        }

        fun indices(stretch: FloatArray): List<Int> =
            stretch.asSequence().map { abs(it) }.filter { it > 0f }.map { ((it - 0.1f) / 0.02f).roundToInt() }.distinct().sorted().toList()

        fun decode(stretch: FloatArray): String = indices(stretch).joinToString(" ") { words[it] }
    }

    @Test
    fun stoppingWhilePreparingLeavesTheMicOff() = runTest(dispatcher) {
        val source = AllAtOnce(FloatArray(0))
        val hearing = FakeHearing { "" }.apply { gate = CompletableDeferred() }
        val session = RevisionSession(1, (0..6).toList())
        val listener = RecitationListener(session, store, audio = { source }, hearing = hearing)
        listener.start()
        runCurrent()
        assertEquals(RecitationListener.Phase.PREPARING, listener.phase)
        // «توقّف» while «يستعدّ للاستماع…»: the model finishes loading afterwards, and the microphone stays off.
        listener.pause()
        assertEquals(RecitationListener.Phase.PAUSED, listener.phase)
        hearing.gate!!.complete(Unit)
        advanceUntilIdle()
        assertFalse(source.started)
        // The same when the screen is left.
        val again = FakeHearing { "" }.apply { gate = CompletableDeferred() }
        val second = AllAtOnce(FloatArray(0))
        val left = RecitationListener(session, store, audio = { second }, hearing = again)
        left.start()
        runCurrent()
        left.close()
        again.gate!!.complete(Unit)
        advanceUntilIdle()
        assertFalse(second.started)
    }

    @Test
    fun aLongAyahIsTrackedAcrossWindows() = runTest(dispatcher) {
        // al-Mulk 67:3, recited slowly: longer than the model's window, so it's heard in two stretches.
        val index = ayah(67, 3)
        val words = RecitationText.wordsOfAyah(store.ayahPlainTexts[index], store.ayahWordCounts[index])
        assertTrue(words.size >= 12)
        val tones = Tones(words, secondsPerWord = 2.0)
        assertTrue(tones.samples.size > 24 * 16_000)
        val source = AllAtOnce(tones.samples)
        val hearing = FakeHearing(tones::decode)
        val session = RevisionSession(store.pageOfAyah(index), listOf(index))
        val listener = RecitationListener(session, store, audio = { source }, hearing = hearing)
        listener.start()
        runCurrent()
        assertEquals(RecitationListener.Phase.LISTENING, listener.phase)
        advanceTimeBy(500)
        runCurrent()
        // Settled in two stretches or more, each within the window, cut between two words: no word is heard twice or
        // in half.
        assertTrue(hearing.heard.size >= 2)
        for (stretch in hearing.heard) assertTrue("${stretch.size / 16_000.0} s", stretch.size <= RecitationListener.LONGEST_STRETCH * 16_000)
        assertEquals(words.indices.toList(), hearing.heard.flatMap(tones::indices))
        assertTrue(tones.indices(hearing.heard[0]).size >= 8)
        // Followed to the end, without a stumble.
        assertTrue(session.isComplete)
        assertTrue(session.stumbles.isEmpty())
        listener.close()
        assertTrue(source.stopped)
    }
}
