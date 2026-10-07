package com.azzamalrashed.aqra.ui.art

import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import kotlin.math.min
import kotlin.math.sin

/** The logo's colors. The star and the doorway's light stay gold in every palette. */
class LogoPalette(
    val background: List<Long>,
    /** Five stops down the arch band, from its crown to where it fades into the book. */
    val band: List<Long>,
    val door: List<Long>,
    val bookBack: List<Long>,
    val bookBackDeep: List<Long>,
    val bookFront: List<Long>,
    val bookFrontDeep: List<Long>,
) {
    companion object {
        /** Aqra's identity: lavender and purple on cream. */
        val AQRA = LogoPalette(
            background = listOf(0xFFFEFCF9, 0xFFF4EEF8, 0xFFE9E0F3),
            band = listOf(0xFFE6DCF7, 0xFFC8B4EE, 0xFFA88BE2, 0xFFD5C7F3, 0xFFEEE8FA),
            door = listOf(0xFFDDD0F5, 0xFFEDE6FA, 0xFFF8F5FD),
            bookBack = listOf(0xFFF2ECFC, 0xFFC6AFEE, 0xFF9B78DD),
            bookBackDeep = listOf(0xFFDCCCF6, 0xFFA184E2, 0xFF7C55CC),
            bookFront = listOf(0xFFF5F0FD, 0xFFCDB9F1, 0xFFA383E0),
            bookFrontDeep = listOf(0xFFE1D4F8, 0xFFA98DE5, 0xFF8460D1),
        )
    }
}

/** How far each part of the logo has come in, 0…1; all 1 shows the finished logo. */
data class LogoReveal(val arch: Float = 1f, val book: Float = 1f, val door: Float = 1f, val star: Float = 1f) {
    companion object {
        val DONE = LogoReveal()
    }
}

/**
 * Aqra's logo (the user's design): a soft arch with a gold star above a glowing doorway, rising out of two open-book
 * curves. Drawn on a 1024-unit canvas scaled to fit the space it's given.
 */
@Composable
fun AqraArchLogo(
    modifier: Modifier = Modifier,
    withBackground: Boolean = true,
    markScale: Float = 1f,
    palette: LogoPalette = LogoPalette.AQRA,
    reveal: LogoReveal = LogoReveal.DONE,
    /** Seconds, for the idle sparkle; a constant keeps it still. */
    time: Double = 0.0,
) {
    Box(modifier.clearAndSetSemantics {}) {
        // A soft white halo around the arch (blurred where the system can blur, Android 12 and later).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Canvas(Modifier.fillMaxSize().blur(14.dp)) {
                logoSpace(markScale) { drawPath(ArchPath.outer, Color.White, alpha = 0.85f * reveal.arch) }
            }
        }
        Canvas(Modifier.fillMaxSize()) {
            val unit = size.minDimension / 1024f
            if (withBackground) {
                drawRect(Brush.radialGradient(
                    colorStops = gradientStops(palette.background.map(::Color), start = 60f, end = 720f),
                    center = Offset(size.width * 0.5f, size.height * 0.46f), radius = 720f * unit,
                ))
            }
            logoSpace(markScale) { drawMark(palette, reveal, time) }
        }
    }
}

/** Draws in the logo's 1024-unit space, the mark scaled about its middle and lifted as it grows. */
private fun DrawScope.logoSpace(markScale: Float, draw: DrawScope.() -> Unit) {
    val unit = size.minDimension / 1024f
    withTransform({
        translate((size.width - 1024f * unit) / 2, (size.height - 1024f * unit) / 2)
        scale(unit, unit, Offset.Zero)
        // The mark's visual center sits about 20 units below the canvas center; lift it as it grows.
        translate(0f, -20f * markScale)
        scale(markScale, markScale, Offset(512f, 512f))
    }) { draw() }
}

