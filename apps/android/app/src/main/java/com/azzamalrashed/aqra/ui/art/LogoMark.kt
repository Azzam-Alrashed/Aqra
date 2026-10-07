package com.azzamalrashed.aqra.ui.art

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.dropShadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.shadow.Shadow
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces

/**
 * The منازل mark: stairs in the colored-Mushaf bands rising to a gold star — «اقرَأ وارقَ». Used on the second
 * onboarding page. [built] steps are up (for the entrance); [twinkle] (−1…1) drives a gentle sparkle on the star.
 */
@Composable
fun AqraLogoMark(built: Float = 5f, starLit: Float = 1f, twinkle: Float = 0f, modifier: Modifier = Modifier) {
    val count = 5
    val width = 60f + (count - 1) * 26f
    val height = 30f + count * 24f
    LeftToRight {
        Box(modifier.requiredSize(width.dp, height.dp).clearAndSetSemantics {}) {
            for (index in count - 1 downTo 0) {
                val (top, bottom) = StepFaces.faces[index]
                val up = (built - index).coerceIn(0f, 1f)
                StepBlock(top, bottom, Modifier
                    .absoluteOffset(x = (width - 60f - index * 26f).dp, y = (height - 30f - index * 24f + (1 - up) * 30f).dp)
                    .graphicsLayer { alpha = up })
            }
            val glow = 9f + twinkle * 3f
            AqraStar(
                Modifier
                    .absoluteOffset(x = (width - 38f - (count - 1) * 26f + 6f).dp, y = (height - 38f - count * 24f - 14f).dp)
                    .size(38.dp)
                    .graphicsLayer {
                        val scale = if (starLit > 0f) (0.1f + 0.9f * starLit) * (1 + twinkle * 0.04f) else 0.1f
                        scaleX = scale; scaleY = scale
                        rotationZ = if (starLit > 0f) twinkle * 6f - 90f * (1 - starLit) else -90f
                        alpha = starLit
                    }
                    .dropShadow(CircleShape, Shadow(radius = glow.dp, color = Palette.gold.copy(alpha = 0.7f * starLit))),
            )
        }
    }
}

/** One of the mark's steps: a soft 3D block in its band's colors. */
@Composable
fun StepBlock(top: Color, bottom: Color, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(11.dp)
    Box(
        modifier
            .size(60.dp, 30.dp)
            .dropShadow(shape, Shadow(radius = 8.dp, color = bottom.copy(alpha = 0.45f), offset = DpOffset(0.dp, 6.dp)))
            .clip(shape)
            .background(Brush.verticalGradient(listOf(top, bottom)))
            .border(1.dp, Color.White.copy(alpha = 0.7f), shape),
    ) {
        Box(Modifier.fillMaxSize().padding(2.dp).clip(shape)
            .background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.75f), 0.5f to Color.White.copy(alpha = 0f))))
    }
}
