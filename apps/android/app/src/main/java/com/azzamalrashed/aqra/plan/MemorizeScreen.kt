package com.azzamalrashed.aqra.plan

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import com.azzamalrashed.aqra.ui.components.pressScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.mushaf.MemorizeFocus
import com.azzamalrashed.aqra.mushaf.MushafBarIcon
import com.azzamalrashed.aqra.mushaf.MushafColorsMenu
import com.azzamalrashed.aqra.mushaf.MushafPageOptions
import com.azzamalrashed.aqra.mushaf.MushafPageView
import com.azzamalrashed.aqra.mushaf.MushafTopBar
import com.azzamalrashed.aqra.mushaf.SystemBars
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.FloatingCapsule
import com.azzamalrashed.aqra.ui.components.FloatingPanel
import com.azzamalrashed.aqra.ui.components.MarkingButton
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumber

/**
 * Memorizing today's portion: its pages, with the portion standing out and the rest faded back. The student reads and
 * repeats it, hides ayat to recite them from memory, then «حفظته» starts its life in the revision engine — or «حفظت
 * جزءًا منه» and a tap on the last ayah memorized records just that part.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MemorizeScreen(app: AqraApp, store: MushafStore, portion: List<Int>, onClose: () -> Unit) {
    val style = MushafStyle.current()
    val haptics = LocalHapticFeedback.current
    val focus = remember(portion) { MemorizeFocus(portion) }
    var repetitions by remember { mutableIntStateOf(0) }
    /** The portion's pages, in Mushaf order. */
    val pages = remember(portion) {
        val pages = HashSet<Int>()
        for (ayah in portion) {
            val first = store.pageOfAyah(ayah)
            pages += first
            if (first < MushafStore.PAGE_COUNT && store.page(first + 1).ayahs.first == ayah) pages += first + 1
        }
        pages.sorted().ifEmpty { listOf(1) }
    }
    val pager = rememberPagerState { pages.size }
    LaunchedEffect(pager.currentPage) { haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }
    LaunchedEffect(focus.hidden) { haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }

    SystemBars(visible = true, lightIcons = style.dark)
    BackHandler(onBack = onClose)

    fun record(memorized: List<Int>) {
        app.plan.record(portion, memorized, store, app.memorization, app.revision)
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        onClose()
    }

    val options = MushafPageOptions(app.prefs.tajweed.value, topics = false, memorization = app.memorization, focus = focus)
    Column(Modifier.fillMaxSize().background(style.paper).statusBarsPadding().navigationBarsPadding()) {
        MushafTopBar(store, pages[pager.currentPage.coerceIn(0, pages.lastIndex)], style,
            leading = { FloatingCapsule(style) { MushafBarIcon(Icons.Rounded.Close, stringResource(R.string.close), style, onClose) } },
            trailing = { FloatingCapsule(style) { MushafColorsMenu(app, style) } })
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth().padding(vertical = 6.dp), key = { pages[it] }) { index ->
                MushafPageView(store.page(pages[index]), store, app.fonts, style, options, Modifier.fillMaxSize())
            }
        }
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            FloatingPanel(style) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    FittedText(PlanFormat.portion(portion, store), aqraStyle(17f, Weight.heavy, style.ink), minScale = 0.7f)
                    Text(
                        stringResource(if (focus.choosingEnd) R.string.tap_the_last_ayah_you_memorized else R.string.read_it_and_repeat_it_then_tap_an_ayah_to),
                        style = aqraStyle(12f, Weight.semibold, style.chrome), textAlign = TextAlign.Center, maxLines = 2,
                    )
                }
                Box(Modifier.size(12.dp))
                AnimatedContent(focus.choosingEnd, label = "choosing") { choosing ->
                    if (choosing) {
                        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            MarkingButton(stringResource(R.string.cancel), style, Modifier.weight(1f)) { focus.choosingEnd = false }
                            MarkingButton(stringResource(R.string.save_this_part), style, Modifier.weight(1f), prominent = true,
                                enabled = focus.memorizedPart.isNotEmpty()) { record(focus.memorizedPart) }
                        }
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                RepetitionsButton(repetitions, style, Modifier.weight(1f), onCount = {
                                    repetitions += 1
                                    haptics.performHapticFeedback(HapticFeedbackType.KeyboardTap)
                                }, onReset = { repetitions = 0 })
                                val allHidden = focus.hidden.size == focus.ayahs.size
                                MarkingButton(stringResource(if (allHidden) R.string.show_all else R.string.hide_all), style, Modifier.weight(1f)) {
                                    if (allHidden) focus.showAll() else focus.hideAll()
                                }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                MarkingButton(stringResource(R.string.only_part_of_it), style, Modifier.weight(1f)) { focus.choosingEnd = true }
                                MarkingButton(stringResource(R.string.i_memorized_it), style, Modifier.weight(1f), prominent = true) { record(portion) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Counts the repetitions; pressing and holding offers to start counting again. */
@Composable
private fun RepetitionsButton(count: Int, style: MushafStyle, modifier: Modifier, onCount: () -> Unit, onReset: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    val label = stringResource(R.string.repetitions_n, count)
    val interaction = remember { MutableInteractionSource() }
    Box(modifier) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 46.dp).pressScale(interaction, 0.96f).background(style.barAccentFill, CircleShape)
                .clip(CircleShape)
                .combinedClickable(interaction, indication = null, onLongClick = { menu = true }, onClick = onCount)
                .semantics { contentDescription = label },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
        ) {
            Icon(Icons.Rounded.Repeat, null, tint = style.barAccent, modifier = Modifier.size(18.dp))
            Box(Modifier.size(6.dp))
            Text(formatNumber(count), style = aqraStyle(15f, Weight.bold, style.barAccent))
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.start_counting_again), style = aqraStyle(15f, Weight.semibold)) },
                onClick = { menu = false; onReset() })
        }
    }
}
