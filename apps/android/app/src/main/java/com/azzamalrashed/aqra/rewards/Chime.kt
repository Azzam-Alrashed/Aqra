package com.azzamalrashed.aqra.rewards

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin

/**
 * The reward chime: two soft bell-like notes (three for a big moment), made here rather than bundled, played only
 * when the ringer is on, as on iOS.
 */
object Chime {
    private const val RATE = 44_100
    private var track: AudioTrack? = null

    fun play(context: Context, big: Boolean) {
        val audio = context.getSystemService(AudioManager::class.java) ?: return
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return
        val notes = if (big) {
            listOf(659.25 to 0.0, 783.99 to 0.12, 1046.5 to 0.24) // E5, G5, C6
        } else {
            listOf(783.99 to 0.0, 1046.5 to 0.1) // G5, C6
        }
        val samples = wave(notes, if (big) 1.1 else 0.7)
        runCatching {
            track?.release()
            val next = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build(),
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(samples.size * 2)
                .build()
            next.write(samples, 0, samples.size)
            next.setVolume(0.35f)
            next.play()
            track = next
        }
    }

    /** Soft decaying sine notes, as 16-bit samples. */
    private fun wave(notes: List<Pair<Double, Double>>, length: Double): ShortArray {
        val count = (length * RATE).toInt()
        return ShortArray(count) { index ->
            val time = index.toDouble() / RATE
            var value = 0.0
            for ((frequency, start) in notes) {
                if (time < start) continue
                val t = time - start
                val envelope = min(t / 0.008, 1.0) * exp(-t * 5)
                value += envelope * (sin(2 * PI * frequency * t) + 0.3 * sin(4 * PI * frequency * t))
            }
            ((value * 0.3).coerceIn(-1.0, 1.0) * Short.MAX_VALUE).toInt().toShort()
        }
    }
}
