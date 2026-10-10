package com.azzamalrashed.aqra.home

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
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
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.ui.platform.LocalConfiguration
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AppTab
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.weekday
import com.azzamalrashed.aqra.memorization.MemorizationSetupScreen
import com.azzamalrashed.aqra.mushaf.MushafThumbnail
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.PlanItem
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.revision.cycleDays
import com.azzamalrashed.aqra.revision.RotationAdvisor
import com.azzamalrashed.aqra.account.InboxButton
import com.azzamalrashed.aqra.plan.PlanEditorScreen
import com.azzamalrashed.aqra.ui.components.ChipButton
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
import com.azzamalrashed.aqra.ui.components.AqraChip
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.ChipText
import com.azzamalrashed.aqra.ui.components.IconTile
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.Check
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.style.TextOverflow
import com.azzamalrashed.aqra.plan.PlanFormat
import com.azzamalrashed.aqra.plan.TodayPortion
import com.azzamalrashed.aqra.tasmee.Booking
import com.azzamalrashed.aqra.ui.util.weekdayName
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.sin

/**
 * The home: the منازل stairs on a glowing stage, then «اليوم» — the day's steps in order, each its own button: revise,
 * memorize, recite — then the Mushaf at the reader's ribbon. The Mushaf and the wird open full screen over it.
 */
@Composable
fun HomeScreen(app: AqraApp, store: MushafStore) {
    val overlays = LocalOverlays.current
    val memorization = app.memorization
    val revision = app.revision
    val haptics = LocalHapticFeedback.current
    var editingMemorization by remember { mutableStateOf(false) }
    var editingPlan by remember { mutableStateOf(false) }
    // «سجّلها»: a page of today's wird revised outside the app.
    var loggingOutside by remember { mutableStateOf(false) }

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
            TodayCard(
                app, store, Modifier.padding(top = 4.dp),
                onChooseMemorization = { editingMemorization = true },
                onEditPlan = { editingPlan = true },
                onLogOutside = { loggingOutside = true },
            )
            SuggestionCard(app, store)
            newTasmee(app)?.let { HeardCard(app, it) }
            MushafCard(app, store) { overlays.open(FullScreen.Mushaf(marking = false)) }
            ProgressLink(app)
        }
    }

    if (editingPlan) {
        AqraSheet(onDismiss = { editingPlan = false }) { PlanEditorScreen(app, store, isSetup = false) { editingPlan = false } }
    }
    if (editingMemorization) {
        AqraSheet(onDismiss = { editingMemorization = false }) {
            MemorizationSetupScreen(app, store, isSheet = true) { editingMemorization = false }
        }
    }
    if (loggingOutside) {
        AqraSheet(onDismiss = { loggingOutside = false }, fullHeight = false) {
            OutsideRevisionSheet(app, store, onDone = { loggingOutside = false }) { page ->
                loggingOutside = false
                overlays.open(FullScreen.Wird(page, outside = true))
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
    // On a short screen (a small phone, or any phone in landscape) the whole composition, glow and chips included, is
    // drawn smaller, so today's wird and its button are on the first screen.
    val scale = if (LocalConfiguration.current.screenHeightDp < 700) 0.76f else 1f
    Box(Modifier.fillMaxWidth().height(360.dp * scale), contentAlignment = Alignment.Center) {
    Box(Modifier.fillMaxWidth().requiredHeight(360.dp).graphicsLayer { scaleX = scale; scaleY = scale }, contentAlignment = Alignment.Center) {
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

// MARK: - Today

/** What's left of today's wird: the pages not yet revised, the first of them leading. */
private fun remaining(revision: RevisionStore): List<PlanItem> = revision.plan?.items?.filter { !it.done }.orEmpty()

/** Whether there's a wird today: something memorized, and pages in today's plan. */
private fun revisesToday(app: AqraApp): Boolean = app.memorization.count > 0 && app.revision.plan?.items?.isNotEmpty() == true

@Composable
private fun cycleLine(app: AqraApp, store: MushafStore): String {
    val pages = RevisionStore.memorizedPages(store, app.memorization).size
    val days = cycleDays(pages, app.revision.effectiveDailyPages(pages))
    return pluralStringResource(R.plurals.a_full_revision_every_n_days, days, days)
}

/** «اليوم»: the day's steps in order, each its own button: revise, memorize, recite. */
@Composable
private fun TodayCard(
    app: AqraApp, store: MushafStore, modifier: Modifier,
    onChooseMemorization: () -> Unit, onEditPlan: () -> Unit, onLogOutside: () -> Unit,
) {
    val portion = if (app.plan.plan == null) null else app.plan.today(app.memorization, store)
    val revises = revisesToday(app)
    val steps = (if (revises) 1 else 0) + (if (portion is TodayPortion.Due || portion is TodayPortion.Done) 1 else 0)
    val done = (if (revises && app.revision.plan?.isComplete == true) 1 else 0) + (if (portion is TodayPortion.Done) 1 else 0)
    AqraCard(modifier.fillMaxWidth(), animated = true, padding = 0.dp, radius = 26.dp) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            IconTile("☀️", Palette.butter, size = 40.dp)
            Column(Modifier.weight(1f).semantics(mergeDescendants = true) { heading() }, verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(stringResource(R.string.today), style = aqraStyle(19f, Weight.heavy, Palette.ink))
                Text(stringResource(R.string.your_days_steps_in_order), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
            }
            if (steps > 0) {
                Box(Modifier.heightIn(min = 28.dp).background(Palette.lavender, CircleShape).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.n_of_n, done, steps), style = aqraStyle(13f, Weight.bold, Palette.brand))
                }
            }
        }
        ReviseStep(app, store, onChooseMemorization)
        AqraRowDivider()
        MemorizeStep(app, store, portion, onEditPlan)
        AqraRowDivider()
        ReciteStep(app)
        if (revises && remaining(app.revision).isNotEmpty()) {
            AqraRowDivider()
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(stringResource(R.string.revised_a_page_outside_the_app_q), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft), modifier = Modifier.weight(1f))
                ChipButton(stringResource(R.string.log_it), filled = false, onClick = onLogOutside)
            }
        }
    }
}

