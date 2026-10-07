package com.azzamalrashed.aqra.rewards

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraChip
import com.azzamalrashed.aqra.ui.components.AqraRow
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.ChipText
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.rememberReduceMotion
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.weekdayName
import com.azzamalrashed.aqra.core.weekday
import kotlinx.coroutines.delay
import java.time.ZoneId
import java.time.temporal.WeekFields
import java.util.Locale

@Composable
fun Achievement.title(): String = stringResource(
    when (this) {
        Achievement.FIRST_REVISION -> R.string.first_revision
        Achievement.FIRST_WIRD -> R.string.a_whole_days_wird
        Achievement.FIRST_PORTION -> R.string.first_new_portion
        Achievement.FIRST_JUZ -> R.string.a_whole_juz
        Achievement.FIRST_VERIFIED -> R.string.heard_clean_by_a_teacher
        Achievement.FIRST_PEER -> R.string.recited_to_a_friend
        Achievement.STREAK_7 -> R.string.s_7_days_in_a_row
        Achievement.STREAK_30 -> R.string.s_30_days_in_a_row
        Achievement.STREAK_100 -> R.string.s_100_days_in_a_row
        Achievement.FIRST_STAGE -> R.string.first_stage_passed
        Achievement.FIVE_STAGES -> R.string.five_stages_passed
        Achievement.WHOLE_QURAN -> R.string.the_whole_quran
    },
)

@Composable
fun Challenge.Kind.title(target: Int): String = when (this) {
    Challenge.Kind.WIRD_DAYS -> pluralStringResource(R.plurals.complete_the_wird_on_n_days, target, target)
    Challenge.Kind.PAGES_REVISED -> pluralStringResource(R.plurals.revise_n_pages, target, target)
    Challenge.Kind.LINES_MEMORIZED -> pluralStringResource(R.plurals.memorize_n_lines, target, target)
    Challenge.Kind.DAILY_REVISION -> stringResource(R.string.revise_every_day_for_a_week)
}

// MARK: - Celebrating

/**
 * The moment something is earned: a small toast of points, or a fuller card for an achievement, a stage or a
 * challenge, with a gentle chime and a haptic. Shown over the tabs, never over the Mushaf's own reading.
 */
@Composable
fun CelebrationOverlay(app: AqraApp) {
    val rewards = app.rewards
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val reduceMotion = rememberReduceMotion()
    val celebration = rewards.celebration
    LaunchedEffect(celebration?.id) {
        val current = celebration ?: return@LaunchedEffect
        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        if (app.prefs.soundsOn.value) Chime.play(context, current.isBig)
        delay(if (current.isBig) 2_600 else 1_600)
        rewards.finishCelebration()
    }
    Box(Modifier.fillMaxSize().statusBarsPadding().padding(top = 8.dp), contentAlignment = Alignment.TopCenter) {
        AnimatedContent(
            celebration,
            transitionSpec = {
                if (reduceMotion) fadeIn() togetherWith fadeOut()
                else (slideInVertically { -it } + scaleIn(initialScale = 0.8f) + fadeIn()) togetherWith
                    (slideOutVertically { -it } + scaleOut(targetScale = 0.8f) + fadeOut())
            },
            contentKey = { it?.id },
            label = "celebration",
        ) { shown ->
            if (shown != null) {
                Box(Modifier.pressable(pressed = 1f) { rewards.finishCelebration() }.semantics { liveRegion = LiveRegionMode.Polite }) {
                    CelebrationContent(shown)
                }
            }
        }
    }
}

