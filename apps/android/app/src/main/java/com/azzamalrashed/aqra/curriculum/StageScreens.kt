package com.azzamalrashed.aqra.curriculum

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.mushaf.MushafFonts
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.AqraSheet
import com.azzamalrashed.aqra.ui.FullScreen
import com.azzamalrashed.aqra.ui.LocalOverlays
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraRowDivider
import com.azzamalrashed.aqra.ui.components.AqraSectionTitle
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.components.TwoLineHeadline
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatLongDay
import com.azzamalrashed.aqra.ui.util.formatNumber
import com.azzamalrashed.aqra.ui.util.formatPercent
import com.azzamalrashed.aqra.ui.util.formatRelativeAhead
import kotlin.random.Random

/** «الأجزاء ٧–٩» */
@Composable
fun stageJuz(stage: Int): String {
    val juz = Curriculum.juz(stage)
    return stringResource(R.string.juz_n_n, juz.first, juz.last)
}

@Composable
private fun requirementTitle(requirement: StageStatus.Requirement, policy: StagePolicy): String = when (requirement) {
    StageStatus.Requirement.MEMORIZED -> stringResource(R.string.memorize_every_ayah_of_it)
    StageStatus.Requirement.MASTERED -> stringResource(R.string.master_n_of_it, Math.round(policy.requiredMastered * 100).toInt())
    StageStatus.Requirement.TEST -> stringResource(R.string.pass_its_test_in_the_app)
    StageStatus.Requirement.SHEIKH -> stringResource(R.string.pass_a_teachers_test_of_it)
}

/** Two thin bars: how much of something is memorized, and how much of it is mastered. */
@Composable
fun ProgressBars(memorized: Double, mastered: Double, modifier: Modifier = Modifier, tint: Color = Palette.brand) {
    val label = stringResource(R.string.memorized_s_mastered_s, formatPercent(memorized, 0), formatPercent(mastered, 0))
    Column(modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = label }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Bar(memorized, tint.copy(alpha = 0.35f))
        Bar(mastered, tint)
    }
}

@Composable
private fun Bar(value: Double, color: Color) {
    BoxWithConstraints(Modifier.fillMaxWidth().height(6.dp).background(Palette.lavender, CircleShape)) {
        val share = value.coerceIn(0.0, 1.0).toFloat()
        if (share > 0) Box(Modifier.width(maxOf(maxWidth * share, 6.dp)).height(6.dp).background(color, CircleShape))
    }
}

// MARK: - The current stage on the home

/** The stage the student is in: how much of it is memorized and mastered; it opens the stage. */
@Composable
fun StageCard(app: AqraApp, store: MushafStore, stage: Int, onOpen: () -> Unit) {
    val status = app.assessments.status(stage, store, app.memorization)
    AqraCard(Modifier.fillMaxWidth().pressable(onClick = onOpen), padding = 14.dp, radius = 24.dp) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconTile(if (status.isPassed) "🏅" else "🪜", Palette.lavender, size = 40.dp)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.stage_n_of_n, stage, Curriculum.STAGE_COUNT), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                Text(stageJuz(stage), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
            }
            Box(Modifier.height(28.dp).background(Palette.lavender, CircleShape).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                Text(formatPercent(status.progress.memorizedShare, 0), style = aqraStyle(13f, Weight.bold, Palette.brand))
            }
        }
        Spacer(Modifier.height(10.dp))
        ProgressBars(status.progress.memorizedShare, status.progress.masteredShare)
    }
}

// MARK: - Every stage

/** The ten stages, each with how much is memorized and mastered, and whether it's passed. */
@Composable
fun StagesSection(app: AqraApp, store: MushafStore, onOpen: (Int) -> Unit) {
    AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
        for (stage in 1..Curriculum.STAGE_COUNT) {
            if (stage > 1) AqraRowDivider()
            val status = app.assessments.status(stage, store, app.memorization)
            val (top, bottom) = StepFaces.forJuz(Curriculum.juz(stage).first)
            Row(Modifier.fillMaxWidth().pressable(pressed = 0.98f) { onOpen(stage) }.padding(14.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(38.dp).background(top, RoundedCornerShape(12.dp)), contentAlignment = Alignment.Center) {
                    Text(formatNumber(stage), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stageJuz(stage), style = aqraStyle(14f, Weight.heavy, Palette.ink), modifier = Modifier.weight(1f))
                        if (status.isPassed) {
                            Box(Modifier.height(22.dp).background(Palette.mint, CircleShape).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                                Text(stringResource(R.string.passed), style = aqraStyle(11f, Weight.bold, Palette.success))
                            }
                        }
                    }
                    ProgressBars(status.progress.memorizedShare, status.progress.masteredShare, tint = bottom)
                }
            }
        }
    }
}

