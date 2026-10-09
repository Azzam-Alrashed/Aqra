package com.azzamalrashed.aqra.plan

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.Confirm
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.weekday
import com.azzamalrashed.aqra.onboarding.OnboardingHeadline
import com.azzamalrashed.aqra.onboarding.OnboardingPageLayout
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.StepButton
import com.azzamalrashed.aqra.ui.art.AqraGlowRings
import com.azzamalrashed.aqra.ui.art.AqraStar
import com.azzamalrashed.aqra.ui.art.GlossyStairs
import com.azzamalrashed.aqra.ui.art.LeftToRight
import com.azzamalrashed.aqra.ui.art.Manazil
import com.azzamalrashed.aqra.ui.art.juzFace
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraChevron
import com.azzamalrashed.aqra.ui.components.AqraChip
import com.azzamalrashed.aqra.ui.components.ChipText
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.iosSpring
import com.azzamalrashed.aqra.ui.rememberReduceMotion
import com.azzamalrashed.aqra.ui.theme.Amiri
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.arabicDigits
import com.azzamalrashed.aqra.ui.util.firstWeekday
import com.azzamalrashed.aqra.ui.util.formatNumber
import com.azzamalrashed.aqra.ui.util.hijriMonth
import com.azzamalrashed.aqra.ui.util.weekdayName
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.ZoneId
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** How the plan is written across the app. */
object PlanFormat {
    /** «نصف وجه»: a daily amount in the Mushaf's own measure. */
    @Composable
    fun amount(lines: Int): String = when (lines) {
        4 -> stringResource(R.string.page)
        8 -> stringResource(R.string.page_2)
        11 -> stringResource(R.string.page_3)
        15 -> stringResource(R.string.s_1_page)
        19 -> stringResource(R.string.s_1_pages)
        23 -> stringResource(R.string.s_1_pages_2)
        else -> pluralStringResource(R.plurals.n_lines, lines, lines)
    }

    /** «الناس ١–٦ · الفلق ١–٥»: a portion's ayat, by surah, in the order they're memorized. */
    fun portion(ayahs: List<Int>, store: MushafStore): String {
        class Group(val surah: Int, val first: Int, var last: Int)
        val groups = ArrayList<Group>()
        for (ayah in ayahs) {
            val (surah, number) = store.reference(ayah)
            val last = groups.lastOrNull()
            if (last != null && last.surah == surah && last.last == number - 1) last.last = number else groups += Group(surah, number, number)
        }
        return groups.joinToString(" · ") { group ->
            val range = if (group.first == group.last) arabicDigits(group.first) else "${arabicDigits(group.first)}–${arabicDigits(group.last)}"
            "${store.surahNames[group.surah].orEmpty()} $range"
        }
    }

    /** «رجب ١٤٤٩»: a far date, by the Hijri month. */
    fun month(date: Moment): String = hijriMonth(date.toInstant())
}

// MARK: - Setting the plan

private const val PLAN_PAGES = 4

/**
 * «كم تحفظ يوميًا؟»: the personal plan, one question to a page in the onboarding's own style — how much a day, on
 * which days, where to begin — then the completion date they lead to, with the منازل stairs climbing to it. The last
 * step of setup, and later a sheet to change, pause or stop the plan.
 */
