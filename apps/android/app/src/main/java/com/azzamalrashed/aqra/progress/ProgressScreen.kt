package com.azzamalrashed.aqra.progress

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.curriculum.StageSheet
import com.azzamalrashed.aqra.curriculum.StagesSection
import com.azzamalrashed.aqra.plan.PlanEditorScreen
import com.azzamalrashed.aqra.plan.PlanFormat
import com.azzamalrashed.aqra.rewards.RewardsSection
import com.azzamalrashed.aqra.social.TogetherSection
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.TabPage
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumber
import com.azzamalrashed.aqra.ui.util.formatPercent
import com.azzamalrashed.aqra.ui.util.weekdayNarrow
import com.azzamalrashed.aqra.ui.util.weekdayWide
import java.time.ZoneId
import java.util.Date

/**
 * تقدّمي: the share of the Quran memorized, the revision streak, a few numbers, and every juz' at a glance — how much
 * of it is memorized and how strong.
 */
@Composable
fun ProgressScreen(app: AqraApp, store: MushafStore) {
    val memorization = app.memorization
    val revision = app.revision
    var editingPlan by remember { mutableStateOf(false) }
    var openedStage by remember { mutableStateOf<Int?>(null) }
    TabPage(top = 16.dp) {
        val share = memorization.quranShare(store)
        Column(Modifier.padding(bottom = 6.dp).semantics(mergeDescendants = true) {}) {
            Text(stringResource(R.string.your_progress), style = aqraStyle(30f, Weight.heavy, Palette.ink))
            Text(formatPercent(share) + " " + stringResource(R.string.of_the_quran), style = aqraStyle(30f, Weight.heavy, Palette.brand))
        }
        SharesCard(app, store)
        StreakCard(app)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            val weekStart = Moment.now().startOfDay(ZoneId.systemDefault()).plusDays(-6, ZoneId.systemDefault())
            Stat("📖", Palette.sky, formatNumber(memorization.count), stringResource(R.string.ayat_memorized), Modifier.weight(1f))
            Stat("🔁", Palette.mint, formatNumber(revision.history.count { it.date >= weekStart }), stringResource(R.string.pages_revised_this_week), Modifier.weight(1f))
            Stat("🌱", Palette.butter, memorization.averageStrength()?.let { formatPercent(it, 0) } ?: "—", stringResource(R.string.memorization_strength), Modifier.weight(1f))
        }
        AqraSectionTitle(stringResource(R.string.strength_by_juz), Modifier.padding(top = 10.dp))
        JuzGrid(app, store)
        Text(stringResource(R.string.the_fuller_a_juz_the_more_of_it_youve_memorized), style = aqraStyle(12f, Weight.medium, Palette.inkSoft))

        AqraSectionTitle(stringResource(R.string.your_plan), Modifier.padding(top = 10.dp))
        PlanCard(app, store) { editingPlan = true }

        AqraSectionTitle(stringResource(R.string.the_stages), Modifier.padding(top = 10.dp))
        StagesSection(app, store) { openedStage = it }

        RewardsSection(app)

        TogetherSection(app, store)
    }
    if (editingPlan) {
        AqraSheet(onDismiss = { editingPlan = false }) { PlanEditorScreen(app, store, isSetup = false) { editingPlan = false } }
    }
    openedStage?.let { stage -> StageSheet(app, store, stage) { openedStage = null } }
}

/** Kept apart: how much is memorized, how much of it is mastered, and how much a teacher heard clean. */
@Composable
private fun SharesCard(app: AqraApp, store: MushafStore) {
    val all = 0 until MushafStore.AYAH_COUNT
    val total = MushafStore.AYAH_COUNT.toDouble()
    val mastered = app.memorization.masteredCount(all) / total
    val verified = app.memorization.verifiedCount(all) / total
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        Row(Modifier.fillMaxWidth()) {
            Share(app.memorization.quranShare(store), stringResource(R.string.memorized), Palette.brand.copy(alpha = 0.45f), Modifier.weight(1f))
            Share(mastered, stringResource(R.string.mastered), Palette.brand, Modifier.weight(1f))
            Share(verified, stringResource(R.string.verified), Color(0xFF2E9B63), Modifier.weight(1f))
        }
    }
}

@Composable
private fun Share(value: Double, label: String, color: Color, modifier: Modifier) {
    Column(modifier.semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(64.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val stroke = 7.dp.toPx()
                val inset = stroke / 2
                val arc = Size(size.width - stroke, size.height - stroke)
                drawArc(Palette.lavender, 0f, 360f, false, Offset(inset, inset), arc, style = Stroke(stroke))
                drawArc(color, -90f, 360f * value.coerceIn(0.0, 1.0).toFloat(), false, Offset(inset, inset), arc, style = Stroke(stroke, cap = StrokeCap.Round))
            }
            Text(formatPercent(value, if (value > 0 && value < 0.01) 1 else 0), style = aqraStyle(14f, Weight.heavy, Palette.ink))
        }
        Text(label, style = aqraStyle(12f, Weight.bold, Palette.inkSoft))
    }
}

