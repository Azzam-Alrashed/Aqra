package com.azzamalrashed.aqra.memorization

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Contrast
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
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
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.ui.art.AqraGlowRings
import com.azzamalrashed.aqra.ui.art.GlossyStairs
import com.azzamalrashed.aqra.ui.art.LogoGold
import com.azzamalrashed.aqra.ui.art.Manazil
import com.azzamalrashed.aqra.ui.art.starPath
import com.azzamalrashed.aqra.ui.components.AqraChip
import com.azzamalrashed.aqra.ui.components.AqraSegmented
import com.azzamalrashed.aqra.ui.components.BrandButton
import com.azzamalrashed.aqra.ui.components.ChipText
import com.azzamalrashed.aqra.ui.components.FittedText
import com.azzamalrashed.aqra.ui.components.pressable
import com.azzamalrashed.aqra.ui.components.softShadow
import com.azzamalrashed.aqra.ui.iosSpring
import com.azzamalrashed.aqra.ui.rememberReduceMotion
import com.azzamalrashed.aqra.ui.theme.Palette
import com.azzamalrashed.aqra.ui.theme.StepFaces
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.formatNumber
import com.azzamalrashed.aqra.ui.util.formatPercent
import com.azzamalrashed.aqra.ui.util.factSeparator
import kotlinx.coroutines.delay

/**
 * «ماذا تحفظ من القرآن؟»: right after onboarding (and later from the home or the Mushaf's marking mode), the student
 * picks the juz' and surahs they've memorized. The منازل stairs above climb as they choose; pages and single ayat are
 * marked in the Mushaf itself. [onFinish] is told whether the student chose to mark in the Mushaf next.
 */
@Composable
fun MemorizationSetupScreen(app: AqraApp, store: MushafStore, isSheet: Boolean, onFinish: (markInMushaf: Boolean) -> Unit) {
    val memorization = app.memorization
    val haptics = LocalHapticFeedback.current
    var showingJuz by rememberSaveable { mutableStateOf(true) }
    val count = memorization.count
    // A soft tick for each choice, and a fuller one when the whole Quran is chosen.
    var lastCount by remember { mutableStateOf(count) }
    LaunchedEffect(count) {
        if (count != lastCount) {
            haptics.performHapticFeedback(if (count == MushafStore.AYAH_COUNT) HapticFeedbackType.Confirm else HapticFeedbackType.SegmentTick)
            lastCount = count
        }
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(Palette.surface).then(if (isSheet) Modifier else Modifier.safeDrawingPadding())) {
        val landscape = maxWidth > maxHeight * 1.1f
        val scale = if (minOf(maxWidth.value, maxHeight.value) >= 600) 1.35f else 1f
        if (landscape) {
            Row(Modifier.fillMaxSize().padding(horizontal = (20 * scale).dp), horizontalArrangement = Arrangement.spacedBy((24 * scale).dp)) {
                Column(Modifier.fillMaxHeight().widthIn(max = (460 * scale).dp).weight(0.42f), verticalArrangement = Arrangement.spacedBy((16 * scale).dp)) {
                    Spacer(Modifier.weight(1f))
                    Hero(app, store, scale * 0.9f)
                    Spacer(Modifier.weight(1f))
                    Footer(count, isSheet, scale, onFinish)
                }
                Column(Modifier.weight(0.58f), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Controls(memorization, showingJuz, scale) { showingJuz = it }
                    SetupList(app, store, showingJuz, if (scale > 1) 5 else 4, scale, Modifier.weight(1f))
                }
            }
        } else {
            Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy((14 * scale).dp)) {
                Hero(app, store, scale, Modifier.padding(top = (12 * scale).dp))
                Box(Modifier.widthIn(max = 760.dp)) { Controls(memorization, showingJuz, scale) { showingJuz = it } }
                // On a tablet all thirty juz' fit without scrolling.
                SetupList(app, store, showingJuz, if (scale > 1) 6 else 3, if (scale > 1) 1.1f else 1f, Modifier.weight(1f).widthIn(max = 760.dp))
                Box(Modifier.widthIn(max = 560.dp)) { Footer(count, isSheet, scale, onFinish) }
            }
        }
    }
}

