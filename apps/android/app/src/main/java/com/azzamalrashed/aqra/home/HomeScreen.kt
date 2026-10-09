package com.azzamalrashed.aqra.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AppTab
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.account.SignInButtons
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.memorization.MemorizationSetupScreen
import com.azzamalrashed.aqra.memorization.memorizedSummary
import com.azzamalrashed.aqra.mushaf.MushafThumbnail
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.DailyAmountScreen
import com.azzamalrashed.aqra.revision.DayPlan
import com.azzamalrashed.aqra.revision.PlanItem
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.revision.cycleDays
import com.azzamalrashed.aqra.revision.RotationAdvisor
import com.azzamalrashed.aqra.account.InboxButton
import com.azzamalrashed.aqra.curriculum.AssessmentStore
import com.azzamalrashed.aqra.curriculum.StageCard
import com.azzamalrashed.aqra.curriculum.StageSheet
import com.azzamalrashed.aqra.plan.PlanEditorScreen
import com.azzamalrashed.aqra.plan.PortionCard
import com.azzamalrashed.aqra.plan.TodayPortion
import com.azzamalrashed.aqra.ui.components.ChipButton
import com.azzamalrashed.aqra.tasmee.Booking
import com.azzamalrashed.aqra.tasmee.TasmeeRecord
import com.azzamalrashed.aqra.tasmee.TasmeeSession
import com.azzamalrashed.aqra.tasmee.placeText
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.FullScreen
import com.azzamalrashed.aqra.ui.LocalOverlays
import com.azzamalrashed.aqra.ui.TabPage
import com.azzamalrashed.aqra.ui.art.AqraGlowRings
import com.azzamalrashed.aqra.ui.art.GlossyStairs
import com.azzamalrashed.aqra.ui.art.Manazil
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraChevron
import com.azzamalrashed.aqra.ui.components.AqraChip
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipText
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.ProblemLine
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressScale
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.iosSpring
import com.azzamalrashed.aqra.ui.rememberAnimationTime
import com.azzamalrashed.aqra.ui.rememberReduceMotion
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumber
import com.azzamalrashed.aqra.ui.util.formatNumberList
import com.azzamalrashed.aqra.ui.util.formatPercent
import com.azzamalrashed.aqra.ui.util.formatWhen
import com.azzamalrashed.aqra.ui.util.hijriToday
import com.azzamalrashed.aqra.ui.util.factSeparator
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.sin

/**
 * The home: the منازل stairs on a glowing stage, today's wird and one button to start it, then the Mushaf where the
 * student left it, today's pages, and what they've memorized. The Mushaf and the wird open full screen over it.
 */