/** ١ Revise: today's wird, started or carried on; a tick once it's done. */
@Composable
private fun ReviseStep(app: AqraApp, store: MushafStore, onChooseMemorization: () -> Unit) {
    val overlays = LocalOverlays.current
    val plan = app.revision.plan
    val left = remaining(app.revision)
    val next = left.firstOrNull()
    when {
        app.memorization.count == 0 -> TodayStep(
            1, "📖", Palette.sky, stringResource(R.string.choose_what_youve_memorized),
            stringResource(R.string.your_daily_revision_starts_from_it), stringResource(R.string.choose), onClick = onChooseMemorization,
        )
        next != null && plan != null -> TodayStep(
            1, "🔁", Palette.sky, stringResource(R.string.revise_todays_wird),
            pluralStringResource(R.plurals.n_pages_from_s, left.size, left.size, store.surahNames[store.page(next.page).surah].orEmpty()) +
                factSeparator() + cycleLine(app, store),
            stringResource(if (plan.doneCount == 0) R.string.start else R.string.carry_on),
        ) { overlays.open(FullScreen.Wird(next.page)) }
        plan != null && plan.isComplete -> TodayStep(
            1, "✅", Palette.mint, pluralStringResource(R.plurals.you_revised_n_pages, plan.items.size, plan.items.size),
            stringResource(R.string.todays_wird_is_done_may_allah_bless_you), done = true,
        )
        else -> TodayStep(1, "🔁", Palette.sky, stringResource(R.string.nothing_to_revise_today), cycleLine(app, store))
    }
}

