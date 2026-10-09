package com.azzamalrashed.aqra.mushaf

import android.graphics.Paint
import android.graphics.RectF
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.memorization.MarkingSession
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.quran.MushafLine
import com.azzamalrashed.aqra.quran.MushafPage
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.quran.MushafWord
import com.azzamalrashed.aqra.revision.RevisionSession
import com.azzamalrashed.aqra.ui.theme.MushafStyle
import com.azzamalrashed.aqra.ui.theme.Weight
import com.azzamalrashed.aqra.ui.theme.aqraStyle
import com.azzamalrashed.aqra.ui.util.arabicDigits
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** What the Mushaf shows on its pages: the colors, and what a tap does. */
class MushafPageOptions(
    /** The page fonts' tajweed colors on the letters. */
    val tajweed: Boolean = true,
    /** Each topic section's soft highlight behind its memorized words. */
    val topics: Boolean = true,
    /** Whose memorization colors the page; null keeps the page plain (a teacher hearing a student). */
    val memorization: MemorizationStore? = null,
    /** Marking mode: taps mark ayat. */
    val marking: MarkingSession? = null,
    /** The revision under way, on its own page. */
    val revision: RevisionSession? = null,
    /** A revision for each page, where every page visited has its own (a listener hearing a recitation). */
    val revisions: ((page: Int) -> RevisionSession?)? = null,
    /** In a revision, what pressing and holding an ayah does (a listener classifying a stumble). */
    val onAyahLongPress: ((Int) -> Unit)? = null,
    /** While a new portion is memorized: its ayat, in focus on the page. */
    val focus: MemorizeFocus? = null,
    /** A tap on the page when it isn't marking or revising (shows and hides the Mushaf's bars). */
    val onTap: (() -> Unit)? = null,
) {
    /** The revision under way on a page, if any. */
    fun revisionOf(page: Int): RevisionSession? = revisions?.invoke(page) ?: revision?.takeIf { it.page == page }
}

/**
 * One Mushaf page: 15 lines in the page's own font, framed by the surah, juz' and page number. Memorized ayat sit on
 * their topic section's color; in marking mode, taps mark ayat; in revision, the page's memorized ayat are veiled and
 * revealed one at a time.
 */
