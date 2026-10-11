package com.azzamalrashed.aqra.recitation

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * Whisper's log-mel features: up to 30 s of 16 kHz audio as [80][3000] — a 400-sample Hann window every 160 samples,
 * its power spectrum through the 80 mel filters, log10, a floor 8 below the loudest value, then (x + 4) / 4. The same
 * numbers as Python Whisper's feature extractor (`logMelMatchesWhisperFixture` holds them to 1e-3).
 *
 * The spectrum comes from a 400-point FFT (400 = 2⁴ · 5², so not a power of two) rather than the plain DFT: a frame
 * costs about 6,000 complex multiply-adds instead of 80,000.
 */
class WhisperFeatures(
    /** The mel filter bank, [201][80] row by row (the model's `mel_filters.bin`). */
    private val filters: FloatArray,
) {
    init {
        require(filters.size == BINS * MELS) { "The mel filter bank has ${filters.size} values, not ${BINS * MELS}" }
    }

    private val fft = Fft(N_FFT)
    private val frameRe = DoubleArray(N_FFT)
    private val frameIm = DoubleArray(N_FFT)
    private val spectrumRe = DoubleArray(N_FFT)
    private val spectrumIm = DoubleArray(N_FFT)
    private val power = DoubleArray(BINS)

    /** The features of up to 30 s of audio; the rest is silence. One stretch at a time (the buffers are shared). */
    fun logMel(samples: FloatArray): FloatArray {
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
        var top = LOG_FLOOR
        for (f in 0 until heard) {
            val start = f * HOP
            for (n in 0 until N_FFT) {
                frameRe[n] = sample(start + n) * WINDOW[n]
                frameIm[n] = 0.0
            }
            fft.transform(frameRe, frameIm, spectrumRe, spectrumIm)
            for (k in 0 until BINS) power[k] = spectrumRe[k] * spectrumRe[k] + spectrumIm[k] * spectrumIm[k]
            for (m in 0 until MELS) {
                var energy = 0.0
                for (k in 0 until BINS) energy += power[k] * filters[k * MELS + m]
                val value = log10(max(energy, 1e-10)).toFloat()
                mel[m * FRAMES + f] = value
                if (value > top) top = value
            }
        }
        val floor = top - 8f
        for (i in mel.indices) mel[i] = (max(mel[i], floor) + 4f) / 4f
        return mel
    }

    companion object {
        const val SAMPLES = 480_000
        const val N_FFT = 400
        const val HOP = 160
        const val BINS = N_FFT / 2 + 1
        const val MELS = 80
        const val FRAMES = 3_000
        val LOG_FLOOR = log10(1e-10f)

        /** A periodic Hann window, as Whisper's. */
        private val WINDOW = DoubleArray(N_FFT) { 0.5 - 0.5 * cos(2 * PI * it / N_FFT) }
    }
}

/**
 * A complex FFT of any size whose prime factors are 2, 3 and 5, by Cooley–Tukey decimation in time: the input is
 * split into `p` interleaved parts, each transformed, and the parts combined with the twiddles, which are read from
 * one table for the full size.
 */
internal class Fft(val size: Int) {
    private val cos = DoubleArray(size) { cos(2 * PI * it / size) }
    private val sin = DoubleArray(size) { sin(2 * PI * it / size) }
    private val sumRe = DoubleArray(5)
    private val sumIm = DoubleArray(5)

    init {
        var rest = size
        for (p in intArrayOf(2, 3, 5)) while (rest % p == 0) rest /= p
        require(rest == 1) { "An FFT of $size points: the size must be a product of 2, 3 and 5" }
    }

    /** The transform of the input (`inRe`, `inIm`), written to the output; the input isn't changed. */
    fun transform(inRe: DoubleArray, inIm: DoubleArray, outRe: DoubleArray, outIm: DoubleArray) {
        step(inRe, inIm, 0, 1, outRe, outIm, 0, size)
    }

    /** Transforms the `n` input values at `inOffset`, `stride` apart, into the `n` outputs from `outOffset`. */
    private fun step(
        inRe: DoubleArray, inIm: DoubleArray, inOffset: Int, stride: Int,
        outRe: DoubleArray, outIm: DoubleArray, outOffset: Int, n: Int,
    ) {
        if (n == 1) {
            outRe[outOffset] = inRe[inOffset]
            outIm[outOffset] = inIm[inOffset]
            return
        }
        val p = if (n % 2 == 0) 2 else if (n % 3 == 0) 3 else 5
        val m = n / p
        // Part r is every p-th input from the r-th; its transform Y_r lands at outOffset + r·m.
        for (r in 0 until p) step(inRe, inIm, inOffset + r * stride, stride * p, outRe, outIm, outOffset + r * m, m)
        // X[k + q·m] = Σ_r W_n^{r(k + q·m)} · Y_r[k], and W_n = W_size^{size/n}. For one k, the p inputs Y_r[k] sit
        // exactly where the p outputs go, so they're all read before any is written.
        val scale = size / n
        for (k in 0 until m) {
            for (q in 0 until p) {
                var re = 0.0
                var im = 0.0
                for (r in 0 until p) {
                    val t = (r * (k + q * m) % n) * scale
                    val wr = cos[t]
                    val wi = -sin[t]
                    val yr = outRe[outOffset + r * m + k]
                    val yi = outIm[outOffset + r * m + k]
                    re += yr * wr - yi * wi
                    im += yr * wi + yi * wr
                }
                sumRe[q] = re
                sumIm[q] = im
            }
            for (q in 0 until p) {
                outRe[outOffset + k + q * m] = sumRe[q]
                outIm[outOffset + k + q * m] = sumIm[q]
            }
        }
    }
}