@Composable
fun HomeScreen(app: AqraApp, store: MushafStore) {
    val overlays = LocalOverlays.current
    val memorization = app.memorization
    val revision = app.revision
    val haptics = LocalHapticFeedback.current
    var editingMemorization by remember { mutableStateOf(false) }
    var editingAmount by remember { mutableStateOf(false) }
    var editingPlan by remember { mutableStateOf(false) }
    var openedStage by remember { mutableStateOf<Int?>(null) }

    // The entrance plays once: the stage opens, the stairs climb, the chips pop out and the rest rises.
    var entered by rememberSaveable { mutableStateOf(false) }
    var chipsOut by rememberSaveable { mutableStateOf(false) }
    val reduceMotion = rememberReduceMotion()
    val share = memorization.quranShare(store)
    val climb = remember { Animatable(if (entered) (share * Manazil.STEP_COUNT).toFloat() else 0f) }
    LaunchedEffect(share) {
        val target = (share * Manazil.STEP_COUNT).toFloat()
        if (!entered) {
            delay(80)
            entered = true
            if (reduceMotion) {
                climb.snapTo(target)
                chipsOut = true
                return@LaunchedEffect
            }
            kotlinx.coroutines.coroutineScope {
                launch { climb.animateTo(target, iosSpring(1.3f, 0.9f)) }
                delay(420)
                if (memorization.count > 0) {
                    chipsOut = true
                    haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
                }
            }
        } else {
            if (memorization.count > 0) chipsOut = true
            if (reduceMotion) climb.snapTo(target) else climb.animateTo(target, iosSpring(0.9f, 0.85f))
        }
    }
    val planComplete = revision.plan?.isComplete == true
    var wasComplete by remember { mutableStateOf(planComplete) }
    LaunchedEffect(planComplete) {
        if (planComplete && !wasComplete) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        wasComplete = planComplete
    }
    val shown by animateFloatAsState(if (entered) 1f else 0f, iosSpring(0.7f, 0.85f), label = "enter")

    TabPage(top = 8.dp) {
        Header(app)
        Stage(app, store, climb.value, chipsOut, entered)
        Column(
            Modifier.graphicsLayer { alpha = shown; translationY = (1 - shown) * 16.dp.toPx() },
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Headline(app, store, Modifier.padding(top = 4.dp))
            Action(app, store, Modifier.padding(top = 10.dp, bottom = 8.dp)) { editingMemorization = true }
            // Today's portion, or the invitation to a plan — not for a student who has memorized the whole Quran.
            if (app.plan.plan != null || memorization.count < MushafStore.AYAH_COUNT) {
                PortionCard(app, store, onMemorize = { overlays.open(FullScreen.Memorize(it)) }, onEditPlan = { editingPlan = true })
            }
            if (memorization.count > 0 || app.plan.plan != null) {
                val stage = currentStage(app, store)
                StageCard(app, store, stage) { openedStage = stage }
            }
            SuggestionCard(app, store)
            newTasmee(app)?.let { HeardCard(app, it) }
            app.tasmee.nextBooking?.let { TasmeeCard(app, it) }
            MushafCard(app, store) { overlays.open(FullScreen.Mushaf(marking = false)) }
            revision.plan?.takeIf { it.items.isNotEmpty() }?.let { PagesCard(app, store, it) }
            if (showsSaveProgress(app)) SaveProgressCard(app)
            MemorizationCard(app, store, onEditMemorization = { editingMemorization = true }, onEditAmount = { editingAmount = true })
        }
    }

    if (editingPlan) {
        AqraSheet(onDismiss = { editingPlan = false }) { PlanEditorScreen(app, store, isSetup = false) { editingPlan = false } }
    }
    openedStage?.let { stage -> StageSheet(app, store, stage) { openedStage = null } }
    if (editingMemorization) {
        AqraSheet(onDismiss = { editingMemorization = false }) {
            MemorizationSetupScreen(app, store, isSheet = true) { editingMemorization = false }
        }
    }
    if (editingAmount) {
        val pages = RevisionStore.memorizedPages(store, memorization).size
        AqraSheet(onDismiss = { editingAmount = false }) {
            DailyAmountScreen(pages, revision.effectiveDailyPages(pages), isEditor = true) {
                revision.setDailyPages(it)
                editingAmount = false
            }
        }
    }
}

@Composable
private fun Header(app: AqraApp) {
    val streak = app.revision.streak()
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(R.string.peace_be_upon_you), style = aqraStyle(20f, Weight.heavy, Palette.ink))
            Text(hijriToday(), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft))
        }
        if (streak > 0) {
            val label = pluralStringResource(R.plurals.revision_streak_n_days, streak, streak)
            AqraChip("🔥", Palette.peach, Modifier.semantics { contentDescription = label }) {
                Text(pluralStringResource(R.plurals.n_days, streak, streak), style = ChipText)
            }
        }
        if (AccountStore.isAvailable) InboxButton(app)
    }
}