/** «ماذا تحفظ من القرآن؟», the summary, and the stairs climbing as juz' and surahs are chosen. */
@Composable
private fun Hero(app: AqraApp, store: MushafStore, scale: Float, modifier: Modifier = Modifier) {
    val memorization = app.memorization
    val share = memorization.quranShare(store)
    val reduceMotion = rememberReduceMotion()
    // The stairs' climb as shown; it follows the memorized count with a spring, starting from the bottom.
    val climb = remember { Animatable(0f) }
    var entered by remember { mutableStateOf(false) }
    LaunchedEffect(share) {
        val target = (share * Manazil.STEP_COUNT).toFloat()
        if (reduceMotion) climb.snapTo(target)
        else if (!entered) {
            delay(250)
            climb.animateTo(target, iosSpring(1.4f, 0.9f))
        } else climb.animateTo(target, iosSpring(0.9f, 0.85f))
        entered = true
    }
    Column(modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy((4 * scale).dp)) {
        FittedText(stringResource(R.string.what_have_you_memorized), aqraStyle(28f * scale, Weight.heavy, Palette.ink), minScale = 0.7f)
        FittedText(stringResource(R.string.of_the_quran_q), aqraStyle(28f * scale, Weight.heavy, Palette.brand), minScale = 0.7f)
        Text(memorizedSummary(app, store), style = aqraStyle(15f * scale, Weight.semibold, Palette.inkSoft), textAlign = TextAlign.Center)
        Stage(climb.value, share, memorization.count > 0, scale)
    }
}

/** «٥٦٤ آية · جزء واحد», or how to start when nothing is chosen yet. */
@Composable
fun memorizedSummary(app: AqraApp, store: MushafStore): String {
    val count = app.memorization.count
    if (count == 0) return stringResource(R.string.choose_what_youve_memorized_to_start_climbing)
    val fullJuz = (1..30).count { juz -> store.juzAyahs[juz]?.let { app.memorization.memorizedCount(it) == it.count() } ?: false }
    val ayat = pluralStringResource(R.plurals.n_ayat, count, count)
    return if (fullJuz > 0) ayat + factSeparator() + pluralStringResource(R.plurals.n_juz, fullJuz, fullJuz) else ayat
}

/** The home's stage, smaller: the stairs in their glowing rings, with the share of the Quran floating beside them. */
@Composable
private fun Stage(climb: Float, share: Double, hasMemorized: Boolean, scale: Float) {
    val rtl = LocalLayoutDirection.current == LayoutDirection.Rtl
    val mirror = if (rtl) 1f else -1f
    Box(Modifier.fillMaxWidth().height((168 * scale).dp), contentAlignment = Alignment.Center) {
        AqraGlowRings(Modifier.graphicsLayer { scaleX = 0.62f * scale; scaleY = 0.62f * scale })
        GlossyStairs(climb, Modifier.graphicsLayer {
            scaleX = 0.66f * scale; scaleY = 0.66f * scale; translationX = (6 * mirror * scale).dp.toPx()
        })
        AnimatedVisibility(hasMemorized, enter = scaleIn(initialScale = 0.4f) + fadeIn(), exit = scaleOut(targetScale = 0.4f) + fadeOut(),
            modifier = Modifier.graphicsLayer { translationX = (100 * mirror * scale).dp.toPx(); translationY = (-52 * scale).dp.toPx(); rotationZ = -4f * mirror }) {
            AqraChip("🪜", Palette.lavender) {
                Text(formatPercent(share) + " " + stringResource(R.string.of_the_quran), style = ChipText)
            }
        }
    }
}

