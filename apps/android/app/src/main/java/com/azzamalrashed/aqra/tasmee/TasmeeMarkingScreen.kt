package com.azzamalrashed.aqra.tasmee

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.List
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.Confirm
import com.azzamalrashed.aqra.curriculum.Curriculum
import com.azzamalrashed.aqra.curriculum.StagePolicy
import com.azzamalrashed.aqra.mushaf.MushafBarIcon
import com.azzamalrashed.aqra.mushaf.MushafColorsMenu
import com.azzamalrashed.aqra.mushaf.MushafIndexSheet
import com.azzamalrashed.aqra.mushaf.MushafPageOptions
import com.azzamalrashed.aqra.mushaf.MushafPager
import com.azzamalrashed.aqra.mushaf.MushafTopBar
import com.azzamalrashed.aqra.mushaf.SystemBars
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionSession
import com.azzamalrashed.aqra.ui.components.FloatingCapsule
import com.azzamalrashed.aqra.ui.components.FloatingPanel
import com.azzamalrashed.aqra.ui.components.MarkingButton
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import kotlinx.coroutines.launch
import com.azzamalrashed.aqra.ui.util.factSeparator

/** What a listener marked: the pages heard, the ayat stumbled on with their types, and for a teacher, a stage test. */
data class TasmeeResult(val pages: List<Int>, val stumbles: List<Int>, val mistakes: List<Mistake>, val test: TasmeeRecord.StageTest?)

/**
 * Someone hearing a student — a teacher in a session, or a friend with the student's code: the Mushaf on the
 * listener's phone, turned page by page as the student recites. A tap marks an ayah the student stumbled on; pressing
 * and holding one says what kind of mistake it was; each page heard is marked as such; «سجّل التسميع» hands it all to
 * [onRecord], which writes it into the student's account, where their own app applies it. The listener's own
 * memorization colors are kept off the page: this is the student's page. [overlay] floats over the page's corner,
 * such as the student's video in a call.
 */
@Composable
fun TasmeeMarkingScreen(
    app: AqraApp,
    store: MushafStore,
    studentName: String,
    startPage: Int,
    allowsStageTest: Boolean = false,
    onClose: () -> Unit,
    overlay: @Composable () -> Unit = {},
    onRecord: (TasmeeResult) -> Unit,
) {
    val style = MushafStyle.current()
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val pager = rememberPagerState(initialPage = startPage.coerceIn(1, MushafStore.PAGE_COUNT) - 1) { MushafStore.PAGE_COUNT }
    val page = pager.settledPage + 1
    /** One revision per page visited, fully revealed, so a tap toggles a stumble. */
    val sessions = remember { mutableStateMapOf<Int, RevisionSession>() }
    var heard by remember { mutableStateOf(emptySet<Int>()) }
    /** The type of each stumble the listener classified; the rest are memorization errors. */
    var types by remember { mutableStateOf(emptyMap<Int, MistakeType>()) }
    var classifying by remember { mutableStateOf<Int?>(null) }
    var showingIndex by remember { mutableStateOf(false) }
    var confirmingLeave by remember { mutableStateOf(false) }
    var stageTest by remember { mutableStateOf<TasmeeRecord.StageTest?>(null) }

    fun prepare(number: Int) {
        if (number in sessions) return
        sessions[number] = RevisionSession(number, store.page(number).ayahs.toList()).also { it.revealAll() }
    }
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage + 1 }.collect { number ->
            prepare(number)
            haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        }
    }

    val stumbles = sessions.values.flatMap { it.stumbles }.toSet()
    // The pages heard: marked as such, or with a stumble on them.
    val recorded = heard + sessions.filterValues { it.stumbles.isNotEmpty() }.keys
    LaunchedEffect(stumbles.size) { if (stumbles.isNotEmpty()) haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick) }

    fun leave() = if (recorded.isEmpty()) onClose() else confirmingLeave = true
    BackHandler(onBack = ::leave)
    SystemBars(visible = true, lightIcons = style.dark)

    Column(Modifier.fillMaxSize().background(style.paper).statusBarsPadding().navigationBarsPadding()) {
        MushafTopBar(store, page, style, leading = {
            FloatingCapsule(style) {
                MushafBarIcon(Icons.Rounded.Close, stringResource(R.string.close), style, ::leave)
                MushafBarIcon(Icons.AutoMirrored.Rounded.List, stringResource(R.string.index), style) { showingIndex = true }
            }
        }, trailing = { FloatingCapsule(style) { MushafColorsMenu(app, style) } })
        Box(Modifier.weight(1f).padding(vertical = 6.dp)) {
            MushafPager(pager, facing = false, store, app.fonts, style, MushafPageOptions(
                tajweed = app.prefs.tajweed.value, topics = false, memorization = null,
                revisions = { sessions[it] },
                onAyahLongPress = { classifying = it },
            ), Modifier.fillMaxSize())
            Box(Modifier.align(Alignment.TopStart).padding(10.dp)) { overlay() }
        }
        val onThisPage = sessions[page]?.stumbles?.size ?: 0
        val pageHeard = page in recorded
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            FloatingPanel(style) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(studentName, style = aqraStyle(17f, Weight.heavy, style.ink), maxLines = 1)
                        Text(pluralStringResource(R.plurals.n_pages, recorded.size, recorded.size) + factSeparator() +
                            pluralStringResource(R.plurals.n_stumbles, stumbles.size, stumbles.size), style = aqraStyle(12f, Weight.semibold, style.chrome))
                    }
                    AnimatedVisibility(onThisPage > 0, enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
                        Box(Modifier.height(30.dp).background(style.stumble.copy(alpha = 0.6f), CircleShape).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                            Text(pluralStringResource(R.plurals.n_stumbles, onThisPage, onThisPage), style = aqraStyle(13f, Weight.bold, style.stumbleText))
                        }
                    }
                    if (allowsStageTest) StageTestMenu(stageTest, style) { stageTest = it }
                }
                Text(stringResource(R.string.tap_an_ayah_the_student_stumbled_on_press_and_hold), style = aqraStyle(12f, Weight.semibold, style.chrome),
                    textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MarkingButton(stringResource(if (pageHeard) R.string.heard else R.string.mark_as_heard), style, Modifier.weight(1f),
                        enabled = !(pageHeard && onThisPage > 0), leading = {
                            Icon(if (pageHeard) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null, tint = style.barAccent, modifier = Modifier.size(18.dp))
                        }) {
                        heard = if (page in heard) heard - page else heard + page
                    }
                    MarkingButton(stringResource(R.string.record_tasmee), style, Modifier.weight(1f), prominent = true, enabled = recorded.isNotEmpty()) {
                        val sorted = stumbles.sorted()
                        onRecord(TasmeeResult(recorded.sorted(), sorted, sorted.map { Mistake(it, types[it] ?: MistakeType.MEMORIZATION) }, stageTest))
                        onClose()
                    }
                }
            }
        }
    }

    classifying?.let { ayah ->
        MistakeDialog(stumbled = ayah in stumbles, onDismiss = { classifying = null }, onChoose = { type ->
            sessions.values.firstOrNull { it.covers(ayah) }?.markStumble(ayah)
            types = types + (ayah to type)
            classifying = null
        }, onUnmark = {
            sessions.values.filter { it.covers(ayah) }.forEach { it.clearStumble(ayah) }
            types = types - ayah
            classifying = null
        })
    }
    if (showingIndex) {
        MushafIndexSheet(store, page, onDismiss = { showingIndex = false }) { chosen ->
            showingIndex = false
            scope.launch { pager.scrollToPage(chosen - 1) }
        }
    }
    if (confirmingLeave) {
        Confirm(stringResource(R.string.leave_without_recording_q), stringResource(R.string.what_you_marked_will_be_lost), stringResource(R.string.leave),
            onDismiss = { confirmingLeave = false }, cancel = stringResource(R.string.stay), onConfirm = onClose)
    }
}

