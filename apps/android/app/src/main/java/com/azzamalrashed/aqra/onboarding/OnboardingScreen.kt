package com.azzamalrashed.aqra.onboarding

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.absoluteOffset
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.SacredText
import com.azzamalrashed.aqra.ui.art.AqraArchLogo
import com.azzamalrashed.aqra.ui.art.AqraGlowRings
import com.azzamalrashed.aqra.ui.art.AqraLogoMark
import com.azzamalrashed.aqra.ui.art.LeftToRight
import com.azzamalrashed.aqra.ui.art.LogoGold
import com.azzamalrashed.aqra.ui.art.LogoReveal
import com.azzamalrashed.aqra.ui.art.gradientStops
import com.azzamalrashed.aqra.ui.art.starPath
import com.azzamalrashed.aqra.ui.components.AqraCard
import com.azzamalrashed.aqra.ui.components.AqraChip
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipText
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.IconTile
import com.azzamalrashed.aqra.ui.iosSpring
import com.azzamalrashed.aqra.ui.rememberAnimationTime
import com.azzamalrashed.aqra.ui.rememberReduceMotion
import com.azzamalrashed.aqra.ui.theme.Amiri
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.arabicDigits
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.min
import kotlin.math.sin

private const val PAGE_COUNT = 4

/** First-launch onboarding: four swipeable pages, ending on «ابدأ». No sign-in: everyone starts anonymously. */
@Composable
fun OnboardingScreen(onFinish: () -> Unit) {
    val pager = rememberPagerState { PAGE_COUNT }
    val scope = rememberCoroutineScope()
    fun next() = scope.launch { pager.animateScrollToPage(pager.currentPage + 1) }
    Box(Modifier.fillMaxSize().background(Palette.surface)) {
        HorizontalPager(pager, Modifier.fillMaxSize()) { page ->
            val active = pager.settledPage == page
            when (page) {
                0 -> WelcomePage(active, onBegin = ::next)
                1 -> ManazilPage(active, onContinue = ::next)
                2 -> FeaturesPage(active, onContinue = ::next)
                else -> StartPage(active, onBegin = onFinish)
            }
        }
    }
}

/**
 * Shared layout for onboarding pages, and pages in their style (the plan's setup): an animated stage, the page's
 * copy, page dots and a button, with [extra] beneath it. [safeDrawing] is off inside a sheet, which keeps clear of
 * the system bars itself.
 */
@Composable
internal fun OnboardingPageLayout(
    currentPage: Int,
    actionsVisible: Boolean,
    button: String,
    onButton: () -> Unit,
    stage: @Composable () -> Unit,
    pageCount: Int = PAGE_COUNT,
    safeDrawing: Boolean = true,
    extra: (@Composable () -> Unit)? = null,
    copy: @Composable ColumnScope.(scale: Float) -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize().background(Palette.surface).then(if (safeDrawing) Modifier.safeDrawingPadding() else Modifier)) {
        val width = maxWidth
        val landscape = maxWidth > maxHeight * 1.1f
        // Tablet-sized space in either orientation.
        val roomy = min(maxWidth.value, maxHeight.value) >= 600
        val actionsAlpha by animateFloatAsState(if (actionsVisible) 1f else 0f, iosSpring(0.55f, 0.82f), label = "actions")
        @Composable
        fun actions(compact: Boolean, large: Boolean) {
            Column(
                Modifier
                    .padding(horizontal = 24.dp)
                    .padding(top = if (compact) 14.dp else 26.dp, bottom = 8.dp)
                    .graphicsLayer { alpha = actionsAlpha; translationY = (1 - actionsAlpha) * 24.dp.toPx() },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(if (compact) 12.dp else 20.dp),
            ) {
                PageDots(pageCount, currentPage)
                BrandButton(button, height = if (large) 64.dp else if (compact) 48.dp else 56.dp, fontSize = if (large) 21f else 18f,
                    enabled = actionsVisible, onClick = onButton)
                extra?.invoke()
            }
        }
        if (landscape) {
            Row(Modifier.fillMaxSize().padding(horizontal = if (roomy) 40.dp else 12.dp), horizontalArrangement = Arrangement.spacedBy(if (roomy) 48.dp else 20.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.width(min(if (roomy) 540f else 400f, width.value * 0.48f).dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    copy(if (roomy) 1.5f else 0.82f)
                    actions(compact = !roomy, large = roomy)
                }
                FittedStage(if (roomy) 1.4f else 1f, Modifier.weight(1f).fillMaxSize(), stage)
            }
        } else {
            Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                FittedStage(if (roomy) 1.6f else 1f, Modifier.weight(1f).fillMaxWidth(), stage)
                Column(Modifier.widthIn(max = if (roomy) 760.dp else Dp.Infinity).padding(horizontal = 18.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    copy(if (roomy) 1.65f else 1f)
                }
                Box(Modifier.widthIn(max = if (roomy) 520.dp else Dp.Infinity)) { actions(compact = false, large = roomy) }
            }
        }
    }
}