@Composable
fun MushafPageView(
    page: MushafPage,
    store: MushafStore,
    fonts: MushafFonts,
    style: MushafStyle,
    options: MushafPageOptions,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val currentOptions by rememberUpdatedState(options)
    // The words are font outlines TalkBack can't read; it gets the page in plain text instead, without the ayat a
    // revision veils or a student hid while memorizing, and the page's taps as actions.
    val spokenRevision = options.revisionOf(page.number)
    val hidden: (Int) -> Boolean = { ayah ->
        spokenRevision?.isVeiled(ayah) ?: (options.focus?.let { ayah in it.hidden } ?: false)
    }
    val spoken = spokenText(page, store, hidden)
    val hiddenCount = page.spokenAyahs.count(hidden)
    val hiddenText = if (hiddenCount > 0) pluralStringResource(R.plurals.n_ayat_hidden, hiddenCount, hiddenCount) else ""
    val actions = pageActions(page, store, options, spokenRevision)
    // What a double tap does: in a revision it reveals the next ayah; where a tap means an ayah, nothing (the ayat are
    // actions), rather than landing on whichever ayah is mid-page; reading, it shows and hides the bars.
    val activation: (() -> Unit)? = when {
        spokenRevision != null -> { { if (!spokenRevision.isComplete) spokenRevision.revealNext() } }
        options.focus != null || options.marking != null -> { {} }
        else -> options.onTap
    }
    // The Mushaf reads right to left in every language.
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        BoxWithConstraints(
            modifier
                .background(style.paper)
                .clearAndSetSemantics {
                    contentDescription = spoken
                    if (hiddenText.isNotEmpty()) stateDescription = hiddenText
                    if (actions.isNotEmpty()) customActions = actions
                    activation?.let { activate -> onClick { activate(); true } }
                },
        ) {
            val metrics = remember(maxWidth, maxHeight) { PageMetrics(maxWidth.value, maxHeight.value) }
            val fontSize = with(density) { metrics.fontSize.dp.toPx() }
            val glyphs by produceState<PageGlyphs?>(null, page.number, fontSize) {
                value = fonts.pageAsync(store, page.number, fontSize)
            }
            val revision = options.revisionOf(page.number)

            // The header and footer bands.
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = metrics.margin.dp)
                    .padding(top = (metrics.topInset + 4).dp)
                    .height((PageMetrics.CHROME - 4).dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("الجزء ${arabicDigits(page.juz)}", style = aqraStyle(14f, Weight.semibold, style.chrome))
                Spacer(Modifier.weight(1f))
                Text(store.surahNames[page.surah].orEmpty(), style = aqraStyle(14f, Weight.semibold, style.chrome))
            }
            Box(
                Modifier.align(Alignment.BottomCenter).height(PageMetrics.CHROME.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    arabicDigits(page.number),
                    style = aqraStyle(13f, Weight.semibold, style.chrome),
                    modifier = Modifier
                        .border(1.dp, style.gold.copy(alpha = 0.6f), CircleShape)
                        .padding(horizontal = 14.dp, vertical = 3.dp),
                )
            }

            // The lines, drawn from the fonts' outlines.
            val paints = remember { PagePaints() }
            Canvas(
                Modifier
                    .fillMaxSize()
                    .pointerInput(page.number, metrics, glyphs) {
                        val glyphs = glyphs
                        fun ayah(x: Float, y: Float): Int? = ayahAt(x / density.density, y / density.density, page, metrics) { line ->
                            glyphs?.lines?.getOrNull(line)?.map { it.width / density.density }
                        }
                        detectTapGestures(
                            onLongPress = { point ->
                                val options = currentOptions
                                val ayah = ayah(point.x, point.y)
                                val revising = options.revisionOf(page.number)
                                when {
                                    revising != null && options.onAyahLongPress != null && ayah != null && revising.covers(ayah) ->
                                        options.onAyahLongPress.invoke(ayah)
                                    revising != null -> revising.tap(ayah)
                                    options.marking != null && ayah != null -> options.marking.beginRange(ayah)
                                }
                            },
                            onTap = { point ->
                                val options = currentOptions
                                val revising = options.revisionOf(page.number)
                                when {
                                    revising != null -> revising.tap(ayah(point.x, point.y))
                                    options.focus != null -> options.focus.tap(ayah(point.x, point.y))
                                    options.marking != null -> ayah(point.x, point.y)?.let(options.marking::tap)
                                    else -> options.onTap?.invoke()
                                }
                            },
                        )
                    },
            ) {
                val glyphs = glyphs ?: return@Canvas
                val px = density.density
                val top = metrics.linesTop(page.lines.size) * px
                val lineHeight = metrics.lineHeight * px
                val left = metrics.textLeft * px
                val lineWidth = metrics.textWidth * px
                page.lines.forEachIndexed { index, line ->
                    val lineTop = top + index * lineHeight
                    when (val kind = line.kind) {
                        is MushafLine.Kind.SurahName -> drawText(
                            fonts.text(store.surahHeaders[kind.surah].orEmpty(), fonts.headerFont, lineWidth * 0.96f / PageMetrics.HEADER_WIDTH_IN_EM),
                            left, lineTop, lineWidth, lineHeight, style.ornament, highlight = null, paints = paints,
                        )
                        MushafLine.Kind.Basmala -> {
                            // The basmala takes the color of the surah's first section once its first ayah is memorized.
                            val color = if (options.topics) highlight(firstWord(page, line), options)?.let { style.topicColor(it) } else null
                            drawText(
                                fonts.text(store.basmala, fonts.hafsFont, glyphs.fontSize * 1.05f),
                                left, lineTop, lineWidth, lineHeight, style.ink, color, paints, padding = glyphs.fontSize * 0.5f,
                            )
                        }
                        is MushafLine.Kind.Ayah -> {
                            val words = glyphs.lines[index] ?: return@forEachIndexed
                            val lineWords = kind.words.mapIndexed { i, word ->
                                LineWord(
                                    isAyahEnd = word.isAyahEnd,
                                    highlight = if (options.topics) highlight(word, options) else null,
                                    state = state(word, options, revision),
                                    glyph = words[i],
                                )
                            }
                            drawAyahLine(lineWords, kind.centered, options.tajweed, glyphs.fontSize, left, lineTop, lineWidth, lineHeight, style, paints)
                        }
                    }
                }
            }
        }
    }
}