/** The glowing rings, the stairs and the floating chips, laid out as one picture. */
@Composable
private fun Stage(app: AqraApp, store: MushafStore, climb: Float, chipsOut: Boolean, open: Boolean) {
    val reduceMotion = rememberReduceMotion()
    val time by rememberAnimationTime(!reduceMotion)
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    // Positions are a fixed composition, mirrored for left-to-right languages.
    val mirror = if (rtl) 1f else -1f
    val share = app.memorization.quranShare(store)
    val strength = app.memorization.averageStrength()
    val openness by animateFloatAsState(if (open) 1f else 0f, iosSpring(0.7f, 0.85f), label = "rings")
    val chips by animateFloatAsState(if (chipsOut) 1f else 0f, iosSpring(0.6f, 0.66f), label = "chips")
    Box(Modifier.fillMaxWidth().height(360.dp), contentAlignment = Alignment.Center) {
        // Behind the stage, so the glow spreads past its edges without widening the page.
        AqraGlowRings(Modifier.graphicsLayer { scaleX = 1.05f; scaleY = 1.05f }, breath = sin(time * 0.9).toFloat(), openness = openness)
        GlossyStairs(climb, Modifier.graphicsLayer { translationX = (8 * mirror).dp.toPx(); translationY = 6.dp.toPx() })
        if (app.memorization.count > 0) {
            // Each chip rests against its side of the stage and flies out to it from the middle.
            FloatingChip(0, Alignment.TopEnd, startX = 92f * mirror, y = -118f, tilt = -5f * mirror, progress = chips, time = time, mirror = mirror) {
                AqraChip("🪜", Palette.lavender) { Text(formatPercent(share) + " " + stringResource(R.string.of_the_quran), style = ChipText) }
            }
            if (strength != null) {
                FloatingChip(1, Alignment.TopStart, startX = -96f * mirror, y = 128f, tilt = 4f * mirror, progress = chips, time = time, mirror = mirror) {
                    AqraChip("🌱", Palette.mint) { Text(stringResource(R.string.memorization_strength) + " " + formatPercent(strength, 0), style = ChipText) }
                }
            }
        }
    }
}

/** A chip at its resting place against one side of the stage, after flying out from the middle. */
@Composable
private fun androidx.compose.foundation.layout.BoxScope.FloatingChip(
    index: Int, side: Alignment, startX: Float, y: Float, tilt: Float, progress: Float, time: Double, mirror: Float,
    content: @Composable () -> Unit,
) {
    val drift = if (progress > 0.5f) sin(time * (0.8 + index * 0.2) + index * 1.3).toFloat() * 5f else 0f
    Box(
        Modifier
            // The share rests on the right in Arabic and on the left in English; the strength on the other side.
            .align(if ((side == Alignment.TopEnd) == (mirror > 0)) AbsoluteAlignment.CenterRight else AbsoluteAlignment.CenterLeft)
            .padding(horizontal = 2.dp)
            .graphicsLayer {
                val s = 0.3f + 0.7f * progress
                scaleX = s; scaleY = s
                rotationZ = tilt * progress
                alpha = progress.coerceIn(0f, 1f)
                translationX = (-startX * (1 - progress)).dp.toPx()
                translationY = (y * progress + drift).dp.toPx()
            },
    ) { content() }
}

// MARK: - Today's wird

private fun remaining(revision: RevisionStore): List<PlanItem> = revision.plan?.items?.filter { !it.done }.orEmpty()

@Composable
private fun cycleLine(app: AqraApp, store: MushafStore): String {
    val pages = RevisionStore.memorizedPages(store, app.memorization).size
    val days = cycleDays(pages, app.revision.effectiveDailyPages(pages))
    return pluralStringResource(R.plurals.a_full_revision_every_n_days, days, days)
}