/** The stage, composed in a 420×440 box and scaled to fit the space it's given. */
@Composable
private fun FittedStage(maxScale: Float, modifier: Modifier, stage: @Composable () -> Unit) {
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val scale = minOf(maxScale, maxHeight.value / 440f, maxWidth.value / 420f)
        Box(Modifier.requiredSize(420.dp, 440.dp).graphicsLayer { scaleX = scale; scaleY = scale }, contentAlignment = Alignment.Center) {
            stage()
        }
    }
}

@Composable
private fun PageDots(count: Int, current: Int) {
    Row(Modifier.clearAndSetSemantics {}, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        repeat(count) { index ->
            Box(Modifier.width(if (index == current) 20.dp else 7.dp).height(7.dp)
                .background(if (index == current) Palette.brand else Palette.inkSoft.copy(alpha = 0.3f), CircleShape))
        }
    }
}

/** A two-line headline, the second line in the brand color, with a detail line beneath. */
@Composable
internal fun OnboardingHeadline(first: String, second: String, detail: String, scale: Float, visible: Boolean) {
    val shown by animateFloatAsState(if (visible) 1f else 0f, iosSpring(0.6f, 0.85f), label = "headline")
    Column(
        Modifier.fillMaxWidth().graphicsLayer { alpha = shown; translationY = (1 - shown) * 14.dp.toPx() },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy((10 * scale).dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            FittedText(first, aqraStyle(31f * scale, Weight.heavy, Palette.ink), minScale = 0.7f)
            FittedText(second, aqraStyle(31f * scale, Weight.heavy, Palette.brand), minScale = 0.7f)
        }
        Text(detail, style = aqraStyle(16f * scale, Weight.medium, Palette.inkSoft), textAlign = TextAlign.Center)
    }
}

/** Plays a page's entrance the first time it's the visible page. */
@Composable
private fun Entrance(active: Boolean, play: suspend () -> Unit) {
    var played by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(active) {
        if (active && !played) {
            played = true
            play()
        }
    }
}

// MARK: - Page 1: the hadith

/** Onboarding page 1: the Aqra logo coming alive, and the hadith «اقرَأ وارقَ» beneath. */
@Composable
private fun WelcomePage(active: Boolean, onBegin: () -> Unit) {
    val reduceMotion = rememberReduceMotion()
    val haptics = LocalHapticFeedback.current
    val arch = remember { Animatable(0f) }
    val book = remember { Animatable(0f) }
    val door = remember { Animatable(0f) }
    val star = remember { Animatable(0f) }
    var headlineIn by rememberSaveable { mutableStateOf(false) }
    val emphasis = remember { Animatable(0f) }
    var actionsIn by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    Entrance(active) {
        if (reduceMotion) {
            listOf(arch, book, door, star, emphasis).forEach { launchSnap(scope, it) }
            headlineIn = true; actionsIn = true
            return@Entrance
        }
        delay(200)
        scope.launch { arch.animateTo(1f, iosSpring(0.8f, 0.78f)) }
        haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
        delay(320)
        scope.launch { book.animateTo(1f, iosSpring(0.7f, 0.8f)) }
        haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
        delay(380)
        scope.launch { door.animateTo(1f, tween(700, easing = FastOutSlowInEasing)) }
        delay(420)
        scope.launch { star.animateTo(1f, iosSpring(0.55f, 0.5f)) }
        haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        delay(300)
        headlineIn = true
        delay(450)
        scope.launch { emphasis.animateTo(1f, tween(450, easing = FastOutSlowInEasing)) }
        haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
        delay(300)
        actionsIn = true
    }

    val time by rememberAnimationTime(active && !reduceMotion)
    OnboardingPageLayout(0, actionsIn, stringResource(R.string.begin), onBegin, stage = {
        AqraArchLogo(
            Modifier.requiredSize((1024 * 0.42f).dp),
            withBackground = false,
            reveal = LogoReveal(arch.value, book.value, door.value, star.value),
            time = time,
        )
    }) { scale -> Hadith(scale, headlineIn, emphasis.value) }
}

