package com.azzamalrashed.aqra.recitation

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The log-mel features the model hears, against two references: the plain DFT the app computed them with before, and
 * Python Whisper's own feature extractor (`transformers.WhisperFeatureExtractor` 4.57.6) run on the same half second
 * of synthesized audio, kept in `src/test/resources/recitation`. The filter bank there is the extractor's, and is
 * byte for byte the model's `mel_filters.bin`.
 */
class WhisperFeaturesTest {
    private fun resource(name: String): ByteArray =
        checkNotNull(javaClass.getResourceAsStream("/recitation/$name")) { "missing fixture $name" }.use { it.readBytes() }

    private fun floats(bytes: ByteArray): FloatArray {
        val out = FloatArray(bytes.size / 4)
        ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer().get(out)
        return out
    }

    private val filters by lazy { floats(resource("whisper-mel-filters.bin")) }
    private val audio by lazy { floats(resource("audio-8000.f32")) }

    @Test
    fun fftMatchesTheDft() {
        val n = 400
        val random = Random(7)
        val re = DoubleArray(n) { random.nextDouble(-1.0, 1.0) }
        val im = DoubleArray(n) { random.nextDouble(-1.0, 1.0) }
        val outRe = DoubleArray(n)
        val outIm = DoubleArray(n)
        Fft(n).transform(re, im, outRe, outIm)
        var worst = 0.0
        for (k in 0 until n) {
            var sumRe = 0.0
            var sumIm = 0.0
            for (t in 0 until n) {
                val angle = -2 * PI * k * t / n
                sumRe += re[t] * cos(angle) - im[t] * sin(angle)
                sumIm += re[t] * sin(angle) + im[t] * cos(angle)
            }
            worst = max(worst, max(abs(sumRe - outRe[k]), abs(sumIm - outIm[k])))
        }
        assertTrue("FFT differs from the DFT by $worst", worst < 1e-9)
    }

    @Test
    fun logMelMatchesTheDftPath() {
        // The fixture's audio, and a two-second sweep that reaches every band.
        val sweep = FloatArray(32_000) { (0.6 * sin(2 * PI * (200.0 + 3_000.0 * it / 32_000) * it / 16_000)).toFloat() }
        for ((name, samples) in listOf("fixture" to audio, "sweep" to sweep)) {
            val fast = WhisperFeatures(filters).logMel(samples)
            val plain = dftLogMel(samples, filters)
            var worst = 0f
            for (i in fast.indices) worst = max(worst, abs(fast[i] - plain[i]))
            assertTrue("$name: the FFT path differs from the DFT path by $worst", worst < 1e-6f)
        }
    }

    @Test
    fun logMelMatchesWhisperFixture() {
        val expected = floats(resource("whisper-logmel-8000.bin"))
        val heard = expected.size / WhisperFeatures.MELS
        assertEquals(53, heard)
        val actual = WhisperFeatures(filters).logMel(audio)
        var worst = 0f
        for (m in 0 until WhisperFeatures.MELS) {
            for (f in 0 until heard) {
                worst = max(worst, abs(actual[m * WhisperFeatures.FRAMES + f] - expected[m * heard + f]))
            }
        }
        assertTrue("differs from Python Whisper's features by $worst", worst < 1e-3f)
        // Past the audio, every frame sits at the floor, 8 below the loudest value.
        val floor = expected.min()
        for (m in 0 until WhisperFeatures.MELS) {
            for (f in heard until WhisperFeatures.FRAMES) {
                assertEquals(floor, actual[m * WhisperFeatures.FRAMES + f], 1e-3f)
            }
        }
    }

    /** The features as the app computed them before the FFT: the same steps with a plain DFT, in double precision. */
    private fun dftLogMel(samples: FloatArray, filters: FloatArray): FloatArray {
        val n = WhisperFeatures.N_FFT
        val hop = WhisperFeatures.HOP
        val bins = WhisperFeatures.BINS
        val mels = WhisperFeatures.MELS
        val frames = WhisperFeatures.FRAMES
        val length = min(samples.size, WhisperFeatures.SAMPLES)
        fun sample(index: Int): Double {
            val i = index - n / 2
            return when {
                i < 0 -> if (-i < length) samples[-i].toDouble() else 0.0
                i < length -> samples[i].toDouble()
                else -> 0.0
            }
        }
        val window = DoubleArray(n) { 0.5 - 0.5 * cos(2 * PI * it / n) }
        val heard = min(frames, (length + n / 2) / hop + 2)
        val floorValue = log10(1e-10f)
        val mel = FloatArray(mels * frames) { floorValue }
        var top = floorValue
        val frame = DoubleArray(n)
        val power = DoubleArray(bins)
        for (f in 0 until heard) {
            for (t in 0 until n) frame[t] = sample(f * hop + t) * window[t]
            for (k in 0 until bins) {
                var re = 0.0
                var im = 0.0
                for (t in 0 until n) {
                    val angle = 2 * PI * k * t / n
                    re += frame[t] * cos(angle)
                    im -= frame[t] * sin(angle)
                }
                power[k] = re * re + im * im
            }
            for (m in 0 until mels) {
                var energy = 0.0
                for (k in 0 until bins) energy += power[k] * filters[k * mels + m]
                val value = log10(max(energy, 1e-10)).toFloat()
                mel[m * frames + f] = value
                if (value > top) top = value
            }
        }
        val floor = top - 8f
        for (i in mel.indices) mel[i] = (max(mel[i], floor) + 4f) / 4f
        return mel
    }
}