@Composable
private fun CelebrationContent(celebration: Celebration) {
    when (val kind = celebration.kind) {
        is Celebration.Kind.Points -> AqraChip("⭐️", Palette.butter, Modifier.padding(top = 4.dp)) {
            Text(pluralStringResource(R.plurals.n_points_2, kind.points, kind.points), style = ChipText.copy(fontSize = ChipText.fontSize * 1.15f))
        }
        is Celebration.Kind.Earned -> CelebrationCard(kind.achievement.icon, Palette.butter, kind.achievement.title(), stringResource(R.string.a_new_achievement))
        is Celebration.Kind.Stage -> CelebrationCard("🏅", Palette.lavender, stringResource(R.string.stage_n_passed, kind.stage), stringResource(R.string.may_allah_bless_you))
        is Celebration.Kind.ChallengeMet -> CelebrationCard(kind.kind.icon, Palette.mint, kind.kind.title(kind.target), stringResource(R.string.challenge_met))
    }
}

@Composable
private fun CelebrationCard(icon: String, tint: Color, title: String, detail: String) {
    val shape = RoundedCornerShape(26.dp)
    Row(
        Modifier.padding(horizontal = 22.dp).widthIn(max = 420.dp).fillMaxWidth().softShadow(shape, strength = 2f, radius = 24.dp, y = 12.dp)
            .background(Color.White, shape).padding(14.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IconTile(icon, tint, size = 48.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = aqraStyle(17f, Weight.heavy, Palette.ink))
            Text(detail, style = aqraStyle(12f, Weight.semibold, Palette.brand))
        }
    }
}

// MARK: - On the progress screen

/** Points, achievements and the week's challenges. */
@Composable
fun RewardsSection(app: AqraApp) {
    val rewards = app.rewards
    var choosing by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        AqraSectionTitle(stringResource(R.string.rewards), Modifier.padding(top = 10.dp))
        AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                IconTile("⭐️", Palette.butter, size = 40.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(pluralStringResource(R.plurals.n_points, rewards.points, rewards.points), style = aqraStyle(19f, Weight.heavy, Palette.ink))
                    Text(stringResource(R.string.n_this_week, rewards.points(weekStart())), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                }
                Box(Modifier.height(24.dp).background(Palette.lavender, CircleShape).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.just_for_you), style = aqraStyle(11f, Weight.bold, Palette.brand))
                }
            }
        }
        AqraCard(Modifier.fillMaxWidth(), padding = 12.dp, radius = 24.dp) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                for (row in Achievement.entries.chunked(4)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        for (achievement in row) AchievementTile(achievement, rewards.earnedAt(achievement) != null, Modifier.weight(1f))
                    }
                }
            }
        }
        Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            AqraSectionTitle(stringResource(R.string.this_weeks_challenges), Modifier.weight(1f))
            val label = stringResource(R.string.new_challenge)
            Box(Modifier.size(30.dp).background(Palette.lavender, CircleShape).pressable { choosing = true }.semantics { contentDescription = label },
                contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Add, null, tint = Palette.brand, modifier = Modifier.size(16.dp))
            }
        }
        val active = rewards.activeChallenges()
        if (active.isEmpty()) {
            AqraCard(Modifier.fillMaxWidth().pressable { choosing = true }, padding = 0.dp, radius = 24.dp) {
                AqraRow("🎯", Palette.peach, stringResource(R.string.set_yourself_a_challenge),
                    detail = stringResource(R.string.a_goal_for_the_week_between_you_and_yourself))
            }
        } else {
            AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
                active.forEachIndexed { index, challenge ->
                    if (index > 0) AqraRowDivider()
                    ChallengeRow(app, challenge)
                }
            }
        }
    }
    if (choosing) {
        AqraSheet(onDismiss = { choosing = false }, fullHeight = false) { ChallengePicker(app) { choosing = false } }
    }
}

/** The start of this week, in this locale. */
private fun weekStart(): Moment {
    val zone = ZoneId.systemDefault()
    val today = java.time.LocalDate.now(zone)
    val first = WeekFields.of(Locale.getDefault()).firstDayOfWeek
    val start = today.with(java.time.temporal.TemporalAdjusters.previousOrSame(first))
    return Moment.of(start.atStartOfDay(zone).toInstant())
}