/** «ما نوع الخطأ؟»: the six kinds, and taking the stumble back. */
@Composable
private fun MistakeDialog(stumbled: Boolean, onDismiss: () -> Unit, onChoose: (MistakeType) -> Unit, onUnmark: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Color.White,
        title = { Text(stringResource(R.string.what_kind_of_mistake_q), style = aqraStyle(19f, Weight.heavy, Palette.ink)) },
        text = {
            Column {
                for (type in MistakeType.entries) {
                    Text(mistakeTitle(type), style = aqraStyle(16f, Weight.semibold, Palette.ink),
                        modifier = Modifier.fillMaxWidth().pressable(pressed = 0.98f) { onChoose(type) }.padding(vertical = 12.dp))
                    HorizontalDivider(color = Palette.lavender)
                }
                if (stumbled) {
                    Text(stringResource(R.string.not_a_mistake), style = aqraStyle(16f, Weight.semibold, Palette.danger),
                        modifier = Modifier.fillMaxWidth().pressable(pressed = 0.98f, onClick = onUnmark).padding(vertical = 12.dp))
                }
            }
        },
        confirmButton = { TextButton(onDismiss) { Text(stringResource(R.string.cancel), style = aqraStyle(15f, Weight.bold, Palette.brand)) } },
    )
}

/** A teacher can count this tasmee' as the test of a stage, with the mistakes allowed per page heard. */
@Composable
private fun StageTestMenu(test: TasmeeRecord.StageTest?, style: MushafStyle, onChange: (TasmeeRecord.StageTest?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Box(
            Modifier.height(30.dp).background(if (test == null) style.barAccentFill else Palette.brand, CircleShape)
                .pressable { open = true }.padding(horizontal = 12.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(if (test != null) stringResource(R.string.stage_n_test, test.stage) else stringResource(R.string.stage_test),
                style = aqraStyle(13f, Weight.bold, if (test == null) style.barAccent else Color.White))
        }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.not_a_test)) }, onClick = { onChange(null); open = false })
            for (stage in 1..Curriculum.STAGE_COUNT) {
                DropdownMenuItem(text = { Text(stringResource(R.string.stage_n, stage)) }, onClick = {
                    onChange(TasmeeRecord.StageTest(stage, test?.allowedMistakesPerPage ?: StagePolicy.STANDARD.allowedMistakesPerPage))
                    open = false
                }, trailingIcon = { if (test?.stage == stage) Icon(Icons.Rounded.CheckCircle, null, tint = Palette.brand) })
            }
            if (test != null) {
                HorizontalDivider()
                Text(stringResource(R.string.mistakes_allowed_per_page), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft), modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
                for (allowed in 0..3) {
                    DropdownMenuItem(text = { Text(pluralStringResource(R.plurals.n_mistakes_per_page, allowed, allowed)) }, onClick = {
                        onChange(test.copy(allowedMistakesPerPage = allowed))
                        open = false
                    }, trailingIcon = { if (test.allowedMistakesPerPage == allowed) Icon(Icons.Rounded.CheckCircle, null, tint = Palette.brand) })
                }
            }
        }
    }
}
