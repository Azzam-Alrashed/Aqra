package com.azzamalrashed.aqra.ui.art

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/** The منازل stairs: ten steps, each worth three juz' of memorization. */
object Manazil {
    const val STEP_COUNT = 10
    const val JUZ_PER_STEP = 3
}

/** Gold for the logo's star, its glow and sparkles. */
object LogoGold {
    val light = Color(0xFFFFE38A)
    val deep = Color(0xFFE8A93A)
    val edge = Color(0xFFC98A22)
    val star = listOf(Color(0xFFF8D371), Color(0xFFEFB54A))
    val glow = Color(0xFFF6CB66)
    val sparkle = Color(0xFFEFC47C)
}

/**
 * The منازل as the onboarding draws them: ten glossy steps, three juz' each, rising in the reading direction toward
 * the gold star. Climbed steps take their colored-Mushaf band from the bottom up; the rest are white glass.
 * [climb] goes from 0 to 10; animate it and the steps fill one after another.
 */
@Composable
fun GlossyStairs(climb: Float, modifier: Modifier = Modifier) {
    val block = Size(44f, 24f)
    val rise = Offset(30f, 17f)
    val count = Manazil.STEP_COUNT
    val width = block.width + (count - 1) * rise.x
    val height = block.height + count * rise.y + 26f
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    // Drawn rising to the left, as Arabic reads; mirrored for left-to-right languages.
    LeftToRight {
    Box(
        modifier
            .requiredSize(width.dp, height.dp)
            .graphicsLayer { scaleX = if (rtl) 1f else -1f }
            .clearAndSetSemantics {},
    ) {
        // The highest step first, so each lower one sits in front of the one above it.
        for (index in count - 1 downTo 0) {
            val face = StepFaces.forJuz(index * Manazil.JUZ_PER_STEP + 1)
            GlossyStep(
                face = face,
                lit = (climb - index).coerceIn(0f, 1f),
                modifier = Modifier
                    .absoluteOffset(x = (width - block.width - index * rise.x).dp, y = (height - block.height - index * rise.y).dp)
                    .size(block.width.dp, block.height.dp),
            )
        }
        AqraStar(
            Modifier
                .absoluteOffset(x = (width - 34f - (count - 1) * rise.x + 5f).dp, y = (height - 34f - count * rise.y - 14f).dp)
                .size(34.dp)
                .dropShadow(CircleShape, Shadow(radius = 10.dp, color = Palette.gold.copy(alpha = 0.6f))),
        )
    }
    }
}

/** One step: white glass, filled from the bottom with its band's color as far as it's climbed, under a sheen. */
@Composable
private fun GlossyStep(face: Pair<Color, Color>, lit: Float, modifier: Modifier) {
    val shape = RoundedCornerShape(10.dp)
    val shadow = if (lit > 0) Shadow(radius = 8.dp, color = face.second.copy(alpha = 0.45f * min(lit * 2, 1f)), offset = DpOffset(0.dp, 6.dp))
    else Shadow(radius = 8.dp, color = Palette.brand.copy(alpha = 0.08f), offset = DpOffset(0.dp, 6.dp))
    Box(
        modifier
            .dropShadow(shape, shadow)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.75f))
            .drawBehind {
                if (lit > 0f) {
                    clipRect(top = size.height * (1 - lit)) {
                        drawRect(Brush.verticalGradient(listOf(face.first, face.second)))
                    }
                }
            }
            .border(1.dp, if (lit > 0) Color.White.copy(alpha = 0.7f) else Palette.lavender, shape),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .padding(2.dp)
                .clip(shape)
                .background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.75f), 0.5f to Color.White.copy(alpha = 0f))),
        )
    }
}

/** The logo's own gold star (never an emoji, which can't be used in a logo). */
@Composable
fun AqraStar(modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val star = starPath(size, points = 5, innerRatio = 0.48f, cornerRadius = 0.18f)
        drawPath(star, Brush.verticalGradient(listOf(LogoGold.light, LogoGold.deep)))
        scale(0.86f, pivot = Offset(size.width / 2, size.height / 2 - 1f)) {
            drawPath(star, Brush.verticalGradient(0f to Color.White.copy(alpha = 0.65f), 0.5f to Color.White.copy(alpha = 0f), startY = 0f, endY = size.height))
        }
        drawPath(star, LogoGold.edge.copy(alpha = 0.55f), style = Stroke(width = 1.dp.toPx()))
    }
}