private fun launchSnap(scope: kotlinx.coroutines.CoroutineScope, animatable: Animatable<Float, *>) {
    scope.launch { animatable.animateTo(1f, tween(400)) }
}

/** The hadith, quoted verbatim, with «اقرَأ وارقَ» lighting up in the brand color. */
@Composable
private fun Hadith(scale: Float, visible: Boolean, emphasis: Float) {
    val shown by animateFloatAsState(if (visible) 1f else 0f, iosSpring(0.6f, 0.85f), label = "hadith")
    val language = LocalConfiguration.current.locales[0].language
    Column(
        Modifier.fillMaxWidth().graphicsLayer { alpha = shown; translationY = (1 - shown) * 14.dp.toPx() },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy((8 * scale).dp),
    ) {
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            Column(
                Modifier.semantics(mergeDescendants = true) {
                    contentDescription = "${SacredText.RECITE_AND_ASCEND_NARRATOR}، قال رسول الله ﷺ: ${SacredText.RECITE_AND_ASCEND}"
                },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy((8 * scale).dp),
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(SacredText.RECITE_AND_ASCEND_NARRATOR, style = aqraStyle(16f * scale, color = Palette.inkSoft).copy(fontFamily = Amiri))
                    Text("قال رسول الله ﷺ:", style = aqraStyle(19f * scale, FontWeight.Bold, Palette.ink).copy(fontFamily = Amiri))
                }
                val text = SacredText.RECITE_AND_ASCEND
                val phrase = SacredText.RECITE_AND_ASCEND_EMPHASIS
                val start = text.indexOf(phrase)
                Text(
                    buildAnnotatedString {
                        append(text.substring(0, start))
                        withStyle(SpanStyle(fontSize = (25f * scale).sp, fontWeight = FontWeight.Bold, color = lerp(Palette.ink, Palette.brand, emphasis))) {
                            append(phrase)
                        }
                        append(text.substring(start + phrase.length))
                    },
                    style = aqraStyle(22f * scale, color = Palette.ink, lineHeight = (22f * scale * 1.55f).sp).copy(fontFamily = Amiri),
                    textAlign = TextAlign.Center,
                )
            }
        }
        Text(stringResource(R.string.reported_by_ahmad), style = aqraStyle(maxOf(12f, 13f * scale), Weight.semibold, Palette.inkSoft))
        if (language != "ar") {
            Text(SacredText.RECITE_AND_ASCEND_TRANSLATION, style = aqraStyle(maxOf(12f, 13f * scale), Weight.medium, Palette.ink.copy(alpha = 0.8f)).copy(fontFamily = FontFamily.Serif),
                textAlign = TextAlign.Center, modifier = Modifier.padding(top = 2.dp))
            Text(stringResource(R.string.translation_jami_at_tirmidhi_2914_darussalam), style = aqraStyle(11f, Weight.medium, Palette.inkSoft))
        }
    }
}

// MARK: - Page 2: the منازل