// MARK: - A stage

/** One stage: its juz', how far it's come, what passing it asks and how far each is met, and its test. */
@Composable
fun StageDetailScreen(app: AqraApp, store: MushafStore, stage: Int, onTakeTest: () -> Unit) {
    val status = app.assessments.status(stage, store, app.memorization)
    Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 22.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)) {
        TwoLineHeadline(stringResource(R.string.stage_n, stage), stageJuz(stage), size = 28f, alignCenter = false, modifier = Modifier.padding(top = 8.dp))
        status.passedAt?.let { passedAt ->
            AqraCard(Modifier.fillMaxWidth(), padding = 14.dp, radius = 24.dp) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconTile("🏅", Palette.butter, size = 40.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(stringResource(R.string.stage_passed), style = aqraStyle(16f, Weight.heavy, Palette.ink))
                        Text(formatLongDay(passedAt.toInstant()), style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
                    }
                }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StageStat("📖", Palette.sky, status.progress.memorizedShare, stringResource(R.string.memorized), Modifier.weight(1f))
            StageStat("💪", Palette.mint, status.progress.masteredShare, stringResource(R.string.mastered), Modifier.weight(1f))
            StageStat("🎓", Palette.butter, status.progress.verifiedShare, stringResource(R.string.verified), Modifier.weight(1f))
        }
        AqraSectionTitle(stringResource(R.string.to_pass_this_stage), Modifier.padding(top = 6.dp))
        AqraCard(Modifier.fillMaxWidth(), padding = 0.dp, radius = 24.dp) {
            status.requirements.forEachIndexed { index, requirement ->
                if (index > 0) AqraRowDivider()
                RequirementRow(requirement, status)
            }
        }
        Text(stringResource(R.string.mastered_revised_clean_until_it_stays_with_you_for_two), style = aqraStyle(12f, Weight.medium, Palette.inkSoft),
            modifier = Modifier.padding(horizontal = 6.dp))
        Box(Modifier.padding(top = 6.dp)) {
            val retestAt = status.retestAt
            when {
                status.canTakeTest() -> BrandButton(stringResource(if (status.testPassed) R.string.take_the_test_again else R.string.take_the_stage_test),
                    height = 54.dp, fontSize = 17f, onClick = onTakeTest)
                retestAt != null -> Text(stringResource(R.string.you_can_take_the_test_again_s, formatRelativeAhead(retestAt.toInstant())),
                    style = aqraStyle(13f, Weight.semibold, Palette.inkSoft), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                else -> Text(stringResource(R.string.the_test_opens_once_every_ayah_of_the_stage_is), style = aqraStyle(13f, Weight.semibold, Palette.inkSoft),
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
            }
        }
    }
}

@Composable
private fun RequirementRow(requirement: StageStatus.Requirement, status: StageStatus) {
    val met = status.isMet(requirement)
    val progress = status.progress
    val detail = when (requirement) {
        StageStatus.Requirement.MEMORIZED -> stringResource(R.string.n_of_n_ayat, progress.memorized, progress.total)
        StageStatus.Requirement.MASTERED -> stringResource(R.string.n_of_n_ayat, progress.mastered, progress.total)
        StageStatus.Requirement.TEST -> status.bestScore?.let { stringResource(R.string.best_score_s, formatPercent(it, 0)) }
            ?: stringResource(R.string.not_taken_yet)
        StageStatus.Requirement.SHEIKH -> stringResource(if (status.sheikhPassed) R.string.passed else R.string.book_a_tasmee_and_ask_for_a_stage_test)
    }
    Row(Modifier.fillMaxWidth().padding(14.dp).semantics(mergeDescendants = true) {}, verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(if (met) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, null,
            tint = if (met) Color(0xFF2E9B63) else Palette.lavender, modifier = Modifier.size(24.dp))
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(requirementTitle(requirement, status.policy), style = aqraStyle(15f, Weight.bold, Palette.ink))
            Text(detail, style = aqraStyle(12f, Weight.semibold, Palette.inkSoft))
        }
    }
}