/** The plan in a line: the daily amount and days, the lines this week and the completion date; or the invitation. */
@Composable
private fun PlanCard(app: AqraApp, store: MushafStore, onOpen: () -> Unit) {
    val current = app.plan.plan
    AqraCard(Modifier.fillMaxWidth().pressable(onClick = onOpen), padding = 0.dp, radius = 24.dp) {
        if (current != null) {
            val week = Math.round(app.plan.lines(inLast = 7)).toInt()
            val lines = pluralStringResource(R.plurals.n_lines_this_week, week, week)
            val date = app.plan.completionDate(app.memorization, store)
            AqraRow(if (current.paused) "⏸️" else "✍️", Palette.butter,
                PlanFormat.amount(current.dailyLines) + " · " + pluralStringResource(R.plurals.n_days_a_week, current.studyDays.size, current.studyDays.size),
                detail = if (date != null) lines + " · " + stringResource(R.string.completion_s, PlanFormat.month(date)) else lines)
        } else {
            AqraRow("✍️", Palette.butter, stringResource(R.string.memorize_new_portions), detail = stringResource(R.string.a_daily_amount_and_the_date_youd_complete_the_quran))
        }
    }
}

@Composable
private fun StreakCard(app: AqraApp) {
    val streak = app.revision.streak()
    val days = app.revision.recentDays()
    val zone = ZoneId.systemDefault()
    val today = Moment.now().startOfDay(zone)
    AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            IconTile("🔥", Palette.peach, size = 40.dp)
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(pluralStringResource(R.plurals.n_days, streak, streak), style = aqraStyle(19f, Weight.heavy, Palette.ink))
                Text(stringResource(R.string.revision_streak), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
            }
        }
        Spacer(Modifier.height(14.dp))
        // The last seven days, oldest first in the reading direction, ending today.
        Row(Modifier.fillMaxWidth()) {
            days.forEachIndexed { index, revised ->
                val day = Date(today.plusDays((index - (days.size - 1)).toLong(), zone).epochMillis)
                val isToday = index == days.size - 1
                val state = stringResource(if (revised) R.string.revised else R.string.not_revised)
                val name = weekdayWide(day)
                Column(
                    Modifier.weight(1f).clearAndSetSemantics { contentDescription = name; stateDescription = state },
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Box(
                        Modifier
                            .size(34.dp)
                            .then(if (isToday) Modifier.border(2.dp, Palette.brand.copy(alpha = 0.35f), CircleShape) else Modifier)
                            .padding(4.dp)
                            .background(if (revised) Palette.brand else Palette.lavender, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (revised) Icon(Icons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
                    }
                    Text(weekdayNarrow(day), style = aqraStyle(11f, Weight.bold, if (isToday) Palette.brand else Palette.inkSoft))
                }
            }
        }
    }
}

@Composable
private fun Stat(icon: String, tint: Color, value: String, label: String, modifier: Modifier) {
    AqraCard(modifier.semantics(mergeDescendants = true) {}, padding = 12.dp, radius = 20.dp) {
        IconTile(icon, tint, size = 32.dp)
        Spacer(Modifier.height(8.dp))
        FittedText(value, aqraStyle(20f, Weight.heavy, Palette.ink), alignCenter = false, minScale = 0.7f)
        Spacer(Modifier.height(8.dp))
        Text(label, style = aqraStyle(11f, Weight.semibold, Palette.inkSoft), minLines = 2, maxLines = 2)
    }
}

@Composable
private fun JuzGrid(app: AqraApp, store: MushafStore) {
    AqraCard(Modifier.fillMaxWidth(), padding = 12.dp, radius = 24.dp) {
        for (row in (1..30).chunked(5)) {
            Row(Modifier.fillMaxWidth().padding(bottom = if (row.last() < 30) 8.dp else 0.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { JuzTile(app, store, it, Modifier.weight(1f)) }
            }
        }
    }
}

/** A juz' fills from the bottom with its band's color as far as it's memorized, deeper as its memorization is stronger. */
@Composable
private fun JuzTile(app: AqraApp, store: MushafStore, juz: Int, modifier: Modifier) {
    val memorization = app.memorization
    val range = store.juzAyahs[juz] ?: 0..0
    val memorized = memorization.memorizedCount(range)
    val share = memorized.toFloat() / range.count()
    val now = Moment.now()
    val strength = if (memorized == 0) 0.0 else range.sumOf { memorization.strength(it, now) ?: 0.0 } / memorized
    val (top, bottom) = StepFaces.forJuz(juz)
    val shape = RoundedCornerShape(14.dp)
    val label = stringResource(R.string.juz_n, juz)
    val value = formatPercent(share.toDouble(), 0) + " · " + formatPercent(strength, 0)
    Box(
        modifier
            .height(56.dp)
            .clip(shape)
            .background(Color.White)
            .drawBehind {
                val height = size.height * share
                drawRect(Brush.verticalGradient(listOf(top, bottom), startY = size.height - height, endY = size.height),
                    topLeft = Offset(0f, size.height - height), size = Size(size.width, height), alpha = 0.35f + 0.65f * strength.toFloat())
            }
            .border(1.2.dp, if (share > 0) Color.White.copy(alpha = 0.8f) else Palette.lavender, shape)
            .clearAndSetSemantics { contentDescription = label; stateDescription = value },
        contentAlignment = Alignment.Center,
    ) {
        Text(formatNumber(juz), style = aqraStyle(17f, Weight.heavy, if (share > 0) Palette.ink else Palette.inkSoft.copy(alpha = 0.7f)))
    }
}