/** Onboarding page 2: the منازل stairs build step by step inside glowing rings, the gold star lands on top. */
@Composable
private fun ManazilPage(active: Boolean, onContinue: () -> Unit) {
    val reduceMotion = rememberReduceMotion()
    val haptics = LocalHapticFeedback.current
    var ringsOpen by rememberSaveable { mutableStateOf(false) }
    var built by rememberSaveable { mutableIntStateOf(0) }
    var starLit by rememberSaveable { mutableStateOf(false) }
    var copyIn by rememberSaveable { mutableStateOf(false) }
    var actionsIn by rememberSaveable { mutableStateOf(false) }

    Entrance(active) {
        if (reduceMotion) {
            ringsOpen = true; built = 5; starLit = true; copyIn = true; actionsIn = true
            return@Entrance
        }
        delay(150)
        ringsOpen = true
        delay(150)
        for (step in 1..5) {
            built = step
            delay(120)
            haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
        }
        starLit = true
        haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        delay(350)
        copyIn = true
        delay(350)
        actionsIn = true
    }

    val time by rememberAnimationTime(active && !reduceMotion)
    val openness by animateFloatAsState(if (ringsOpen) 1f else 0f, iosSpring(0.9f, 0.8f), label = "rings")
    val builtSteps by animateFloatAsState(built.toFloat(), iosSpring(0.42f, 0.62f), label = "steps")
    val star by animateFloatAsState(if (starLit) 1f else 0f, iosSpring(0.5f, 0.45f), label = "star")
    OnboardingPageLayout(1, actionsIn, stringResource(R.string.continue_action), onContinue, stage = {
        Box(Modifier.requiredSize(420.dp, 440.dp), contentAlignment = Alignment.Center) {
            AqraGlowRings(Modifier.graphicsLayer { scaleX = 1.15f; scaleY = 1.15f }, breath = sin(time * 0.9).toFloat(), openness = openness)
            AqraLogoMark(builtSteps, star, sin(time * 2.2).toFloat(),
                Modifier.graphicsLayer { scaleX = 1.45f; scaleY = 1.45f; translationX = 8.dp.toPx(); translationY = 6.dp.toPx() })
        }
    }) { scale ->
        OnboardingHeadline(
            stringResource(R.string.strengthen_your_memorization), stringResource(R.string.and_rise_ayah_by_ayah),
            stringResource(R.string.revise_every_day_and_climb_your_stations_in_aqra), scale, copyIn,
        )
    }
}

// MARK: - Page 3: what Aqra offers

/** Onboarding page 3: what Aqra offers, as cards that burst out of a soft glow and keep floating. */
@Composable
private fun FeaturesPage(active: Boolean, onContinue: () -> Unit) {
    val reduceMotion = rememberReduceMotion()
    val haptics = LocalHapticFeedback.current
    var glowIn by rememberSaveable { mutableStateOf(false) }
    var cardsOut by rememberSaveable { mutableIntStateOf(0) }
    var streakDays by rememberSaveable { mutableIntStateOf(0) }
    var manzil by rememberSaveable { mutableStateOf(false) }
    var copyIn by rememberSaveable { mutableStateOf(false) }
    var actionsIn by rememberSaveable { mutableStateOf(false) }

    Entrance(active) {
        if (reduceMotion) {
            glowIn = true; cardsOut = 5; streakDays = 5; manzil = true; copyIn = true; actionsIn = true
            return@Entrance
        }
        delay(120)
        glowIn = true
        delay(200)
        for (card in 1..5) {
            cardsOut = card
            haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
            delay(110)
        }
        manzil = true
        for (day in 1..5) {
            streakDays = day
            delay(80)
        }
        copyIn = true
        delay(350)
        actionsIn = true
    }

    val time by rememberAnimationTime(active && !reduceMotion)
    val glow by animateFloatAsState(if (glowIn) 1f else 0f, iosSpring(0.8f, 0.8f), label = "glow")
    val progress by animateFloatAsState(if (manzil) 0.68f else 0f, tween(900), label = "manzil")
    OnboardingPageLayout(2, actionsIn, stringResource(R.string.continue_action), onContinue, stage = {
        LeftToRight {
            Box(Modifier.requiredSize(420.dp, 440.dp), contentAlignment = Alignment.Center) {
                Canvas(Modifier.requiredSize(400.dp).graphicsLayer {
                    val s = if (glowIn) 1 + sin(time * 0.9).toFloat() * 0.03f else 0.3f + 0.7f * glow
                    scaleX = s; scaleY = s; alpha = glow
                }) {
                    drawCircle(Brush.radialGradient(*gradientStops(listOf(Palette.lavender, Palette.rose.copy(alpha = 0.45f), Palette.surface.copy(alpha = 0f)), 10f, 200f),
                        radius = size.width / 2))
                }
                Floating(0, cardsOut, Depth.BACK, Offset(-112f, -168f), -8f, time) {
                    AqraChip("⭐️", Palette.butter) { Text("+٥٠ نقطة", style = ChipText) }
                }
                Floating(1, cardsOut, Depth.FRONT, Offset(58f, -104f), 4f, time) { StreakCard(streakDays) }
                Floating(2, cardsOut, Depth.FRONT, Offset(-66f, 24f), -3f, time) { ManzilCard(progress) }
                Floating(3, cardsOut, Depth.MID, Offset(76f, 138f), 5f, time) { SessionCard() }
                Floating(4, cardsOut, Depth.BACK, Offset(-98f, 180f), 3f, time) {
                    AqraChip("✅", Palette.mint) { Text("أتممت الجزء ٣٠", style = ChipText) }
                }
            }
        }
    }) { scale ->
        OnboardingHeadline(
            stringResource(R.string.everything_that_helps_your_memorization), stringResource(R.string.in_one_place),
            stringResource(R.string.daily_revision_tasmee_with_qualified_teachers_and_rewards_that_motivate), scale, copyIn,
        )
    }
}