/** The page for TalkBack: the official plain (Imla'i) text, with the surah, juz' and page first, without hidden ayat. */
private fun spokenText(page: MushafPage, store: MushafStore, hidden: (Int) -> Boolean): String {
    val surah = store.surahNames[page.surah].orEmpty()
    val heading = "سورة $surah، الجزء ${arabicDigits(page.juz)}، الصفحة ${arabicDigits(page.number)}."
    val read = page.spokenAyat.filterIndexed { index, _ -> page.spokenAyahs.getOrNull(index)?.let(hidden) != true }
    return (listOf(heading) + read).joinToString(" ")
}

/**
 * The page's taps, for TalkBack: revealing and marking stumbles in a revision, hiding and showing ayat while
 * memorizing, and marking ayat in marking mode.
 */
@Composable
private fun pageActions(page: MushafPage, store: MushafStore, options: MushafPageOptions, revision: RevisionSession?): List<CustomAccessibilityAction> {
    val ayat = page.spokenAyahs
    val surahs = remember(page.number) { ayat.map { store.reference(it).first }.toSet() }
    @Composable
    fun name(ayah: Int): String {
        val (surah, number) = store.reference(ayah)
        // By its number, and its surah too when the page has more than one.
        return if (surahs.size > 1) stringResource(R.string.ayah_n_of_s, number, store.surahNames[surah].orEmpty())
        else stringResource(R.string.ayah_n, number)
    }
    fun action(label: String, perform: () -> Unit) = CustomAccessibilityAction(label) { perform(); true }
    val actions = ArrayList<CustomAccessibilityAction>()
    val focus = options.focus
    val marking = options.marking
    when {
        revision != null -> {
            if (!revision.isComplete) actions += action(stringResource(R.string.reveal_the_next_ayah)) { revision.revealNext() }
            for (ayah in ayat.filter { revision.covers(it) && !revision.isVeiled(it) }) {
                val ayahName = name(ayah)
                actions += if (ayah in revision.stumbles) action(stringResource(R.string.remove_the_stumble_on_s, ayahName)) { revision.clearStumble(ayah) }
                else action(stringResource(R.string.stumbled_on_s, ayahName)) { revision.markStumble(ayah) }
                options.onAyahLongPress?.let { classify ->
                    actions += action(stringResource(R.string.say_what_kind_of_stumble_on_s, ayahName)) { classify(ayah) }
                }
            }
        }
        focus != null -> for (ayah in ayat.filter { it in focus.ayahs }) {
            val ayahName = name(ayah)
            val label = when {
                focus.choosingEnd -> stringResource(R.string.i_memorized_up_to_s, ayahName)
                ayah in focus.hidden -> stringResource(R.string.show_s, ayahName)
                else -> stringResource(R.string.hide_s, ayahName)
            }
            actions += action(label) { focus.tap(ayah) }
        }
        marking != null -> for (ayah in ayat) {
            val ayahName = name(ayah)
            val label = if (marking.memorization.isMemorized(ayah)) stringResource(R.string.unmark_s, ayahName)
                else stringResource(R.string.mark_s_as_memorized, ayahName)
            actions += action(label) { marking.tap(ayah) }
        }
    }
    return actions
}

/** The soft highlight behind a memorized word: its section's color, faint when new and fuller as it grows strong. */
class TopicHighlight(val topic: Int, strength: Double) {
    /** The strength in five steps, so ayat of nearly equal strength share one shade. */
    val level: Int = (strength.coerceIn(0.0, 1.0) * 4).roundToInt()

    companion object {
        /** Its size, as fractions of the line height. */
        const val HEIGHT = 0.76f
        const val CORNER_RADIUS = 0.3f
        /** The space left between two sections' highlights on one line, as a fraction of the word spacing. */
        const val SEPARATION = 0.5f
    }
}

private fun MushafStyle.topicColor(highlight: TopicHighlight, level: Int = highlight.level): Color =
    topic(highlight.topic).copy(alpha = 0.5f + 0.5f * level / 4f)

/** A memorized word's highlight; null for words not memorized, which stay on plain paper. */
private fun highlight(word: MushafWord?, options: MushafPageOptions): TopicHighlight? {
    val topic = word?.topic ?: return null
    val strength = options.memorization?.strength(word.ayah) ?: return null
    return TopicHighlight(topic, strength)
}