/** A star with softly rounded points, filling a box of [size]. */
fun starPath(size: Size, points: Int, innerRatio: Float, cornerRadius: Float, origin: Offset = Offset.Zero): Path {
    val center = Offset(origin.x + size.width / 2, origin.y + size.height / 2 + size.height * 0.04f)
    val outer = min(size.width, size.height) / 2
    val inner = outer * innerRatio
    val vertices = (0 until points * 2).map { i ->
        val radius = if (i % 2 == 0) outer else inner
        val angle = i * PI / points - PI / 2
        Offset(center.x + radius * cos(angle).toFloat(), center.y + radius * sin(angle).toFloat())
    }
    fun toward(a: Offset, b: Offset, distance: Float): Offset {
        val dx = b.x - a.x
        val dy = b.y - a.y
        val length = maxOf(sqrt(dx * dx + dy * dy), 0.001f)
        val d = min(distance, length / 2)
        return Offset(a.x + dx / length * d, a.y + dy / length * d)
    }
    val r = outer * cornerRadius
    return Path().apply {
        vertices.forEachIndexed { i, current ->
            val previous = vertices[(i + vertices.size - 1) % vertices.size]
            val next = vertices[(i + 1) % vertices.size]
            val start = toward(current, previous, r)
            val end = toward(current, next, r)
            if (i == 0) moveTo(start.x, start.y) else lineTo(start.x, start.y)
            quadraticTo(current.x, current.y, end.x, end.y)
        }
        close()
    }
}

/**
 * Glowing concentric rings behind the mark. [breath] (−1…1) drives a slow breathing motion; [open] grows them out of
 * the middle.
 */
@Composable
fun AqraGlowRings(
    modifier: Modifier = Modifier,
    open: Boolean = true,
    breath: Float = 0f,
    glow: List<Color> = listOf(Palette.lavender, Palette.rose.copy(alpha = 0.5f)),
    ring: Color = Color.White,
    openness: Float = if (open) 1f else 0f,
) {
    Canvas(modifier.requiredSize(380.dp).clearAndSetSemantics {}) {
        val center = Offset(size.width / 2, size.height / 2)
        val unit = size.width / 380f
        val glowScale = 1 + breath * 0.03f
        val stops = buildList {
            add(0f to glow[0])
            add(10f / 190f to glow[0])
            for ((i, color) in glow.withIndex()) if (i > 0) add((10f + 180f * i / glow.size) / 190f to color)
            add(1f to glow[0].copy(alpha = 0f))
        }.toTypedArray()
        drawCircle(
            Brush.radialGradient(*stops, center = center, radius = 190f * unit * glowScale),
            radius = 190f * unit * glowScale, center = center, alpha = openness,
        )
        val ringScale = 0.2f + 0.8f * openness + breath * 0.015f * openness
        for (diameter in listOf(110f, 190f, 270f)) {
            drawCircle(ring, radius = (diameter / 2 - 0.75f) * unit * ringScale, center = center, alpha = 0.9f * openness,
                style = Stroke(width = 1.5f * unit))
        }
        drawCircle(ring.copy(alpha = 0.55f), radius = 55f * unit * (0.2f + 0.8f * openness), center = center, alpha = openness)
    }
}

/** A juz' or surah number's tile color: the band of its juz' on the stairs. */
fun juzFace(juz: Int) = StepFaces.forJuz(juz)

/** Lays its content out left to right: artwork is a fixed composition, mirrored on purpose where it must be. */
@Composable
fun LeftToRight(content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr, content = content)
}

/** Places [content] with its own box centered, ignoring the space it's given (for artwork drawn at a fixed size). */
@Composable
fun Centered(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(modifier, contentAlignment = Alignment.Center) { content() }
}