private enum class Depth(val scale: Float, val drift: Float, val layer: Float) {
    BACK(0.86f, 3f, 0f), MID(0.94f, 5f, 1f), FRONT(1f, 7f, 2f)
}

/** A card that flies out of the middle to its place, tilted, and keeps drifting gently. */
@Composable
private fun Floating(index: Int, cardsOut: Int, depth: Depth, target: Offset, tilt: Float, time: Double, content: @Composable () -> Unit) {
    val out = index < cardsOut
    val progress by animateFloatAsState(if (out) 1f else 0f, iosSpring(0.62f, 0.66f), label = "card$index")
    val drift = if (out) sin(time * (0.8 + index * 0.17) + index * 1.3).toFloat() * depth.drift else 0f
    Box(
        Modifier
            .absoluteOffset { IntOffset((target.x * progress).dp.roundToPx(), (target.y * progress + drift).dp.roundToPx()) }
            .graphicsLayer {
                val s = 0.3f + (depth.scale - 0.3f) * progress
                scaleX = s; scaleY = s
                rotationZ = tilt * progress
                alpha = progress.coerceIn(0f, 1f)
            },
    ) {
        // Positions are a fixed composition; each card's contents keep the screen's direction.
        CompositionLocalProvider(LocalLayoutDirection provides if (LocalConfiguration.current.layoutDirection == android.view.View.LAYOUT_DIRECTION_RTL) LayoutDirection.Rtl else LayoutDirection.Ltr) {
            content()
        }
    }
}