/** The first word after a line on this page. */
private fun firstWord(page: MushafPage, line: MushafLine): MushafWord? =
    page.lines.firstOrNull { it.number > line.number && it.kind is MushafLine.Kind.Ayah }
        ?.let { (it.kind as MushafLine.Kind.Ayah).words.firstOrNull() }

/** How a word draws during a revision of this page, or while a portion is memorized. */
private fun state(word: MushafWord, options: MushafPageOptions, revision: RevisionSession?): WordState {
    options.focus?.let { focus ->
        if (word.ayah !in focus.ayahs) return WordState.DIMMED
        if (focus.choosingEnd) return if (focus.isChosen(word.ayah)) WordState.CHOSEN else WordState.NORMAL
        return if (word.ayah in focus.hidden) WordState.VEILED else WordState.NORMAL
    }
    revision ?: return WordState.NORMAL
    if (!revision.covers(word.ayah)) return WordState.DIMMED
    if (revision.isVeiled(word.ayah, word.position)) return WordState.VEILED
    if (RevisionSession.WordRef(word.ayah, word.position) in revision.prompts) return WordState.PROMPTED
    return if (word.ayah in revision.stumbles) WordState.STUMBLED else WordState.NORMAL
}

enum class WordState {
    NORMAL,
    /** Not yet revealed in a revision: a soft bar where the word sits. */
    VEILED,
    /** Revealed and marked as stumbled on. */
    STUMBLED,
    /** Shown as a prompt after a long pause. */
    PROMPTED,
    /** Chosen as memorized, when only part of a portion was. */
    CHOSEN,
    /** Not memorized, so not part of the revision under way. */
    DIMMED,
}

/** A word as a line draws it. */
private class LineWord(val isAyahEnd: Boolean, val highlight: TopicHighlight?, val state: WordState, val glyph: WordGlyph)

/** Reused paints, so drawing a page allocates nothing. */
private class PagePaints {
    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    val rect = RectF()
}

/** A line drawn as text (a surah header, the basmala), centered in its line, with an optional highlight behind. */
private fun DrawScope.drawText(
    glyph: WordGlyph, left: Float, top: Float, width: Float, height: Float, color: Color, highlight: Color?, paints: PagePaints,
    padding: Float = 0f,
) {
    drawIntoCanvas { canvas ->
        val native = canvas.nativeCanvas
        val x = left + (width - glyph.width) / 2
        val y = top + (height - glyph.height) / 2
        if (highlight != null) {
            val boxHeight = height * TopicHighlight.HEIGHT
            paints.rect.set(x - padding, top + (height - boxHeight) / 2, x + glyph.width + padding, top + (height + boxHeight) / 2)
            paints.fill.color = highlight.toArgb()
            native.drawRoundRect(paints.rect, height * TopicHighlight.CORNER_RADIUS, height * TopicHighlight.CORNER_RADIUS, paints.fill)
        }
        native.save()
        native.translate(x, y)
        paints.fill.color = color.toArgb()
        native.drawPath(glyph.outline, paints.fill)
        native.restore()
    }
}