@Composable
fun PlanEditorScreen(app: AqraApp, store: MushafStore, isSetup: Boolean, onDone: (MemorizationPlan?) -> Unit) {
    val planStore = app.plan
    val policy = planStore.policy
    // The plan being changed: its completion date is shown beside the new one, and it can be paused or stopped.
    val current = if (isSetup) null else planStore.plan
    var draft by remember {
        mutableStateOf(current ?: MemorizationPlan(policy.defaultAmount, policy.defaultStudyDays,
            PlanStore.suggestedOrder(app.memorization, store)))
    }
    var confirmingStop by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(draft) { haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }
    val pager = rememberPagerState { PLAN_PAGES }
    val scope = rememberCoroutineScope()
    fun next() {
        scope.launch { pager.animateScrollToPage((pager.currentPage + 1).coerceAtMost(PLAN_PAGES - 1)) }
    }

    fun finish(plan: MemorizationPlan?) {
        // In setup, «ليس الآن» leaves no plan; outside it, only «إيقاف الخطة» removes one.
        if (plan != null || !isSetup) planStore.setPlan(plan)
        onDone(plan)
    }

    Box(Modifier.fillMaxSize().background(Palette.surface)) {
        HorizontalPager(pager, Modifier.fillMaxSize()) { page ->
            when (page) {
                0 -> AmountPage(draft.dailyLines, policy, isSetup, { draft = draft.copy(dailyLines = it) }, ::next)
                1 -> DaysPage(draft.studyDays, isSetup, { draft = draft.copy(studyDays = it) }, ::next)
                2 -> OrderPage(draft.order, isSetup, { draft = draft.copy(order = it) }, ::next)
                else -> FinishPage(
                    app, store, draft, current, isSetup, active = pager.settledPage == PLAN_PAGES - 1,
                    title = stringResource(if (current == null) R.string.start_my_plan else R.string.save),
                    onSave = { finish(draft.copy(paused = false)) },
                    extra = current?.let { plan ->
                        { Manage(plan, onPause = { finish(plan.copy(paused = !plan.paused)) }, onStop = { confirmingStop = true }) }
                    },
                )
            }
        }
        Box(Modifier.align(Alignment.TopEnd).then(if (isSetup) Modifier.safeDrawingPadding() else Modifier)) {
            if (isSetup) {
                Text(stringResource(R.string.not_now), style = aqraStyle(15f, Weight.semibold, Palette.inkSoft),
                    modifier = Modifier.pressable { finish(null) }.padding(horizontal = 20.dp, vertical = 10.dp))
            } else {
                val close = stringResource(R.string.close)
                Box(
                    Modifier.padding(horizontal = 18.dp, vertical = 12.dp).size(36.dp)
                        .softShadow(CircleShape, radius = 8.dp, y = 4.dp).background(Color.White, CircleShape)
                        .pressable { onDone(current) }.semantics { contentDescription = close },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Close, null, tint = Palette.inkSoft, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
    if (confirmingStop) {
        Confirm(
            stringResource(R.string.stop_your_plan_q), stringResource(R.string.what_youve_memorized_stays_and_its_revision_goes_on_you),
            stringResource(R.string.stop), onDismiss = { confirmingStop = false }, cancel = stringResource(R.string.keep_it),
        ) {
            confirmingStop = false
            finish(null)
        }
    }
}

/** «إيقاف مؤقت» and «إيقاف الخطة», under «حفظ» when changing a plan. */
@Composable
private fun Manage(plan: MemorizationPlan, onPause: () -> Unit, onStop: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
        Text(stringResource(if (plan.paused) R.string.resume else R.string.pause), style = aqraStyle(15f, Weight.semibold, Palette.brand),
            modifier = Modifier.pressable(onClick = onPause).padding(6.dp))
        Text(stringResource(R.string.stop_the_plan), style = aqraStyle(15f, Weight.semibold, Palette.danger),
            modifier = Modifier.pressable(onClick = onStop).padding(6.dp))
    }
}

// 1. How much a day

/** An open Mushaf whose lines light up, right page first, as far as the daily amount reaches, with − and + beneath. */
@Composable
private fun AmountPage(lines: Int, policy: PlanPolicy, inSetup: Boolean, onChange: (Int) -> Unit, onContinue: () -> Unit) {
    val options = policy.amountOptions
    val index = options.indexOf(lines).coerceAtLeast(0)
    val lit by animateFloatAsState(lines.toFloat(), iosSpring(0.7f, 0.85f), label = "lit")
    val amount = PlanFormat.amount(lines)
    val label = stringResource(R.string.daily_amount)
    OnboardingPageLayout(0, true, stringResource(R.string.continue_action), onContinue, pageCount = PLAN_PAGES, safeDrawing = inSetup, stage = {
        Box(Modifier.requiredSize(420.dp, 440.dp), contentAlignment = Alignment.Center) {
            AqraGlowRings(Modifier.graphicsLayer { translationY = (-40).dp.toPx() })
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(26.dp)) {
                Box {
                    OpenMushaf(lit)
                    AqraChip("📖", Palette.lavender, Modifier.align(Alignment.TopStart)
                        .graphicsLayer { translationX = (-26).dp.toPx(); translationY = (-22).dp.toPx(); rotationZ = -5f }) {
                        Text(pluralStringResource(R.plurals.n_lines, lines, lines), style = ChipText)
                    }
                }
                Row(Modifier.width(380.dp), verticalAlignment = Alignment.CenterVertically) {
                    StepButton(Icons.Rounded.Remove, enabled = index > 0) { if (index > 0) onChange(options[index - 1]) }
                    FittedText(amount, aqraStyle(36f, Weight.heavy, Palette.brand), minScale = 0.5f,
                        modifier = Modifier.weight(1f).padding(horizontal = 10.dp).semantics { contentDescription = "$label, $amount" })
                    StepButton(Icons.Rounded.Add, enabled = index < options.size - 1) { if (index < options.size - 1) onChange(options[index + 1]) }
                }
            }
        }
    }) { scale ->
        OnboardingHeadline(stringResource(R.string.how_much_will_you_memorize), stringResource(R.string.each_day_q),
            stringResource(R.string.a_little_every_day_and_the_review_engine_keeps_it), scale, true)
    }
}

/**
 * Two facing pages of the fifteen-line Mushaf. [lit] lines glow from the top of the right-hand page, each lighting
 * from right to left as Arabic is read, then on into the left-hand page.
 */
@Composable
private fun OpenMushaf(lit: Float) {
    LeftToRight {
        // The Mushaf opens right to left: the first page is on the right.
        Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            MushafSheet(first = 15, lit = lit, outerLeft = true)
            MushafSheet(first = 0, lit = lit, outerLeft = false)
        }
    }
}

@Composable
private fun MushafSheet(first: Int, lit: Float, outerLeft: Boolean) {
    val outer = 20.dp
    val inner = 5.dp
    val shape = RoundedCornerShape(
        topStart = if (outerLeft) outer else inner, bottomStart = if (outerLeft) outer else inner,
        topEnd = if (outerLeft) inner else outer, bottomEnd = if (outerLeft) inner else outer,
    )
    Canvas(
        Modifier.size(150.dp, 214.dp).softShadow(shape, strength = 1.2f, radius = 20.dp, y = 12.dp)
            .background(Color.White, shape).border(1.dp, Palette.lavender, shape).padding(horizontal = 18.dp, vertical = 16.dp),
    ) {
        val slot = size.height / 15
        val height = 5.dp.toPx()
        val corner = CornerRadius(height / 2)
        for (line in 0 until 15) {
            val y = slot * line + (slot - height) / 2
            drawRoundRect(Palette.lavender.copy(alpha = 0.7f), Offset(0f, y), Size(size.width, height), corner)
            val fill = (lit - (first + line)).coerceIn(0f, 1f)
            if (fill > 0f) {
                val width = maxOf(size.width * fill, height)
                drawRoundRect(
                    Brush.horizontalGradient(listOf(Palette.brand.copy(alpha = 0.75f), Palette.brand), startX = size.width - width, endX = size.width),
                    Offset(size.width - width, y), Size(width, height), corner,
                )
            }
        }
    }
}

// 2. Which days

/** The seven days set around the glowing rings in the week's reading order, the count of study days at the center. */
@Composable
private fun DaysPage(days: Set<Int>, inSetup: Boolean, onChange: (Set<Int>) -> Unit, onContinue: () -> Unit) {
    // The week from its first day in this locale, around the ring in the reading direction from the top.
    val first = firstWeekday()
    val week = (0 until 7).map { (first - 1 + it) % 7 + 1 }
    val turn = if (LocalLayoutDirection.current == LayoutDirection.Rtl) -1 else 1
    val count = pluralStringResource(R.plurals.n_days_a_week, days.size, days.size)
    OnboardingPageLayout(1, true, stringResource(R.string.continue_action), onContinue, pageCount = PLAN_PAGES, safeDrawing = inSetup, stage = {
        LeftToRight {
            Box(Modifier.requiredSize(420.dp, 440.dp), contentAlignment = Alignment.Center) {
                AqraGlowRings(Modifier.graphicsLayer { scaleX = 1.04f; scaleY = 1.04f })
                Column(Modifier.clearAndSetSemantics { contentDescription = count }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(formatNumber(days.size), style = aqraStyle(64f, Weight.heavy, Palette.brand))
                    Text(stringResource(R.string.a_week_2), style = aqraStyle(15f, Weight.bold, Palette.ink))
                }
                week.forEachIndexed { position, weekday ->
                    val angle = (-90.0 + turn * position * 360.0 / 7) * PI / 180
                    DayButton(weekday, on = weekday in days, Modifier.offset(x = (138 * cos(angle)).dp, y = (138 * sin(angle)).dp)) {
                        val on = weekday in days
                        onChange(if (on && days.size > 1) days - weekday else days + weekday)
                    }
                }
            }
        }
    }) { scale ->
        OnboardingHeadline(stringResource(R.string.which_days), stringResource(R.string.will_you_memorize_q),
            stringResource(R.string.revision_goes_on_every_day), scale, true)
    }
}

@Composable
private fun DayButton(weekday: Int, on: Boolean, modifier: Modifier, onToggle: () -> Unit) {
    val scale by animateFloatAsState(if (on) 1f else 0.88f, iosSpring(0.35f, 0.6f), label = "day")
    val name = weekdayName(weekday, narrow = false)
    Box(
        modifier.size(60.dp).graphicsLayer { scaleX = scale; scaleY = scale }
            .softShadow(CircleShape, strength = if (on) 2.5f else 0.8f, radius = if (on) 10.dp else 6.dp, y = if (on) 6.dp else 3.dp)
            .background(if (on) Brush.verticalGradient(Palette.brandGradient) else Brush.verticalGradient(listOf(Color.White, Color.White)), CircleShape)
            .border(1.5.dp, if (on) Color.White.copy(alpha = 0.25f) else Palette.lavender, CircleShape)
            .pressable(pressed = 0.94f, onClick = onToggle)
            .semantics { contentDescription = name; selected = on },
        contentAlignment = Alignment.Center,
    ) {
        Text(weekdayName(weekday, narrow = true), style = aqraStyle(20f, Weight.heavy, if (on) Color.White else Palette.inkSoft))
    }
}

// 3. Where to begin

/** Two Mushaf covers in their juz' colors; the one chosen stands forward. */
@Composable
private fun OrderPage(order: MemorizationPlan.Order, inSetup: Boolean, onChoose: (MemorizationPlan.Order) -> Unit, onContinue: () -> Unit) {
    val detail = stringResource(if (order == MemorizationPlan.Order.FROM_END) R.string.from_an_nas_back_toward_al_baqarah_each_surah_from
        else R.string.from_the_beginning_of_the_mushaf_in_its_order)
    OnboardingPageLayout(2, true, stringResource(R.string.continue_action), onContinue, pageCount = PLAN_PAGES, safeDrawing = inSetup, stage = {
        Box(Modifier.requiredSize(420.dp, 440.dp), contentAlignment = Alignment.Center) {
            AqraGlowRings()
            // The two overlap a little; offsets follow the reading direction, toward each other.
            Row(verticalAlignment = Alignment.CenterVertically) {
                Cover(order == MemorizationPlan.Order.FROM_END, "جزء عمّ", stringResource(R.string.from_juz_amma), juz = 30, tilt = -7f,
                    Modifier.offset(x = 7.dp)) { onChoose(MemorizationPlan.Order.FROM_END) }
                Cover(order == MemorizationPlan.Order.FROM_START, "البقرة", stringResource(R.string.from_al_baqarah), juz = 1, tilt = 7f,
                    Modifier.offset(x = (-7).dp)) { onChoose(MemorizationPlan.Order.FROM_START) }
            }
        }
    }) { scale ->
        OnboardingHeadline(stringResource(R.string.where_will_you), stringResource(R.string.begin_q), detail, scale, true)
    }
}

@Composable
private fun Cover(selected: Boolean, title: String, label: String, juz: Int, tilt: Float, modifier: Modifier, onChoose: () -> Unit) {
    val face = juzFace(juz)
    val shape = RoundedCornerShape(22.dp)
    val spring = iosSpring<Float>(0.45f, 0.68f)
    val scale by animateFloatAsState(if (selected) 1.04f else 0.88f, spring, label = "cover")
    val rotation by animateFloatAsState(if (selected) tilt * 0.3f else tilt, spring, label = "tilt")
    val shown by animateFloatAsState(if (selected) 1f else 0.8f, spring, label = "alpha")
    Column(
        modifier.zIndex(if (selected) 1f else 0f)
            .graphicsLayer { scaleX = scale; scaleY = scale; rotationZ = rotation; alpha = shown }
            .pressable(onClick = onChoose)
            .semantics(mergeDescendants = true) { this.selected = selected },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.size(158.dp, 214.dp).softShadow(shape, strength = if (selected) 3f else 1.2f, radius = if (selected) 22.dp else 10.dp,
            y = if (selected) 14.dp else 6.dp)) {
            Box(Modifier.matchParentSize().background(Brush.verticalGradient(listOf(face.first, face.second)), shape))
            Box(Modifier.matchParentSize().padding(3.dp)
                .background(Brush.verticalGradient(0f to Color.White.copy(alpha = 0.55f), 0.5f to Color.White.copy(alpha = 0f)), shape))
            Box(Modifier.matchParentSize().padding(10.dp).border(1.5.dp, Color.White.copy(alpha = 0.75f), shape))
            Column(Modifier.align(Alignment.Center).clearAndSetSemantics {}, horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                AqraStar(Modifier.size(26.dp))
                Text(title, style = TextStyle(fontFamily = Amiri, fontWeight = FontWeight.Bold, fontSize = 34.sp, color = Palette.ink))
            }
            if (selected) {
                Box(
                    Modifier.align(Alignment.TopEnd).offset(x = 10.dp, y = (-10).dp).size(34.dp)
                        .background(Palette.brand, CircleShape).border(3.dp, Color.White, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(17.dp))
                }
            }
        }
        Box(
            Modifier.heightIn(min = 38.dp).background(if (selected) Palette.brand else Color.White, CircleShape).padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(label, style = aqraStyle(15f, Weight.bold, if (selected) Color.White else Palette.brand), maxLines = 1)
        }
    }
}