@Composable
private fun StreakCard(days: Int) {
    AqraCard {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                IconTile("🔥", Palette.peach)
                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text("${arabicDigits(days)} أيام", style = aqraStyle(16f, Weight.heavy, Palette.ink))
                    Text("سلسلة المراجعة", style = aqraStyle(11f, Weight.semibold, Palette.inkSoft))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                repeat(7) { day ->
                    Box(Modifier.size(16.dp).background(if (day < days) Palette.brand else Palette.lavender, CircleShape), contentAlignment = Alignment.Center) {
                        if (day < days) Icon(Icons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(10.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun ManzilCard(progress: Float) {
    AqraCard {
        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                IconTile("🪜", Palette.lavender)
                Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text("المنزلة ١٢", style = aqraStyle(16f, Weight.heavy, Palette.ink))
                    Text("٣٤ آية إلى التالية", style = aqraStyle(11f, Weight.semibold, Palette.inkSoft))
                }
            }
            Box(Modifier.width(132.dp).height(7.dp).background(Palette.lavender, CircleShape)) {
                Box(Modifier.width((132 * progress).dp).height(7.dp)
                    .background(Brush.horizontalGradient(listOf(Palette.brand, Color(0xFFB36AD8))), CircleShape))
            }
        }
    }
}

@Composable
private fun SessionCard() {
    AqraCard {
        Row(Modifier.padding(end = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            IconTile("🎙️", Palette.sky)
            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text("تسميع مع شيخ", style = aqraStyle(15f, Weight.heavy, Palette.ink))
                Text("غدًا · ٨:٠٠ م", style = aqraStyle(11f, Weight.semibold, Palette.inkSoft))
            }
        }
    }
}

// MARK: - Page 4: the start of the journey

/** Onboarding page 4, the last: a gold star with rising sparkles, and the start of the journey. */
@Composable
private fun StartPage(active: Boolean, onBegin: () -> Unit) {
    val reduceMotion = rememberReduceMotion()
    val haptics = LocalHapticFeedback.current
    var glowIn by rememberSaveable { mutableStateOf(false) }
    var starIn by rememberSaveable { mutableStateOf(false) }
    var copyIn by rememberSaveable { mutableStateOf(false) }
    var actionsIn by rememberSaveable { mutableStateOf(false) }

    Entrance(active) {
        if (reduceMotion) {
            glowIn = true; starIn = true; copyIn = true; actionsIn = true
            return@Entrance
        }
        delay(120)
        glowIn = true
        delay(250)
        starIn = true
        haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        delay(450)
        copyIn = true
        delay(350)
        actionsIn = true
    }

    val time by rememberAnimationTime(active && !reduceMotion)
    val glow by animateFloatAsState(if (glowIn) 1f else 0f, iosSpring(0.9f, 0.8f), label = "glow")
    val star by animateFloatAsState(if (starIn) 1f else 0f, iosSpring(0.7f, 0.55f), label = "star")
    OnboardingPageLayout(3, actionsIn, stringResource(R.string.begin), onBegin, stage = {
        Canvas(Modifier.requiredSize(420.dp, 440.dp).clearAndSetSemantics {}) {
            val center = Offset(size.width / 2, size.height / 2)
            val unit = size.width / 420f
            val breath = sin(time * 0.9).toFloat()
            val glowScale = (0.3f + 0.7f * glow) * (if (glowIn) 1 + breath * 0.03f else 1f)
            drawCircle(Brush.radialGradient(*gradientStops(listOf(Color(0xFFFFF1D6), Palette.lavender, Palette.rose.copy(alpha = 0.4f), Palette.surface.copy(alpha = 0f)), 10f, 210f),
                center = center, radius = 210f * unit * glowScale), radius = 210f * unit * glowScale, center = center, alpha = glow)
            for (diameter in listOf(150f, 240f, 330f)) {
                val ring = (0.2f + 0.8f * glow) * (1 + sin(time * 0.9 + diameter).toFloat() * 0.015f)
                drawCircle(Color.White, radius = (diameter / 2) * unit * ring, center = center, alpha = 0.9f * glow, style = Stroke(1.5f * unit))
            }
            // Small gold sparkles drifting upward around the star, fading in and out.
            for ((x, speed, phase, sparkle) in SPARKLES) {
                val progress = ((time * speed + phase) % 1.0).toFloat()
                val point = Offset(center.x + x * unit, center.y + (170f - progress * 360f) * unit)
                drawPath(starPath(Size(sparkle * unit, sparkle * unit), 4, 0.38f, 0.1f, Offset(point.x - sparkle * unit / 2, point.y - sparkle * unit / 2)),
                    LogoGold.sparkle, alpha = star * sin(progress * Math.PI).toFloat())
            }
            val starScale = (0.3f + 0.7f * star) * (if (starIn) 1 + 0.03f * sin(time * 2).toFloat() else 1f)
            val starSize = 150f * unit * starScale
            val starCenter = Offset(center.x, center.y + (1 - star) * 90f * unit)
            drawCircle(Brush.radialGradient(listOf(LogoGold.glow.copy(alpha = 0.55f), LogoGold.glow.copy(alpha = 0f)), center = starCenter,
                radius = starSize / 2 + (36f + 10f * sin(time * 2).toFloat()) * unit), radius = starSize / 2 + 46f * unit, center = starCenter, alpha = star)
            drawContext.transform.rotate((1 - star) * -140f, starCenter)
            drawPath(starPath(Size(starSize, starSize), 8, 0.38f, 0.04f, Offset(starCenter.x - starSize / 2, starCenter.y - starSize / 2)),
                Brush.verticalGradient(LogoGold.star, startY = starCenter.y - starSize / 2, endY = starCenter.y + starSize / 2), alpha = star.coerceIn(0f, 1f))
            drawContext.transform.rotate((1 - star) * 140f, starCenter)
        }
    }) { scale ->
        OnboardingHeadline(
            stringResource(R.string.everything_is_ready), stringResource(R.string.begin_your_journey),
            stringResource(R.string.your_progress_is_saved_on_your_device_and_you_can), scale, copyIn,
        )
    }
}

private data class Sparkle(val x: Float, val speed: Double, val phase: Double, val size: Float)

private val SPARKLES = listOf(
    Sparkle(-150f, 0.10, 0.0, 14f), Sparkle(-95f, 0.14, 0.45, 10f), Sparkle(-40f, 0.08, 0.2, 12f), Sparkle(35f, 0.12, 0.7, 10f),
    Sparkle(90f, 0.09, 0.35, 14f), Sparkle(145f, 0.13, 0.9, 11f), Sparkle(-120f, 0.11, 0.6, 9f), Sparkle(120f, 0.1, 0.15, 9f),
)