/** One line of ayat, drawn word by word from the page font's outlines and spaced by [AyahLineLayout]. */
private fun DrawScope.drawAyahLine(
    words: List<LineWord>, centered: Boolean, tajweed: Boolean, fontSize: Float,
    left: Float, top: Float, width: Float, height: Float, style: MushafStyle, paints: PagePaints,
) {
    val wordSpacing = fontSize * 0.25f
    val lefts = AyahLineLayout.lefts(words.map { it.glyph.width }, width, centered, wordSpacing).map { it + left }
    drawIntoCanvas { canvas ->
        val native = canvas.nativeCanvas
        drawHighlights(native, words, lefts, top, height, wordSpacing, style, paints)
        drawWashes(WordState.STUMBLED, style.stumble, native, words, lefts, top, height, fontSize, paints)
        drawWashes(WordState.CHOSEN, style.chosen, native, words, lefts, top, height, fontSize, paints)
        drawWashes(WordState.PROMPTED, style.prompt, native, words, lefts, top, height, fontSize, paints)
        val ink = style.ink.toArgb()
        for ((word, wordLeft) in words.zip(lefts)) {
            native.save()
            native.translate(wordLeft, top + (height - word.glyph.height) / 2)
            val box = word.glyph.inkBox
            if (word.isAyahEnd) {
                // A soft oval laid exactly behind the marker's rosette; an ayah stumbled on shows it in coral.
                val alpha = if (word.state == WordState.DIMMED) 0.35f else 1f
                paints.rect.set(box.left + box.width() * 0.07f, box.top + box.height() * 0.08f, box.right - box.width() * 0.07f, box.bottom - box.height() * 0.08f)
                val fill = when (word.state) {
                    WordState.STUMBLED -> style.stumble
                    WordState.CHOSEN -> style.chosen
                    else -> style.markerFill
                }
                paints.fill.color = fill.copy(alpha = alpha).toArgb()
                native.drawOval(paints.rect, paints.fill)
                paints.fill.color = style.marker.copy(alpha = alpha).toArgb()
                native.drawPath(word.glyph.outline, paints.fill)
                native.restore()
                continue
            }
            when (word.state) {
                WordState.VEILED -> {
                    // A soft bar in the word's own place and width, around the body of its letters.
                    val barHeight = fontSize * 0.62f
                    val barTop = word.glyph.baseline - fontSize * 0.3f - barHeight / 2
                    paints.rect.set(box.left, barTop, box.right, barTop + barHeight)
                    paints.fill.color = style.veil.toArgb()
                    native.drawRoundRect(paints.rect, barHeight / 2, barHeight / 2, paints.fill)
                }
                WordState.DIMMED -> {
                    paints.fill.color = style.ink.copy(alpha = 0.3f).toArgb()
                    native.drawPath(word.glyph.outline, paints.fill)
                }
                WordState.NORMAL, WordState.STUMBLED, WordState.CHOSEN, WordState.PROMPTED -> {
                    paints.fill.color = ink
                    native.drawPath(word.glyph.outline, paints.fill)
                    if (tajweed && word.glyph.layers.isNotEmpty()) {
                        // The colors tint the letters they belong to and nothing outside them.
                        native.clipPath(word.glyph.outline)
                        for (layer in word.glyph.layers) {
                            paints.fill.color = (0xFF shl 24) or (if (style.dark) layer.dark else layer.light)
                            native.drawPath(layer.path, paints.fill)
                        }
                    }
                }
            }
            native.restore()
        }
    }
}

/**
 * A wash behind each run of words in a state — coral for stumbles, mint for ayat chosen as memorized, gold for prompts —
 * joined across the gaps between them.
 */
private fun drawWashes(
    state: WordState, color: Color, native: android.graphics.Canvas, words: List<LineWord>, lefts: List<Float>, top: Float,
    height: Float, fontSize: Float, paints: PagePaints,
) {
    var index = 0
    while (index < words.size) {
        if (words[index].state != state) { index += 1; continue }
        var end = index
        while (end + 1 < words.size && words[end + 1].state == state) end += 1
        val glyph = words[index].glyph
        val wordTop = top + (height - glyph.height) / 2
        val right = lefts[index] + glyph.width + fontSize * 0.1f
        val left = lefts[end] - fontSize * 0.1f
        val washTop = wordTop + glyph.baseline - fontSize * 0.95f
        paints.rect.set(left, washTop, right, washTop + fontSize * 1.3f)
        paints.fill.color = color.toArgb()
        native.drawRoundRect(paints.rect, fontSize * 0.35f, fontSize * 0.35f, paints.fill)
        index = end + 1
    }
}

/**
 * Colors each run of memorized words from the same topic section with one soft highlight, shaded within it ayah by
 * ayah by how strong each one's memorization is.
 */