/** ٢ Memorize: today's portion of the plan, a rest day, or the invitation to a plan. */
@Composable
private fun MemorizeStep(app: AqraApp, store: MushafStore, today: TodayPortion?, onEditPlan: () -> Unit) {
    val overlays = LocalOverlays.current
    when (today) {
        null -> if (app.plan.plan?.paused == true) {
            TodayStep(2, "⏸️", Palette.lavender, stringResource(R.string.your_memorization_plan_is_paused),
                stringResource(R.string.resume_it_from_your_plan), stringResource(R.string.your_plan), onClick = onEditPlan)
        } else {
            TodayStep(2, "✍️", Palette.butter, stringResource(R.string.memorize_new_portions),
                stringResource(R.string.a_daily_amount_and_the_date_youd_complete_the_quran), stringResource(R.string.start), onClick = onEditPlan)
        }
        is TodayPortion.Due -> TodayStep(2, "✍️", Palette.butter, stringResource(R.string.memorize_todays_portion),
            PlanFormat.portion(today.ayahs, store), stringResource(R.string.memorize)) { overlays.open(FullScreen.Memorize(today.ayahs)) }
        is TodayPortion.Done -> TodayStep(2, "✅", Palette.mint, stringResource(R.string.memorized_today),
            PlanFormat.portion(today.portion.memorized, store), done = true)
        is TodayPortion.RestDay -> TodayStep(2, "🌙", Palette.lavender, stringResource(R.string.a_rest_day_from_new_memorization),
            stringResource(R.string.next_portion_s, weekdayName(today.next.weekday(ZoneId.systemDefault()), narrow = false)))
        TodayPortion.Complete -> TodayStep(2, "⭐️", Palette.butter, stringResource(R.string.every_ayah_is_memorized),
            stringResource(R.string.may_allah_bless_you), done = true)
    }
}

/** ٣ Recite: the next tasmee' booked, or where to book one. */
@Composable
private fun ReciteStep(app: AqraApp) {
    val booking = app.tasmee.nextBooking
    if (booking != null) {
        val live = app.tasmee.session(booking)
        val cancelled = live?.status == TasmeeSession.Status.CANCELLED
        TodayStep(
            3, "🎓", if (cancelled) Palette.rose else Palette.mint,
            if (cancelled) stringResource(R.string.tasmee_cancelled) else stringResource(R.string.your_tasmee_with_s, booking.teacherName),
            formatWhen((live?.startsAt ?: booking.startsAt).toInstant()) + factSeparator() + placeText(live?.let(::Booking) ?: booking),
            stringResource(R.string.open),
        ) { app.router.tab = AppTab.TASMEE }
    } else {
        TodayStep(3, "🎤", Palette.peach, stringResource(R.string.recite_to_a_sheikh_or_a_friend),
            stringResource(R.string.book_a_session_or_recite_to_a_friend_with_a), stringResource(R.string.book)) { app.router.tab = AppTab.TASMEE }
    }
}

/** A step of «اليوم»: its number on its icon, what it is, and one button for it, or a tick once it's done. */
@Composable
private fun TodayStep(
    number: Int, icon: String, tint: Color, title: String, detail: String,
    action: String? = null, done: Boolean = false, onClick: (() -> Unit)? = null,
) {
    val doneLabel = stringResource(R.string.done)
    Row(
        Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.pressable(pressed = 0.98f, onClick = onClick) else Modifier)
            .semantics(mergeDescendants = true) {}
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box {
            IconTile(icon, tint, size = 38.dp)
            Box(
                Modifier.align(Alignment.TopEnd).offset(x = 6.dp, y = (-6).dp).size(18.dp).background(Palette.brand, CircleShape)
                    .clearAndSetSemantics {},
                contentAlignment = Alignment.Center,
            ) {
                Text(formatNumber(number), style = aqraStyle(10f, Weight.heavy, Color.White))
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = aqraStyle(16f, Weight.heavy, if (done) Palette.inkSoft else Palette.ink), maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(detail, style = aqraStyle(12f, Weight.semibold, Palette.inkSoft), maxLines = 3, overflow = TextOverflow.Ellipsis)
        }
        if (done) {
            Box(Modifier.size(30.dp).background(Palette.mint, CircleShape).semantics { contentDescription = doneLabel }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Check, null, tint = Palette.brand, modifier = Modifier.size(16.dp))
            }
        } else if (action != null) {
            Box(
                Modifier.heightIn(min = 36.dp).background(Brush.verticalGradient(Palette.brandGradient), CircleShape).padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(action, style = aqraStyle(14f, Weight.bold, Color.White), maxLines = 1)
            }
        }
    }
}