@Composable
private fun AchievementTile(achievement: Achievement, earned: Boolean, modifier: Modifier) {
    val state = stringResource(if (earned) R.string.earned else R.string.not_yet)
    Column(modifier.semantics(mergeDescendants = true) { stateDescription = state }, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Box(
            Modifier.size(48.dp).alpha(if (earned) 1f else 0.45f)
                .background(if (earned) Palette.butter else Palette.lavender.copy(alpha = 0.6f), RoundedCornerShape(15.dp)),
            contentAlignment = Alignment.Center,
        ) {
            // Not yet earned, the emoji is shown in grey.
            Text(achievement.icon, style = aqraStyle(24f), modifier = if (earned) Modifier else Modifier.grayscale())
        }
        Text(achievement.title(), style = aqraStyle(10f, Weight.bold, if (earned) Palette.ink else Palette.inkSoft), textAlign = TextAlign.Center,
            maxLines = 2, minLines = 2)
    }
}

/** Draws its content without color. */
private fun Modifier.grayscale(): Modifier = drawWithContent {
    val paint = Paint().apply { colorFilter = ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(0f) }) }
    drawContext.canvas.saveLayer(Rect(0f, 0f, size.width, size.height), paint)
    drawContent()
    drawContext.canvas.restore()
}

@Composable
private fun ChallengeRow(app: AqraApp, challenge: Challenge) {
    val progress = app.rewards.progress(challenge, app.revision, app.plan)
    val done = challenge.completedAt != null
    Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        IconTile(if (done) "🏆" else challenge.kind.icon, if (done) Palette.butter else Palette.peach, size = 38.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(challenge.kind.title(challenge.target), style = aqraStyle(15f, Weight.heavy, Palette.ink))
            LinearProgressIndicator(
                progress = { minOf(progress, challenge.target).toFloat() / maxOf(challenge.target, 1) },
                modifier = Modifier.fillMaxWidth().height(5.dp), color = if (done) Palette.success else Palette.brand, trackColor = Palette.lavender,
                drawStopIndicator = {},
            )
            Text(
                if (done) stringResource(R.string.done)
                else stringResource(R.string.n_of_n_until_s, minOf(progress, challenge.target), challenge.target,
                    weekdayName(challenge.end.weekday(ZoneId.systemDefault()), narrow = false)),
                style = aqraStyle(11f, Weight.semibold, Palette.inkSoft),
            )
        }
        if (!done) {
            val label = stringResource(R.string.remove_the_challenge)
            Box(Modifier.size(26.dp).background(Palette.lavender, CircleShape).pressable { app.rewards.remove(challenge) }
                .semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Close, null, tint = Palette.inkSoft, modifier = Modifier.size(14.dp))
            }
        }
    }
}

/** Choosing a challenge for the coming week. */
@Composable
private fun ChallengePicker(app: AqraApp, onDone: () -> Unit) {
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        TwoLineHeadline(stringResource(R.string.a_challenge), stringResource(R.string.for_this_week), size = 26f, alignCenter = false,
            modifier = Modifier.padding(top = 8.dp))
        Text(stringResource(R.string.between_you_and_yourself_nobody_else_sees_it), style = aqraStyle(14f, Weight.medium, Palette.inkSoft))
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            val options = Challenge.OPTIONS.filter { it.first != Challenge.Kind.LINES_MEMORIZED || app.plan.plan != null }
            options.forEachIndexed { index, (kind, target) ->
                if (index > 0) AqraRowDivider()
                AqraRow(kind.icon, Palette.peach, kind.title(target), Modifier.pressable(pressed = 0.98f) {
                    app.rewards.start(kind, target)
                    onDone()
                }) {
                    Icon(Icons.Rounded.AddCircle, null, tint = Palette.brand, modifier = Modifier.size(24.dp))
                }
            }
        }
        Spacer(Modifier.height(8.dp))
    }
}
