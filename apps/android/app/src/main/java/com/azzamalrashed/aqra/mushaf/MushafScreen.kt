package com.azzamalrashed.aqra.mushaf

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.systemBarsIgnoringVisibility
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.List
import androidx.compose.material.icons.automirrored.rounded.Undo
import androidx.compose.material.icons.outlined.Verified
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Palette
import androidx.compose.material.icons.rounded.Verified
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.memorization.MarkingSession
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.components.FloatingCapsule
import com.azzamalrashed.aqra.ui.components.FloatingPanel
import com.azzamalrashed.aqra.ui.components.MarkingButton
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import androidx.compose.foundation.layout.height
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.arabicDigits
import com.azzamalrashed.aqra.ui.util.factSeparator
import com.azzamalrashed.aqra.ui.util.ARABIC_SEPARATOR
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/**
 * The Mushaf, opened full screen from the home on the last page read, and turned like a book (right to left). On a
 * wide screen in landscape it shows two facing pages, odd on the right, as in the printed Madinah Mushaf.
 */
@Composable
fun MushafScreen(
    app: AqraApp,
    store: MushafStore,
    startsMarking: Boolean,
    onClose: () -> Unit,
    onChooseJuzAndSurahs: () -> Unit,
) {
    val style = MushafStyle.current()
    val prefs = app.prefs
    var lastPage by prefs.lastPage
    var toolbarVisible by remember { mutableStateOf(startsMarking) }
    var showingIndex by remember { mutableStateOf(false) }
    var marking by remember { mutableStateOf(if (startsMarking) MarkingSession(app.memorization) else null) }
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()

    SystemBars(visible = toolbarVisible, lightIcons = style.dark)
    BackHandler {
        if (marking != null) app.memorization.saveNow()
        onClose()
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(style.paper)) {
        val facing = maxWidth > maxHeight && maxWidth >= 900.dp
        val pageCount = if (facing) MushafStore.PAGE_COUNT / 2 else MushafStore.PAGE_COUNT
        val pagerState = rememberPagerState(initialPage = if (facing) (lastPage - 1) / 2 else lastPage - 1) { pageCount }
        // Set when the toolbar itself moves the page, so the toolbar stays open.
        var movedByToolbar by remember { mutableStateOf(false) }

        fun go(page: Int) {
            movedByToolbar = page != lastPage
            scope.launch { pagerState.scrollToPage(if (facing) (page - 1) / 2 else page - 1) }
        }

        LaunchedEffect(pagerState, facing) {
            snapshotFlow { pagerState.settledPage }.distinctUntilChanged().collect { settled ->
                val page = if (facing) settled * 2 + 1 else settled + 1
                // Only a turn to another spread moves the page, so the left (even) page survives rotation.
                if (facing && (lastPage + 1) / 2 == settled + 1) return@collect
                if (page == lastPage) return@collect
                val juzChanged = store.page(page).juz != store.page(lastPage).juz
                lastPage = page
                haptics.performHapticFeedback(if (juzChanged) HapticFeedbackType.GestureThresholdActivate else HapticFeedbackType.SegmentTick)
                // Swiping to another page hides the toolbar; jumps made from the toolbar keep it open.
                if (movedByToolbar) movedByToolbar = false
                else if (toolbarVisible && marking == null) toolbarVisible = false
            }
        }

        val options = MushafPageOptions(
            tajweed = prefs.tajweed.value,
            topics = prefs.topics.value,
            memorization = app.memorization,
            marking = marking,
            // In marking mode, taps belong to the page and the toolbar stays.
            onTap = { if (marking == null) toolbarVisible = !toolbarVisible },
        )
        MushafPager(pagerState, facing, store, app.fonts, style, options)

        Column(Modifier.fillMaxSize()) {
            AnimatedVisibility(toolbarVisible, enter = fadeIn(), exit = fadeOut()) {
                MushafTopBar(store, lastPage, style, Modifier.statusBarsPadding(), leading = {
                    FloatingCapsule(style) {
                        MushafBarIcon(Icons.Rounded.Home, stringResource(R.string.home), style) {
                            if (marking != null) app.memorization.saveNow()
                            onClose()
                        }
                        MushafBarIcon(Icons.AutoMirrored.Rounded.List, stringResource(R.string.index), style) { showingIndex = true }
                    }
                }, trailing = {
                    FloatingCapsule(style) {
                        MushafBarIcon(if (marking == null) Icons.Outlined.Verified else Icons.Rounded.Verified, stringResource(R.string.my_memorization), style) {
                            marking = if (marking == null) MarkingSession(app.memorization) else null
                            toolbarVisible = true
                        }
                        MushafColorsMenu(app, style)
                    }
                })
            }
            Spacer(Modifier.weight(1f))
            AnimatedVisibility(toolbarVisible, enter = fadeIn(), exit = fadeOut()) {
                Box(Modifier.navigationBarsPadding()) {
                    val session = marking
                    if (session != null) {
                        val pages = if (facing) ((lastPage + 1) / 2).let { listOf(it * 2 - 1, it * 2) } else listOf(lastPage)
                        MarkingBar(app, store, session, pages, style, onChooseJuzAndSurahs) {
                            app.memorization.saveNow()
                            // Marking as part of setup, Done closes the Mushaf: the daily amount and the plan follow.
                            if (startsMarking) onClose() else marking = null
                        }
                    } else {
                        PageSlider(lastPage, style, ::go)
                    }
                }
            }
        }

        if (showingIndex) {
            MushafIndexSheet(store, lastPage, onDismiss = { showingIndex = false }) { page ->
                showingIndex = false
                go(page)
            }
        }
    }

    // A soft tap as ayat are marked or unmarked.
    val count = app.memorization.count
    var lastCount by remember { mutableStateOf(count) }
    LaunchedEffect(count) {
        if (marking != null && count != lastCount) haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
        lastCount = count
    }
}