private fun drawHighlights(
    native: android.graphics.Canvas, words: List<LineWord>, lefts: List<Float>, top: Float, height: Float, wordSpacing: Float,
    style: MushafStyle, paints: PagePaints,
) {
    // Runs of consecutive words in the same section; a zero-width mark stays with the word before it.
    class Run(val topic: Int?, val first: Int, var last: Int)
    val runs = ArrayList<Run>()
    words.forEachIndexed { index, word ->
        val run = runs.lastOrNull()
        if (run != null && (run.topic == word.highlight?.topic || word.glyph.width == 0f)) run.last = index
        else runs += Run(word.highlight?.topic, index, index)
    }
    if (runs.none { it.topic != null }) return
    val edges = runs.map { (lefts[it.first] + words[it.first].glyph.width) to lefts[it.last] }
    // Each highlight reaches a little past its words. Where one section ends and the next begins on a line, the
    // starting section keeps its reach and the ending one gives way, leaving a small space between them.
    val separation = TopicHighlight.SEPARATION * wordSpacing
    fun startReach(index: Int): Float {
        if (index == 0) return wordSpacing
        return min(wordSpacing, max(edges[index - 1].second - edges[index].first - separation, 0f))
    }
    fun endReach(index: Int): Float {
        if (index == runs.size - 1) return wordSpacing
        val gap = edges[index].second - edges[index + 1].first
        return min(wordSpacing, max(gap - startReach(index + 1) - separation, 0f))
    }
    for ((index, run) in runs.withIndex()) {
        val topic = run.topic ?: continue
        val right = edges[index].first + startReach(index)
        val left = edges[index].second - endReach(index)
        val boxTop = top + height * (1 - TopicHighlight.HEIGHT) / 2
        val boxBottom = boxTop + height * TopicHighlight.HEIGHT
        val radius = height * TopicHighlight.CORNER_RADIUS
        native.save()
        val clip = android.graphics.Path().apply {
            addRoundRect(RectF(left, boxTop, right, boxBottom), radius, radius, android.graphics.Path.Direction.CW)
        }
        native.clipPath(clip)
        // Within the section, each stretch of words at one strength gets its shade, meeting its neighbor halfway
        // across the gap between them.
        var segmentRight = right
        var wordIndex = run.first
        while (wordIndex <= run.last) {
            val level = words[wordIndex].highlight?.level ?: 0
            var end = wordIndex
            while (end < run.last && ((words[end + 1].highlight?.level ?: level) == level || words[end + 1].glyph.width == 0f)) end += 1
            val segmentLeft = if (end < run.last) (lefts[end] + lefts[end + 1] + words[end + 1].glyph.width) / 2 else left
            paints.fill.color = style.topic(topic).copy(alpha = 0.5f + 0.5f * level / 4f).toArgb()
            native.drawRect(segmentLeft, boxTop, segmentRight, boxBottom, paints.fill)
            segmentRight = segmentLeft
            wordIndex = end + 1
        }
        native.restore()
    }
}

/** A miniature of a Mushaf page: the real page, drawn at a phone's size and scaled down. */
@Composable
fun MushafThumbnail(page: MushafPage, store: MushafStore, fonts: MushafFonts, memorization: MemorizationStore?, modifier: Modifier = Modifier) {
    val style = MushafStyle.LIGHT
    BoxWithConstraints(modifier.background(style.paper).clipToBounds().clearAndSetSemantics {}) {
        val scale = min(maxWidth.value / 380f, maxHeight.value / 600f)
        Box(
            Modifier
                .wrapContentSize(AbsoluteAlignment.TopLeft, unbounded = true)
                .requiredSize(380.dp, 600.dp)
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    transformOrigin = TransformOrigin(0f, 0f)
                },
        ) {
            MushafPageView(page, store, fonts, style, MushafPageOptions(memorization = memorization), Modifier.fillMaxSize())
        }
    }
}

/**
 * A new portion being memorized: its ayat stand out on the page and the rest fade back; a tap hides an ayah to recite
 * it from memory, or, when choosing where the student stopped, picks the last ayah memorized.
 */
class MemorizeFocus(
    /** The portion, in the order it's memorized. */
    val portion: List<Int>,
) {
    val ayahs: Set<Int> = portion.toSet()
    var hidden: Set<Int> by androidx.compose.runtime.mutableStateOf(emptySet())
        private set
    /** Choosing the last ayah memorized, when only part of the portion was. */
    var choosingEnd: Boolean by androidx.compose.runtime.mutableStateOf(false)
    var end: Int? by androidx.compose.runtime.mutableStateOf(null)
        private set

    fun tap(ayah: Int?) {
        if (ayah == null || ayah !in ayahs) return
        when {
            choosingEnd -> end = ayah
            ayah in hidden -> hidden = hidden - ayah
            else -> hidden = hidden + ayah
        }
    }

    fun hideAll() { hidden = ayahs }
    fun showAll() { hidden = emptySet() }

    /** The ayat memorized when the student stopped at [end]: the portion up to it. */
    val memorizedPart: List<Int>
        get() {
            val index = end?.let(portion::indexOf) ?: return emptyList()
            return if (index < 0) emptyList() else portion.subList(0, index + 1)
        }

    /** Whether an ayah is part of what's chosen as memorized. */
    fun isChosen(ayah: Int): Boolean = ayah in memorizedPart
}
