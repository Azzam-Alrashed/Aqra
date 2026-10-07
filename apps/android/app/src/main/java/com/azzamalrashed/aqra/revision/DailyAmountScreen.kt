package com.azzamalrashed.aqra.revision

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.ui.art.AqraGlowRings
import com.azzamalrashed.aqra.ui.components.AqraChip
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipText
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumber
import kotlin.math.ceil

/** The days a full pass through everything memorized takes at a daily amount. */
fun cycleDays(memorizedPages: Int, amount: Int): Int = ceil(memorizedPages.toDouble() / amount.coerceAtLeast(1)).toInt().coerceAtLeast(1)

/**
 * «كم تراجع يوميًا؟»: the pages to revise each day, with the length of a full revision cycle shown as it changes.
 * Shown right after «ماذا تحفظ؟», and later from the home to change it.
 */
@Composable
fun DailyAmountScreen(memorizedPages: Int, initial: Int, isEditor: Boolean, onDone: (Int) -> Unit) {
    var amount by rememberSaveable { mutableIntStateOf(initial.coerceIn(1, 40)) }
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(amount) { haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }
    val suggested = ReviewPolicy.suggestedDailyPages(memorizedPages)
    Column(
        Modifier
            .fillMaxSize()
            .background(Palette.surface)
            .then(if (isEditor) Modifier else Modifier.safeDrawingPadding())
            .padding(horizontal = 24.dp)
            .padding(bottom = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.weight(1f))
        // The amount in the glowing rings, − and + on either side, and chips for the cycle and the suggestion.
        Box(Modifier.fillMaxWidth().height(340.dp), contentAlignment = Alignment.Center) {
            AqraGlowRings(Modifier.graphicsLayer { scaleX = 1.02f; scaleY = 1.02f })
            Row(verticalAlignment = Alignment.CenterVertically) {
                StepButton(Icons.Rounded.Remove, enabled = amount > 1) { amount = (amount - 1).coerceAtLeast(1) }
                Column(Modifier.width(170.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    AnimatedContent(amount, transitionSpec = {
                        val up = targetState > initialState
                        (slideInVertically { if (up) it / 2 else -it / 2 } + fadeIn()) togetherWith (slideOutVertically { if (up) -it / 2 else it / 2 } + fadeOut())
                    }, label = "amount") { value ->
                        Text(formatNumber(value), style = aqraStyle(76f, Weight.heavy, Palette.brand))
                    }
                    // A unit label under the large number, read the same whatever the number.
                    Text(stringResource(R.string.pages_a_day), style = aqraStyle(15f, Weight.bold, Palette.ink))
                }
                StepButton(Icons.Rounded.Add, enabled = amount < 40) { amount = (amount + 1).coerceAtMost(40) }
            }
            AqraChip("🗓️", Palette.peach, Modifier.graphicsLayer { translationY = 132.dp.toPx(); rotationZ = -3f }) {
                val days = cycleDays(memorizedPages, amount)
                Text(pluralStringResource(R.plurals.a_full_revision_every_n_days, days, days), style = ChipText)
            }
            androidx.compose.animation.AnimatedVisibility(amount != suggested, Modifier.graphicsLayer { translationY = (-128).dp.toPx(); rotationZ = 4f },
                enter = scaleIn(initialScale = 0.5f) + fadeIn(), exit = scaleOut(targetScale = 0.5f) + fadeOut()) {
                AqraChip("✨", Palette.butter, Modifier.pressable { amount = suggested }) {
                    Text(stringResource(R.string.suggested_n, suggested), style = ChipText)
                }
            }
        }
        TwoLineHeadline(stringResource(R.string.how_much_will_you), stringResource(R.string.revise_each_day_q), modifier = Modifier.padding(top = 8.dp))
        Spacer(Modifier.weight(1f))
        BrandButton(stringResource(if (isEditor) R.string.save else R.string.begin), Modifier.widthIn(max = 520.dp).padding(top = 24.dp)) {
            onDone(amount)
        }
    }
}

/** − or +: a white circle; holding it keeps stepping. */
@Composable
fun StepButton(icon: androidx.compose.ui.graphics.vector.ImageVector, enabled: Boolean, size: androidx.compose.ui.unit.Dp = 58.dp, onStep: () -> Unit) {
    val step by rememberUpdatedState(onStep)
    val label = if (icon == Icons.Rounded.Add) "+" else "−"
    Box(
        Modifier
            .size(size)
            .softShadow(CircleShape, strength = 1.2f, radius = 12.dp, y = 6.dp)
            .background(Color.White, CircleShape)
            .semantics { role = Role.Button; contentDescription = label; onClick { step(); true } }
            .pointerInput(enabled) {
                if (!enabled) return@pointerInput
                awaitEachGesture {
                    awaitFirstDown()
                    step()
                    // Held down, it repeats, faster after a moment.
                    var wait = 450L
                    while (true) {
                        val ended = withTimeoutOrNull(wait) {
                            waitForUpOrCancellation()
                            true
                        }
                        if (ended == true) break
                        step()
                        wait = 110L
                    }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = if (enabled) Palette.brand else Palette.inkSoft.copy(alpha = 0.4f), modifier = Modifier.size(size * 0.48f))
    }
}
