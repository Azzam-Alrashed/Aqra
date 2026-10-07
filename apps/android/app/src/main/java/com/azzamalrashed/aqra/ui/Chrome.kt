package com.azzamalrashed.aqra.ui

import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AccountCircle
import androidx.compose.material.icons.rounded.BarChart
import androidx.compose.material.icons.rounded.Groups
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AppTab
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle

/** The tab bar's height (its items and the capsule's padding) and the gap below it, above the navigation bar. */
val TabBarHeight = 64.dp
val TabBarBottomPadding = 2.dp

/** The app's tab bar: a floating white capsule, the selected tab in a lavender pill that slides between them. */
@Composable
fun AqraTabBar(selection: AppTab, modifier: Modifier = Modifier, onSelect: (AppTab) -> Unit) {
    val haptics = LocalHapticFeedback.current
    Box(modifier.fillMaxWidth().navigationBarsPadding().padding(bottom = TabBarBottomPadding, start = 22.dp, end = 22.dp), contentAlignment = Alignment.Center) {
        BoxWithConstraints(
            Modifier
                .widthIn(max = 440.dp)
                .fillMaxWidth()
                .softShadow(CircleShape, strength = 1.4f, radius = 18.dp, y = 8.dp)
                .background(Color.White, CircleShape)
                .padding(5.dp),
        ) {
            val itemWidth = (maxWidth - 2.dp * (AppTab.entries.size - 1)) / AppTab.entries.size
            val index = AppTab.entries.indexOf(selection)
            val pillOffset by animateDpAsState((itemWidth + 2.dp) * index, spring(dampingRatio = 0.82f, stiffness = Spring.StiffnessMediumLow), label = "pill")
            Box(Modifier.offset { IntOffset(pillOffset.roundToPx(), 0) }.width(itemWidth).height(54.dp).background(Palette.lavender, CircleShape))
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                for (tab in AppTab.entries) {
                    val selected = tab == selection
                    val interaction = remember(tab) { MutableInteractionSource() }
                    Column(
                        Modifier
                            .width(itemWidth)
                            .height(54.dp)
                            .clickable(interaction, indication = null, role = Role.Tab) {
                                if (!selected) {
                                    haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                                    onSelect(tab)
                                }
                            }
                            .semantics { this.selected = selected },
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center,
                    ) {
                        val color = if (selected) Palette.brand else Palette.inkSoft
                        Icon(tab.icon, contentDescription = null, tint = color, modifier = Modifier.size(22.dp))
                        Spacer(Modifier.height(2.dp))
                        FittedText(stringResource(tab.title), aqraStyle(11f, Weight.bold, color), minScale = 0.8f)
                    }
                }
            }
        }
    }
}

private val AppTab.title: Int
    get() = when (this) {
        AppTab.HOME -> R.string.home
        AppTab.TASMEE -> R.string.tasmee
        AppTab.PROGRESS -> R.string.progress
        AppTab.ACCOUNT -> R.string.account
    }

private val AppTab.icon
    get() = when (this) {
        AppTab.HOME -> Icons.Rounded.Home
        AppTab.TASMEE -> Icons.Rounded.Groups
        AppTab.PROGRESS -> Icons.Rounded.BarChart
        AppTab.ACCOUNT -> Icons.Rounded.AccountCircle
    }

/** The space a scrolling page keeps at its end, so its last card stops above the floating tab bar. */
@Composable
fun tabBarSpace(): Dp = TabBarHeight + TabBarBottomPadding + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 24.dp

/**
 * A tab's scrolling page: centered and no wider than a phone's, starting below the status bar, its end clear of the
 * tab bar, and what scrolls up fading away under the status bar.
 */
@Composable
fun TabPage(modifier: Modifier = Modifier, top: Dp = 8.dp, content: @Composable ColumnScope.() -> Unit) {
    val statusBar = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    Box(modifier.fillMaxSize().background(Palette.surface)) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(top = statusBar + top, bottom = tabBarSpace()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().padding(horizontal = 22.dp), verticalArrangement = Arrangement.spacedBy(14.dp), content = content)
        }
        // What scrolls up fades away under the status bar instead of running into it.
        Box(
            Modifier
                .fillMaxWidth()
                .height(statusBar + 14.dp)
                .background(Brush.verticalGradient(listOf(Palette.surface, Palette.surface.copy(alpha = 0f)))),
        )
    }
}

/** A sheet over the screen, in the app's surface, opened all the way. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AqraSheet(onDismiss: () -> Unit, fullHeight: Boolean = true, content: @Composable ColumnScope.() -> Unit) {
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Palette.surface,
        contentWindowInsets = { WindowInsets(0) },
    ) {
        Column(if (fullHeight) Modifier.fillMaxHeight(0.96f) else Modifier, content = content)
    }
}