/** «سجّلها»: a page of today's wird revised outside the app (in prayer, to a friend), clean or with stumbles. */
@Composable
private fun OutsideRevisionSheet(app: AqraApp, store: MushafStore, onDone: () -> Unit, onStumbles: (Int) -> Unit) {
    val pages = remaining(app.revision)
    Column(Modifier.fillMaxWidth().navigationBarsPadding(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(
            Modifier.fillMaxWidth().padding(top = 8.dp, start = 22.dp, end = 22.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            TwoLineHeadline(stringResource(R.string.revised_outside_the_app_q), stringResource(R.string.log_the_page), size = 24f)
            Text(stringResource(R.string.in_prayer_or_to_a_friend_it_counts_in_todays), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft), textAlign = TextAlign.Center)
        }
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            pages.forEach { item ->
                val page = store.page(item.page)
                AqraCard(Modifier.fillMaxWidth(), padding = 12.dp, radius = 20.dp) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Box(
                            Modifier.size(44.dp).background(StepFaces.forJuz(page.juz).first.copy(alpha = 0.6f), RoundedCornerShape(14.dp)),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(formatNumber(item.page), style = aqraStyle(17f, Weight.heavy, Palette.ink))
                        }
                        Text(store.surahNames[page.surah].orEmpty(), style = aqraStyle(15f, Weight.bold, Palette.ink), maxLines = 1,
                            overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        ChipButton(stringResource(R.string.no_stumbles), filled = true) {
                            val ayahs = page.ayahs.filter(app.memorization::isMemorized)
                            app.revision.record(item.page, ayahs, emptySet(), RevisionRecord.Source.OUTSIDE, app.memorization)
                            if (app.revision.plan?.items?.all { it.done } == true) onDone()
                        }
                        ChipButton(stringResource(R.string.with_stumbles), filled = false) { onStumbles(item.page) }
                    }
                }
            }
        }
    }
}

// MARK: - Cards

/** The Mushaf, open on the reader's ribbon (or the page last read). */
@Composable
private fun MushafCard(app: AqraApp, store: MushafStore, onOpen: () -> Unit) {
    val bookmark = app.reading.bookmark?.page
    val page = store.page(bookmark ?: app.prefs.lastPage.value)
    val interaction = remember { MutableInteractionSource() }
    AqraCard(
        Modifier.fillMaxWidth().pressScale(interaction)
            .combinedClickable(interaction, indication = null) {
                if (bookmark != null) app.prefs.lastPage.value = bookmark
                onOpen()
            },
        padding = 12.dp, radius = 24.dp,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            val shape = RoundedCornerShape(8.dp)
            MushafThumbnail(page, store, app.fonts, app.memorization,
                Modifier.size(40.dp, 63.dp).clip(shape).border(1.dp, MushafStyle.LIGHT.chrome.copy(alpha = 0.25f), shape))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(if (bookmark != null) R.string.your_bookmark else R.string.continue_reading), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                Text(store.surahNames[page.surah].orEmpty() + factSeparator() + stringResource(R.string.page_n, page.number),
                    style = aqraStyle(16f, Weight.heavy, Palette.ink), maxLines = 1)
            }
            IconTile(if (bookmark != null) "🔖" else "📖", if (bookmark != null) Palette.rose else Palette.sky, size = 40.dp)
        }
    }
}

/** Where the plan, the stages and the rewards are now. */
@Composable
private fun ProgressLink(app: AqraApp) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp).pressable(pressed = 0.98f) { app.router.tab = AppTab.PROGRESS },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
    ) {
        Text(stringResource(R.string.your_plan_stages_and_rewards_are_in_progress), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft),
            textAlign = TextAlign.Center, modifier = Modifier.weight(1f, fill = false))
        Spacer(Modifier.width(6.dp))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, null, tint = Palette.brand, modifier = Modifier.size(16.dp))
    }
}

// MARK: - Suggestions

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