/** Juz' or surahs, and the whole Quran at once. */
@Composable
private fun Controls(memorization: MemorizationStore, showingJuz: Boolean, scale: Float, onSection: (Boolean) -> Unit) {
    val isAll = memorization.count == MushafStore.AYAH_COUNT
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        AqraSegmented(showingJuz, listOf(true to stringResource(R.string.juz), false to stringResource(R.string.surahs)), onSection, scale = scale)
        Spacer(Modifier.weight(1f))
        Row(
            Modifier
                .height((46 * scale).dp)
                .background(if (isAll) Palette.butter else Color.White, CircleShape)
                .border(1.5.dp, if (isAll) Color(0xFFEFC46A) else Palette.lavender, CircleShape)
                .clip(CircleShape)
                .pressable(pressed = 0.96f) { memorization.mark(0 until MushafStore.AYAH_COUNT, memorized = !isAll) }
                .padding(horizontal = (14 * scale).dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            androidx.compose.foundation.Canvas(Modifier.size((16 * scale).dp)) {
                drawPath(starPath(size, 8, 0.42f, 0.05f), Brush.verticalGradient(LogoGold.star))
            }
            Text(stringResource(R.string.the_whole_quran), style = aqraStyle(14f * scale, Weight.bold, if (isAll) Color(0xFF8A5A12) else Palette.brand))
        }
    }
}