// 4. The finish

/**
 * The completion date the choices lead to, with the منازل stairs climbing from what's memorized to the star — and,
 * when a plan is being changed, the date it led to before.
 */
@Composable
private fun FinishPage(
    app: AqraApp, store: MushafStore, plan: MemorizationPlan, previous: MemorizationPlan?, inSetup: Boolean, active: Boolean,
    title: String, onSave: () -> Unit, extra: (@Composable () -> Unit)?,
) {
    val remaining = PlanStore.remainingLines(app.memorization, store)
    val now = remember { Moment.now() }
    val date = PlanStore.estimate(plan, remaining, null, now)
    val before = previous?.let { PlanStore.estimate(it, remaining, null, now) }
    // The earlier date, only when the change moves the completion to another month.
    val moved = before?.takeIf { date != null && PlanFormat.month(it) != PlanFormat.month(date) }
    val reduceMotion = rememberReduceMotion()
    val haptics = LocalHapticFeedback.current
    val climb = remember { Animatable(0f) }
    LaunchedEffect(active) {
        if (!active) return@LaunchedEffect
        climb.snapTo((app.memorization.quranShare(store) * Manazil.STEP_COUNT).toFloat())
        if (reduceMotion) {
            climb.snapTo(Manazil.STEP_COUNT.toFloat())
            return@LaunchedEffect
        }
        delay(250)
        launch { climb.animateTo(Manazil.STEP_COUNT.toFloat(), tween(1600, easing = FastOutSlowInEasing)) }
        delay(1300)
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
    }
    val mirror = if (LocalLayoutDirection.current == LayoutDirection.Rtl) -1f else 1f
    val summary = PlanFormat.amount(plan.dailyLines) + stringResource(R.string.fact_separator) +
        pluralStringResource(R.plurals.n_days_a_week, plan.studyDays.size, plan.studyDays.size)
    OnboardingPageLayout(3, true, title, onSave, pageCount = PLAN_PAGES, safeDrawing = inSetup, extra = extra, stage = {
        Box(Modifier.requiredSize(420.dp, 440.dp), contentAlignment = Alignment.Center) {
            AqraGlowRings(Modifier.graphicsLayer { scaleX = 1.1f; scaleY = 1.1f }, glow = listOf(Palette.butter, Palette.peach.copy(alpha = 0.5f)))
            GlossyStairs(climb.value, Modifier.graphicsLayer { scaleX = 1.15f; scaleY = 1.15f })
            AnimatedVisibility(moved != null, enter = scaleIn(initialScale = 0.5f) + fadeIn(), exit = scaleOut(targetScale = 0.5f) + fadeOut(),
                modifier = Modifier.graphicsLayer { translationX = 70.dp.toPx(); translationY = 150.dp.toPx(); rotationZ = -4f * mirror }) {
                // Beneath the stairs, away from their low end.
                AqraChip("🗓️", Palette.lavender) {
                    Text(stringResource(R.string.before_s, moved?.let { PlanFormat.month(it) }.orEmpty()), style = ChipText)
                }
            }
        }
    }) { scale ->
        if (date != null) {
            OnboardingHeadline(stringResource(R.string.youll_finish_god_willing), stringResource(R.string.in_s, inMonth(date)), summary, scale, true)
        } else {
            OnboardingHeadline(stringResource(R.string.youve_memorized), stringResource(R.string.the_whole_quran_2), "", scale, true)
        }
    }
}