@Composable
private fun Headline(app: AqraApp, store: MushafStore, modifier: Modifier) {
    val plan = app.revision.plan
    val remaining = remaining(app.revision)
    Column(modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val journeyBegins = app.memorization.count == 0 && app.plan.plan != null
        when {
            journeyBegins -> TwoLineHeadline(stringResource(R.string.begin_your_journey), stringResource(R.string.with_todays_portion))
            app.memorization.count == 0 || plan == null || plan.items.isEmpty() ->
                TwoLineHeadline(stringResource(R.string.what_have_you_memorized), stringResource(R.string.of_the_quran_q))
            remaining.isNotEmpty() -> TwoLineHeadline(
                stringResource(R.string.your_revision_today),
                pluralStringResource(R.plurals.n_pages_from_s, remaining.size, remaining.size, store.surahNames[store.page(remaining.first().page).surah].orEmpty()),
            )
            else -> TwoLineHeadline(stringResource(R.string.todays_revision_is_done), stringResource(R.string.may_allah_bless_you))
        }
        Text(
            when {
                journeyBegins -> stringResource(R.string.every_ayah_you_memorize_is_a_step_up)
                app.memorization.count == 0 -> stringResource(R.string.choose_what_youve_memorized_to_start_climbing)
                else -> cycleLine(app, store)
            },
            style = aqraStyle(16f, Weight.medium, Palette.inkSoft), textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun Action(app: AqraApp, store: MushafStore, modifier: Modifier, onChooseMemorization: () -> Unit) {
    val overlays = LocalOverlays.current
    val next = remaining(app.revision).firstOrNull()
    val plan = app.revision.plan
    when {
        app.memorization.count == 0 && app.plan.plan != null -> Unit
        app.memorization.count == 0 -> BrandButton(stringResource(R.string.choose_what_youve_memorized), modifier, onClick = onChooseMemorization)
        next != null && plan != null -> BrandButton(
            stringResource(if (plan.doneCount == 0) R.string.start_todays_revision else R.string.continue_todays_revision), modifier,
        ) { overlays.open(FullScreen.Wird(next.page)) }
    }
}

// MARK: - Cards

/** The Mushaf, open on the page last read. */
@Composable
private fun MushafCard(app: AqraApp, store: MushafStore, onOpen: () -> Unit) {
    val page = store.page(app.prefs.lastPage.value)
    val interaction = remember { MutableInteractionSource() }
    AqraCard(
        Modifier.fillMaxWidth().pressScale(interaction)
            .combinedClickable(interaction, indication = null, onClick = onOpen),
        padding = 12.dp, radius = 24.dp,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            val shape = RoundedCornerShape(8.dp)
            MushafThumbnail(page, store, app.fonts, app.memorization,
                Modifier.size(40.dp, 63.dp).clip(shape).border(1.dp, MushafStyle.LIGHT.chrome.copy(alpha = 0.25f), shape))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.continue_reading), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                Text(store.surahNames[page.surah].orEmpty() + factSeparator() + stringResource(R.string.page_n, page.number),
                    style = aqraStyle(16f, Weight.heavy, Palette.ink), maxLines = 1)
            }
            IconTile("📖", Palette.sky, size = 40.dp)
        }
    }
}

@Composable
private fun PagesCard(app: AqraApp, store: MushafStore, plan: DayPlan) {
    AqraCard(Modifier.fillMaxWidth(), animated = true, padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            IconTile("📄", Palette.sky, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(stringResource(R.string.todays_pages), style = aqraStyle(19f, Weight.heavy, Palette.ink))
                if (!plan.isComplete) {
                    Text(stringResource(R.string.revised_a_page_outside_the_app_q_press_and_hold), style = aqraStyle(11f, Weight.semibold, Palette.inkSoft))
                }
            }
            Box(Modifier.height(28.dp).background(Palette.lavender, CircleShape).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.n_of_n, plan.doneCount, plan.items.size), style = aqraStyle(13f, Weight.bold, Palette.brand))
            }
        }
        Spacer(Modifier.height(14.dp))
        for (row in plan.items.chunked(3)) {
            Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { PageTile(app, store, it, Modifier.weight(1f)) }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** A page of today's wird, in its juz's band color: tap to revise it, press and hold if it was revised elsewhere. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun PageTile(app: AqraApp, store: MushafStore, item: PlanItem, modifier: Modifier) {
    val overlays = LocalOverlays.current
    val page = store.page(item.page)
    val (top, bottom) = StepFaces.forJuz(page.juz)
    val shape = RoundedCornerShape(16.dp)
    var menu by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    val haptics = LocalHapticFeedback.current
    val revised = stringResource(R.string.revised)
    Box(modifier) {
        Column(
            Modifier
                .fillMaxWidth()
                .height(62.dp)
                .pressScale(interaction)
                .clip(shape)
                .background(if (item.done) Brush.verticalGradient(listOf(top.copy(alpha = 0.14f), top.copy(alpha = 0.14f)))
                    else Brush.verticalGradient(listOf(top.copy(alpha = 0.6f), top.copy(alpha = 0.28f))))
                .border(1.dp, Color.White.copy(alpha = 0.8f), shape)
                .combinedClickable(interaction, indication = null,
                    onLongClick = { if (!item.done) { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menu = true } },
                    onClick = { overlays.open(FullScreen.Wird(item.page)) })
                .semantics { if (item.done) stateDescription = revised }
                .padding(horizontal = 6.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(formatNumber(item.page), style = aqraStyle(18f, Weight.heavy, if (item.done) Palette.inkSoft else Palette.ink))
            if (item.kind == PlanItem.Kind.FOLLOW_UP) {
                Text(stringResource(R.string.follow_up), style = aqraStyle(11f, Weight.semibold, Palette.warning), maxLines = 1)
            } else {
                Text(store.surahNames[page.surah].orEmpty(), style = aqraStyle(11f, Weight.semibold, Palette.inkSoft), maxLines = 1)
            }
        }
        AnimatedVisibility(item.done, Modifier.align(Alignment.TopEnd).padding(6.dp), enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
            Box(Modifier.size(16.dp).background(Color.White, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.CheckCircle, null, tint = bottom, modifier = Modifier.size(18.dp))
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.revised_outside_the_app), style = aqraStyle(15f, Weight.semibold)) },
                leadingIcon = { Icon(Icons.Rounded.CheckCircle, null) },
                onClick = {
                    menu = false
                    val ayahs = page.ayahs.filter(app.memorization::isMemorized)
                    app.revision.record(item.page, ayahs, emptySet(), RevisionRecord.Source.OUTSIDE, app.memorization)
                },
            )
            DropdownMenuItem(
                text = { Text(stringResource(R.string.revised_outside_the_app_with_stumbles), style = aqraStyle(15f, Weight.semibold)) },
                leadingIcon = { Icon(Icons.Rounded.ErrorOutline, null) },
                onClick = {
                    menu = false
                    overlays.open(FullScreen.Wird(item.page, outside = true))
                },
            )
        }
    }
}

