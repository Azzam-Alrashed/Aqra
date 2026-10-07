package com.azzamalrashed.aqra.plan

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.MenuBook
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.account.Confirm
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraChevron
import com.azzamalrashed.aqra.ui.components.AqraChip
import com.azzamalrashed.aqra.ui.components.AqraSegmented
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipText
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.arabicDigits
import com.azzamalrashed.aqra.ui.util.firstWeekday
import com.azzamalrashed.aqra.ui.util.hijriMonth
import com.azzamalrashed.aqra.ui.util.weekdayName
import com.azzamalrashed.aqra.core.weekday
import java.time.ZoneId

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

/**
 * «كم تحفظ يوميًا؟»: the personal plan — how much new memorization a day, on which days, in which order — with the
 * completion date it leads to. Shown at the end of setup, and later to change the plan.
 */
@Composable
fun PlanEditorScreen(app: AqraApp, store: MushafStore, isSetup: Boolean, onDone: (MemorizationPlan?) -> Unit) {
    val planStore = app.plan
    val policy = planStore.policy
    var draft by remember {
        mutableStateOf(planStore.plan ?: MemorizationPlan(policy.defaultAmount, policy.defaultStudyDays,
            PlanStore.suggestedOrder(app.memorization, store)))
    }
    var confirmingStop by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    LaunchedEffect(draft) { haptics.performHapticFeedback(HapticFeedbackType.SegmentTick) }

    fun finish(plan: MemorizationPlan?) {
        // In setup, «ليس الآن» leaves no plan; outside it, only «إيقاف الخطة» removes one.
        if (plan != null || !isSetup) planStore.setPlan(plan)
        onDone(plan)
    }

    Column(Modifier.fillMaxSize().background(Palette.surface).then(if (isSetup) Modifier.safeDrawingPadding() else Modifier)) {
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(18.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                TwoLineHeadline(stringResource(R.string.how_much_will_you_memorize), stringResource(R.string.each_day_q), size = 30f,
                    modifier = Modifier.padding(top = if (isSetup) 28.dp else 24.dp))
                Text(stringResource(R.string.a_little_every_day_and_the_review_engine_keeps_it), style = aqraStyle(15f, Weight.medium, Palette.inkSoft),
                    textAlign = TextAlign.Center)
                AmountCard(draft.dailyLines, policy) { draft = draft.copy(dailyLines = it) }
                DaysCard(draft.studyDays) { draft = draft.copy(studyDays = it) }
                OrderCard(draft.order) { draft = draft.copy(order = it) }
                val remaining = PlanStore.remainingLines(app.memorization, store)
                val date = PlanStore.estimate(draft, remaining, null, Moment.now())
                Box(Modifier.padding(top = 4.dp)) {
                    if (date != null) {
                        AqraChip("🏁", Palette.mint) { Text(stringResource(R.string.your_expected_completion_god_willing_s, PlanFormat.month(date)), style = ChipText) }
                    } else {
                        AqraChip("⭐️", Palette.butter) { Text(stringResource(R.string.youve_memorized_the_whole_quran), style = ChipText) }
                    }
                }
            }
        }
        Column(
            Modifier.fillMaxWidth().background(Palette.surface.copy(alpha = 0.95f)).padding(horizontal = 24.dp).padding(top = 10.dp, bottom = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val current = planStore.plan
            BrandButton(stringResource(if (isSetup || current == null) R.string.start_my_plan else R.string.save), Modifier.widthIn(max = 520.dp)) {
                finish(draft.copy(paused = false))
            }
            if (isSetup) {
                Text(stringResource(R.string.not_now), style = aqraStyle(15f, Weight.semibold, Palette.brand),
                    modifier = Modifier.pressable { finish(null) }.padding(6.dp))
            } else if (current != null) {
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    Text(stringResource(if (current.paused) R.string.resume else R.string.pause), style = aqraStyle(15f, Weight.semibold, Palette.brand),
                        modifier = Modifier.pressable {
                            val changed = current.copy(paused = !current.paused)
                            planStore.setPlan(changed)
                            onDone(changed)
                        }.padding(6.dp))
                    Text(stringResource(R.string.stop_the_plan), style = aqraStyle(15f, Weight.semibold, Palette.danger),
                        modifier = Modifier.pressable { confirmingStop = true }.padding(6.dp))
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

@Composable
private fun CardLabel(icon: String, tint: Color, title: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        IconTile(icon, tint, size = 32.dp)
        Text(title, style = aqraStyle(16f, Weight.heavy, Palette.ink))
    }
}

@Composable
private fun AmountCard(lines: Int, policy: PlanPolicy, onChoose: (Int) -> Unit) {
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        CardLabel("✍️", Palette.butter, stringResource(R.string.daily_amount))
        Spacer(Modifier.size(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (row in policy.amountOptions.chunked(3)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (option in row) {
                        val selected = option == lines
                        Box(
                            Modifier.weight(1f).heightIn(min = 44.dp)
                                .background(if (selected) Brush.verticalGradient(Palette.brandGradient) else Brush.verticalGradient(listOf(Palette.lavender, Palette.lavender)), CircleShape)
                                .pressable(pressed = 0.96f) { onChoose(option) }
                                .semantics { this.selected = selected }
                                .padding(horizontal = 6.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            FittedText(PlanFormat.amount(option), aqraStyle(15f, Weight.bold, if (selected) Color.White else Palette.brand), minScale = 0.8f)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DaysCard(days: Set<Int>, onChange: (Set<Int>) -> Unit) {
    // The week from its first day in this locale, Saturday or Sunday or Monday.
    val first = firstWeekday()
    val week = (0 until 7).map { (first - 1 + it) % 7 + 1 }
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CardLabel("🗓️", Palette.peach, stringResource(R.string.study_days), Modifier.weight(1f))
            Text(pluralStringResource(R.plurals.n_days_a_week, days.size, days.size), style = aqraStyle(13f, Weight.bold, Palette.brand))
        }
        Spacer(Modifier.size(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (weekday in week) {
                val on = weekday in days
                val name = weekdayName(weekday, narrow = false)
                Box(
                    Modifier.weight(1f).size(42.dp).background(if (on) Palette.brand else Palette.lavender, CircleShape)
                        .pressable(pressed = 0.94f) { onChange(if (on && days.size > 1) days - weekday else days + weekday) }
                        .semantics { contentDescription = name; selected = on },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(weekdayName(weekday, narrow = true), style = aqraStyle(15f, Weight.heavy, if (on) Color.White else Palette.inkSoft))
                }
            }
        }
    }
}

@Composable
private fun OrderCard(order: MemorizationPlan.Order, onChoose: (MemorizationPlan.Order) -> Unit) {
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        CardLabel("🧭", Palette.sky, stringResource(R.string.where_to_go_next))
        Spacer(Modifier.size(12.dp))
        AqraSegmented(order, listOf(MemorizationPlan.Order.FROM_END to stringResource(R.string.from_juz_amma),
            MemorizationPlan.Order.FROM_START to stringResource(R.string.from_al_baqarah)), onChoose)
        Spacer(Modifier.size(12.dp))
        Text(
            stringResource(if (order == MemorizationPlan.Order.FROM_END) R.string.from_an_nas_back_toward_al_baqarah_each_surah_from
                else R.string.from_the_beginning_of_the_mushaf_in_its_order),
            style = aqraStyle(12f, Weight.semibold, Palette.inkSoft),
        )
    }
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