/** «في ذي الحجة ١٤٤٩»: the Hijri month to follow «في», which puts ذو in the genitive. */
private fun inMonth(date: Moment): String {
    val month = PlanFormat.month(date)
    return if (month.startsWith("ذو ")) "ذي " + month.removePrefix("ذو ") else month
}

// MARK: - Today's portion on the home

/**
 * Today's new memorization on the home: the portion and «احفظ», done for today, or a day of rest — with the date the
 * plan leads to. Without a plan, an invitation to make one.
 */
@Composable
fun PortionCard(app: AqraApp, store: MushafStore, onMemorize: (List<Int>) -> Unit, onEditPlan: () -> Unit) {
    val plan = app.plan
    AqraCard(Modifier.fillMaxWidth(), animated = true, padding = 14.dp, radius = 24.dp) {
        val today = plan.today(app.memorization, store)
        when {
            plan.plan == null -> Row(Modifier.fillMaxWidth().pressable(pressed = 0.98f, onClick = onEditPlan),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile("✍️", Palette.butter, size = 40.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(stringResource(R.string.memorize_new_portions), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                    Text(stringResource(R.string.a_daily_amount_and_the_date_youd_complete_the_quran), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                }
                AqraChevron()
            }
            today == null -> Row(Modifier.fillMaxWidth().pressable(pressed = 0.98f, onClick = onEditPlan),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile("⏸️", Palette.lavender, size = 40.dp)
                Text(stringResource(R.string.your_memorization_plan_is_paused), style = aqraStyle(15f, Weight.heavy, Palette.ink), modifier = Modifier.weight(1f))
                AqraChevron()
            }
            else -> PortionContent(app, store, today, onMemorize, onEditPlan)
        }
    }
}

@Composable
private fun PortionContent(app: AqraApp, store: MushafStore, today: TodayPortion, onMemorize: (List<Int>) -> Unit, onEditPlan: () -> Unit) {
    val (icon, tint) = when (today) {
        is TodayPortion.Due -> "✍️" to Palette.butter
        is TodayPortion.Done -> "✅" to Palette.mint
        is TodayPortion.RestDay -> "🌙" to Palette.lavender
        TodayPortion.Complete -> "⭐️" to Palette.butter
    }
    val title = when (today) {
        is TodayPortion.Due -> stringResource(R.string.todays_new_portion)
        is TodayPortion.Done -> stringResource(R.string.memorized_today)
        is TodayPortion.RestDay -> stringResource(R.string.a_rest_day_from_new_memorization)
        TodayPortion.Complete -> stringResource(R.string.every_ayah_is_memorized)
    }
    val detail = when (today) {
        is TodayPortion.Due -> PlanFormat.portion(today.ayahs, store)
        is TodayPortion.Done -> PlanFormat.portion(today.portion.memorized, store)
        is TodayPortion.RestDay -> stringResource(R.string.next_portion_s, weekdayName(today.next.weekday(ZoneId.systemDefault()), narrow = false))
        TodayPortion.Complete -> stringResource(R.string.may_allah_bless_you)
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile(icon, tint, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(title, style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                Text(detail, style = aqraStyle(16f, Weight.heavy, Palette.ink), maxLines = 2)
            }
            val label = stringResource(R.string.your_plan)
            Box(
                Modifier.size(30.dp).background(Palette.lavender, CircleShape).pressable(onClick = onEditPlan).semantics { contentDescription = label },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Rounded.Tune, null, tint = Palette.brand, modifier = Modifier.size(16.dp))
            }
        }
        if (today is TodayPortion.Due) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 46.dp).background(Brush.verticalGradient(Palette.brandGradient), CircleShape)
                    .pressable(pressed = 0.96f) { onMemorize(today.ayahs) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.AutoMirrored.Rounded.MenuBook, null, tint = Color.White, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text(stringResource(R.string.memorize), style = aqraStyle(16f, Weight.bold, Color.White))
            }
        }
        app.plan.completionDate(app.memorization, store)?.let { date ->
            Text(stringResource(R.string.your_expected_completion_god_willing_s, PlanFormat.month(date)), style = aqraStyle(12f, Weight.bold, Palette.brand))
        }
    }
}