/** The pages (or the spreads), right to left: page 1 sits on the right and the next comes in from the left. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MushafPager(
    pagerState: PagerState, facing: Boolean, store: MushafStore, fonts: MushafFonts, style: MushafStyle, options: MushafPageOptions,
    modifier: Modifier = Modifier, userScrollEnabled: Boolean = true,
) {
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        // The page lays out inside the screen's safe area, which stays put while the status bar hides and shows.
        HorizontalPager(
            pagerState,
            modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBarsIgnoringVisibility.union(WindowInsets.displayCutout)),
            beyondViewportPageCount = 1, userScrollEnabled = userScrollEnabled, key = { it },
        ) { index ->
            if (facing) {
                Row(Modifier.fillMaxSize()) {
                    MushafPageView(store.page(index * 2 + 1), store, fonts, style, options, Modifier.weight(1f).fillMaxSize())
                    Box(Modifier.width(1.dp).fillMaxSize().background(style.chrome.copy(alpha = 0.18f)))
                    MushafPageView(store.page(index * 2 + 2), store, fonts, style, options, Modifier.weight(1f).fillMaxSize())
                }
            } else {
                MushafPageView(store.page(index + 1), store, fonts, style, options, Modifier.fillMaxSize())
            }
        }
    }
}

/** The status bar hides with the Mushaf's bars, and its icons follow the page's paper. */
@Composable
fun SystemBars(visible: Boolean, lightIcons: Boolean) {
    val view = LocalView.current
    LaunchedEffect(visible, lightIcons) {
        val window = (view.context as? Activity)?.window ?: return@LaunchedEffect
        val controller = WindowCompat.getInsetsController(window, view)
        controller.isAppearanceLightStatusBars = !lightIcons
        controller.isAppearanceLightNavigationBars = !lightIcons
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (visible) controller.show(WindowInsetsCompat.Type.statusBars()) else controller.hide(WindowInsetsCompat.Type.statusBars())
    }
}

/** The Mushaf's top bar: the surah, juz' and page in the middle, with buttons on either side. */
@Composable
fun MushafTopBar(
    store: MushafStore,
    pageNumber: Int,
    style: MushafStyle,
    modifier: Modifier = Modifier,
    leading: @Composable () -> Unit,
    trailing: @Composable () -> Unit,
) {
    val page = store.page(pageNumber)
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Box(modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 2.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                leading()
                Spacer(Modifier.weight(1f).widthIn(min = 8.dp))
                trailing()
            }
            // The title stays centered, whatever the buttons on either side.
            FloatingCapsule(style, Modifier.align(Alignment.Center)) {
                Column(Modifier.padding(horizontal = 14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(store.surahNames[page.surah].orEmpty(), style = aqraStyle(15f, Weight.heavy, style.ink), maxLines = 1)
                    Text("الجزء ${arabicDigits(page.juz)}${ARABIC_SEPARATOR}الصفحة ${arabicDigits(page.number)}", style = aqraStyle(11f, Weight.semibold, style.chrome), maxLines = 1)
                }
            }
        }
    }
}

/** A button's icon in the Mushaf's top bar. */
@Composable
fun MushafBarIcon(icon: ImageVector, label: String, style: MushafStyle, onClick: () -> Unit) {
    Box(
        Modifier
            .size(42.dp)
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = style.barAccent, modifier = Modifier.size(22.dp))
    }
}

/** The tajweed and topic color switches, kept for the whole app. */
@Composable
fun MushafColorsMenu(app: AqraApp, style: MushafStyle) {
    var open by remember { mutableStateOf(false) }
    Box {
        MushafBarIcon(Icons.Rounded.Palette, stringResource(R.string.colors), style) { open = true }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            ColorToggle(stringResource(R.string.tajweed_colors), app.prefs.tajweed.value) { app.prefs.tajweed.value = it }
            ColorToggle(stringResource(R.string.topic_colors), app.prefs.topics.value) { app.prefs.topics.value = it }
        }
    }
}

@Composable
private fun ColorToggle(title: String, on: Boolean, onChange: (Boolean) -> Unit) {
    DropdownMenuItem(
        text = { Text(title, style = aqraStyle(15f, Weight.semibold)) },
        onClick = { onChange(!on) },
        trailingIcon = { if (on) Icon(Icons.Rounded.Check, contentDescription = null) },
    )
}