@Composable
private fun StageStat(icon: String, tint: Color, value: Double, label: String, modifier: Modifier) {
    AqraCard(modifier.semantics(mergeDescendants = true) {}, padding = 12.dp, radius = 20.dp) {
        IconTile(icon, tint, size = 32.dp)
        Spacer(Modifier.height(8.dp))
        Text(formatPercent(value, 0), style = aqraStyle(20f, Weight.heavy, Palette.ink))
        Text(label, style = aqraStyle(11f, Weight.semibold, Palette.inkSoft), maxLines = 1)
    }
}

// MARK: - The stage's test

/**
 * A stage's in-app test: questions on its memorized ayat, each answered at once with the right answer shown, and the
 * score at the end. Ayat are shown in the Complex's text and Hafs Smart font, exactly as published.
 */
@Composable
fun StageTestScreen(app: AqraApp, store: MushafStore, stage: Int, onClose: () -> Unit) {
    val assessments = app.assessments
    val haptics = LocalHapticFeedback.current
    val questions = remember { TestQuestion.test(stage, assessments.policy.testQuestions, store, app.memorization, Random.Default) }
    var index by remember { mutableIntStateOf(0) }
    var chosen by remember { mutableStateOf<Int?>(null) }
    var correct by remember { mutableIntStateOf(0) }
    var finished by remember { mutableStateOf(false) }
    LaunchedEffect(chosen) {
        val answer = questions.getOrNull(index)?.answer ?: return@LaunchedEffect
        val choice = chosen ?: return@LaunchedEffect
        haptics.performHapticFeedback(if (choice == answer) HapticFeedbackType.Confirm else HapticFeedbackType.Reject)
    }

    fun advance() {
        if (index + 1 < questions.size) {
            index += 1
            chosen = null
        } else {
            assessments.record(AssessmentStore.TestResult(stage = stage, date = com.azzamalrashed.aqra.core.Moment.now(), questions = questions.size, correct = correct))
            assessments.checkPasses(store, app.memorization)
            finished = true
        }
    }

    Box(Modifier.fillMaxSize().background(Palette.surface).safeDrawingPadding(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 600.dp).fillMaxSize().padding(horizontal = 22.dp).padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                val closeLabel = stringResource(R.string.close)
                Box(Modifier.size(38.dp).background(Palette.lavender, CircleShape).pressable(onClick = onClose).semantics { contentDescription = closeLabel },
                    contentAlignment = Alignment.Center) {
                    Icon(Icons.Rounded.Close, null, tint = Palette.brand, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.weight(1f))
                if (questions.isNotEmpty() && !finished) {
                    Text(stringResource(R.string.n_of_n, index + 1, questions.size), style = aqraStyle(14f, Weight.bold, Palette.brand))
                }
            }
            when {
                finished -> TestResult(correct, questions.size, assessments.policy, onClose)
                index in questions.indices -> AnimatedContent(index, transitionSpec = { fadeIn() togetherWith fadeOut() }, label = "question") { shown ->
                    Question(app, store, questions[shown], chosen, onChoose = { option ->
                        if (chosen == null) {
                            chosen = option
                            if (option == questions[shown].answer) correct += 1
                        }
                    }, onNext = ::advance, isLast = shown + 1 >= questions.size)
                }
                else -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Text(stringResource(R.string.there_isnt_enough_memorized_in_this_stage_for_a_test), style = aqraStyle(15f, Weight.semibold, Palette.inkSoft),
                        textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun Question(app: AqraApp, store: MushafStore, question: TestQuestion, chosen: Int?, onChoose: (Int) -> Unit, onNext: () -> Unit, isLast: Boolean) {
    val ink = MushafStyle.LIGHT.ink
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(if (question.kind == TestQuestion.Kind.NEXT_AYAH) R.string.which_ayah_comes_next_q else R.string.which_surah_is_this_ayah_from_q),
            style = aqraStyle(20f, Weight.heavy, Palette.ink), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        val paper = RoundedCornerShape(22.dp)
        Box(Modifier.fillMaxWidth().background(MushafStyle.LIGHT.paper, paper).border(1.dp, MushafStyle.LIGHT.gold.copy(alpha = 0.5f), paper).padding(18.dp)) {
            AyahText(store.ayahTexts[question.ayah], store.ayahPlainTexts[question.ayah], 24.dp, app.fonts, ink)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for (option in question.options) {
                val isAnswer = option == question.answer
                val (fill, border) = when {
                    chosen == null -> Color.White to Palette.lavender
                    isAnswer -> Color(0xFFD8F2E3) to Color(0xFF2E9B63)
                    chosen == option -> Color(0xFFFCDCE7) to Color(0xFFD0505A)
                    else -> Color.White to Palette.lavender
                }
                val faded = chosen != null && !isAnswer && chosen != option
                val shape = RoundedCornerShape(18.dp)
                Box(
                    Modifier.fillMaxWidth().alpha(if (faded) 0.5f else 1f).background(fill, shape).border(2.dp, border, shape)
                        .pressable(pressed = 0.97f) { onChoose(option) }.padding(horizontal = 14.dp, vertical = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    if (question.kind == TestQuestion.Kind.NEXT_AYAH) {
                        AyahText(store.ayahTexts[option], store.ayahPlainTexts[option], 21.dp, app.fonts, ink, showsNumber = false)
                    } else {
                        Text(store.surahNames[option].orEmpty(), style = aqraStyle(18f, Weight.bold, ink))
                    }
                }
            }
        }
        AnimatedVisibility(chosen != null, enter = slideInVertically { it } + fadeIn(), exit = fadeOut()) {
            BrandButton(stringResource(if (isLast) R.string.see_the_result else R.string.next), height = 54.dp, fontSize = 17f, onClick = onNext)
        }
    }
}

@Composable
private fun TestResult(correct: Int, questions: Int, policy: StagePolicy, onDone: () -> Unit) {
    val score = correct.toDouble() / maxOf(questions, 1)
    val passed = score >= policy.testPassScore - 0.000_1
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Spacer(Modifier.weight(1f))
        Text(if (passed) "🏅" else "🌱", style = aqraStyle(72f))
        Text(formatPercent(score, 0), style = aqraStyle(48f, Weight.heavy, Palette.brand))
        Text(stringResource(if (passed) R.string.you_passed_the_stages_test else R.string.not_passed_yet), style = aqraStyle(22f, Weight.heavy, Palette.ink))
        Text(stringResource(if (passed) R.string.n_of_n_right_may_allah_bless_you else R.string.n_of_n_right_revise_the_stage_and_try_again, correct, questions),
            style = aqraStyle(15f, Weight.medium, Palette.inkSoft), textAlign = TextAlign.Center)
        Spacer(Modifier.weight(1f))
        BrandButton(stringResource(R.string.done), height = 54.dp, fontSize = 17f, onClick = onDone)
    }
}

// MARK: - An ayah on its own

/**
 * The text without its ayah-end marker: the Complex's text ends every ayah with one right-to-left mark and one glyph,
 * U+E959 plus the ayah's number, that draws the numbered marker; only that last word is left out.
 */
fun ayahWithoutNumber(text: String): String {
    val space = text.lastIndexOf(' ')
    if (space < 0) return text
    val last = text.substring(space + 1).codePoints().toArray()
    if (last.size != 2 || last[0] != 0x200F || last[1] !in 0xE95A..0xE959 + 286) return text
    return text.substring(0, space)
}

/**
 * One ayah in the Complex's own text and Hafs Smart font, as published, wrapping over as many lines as it needs —
 * where an ayah stands on its own (the stage tests). Each word is drawn from the font by Aqra's own font reader, and
 * the words flow from the right, line after line, each line centered, in any language of the app. A stage test's
 * options leave out the ayah-end marker ([showsNumber]), so the answer can't be read from the numbers.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun AyahText(text: String, spoken: String, size: Dp, fonts: MushafFonts, color: Color, showsNumber: Boolean = true) {
    val density = LocalDensity.current
    val pixels = with(density) { size.toPx() }
    val shown = if (showsNumber) text else ayahWithoutNumber(text)
    val words = remember(shown, pixels) { shown.split(' ').filter { it.isNotEmpty() }.map { fonts.text(it, fonts.hafsFont, pixels) } }
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        FlowRow(
            Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = spoken },
            horizontalArrangement = Arrangement.spacedBy(size * 0.28f, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(size * 0.1f),
        ) {
            for (word in words) {
                Canvas(Modifier.size(with(density) { word.width.toDp() }, with(density) { word.height.toDp() })) {
                    drawIntoCanvas { canvas ->
                        val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { this.color = color.toArgb() }
                        canvas.nativeCanvas.drawPath(word.outline, paint)
                    }
                }
            }
        }
    }
}

/** A stage in a sheet; its test opens full screen over the app. */
@Composable
fun StageSheet(app: AqraApp, store: MushafStore, stage: Int, onDismiss: () -> Unit) {
    val overlays = LocalOverlays.current
    AqraSheet(onDismiss = onDismiss) {
        StageDetailScreen(app, store, stage) {
            onDismiss()
            overlays.open(FullScreen.Custom("stage-test-$stage") { close -> StageTestScreen(app, store, stage, close) })
        }
    }
}