// MARK: - The journey

/** The stage the student is in. */
private fun currentStage(app: AqraApp, store: MushafStore): Int {
    val plan = app.plan.plan
    val next = if (plan != null && !plan.paused) (app.plan.today(app.memorization, store) as? TodayPortion.Due)?.ayahs?.firstOrNull() else null
    return AssessmentStore.currentStage(next, app.memorization, store, app.assessments.passes)
}

/** Pages that keep slipping, suggested for extra follow-up. */
@Composable
private fun SuggestionCard(app: AqraApp, store: MushafStore) {
    var version by remember { mutableIntStateOf(0) }
    val dismissed = remember(version) { app.prefs.rotationDismissed.mapValues { Moment.ofEpochSeconds(it.value) } }
    val pages = RotationAdvisor.suggestions(store, app.memorization, app.revision, dismissed)
    AnimatedVisibility(pages.isNotEmpty(), enter = scaleIn(initialScale = 0.95f) + fadeIn(), exit = scaleOut(targetScale = 0.95f) + fadeOut()) {
        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile("🌿", Palette.mint, size = 40.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(stringResource(R.string.these_pages_keep_slipping), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                    Text(stringResource(R.string.pages_s_bring_them_back_tomorrow_to_make_them_firm, formatNumberList(pages)),
                        style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                }
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ChipButton(stringResource(R.string.not_now), filled = false) {
                    val now = Moment.now()
                    app.prefs.rotationDismissed = RotationAdvisor.dismiss(pages, dismissed, now).mapValues { it.value.epochSeconds }
                    version += 1
                }
                ChipButton(stringResource(R.string.add_to_follow_up), filled = true) {
                    RotationAdvisor.accept(pages, app.revision)
                    version += 1
                }
            }
        }
    }
}

// MARK: - Tasmee'

/** The next tasmee' booked, with a teacher: when and where, or that the teacher cancelled it. */
@Composable
private fun TasmeeCard(app: AqraApp, booking: Booking) {
    val live = app.tasmee.session(booking)
    val cancelled = live?.status == TasmeeSession.Status.CANCELLED
    AqraCard(Modifier.fillMaxWidth().pressable { app.router.tab = AppTab.TASMEE }.semantics(mergeDescendants = true) {}, padding = 12.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile("🎓", if (cancelled) Palette.rose else Palette.mint, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(if (cancelled) R.string.tasmee_cancelled else R.string.your_next_tasmee), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                Text(booking.teacherName, style = aqraStyle(16f, Weight.heavy, Palette.ink), maxLines = 1)
                Text(
                    formatWhen((live?.startsAt ?: booking.startsAt).toInstant()) + factSeparator() + placeText(live?.let(::Booking) ?: booking),
                    style = aqraStyle(12f, Weight.bold, if (cancelled) Palette.inkSoft else Palette.brand)
                        .copy(textDecoration = if (cancelled) TextDecoration.LineThrough else null),
                    maxLines = 1,
                )
            }
            AqraChevron()
        }
    }
}