/** Dragging only moves the number; the Mushaf turns once, to the page let go on. Page 1 sits at the right end. */
@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun PageSlider(lastPage: Int, style: MushafStyle, onGo: (Int) -> Unit) {
    var dragging by remember { mutableStateOf<Float?>(null) }
    val shown = (dragging ?: lastPage.toFloat()).let { Math.round(it) }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 6.dp), contentAlignment = Alignment.Center) {
            FloatingCapsule(style, Modifier.widthIn(max = 620.dp).fillMaxWidth()) {
                Box(
                    Modifier
                        .padding(start = 4.dp)
                        .widthIn(min = 40.dp)
                        .background(style.barAccentFill, CircleShape)
                        .padding(horizontal = 8.dp, vertical = 6.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(arabicDigits(shown), style = aqraStyle(16f, Weight.heavy, style.barAccent))
                }
                val colors = SliderDefaults.colors(thumbColor = Color.White, activeTrackColor = style.barAccent, inactiveTrackColor = style.barAccentFill)
                Slider(
                    value = dragging ?: lastPage.toFloat(),
                    onValueChange = { dragging = it },
                    onValueChangeFinished = {
                        dragging?.let { onGo(Math.round(it)) }
                        dragging = null
                    },
                    valueRange = 1f..MushafStore.PAGE_COUNT.toFloat(),
                    colors = colors,
                    // A thin track and a round white thumb.
                    thumb = {
                        Box(Modifier.size(26.dp).softShadow(CircleShape, strength = 2f, radius = 4.dp, y = 2.dp).background(Color.White, CircleShape))
                    },
                    track = { state ->
                        SliderDefaults.Track(state, Modifier.height(4.dp), colors = colors, drawStopIndicator = null, thumbTrackGapSize = 0.dp)
                    },
                    modifier = Modifier.weight(1f).padding(start = 12.dp, end = 14.dp),
                )
            }
        }
    }
}

/** Marking mode's bar: what a tap does, the whole page (or both pages), juz' and surahs, and done. */
@Composable
private fun MarkingBar(
    app: AqraApp,
    store: MushafStore,
    marking: MarkingSession,
    pages: List<Int>,
    style: MushafStyle,
    onChooseJuzAndSurahs: () -> Unit,
    onDone: () -> Unit,
) {
    val ayahs = store.page(pages.first()).ayahs.first..store.page(pages.last()).ayahs.last
    // The app's own direction, for the bar's lines of text inside its Mushaf-ordered (right-to-left) layout.
    val direction = LocalLayoutDirection.current
    val unmarked = marking.unmarked
    // The undo is offered for a few seconds after each unmarking.
    LaunchedEffect(marking.unmarkedVersion) {
        val version = marking.unmarkedVersion
        delay(6_000)
        marking.expireUndo(version)
    }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        FloatingPanel(style) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                // While a range waits for its end, the bar says so.
                AnimatedContent(marking.rangeStart == null, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "marking") { idle ->
                    Text(
                        stringResource(if (idle) R.string.tap_the_ayat_youve_memorized else R.string.now_tap_the_last_ayah_of_the_range),
                        style = aqraStyle(17f, Weight.heavy, style.ink),
                    )
                }
                if (unmarked.isEmpty()) {
                    Text(
                        pluralStringResource(R.plurals.n_ayat_memorized, app.memorization.count, app.memorization.count) + factSeparator() +
                            stringResource(R.string.press_and_hold_an_ayah_to_mark_from_it_to),
                        style = aqraStyle(12f, Weight.semibold, style.chrome), maxLines = 1,
                    )
                } else {
                    // An unmarked ayah loses its record; for a moment it can be brought back as it was.
                    CompositionLocalProvider(LocalLayoutDirection provides direction) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(pluralStringResource(R.plurals.unmarked_n_ayat, unmarked.size, unmarked.size),
                                style = aqraStyle(12f, Weight.semibold, style.chrome), maxLines = 1)
                            Row(
                                Modifier.heightIn(min = 26.dp).background(style.barAccentFill, CircleShape)
                                    .pressable { marking.undo() }.padding(horizontal = 10.dp),
                                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Icon(Icons.AutoMirrored.Rounded.Undo, null, tint = style.barAccent, modifier = Modifier.size(14.dp))
                                Text(stringResource(R.string.undo), style = aqraStyle(12f, Weight.bold, style.barAccent))
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.size(14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MarkingButton(stringResource(if (pages.size > 1) R.string.both_pages else R.string.whole_page), style, Modifier.weight(1f)) {
                    marking.toggle(ayahs)
                }
                MarkingButton(stringResource(R.string.juz_surahs), style, Modifier.weight(1f), onClick = onChooseJuzAndSurahs)
                MarkingButton(stringResource(R.string.done), style, Modifier.weight(1f), prominent = true, onClick = onDone)
            }
        }
    }
}