@Composable
private fun SetupList(app: AqraApp, store: MushafStore, showingJuz: Boolean, columns: Int, scale: Float, modifier: Modifier) {
    // The list fades out under the controls and above the footer rather than ending at a hard line.
    val fade = Modifier.graphicsLayer { compositingStrategy = androidx.compose.ui.graphics.CompositingStrategy.Offscreen }.drawWithFade()
    if (showingJuz) {
        LazyVerticalGrid(GridCells.Fixed(columns), modifier.then(fade), contentPadding = PaddingValues(vertical = 6.dp, horizontal = 2.dp),
            horizontalArrangement = Arrangement.spacedBy((12 * scale).dp), verticalArrangement = Arrangement.spacedBy((12 * scale).dp)) {
            items((1..30).toList()) { juz -> store.juzAyahs[juz]?.let { JuzTile(app.memorization, juz, it, scale) } }
        }
    } else {
        LazyColumn(modifier.then(fade), contentPadding = PaddingValues(vertical = 6.dp, horizontal = 2.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items((1..114).toList()) { surah -> store.surahAyahs[surah]?.let { SurahRow(app.memorization, store, surah, it) } }
        }
    }
}

private fun Modifier.drawWithFade(): Modifier = drawWithContent {
    drawContent()
    drawRect(Brush.verticalGradient(0f to Color.Transparent, 0.03f to Color.Black, 0.95f to Color.Black, 1f to Color.Transparent),
        blendMode = androidx.compose.ui.graphics.BlendMode.DstIn)
}

/** A juz' tile, in its band's color on the stairs, fills from the bottom up as its ayat are memorized. */
@Composable
private fun JuzTile(memorization: MemorizationStore, juz: Int, range: IntRange, scale: Float) {
    val fraction = memorization.memorizedCount(range).toFloat() / range.count()
    val shown by animateFloatAsState(fraction, iosSpring(0.45f, 0.8f), label = "juz$juz")
    // A small pop as a juz' is completed.
    val pop = remember { Animatable(1f) }
    LaunchedEffect(fraction == 1f) {
        if (fraction == 1f) {
            pop.animateTo(1.06f, iosSpring(0.12f, 0.7f))
            pop.animateTo(1f, iosSpring(0.35f, 0.5f))
        }
    }
    val (top, bottom) = StepFaces.forJuz(juz)
    val shape = RoundedCornerShape(20.dp)
    val percent = formatPercent(fraction.toDouble(), 0)
    val label = stringResource(R.string.juz_n, juz)
    Box(
        Modifier
            .height((72 * scale).dp)
            .graphicsLayer { scaleX = pop.value; scaleY = pop.value }
            .softShadow(shape, strength = if (fraction > 0) 2.5f else 0.5f, radius = 10.dp, y = 5.dp)
            .background(Color.White, shape)
            .clip(shape)
            .drawBehind {
                val height = size.height * shown
                drawRect(Brush.verticalGradient(listOf(top.copy(alpha = 0.75f), top), startY = size.height - height, endY = size.height),
                    topLeft = androidx.compose.ui.geometry.Offset(0f, size.height - height), size = androidx.compose.ui.geometry.Size(size.width, height))
            }
            .border(1.5.dp, if (fraction > 0) Color.White.copy(alpha = 0.7f) else top.copy(alpha = 0.9f), shape)
            .pressable(pressed = 0.96f) { memorization.mark(range, memorized = fraction < 1f) }
            .semantics { contentDescription = label; stateDescription = percent },
        contentAlignment = Alignment.Center,
    ) {
        Text(formatNumber(juz), style = aqraStyle(30f * scale, Weight.heavy, if (fraction > 0) Palette.ink else Palette.brand))
        AnimatedVisibility(fraction == 1f, Modifier.align(Alignment.TopEnd).padding(8.dp), enter = scaleIn() + fadeIn(), exit = scaleOut() + fadeOut()) {
            Box(Modifier.size(20.dp).background(bottom, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.Check, null, tint = Color.White, modifier = Modifier.size(13.dp))
            }
        }
    }
}

@Composable
private fun SurahRow(memorization: MemorizationStore, store: MushafStore, surah: Int, range: IntRange) {
    val memorized = memorization.memorizedCount(range)
    // The surah takes the band color of the juz' it begins in.
    val juz = (1..30).firstOrNull { store.juzAyahs[it]?.contains(range.first) == true } ?: 1
    val (top, bottom) = StepFaces.forJuz(juz)
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .softShadow(shape, strength = 0.5f, radius = 8.dp, y = 4.dp)
            .background(if (memorized == range.count()) top.copy(alpha = 0.35f).compositeOver(Color.White) else Color.White, shape)
            .clip(shape)
            .pressable(pressed = 0.96f) { memorization.mark(range, memorized = memorized < range.count()) }
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(38.dp).background(top, CircleShape), contentAlignment = Alignment.Center) {
            Text(formatNumber(surah), style = aqraStyle(14f, Weight.bold, Palette.ink))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(store.surahNames[surah].orEmpty(), style = aqraStyle(18f, Weight.bold, Palette.ink))
            Text(pluralStringResource(R.plurals.n_ayat, range.count(), range.count()), style = aqraStyle(13f, Weight.medium, Palette.inkSoft))
        }
        Icon(
            when {
                memorized == range.count() -> Icons.Rounded.CheckCircle
                memorized > 0 -> Icons.Rounded.Contrast
                else -> Icons.Rounded.RadioButtonUnchecked
            },
            contentDescription = null, tint = if (memorized > 0) bottom else Palette.lavender, modifier = Modifier.size(26.dp),
        )
    }
}

@Composable
private fun Footer(count: Int, isSheet: Boolean, scale: Float, onFinish: (Boolean) -> Unit) {
    // With nothing chosen, the student is starting from zero; once something is chosen, they continue.
    val title = when {
        isSheet -> R.string.done
        count == 0 -> R.string.im_just_starting
        else -> R.string.continue_action
    }
    val buttonScale = minOf(scale, 1.15f)
    Column(Modifier.padding(horizontal = 4.dp).padding(bottom = 8.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)) {
        BrandButton(stringResource(title), height = (56 * buttonScale).dp, fontSize = 18f * buttonScale) { onFinish(false) }
        if (!isSheet) {
            Text(
                stringResource(R.string.mark_pages_and_ayat_in_the_mushaf),
                style = aqraStyle(15f * buttonScale, Weight.semibold, Palette.brand),
                modifier = Modifier.clip(CircleShape).pressable { onFinish(true) }.padding(horizontal = 12.dp, vertical = 6.dp),
            )
        }
    }
}