/** A tasmee' applied in the last two days that the student hasn't closed yet. */
private fun newTasmee(app: AqraApp): TasmeeRecord? {
    val record = app.tasmee.history.firstOrNull { it.appliedAt != null } ?: return null
    if (record.id == app.prefs.seenTasmee.value || record.at < Moment.now() + (-2 * 86_400.0)) return null
    return record
}

/** What a teacher or a friend heard, now applied to the student's progress. */
@Composable
private fun HeardCard(app: AqraApp, record: TasmeeRecord) {
    val pages = record.pages.toSet().size
    val peer = record.kind == TasmeeRecord.Kind.PEER
    AqraCard(Modifier.fillMaxWidth().pressable { app.router.tab = AppTab.TASMEE }, padding = 12.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile(if (peer) "🤝" else "🎓", if (peer) Palette.peach else Palette.mint, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(pluralStringResource(if (peer) R.plurals.your_friend_heard_n_pages else R.plurals.your_teacher_heard_n_pages, pages, pages),
                    style = aqraStyle(16f, Weight.heavy, Palette.ink), maxLines = 1)
                Text(
                    if (record.kind == TasmeeRecord.Kind.SHEIKH && record.stumbles.isEmpty()) stringResource(R.string.no_stumbles_the_ayat_heard_are_verified)
                    else pluralStringResource(R.plurals.n_stumbles_added_to_your_revision, record.stumbles.size, record.stumbles.size),
                    style = aqraStyle(12f, Weight.semibold, Palette.brand), maxLines = 1,
                )
            }
            Box(
                Modifier.size(28.dp).background(Palette.lavender, CircleShape).pressable { app.prefs.seenTasmee.value = record.id },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.Close, stringResource(R.string.close), tint = Palette.brand, modifier = Modifier.size(16.dp))
            }
        }
    }
}

// MARK: - Saving progress

/** The invitation to sign in: only for an anonymous student, and only once they've revised, so it comes after something worth keeping. */
private fun showsSaveProgress(app: AqraApp): Boolean =
    AccountStore.isAvailable && app.account.profile?.isAnonymous == true && app.revision.revisedDays.isNotEmpty() &&
        System.currentTimeMillis() / 1000.0 > app.prefs.saveProgressSnoozedUntil.value

@Composable
private fun SaveProgressCard(app: AqraApp) {
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile("🪪", Palette.butter, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(stringResource(R.string.save_your_progress), style = aqraStyle(17f, Weight.heavy, Palette.ink))
                Text(stringResource(R.string.your_progress_is_only_on_this_device_until_you_sign), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
            }
            Box(
                Modifier.height(28.dp).background(Palette.lavender, CircleShape)
                    .pressable { app.prefs.saveProgressSnoozedUntil.value = System.currentTimeMillis() / 1000.0 + 7 * 86_400 }
                    .padding(horizontal = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(stringResource(R.string.later), style = aqraStyle(13f, Weight.bold, Palette.brand))
            }
        }
        Spacer(Modifier.height(14.dp))
        SignInButtons(app)
        app.account.problem?.let { ProblemLine(it, Modifier.padding(top = 10.dp)) }
    }
}

/** What's memorized and how much is revised each day, each opening its editor. */
@Composable
private fun MemorizationCard(app: AqraApp, store: MushafStore, onEditMemorization: () -> Unit, onEditAmount: () -> Unit) {
    val count = app.memorization.count
    AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
        AqraRow("✏️", Palette.butter,
            stringResource(if (count == 0) R.string.choose_what_youve_memorized else R.string.edit_what_youve_memorized),
            Modifier.pressable(pressed = 1f, onClick = onEditMemorization),
            detail = if (count == 0) null else memorizedSummary(app, store))
        if (count > 0) {
            AqraRowDivider()
            val pages = RevisionStore.memorizedPages(store, app.memorization).size
            val daily = app.revision.effectiveDailyPages(pages)
            AqraRow("🗓️", Palette.peach, pluralStringResource(R.plurals.n_pages_a_day, daily, daily),
                Modifier.pressable(pressed = 1f, onClick = onEditAmount), detail = cycleLine(app, store))
        }
    }
}
