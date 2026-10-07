package com.azzamalrashed.aqra.ui

import android.provider.Settings
import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.spring
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.withFrameNanos
import kotlin.math.PI
import kotlin.math.pow

/**
 * A spring as SwiftUI describes one, by its response (seconds for one swing) and damping fraction, so the app moves
 * the way the iOS app does.
 */
fun <T> iosSpring(response: Float, damping: Float): AnimationSpec<T> =
    spring(dampingRatio = damping, stiffness = (2 * PI / response).pow(2).toFloat())

/** Whether the system asks for less motion (animations turned off in the developer or accessibility settings). */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

/** Seconds that tick on every frame while [running], for idle motion such as breathing rings; still otherwise. */
@Composable
fun rememberAnimationTime(running: Boolean): State<Double> = produceState(0.0, running) {
    if (!running) return@produceState
    val start = withFrameNanos { it }
    val offset = value
    while (true) {
        withFrameNanos { now -> value = offset + (now - start) / 1e9 }
    }
}