private fun DrawScope.drawMark(palette: LogoPalette, reveal: LogoReveal, time: Double) {
    val colors = { list: List<Long> -> list.map(::Color) }

    // The arch: a band that fades as it reaches the book, grown up from its foot.
    withTransform({ scale(0.92f + 0.08f * reveal.arch, 0.92f + 0.08f * reveal.arch, Offset(512f, 1024f * 0.9f)) }) {
        val band = colors(palette.band)
        drawPath(ArchPath.outer, Brush.verticalGradient(
            0f to band[0], 0.35f to band[1], 0.55f to band[2], 0.66f to band[3], 0.72f to band[4],
            startY = 1024f * 0.15f, endY = 1024f * 0.9f,
        ), alpha = reveal.arch)
        drawPath(ArchPath.inner, Color(0xFFFEFEFF), alpha = reveal.arch)
    }

    // Warm light gathering behind the doorway.
    drawPath(ArchPath.inner, Brush.radialGradient(
        colorStops = gradientStops(listOf(Color(0xFFFFE9C4).copy(alpha = 0.55f), Color(0xFFFFF6E8).copy(alpha = 0.25f), Color.White.copy(alpha = 0f)), 10f, 280f),
        center = Offset(512f, 1024f * 0.55f), radius = 280f,
    ), alpha = (reveal.door * (0.85f + 0.15f * sin(time * 1.4).toFloat())).coerceIn(0f, 1f))

    // The doorway: a small arch with a glowing path inside, rising toward the star.
    val door = colors(palette.door)
    drawPath(ArchPath.door, Brush.verticalGradient(listOf(door[0], door[1], door[2].copy(alpha = 0.4f)), startY = 1024f * 0.46f, endY = 1024f * 0.7f), alpha = reveal.arch)
    drawPath(ArchPath.doorOpening, Color(0xFFFFFEFB), alpha = reveal.arch)
    drawPath(ArchPath.doorLight, Brush.verticalGradient(
        listOf(Color(0xFFF8CF92), Color(0xFFFBE3BD), Color(0xFFFFF7EA).copy(alpha = 0.2f)), startY = 1024f * 0.55f, endY = 1024f * 0.73f,
    ), alpha = reveal.arch * reveal.door)

    // The open book: two overlapping curves, the right one in front, rising into the arch.
    clipPath(ArchPath.outer) {
        translate(0f, (1 - reveal.book) * 260f) {
            val alpha = min(1f, reveal.book * 1.5f)
            ellipse(Offset(240f, 1000f), Size(660f, 720f), colors(palette.bookBack), alpha)
            ellipse(Offset(228f, 1040f), Size(600f, 640f), colors(palette.bookBackDeep), alpha)
            ellipse(Offset(784f, 1000f), Size(660f, 720f), colors(palette.bookFront), alpha)
            drawOval(Color.White.copy(alpha = 0.55f), topLeft = Offset(784f - 330f, 1000f - 360f), size = Size(660f, 720f), alpha = alpha, style = Stroke(2f))
            ellipse(Offset(796f, 1040f), Size(600f, 640f), colors(palette.bookFrontDeep), alpha)
        }
    }

    // The star, glowing, and its sparkles.
    val pulse = sin(time * 2).toFloat()
    if (reveal.star > 0f) {
        drawCircle(Brush.radialGradient(
            listOf(LogoGold.glow.copy(alpha = 0.45f), LogoGold.glow.copy(alpha = 0f)), center = Offset(512f, 380f), radius = 61f + 30f + 8f * pulse,
        ), radius = 61f + 30f + 8f * pulse, center = Offset(512f, 380f), alpha = reveal.star)
        val starScale = maxOf(0.01f, reveal.star) * (1 + 0.03f * pulse)
        withTransform({
            rotate((1 - reveal.star) * -120f, Offset(512f, 380f))
            scale(starScale, starScale, Offset(512f, 380f))
        }) {
            drawPath(starPath(Size(122f, 122f), 8, 0.38f, 0.04f, Offset(512f - 61f, 380f - 61f)),
                Brush.verticalGradient(LogoGold.star, startY = 380f - 61f, endY = 380f + 61f), alpha = reveal.star)
        }
        listOf(Offset(353f, 461f), Offset(671f, 461f), Offset(372f, 590f), Offset(651f, 590f)).forEachIndexed { index, point ->
            val sparkle = reveal.star * (0.85f + 0.25f * sin(time * 2.6 + index * 1.7).toFloat())
            scale(sparkle, sparkle, point) {
                drawPath(starPath(Size(22f, 22f), 4, 0.38f, 0.1f, Offset(point.x - 11f, point.y - 11f)), LogoGold.sparkle, alpha = reveal.star)
            }
        }
    }
}

/** An ellipse of [size] centered on [center], shaded from its top to 42% of the way down. */
private fun DrawScope.ellipse(center: Offset, size: Size, colors: List<Color>, alpha: Float) {
    val top = center.y - size.height / 2
    drawOval(Brush.verticalGradient(colors, startY = top, endY = top + size.height * 0.42f),
        topLeft = Offset(center.x - size.width / 2, top), size = size, alpha = alpha)
}

/** A radial gradient's stops between two radii, as SwiftUI spreads them, for a brush whose radius is [end]. */
fun gradientStops(colors: List<Color>, start: Float, end: Float): Array<Pair<Float, Color>> {
    val from = start / end
    return Array(colors.size + 1) { i ->
        if (i == 0) 0f to colors[0] else (from + (1 - from) * (i - 1) / (colors.size - 1).coerceAtLeast(1)) to colors[i - 1]
    }
}

/** Outlines of the arch, in 1024-unit canvas coordinates. */
private object ArchPath {
    /** An ogee arch: straight sides, a rounded base, and a pointed crown. */
    fun arch(left: Float, right: Float, shoulder: Float, apex: Float, bottom: Float, corner: Float, crown: Float) = Path().apply {
        val mid = (left + right) / 2
        moveTo(left, shoulder)
        lineTo(left, bottom - corner)
        quadraticTo(left, bottom, left + corner, bottom)
        lineTo(right - corner, bottom)
        quadraticTo(right, bottom, right, bottom - corner)
        lineTo(right, shoulder)
        cubicTo(right, shoulder - (shoulder - apex) * 0.55f, mid + (right - mid) * crown, apex + (shoulder - apex) * 0.22f, mid, apex)
        cubicTo(mid - (right - mid) * crown, apex + (shoulder - apex) * 0.22f, left, shoulder - (shoulder - apex) * 0.55f, left, shoulder)
        close()
    }

    val outer = arch(228f, 796f, 470f, 152f, 912f, 150f, 0.42f)
    val inner = arch(270f, 754f, 488f, 212f, 870f, 115f, 0.42f)
    val door = arch(432f, 592f, 590f, 476f, 800f, 0f, 0.35f)
    val doorOpening = arch(470f, 554f, 610f, 538f, 800f, 0f, 0.35f)
    val doorLight = arch(489f, 535f, 600f, 562f, 800f, 0f, 0.3f)
}
