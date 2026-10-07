package com.azzamalrashed.aqra.mushaf

import android.graphics.Path
import android.graphics.RectF
import com.azzamalrashed.aqra.quran.MushafLine
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.quran.Outline
import com.azzamalrashed.aqra.quran.QuranFiles
import com.azzamalrashed.aqra.quran.SfntFont
import com.azzamalrashed.aqra.quran.WordLayout
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** A word (or a line of text) ready to draw: its outline in pixels, its frame, and its tajweed layers. */
class WordGlyph(
    /** The whole word as one outline. This is the text as drawn, with or without tajweed. */
    val outline: Path,
    /** The word's colored tajweed layers in drawing order, painted only inside the outline. */
    val layers: List<TajweedLayer>,
    /** The tight box around its ink, in the word's frame. */
    val inkBox: RectF,
    /** The baseline's distance from the frame's top (the font's ascent). */
    val baseline: Float,
    /** The frame CoreText gives it: its advance, and the font's ascent plus descent plus leading. */
    val width: Float,
    val height: Float,
) {
    val isEmpty: Boolean get() = outline.isEmpty
}

/** One tajweed color layer: its outline, and its color in the font's light and dark palettes (0xRRGGBB). */
class TajweedLayer(val path: Path, val light: Int, val dark: Int)

/** A page's words at one font size, line by line (null for the header and basmala lines). */
class PageGlyphs(val fontSize: Float, val lines: List<List<WordGlyph>?>)

/**
 * The Mushaf's fonts, read from the app's assets with Aqra's own font reader (see `SfntFont`): the 604 page fonts,
 * whose glyphs are the page's words, the surah header font and the Hafs Smart font for the basmala. Words are drawn
 * from their plain outlines, and the tajweed colors only tint them, as on iOS.
 */
class MushafFonts(private val files: QuranFiles) {
    private val fonts = LinkedHashMap<Int, SfntFont>()
    private val pages = LinkedHashMap<String, PageGlyphs>()
    private val tajweedColors = HashMap<Int, Array<IntArray?>>()

    /** The words of the pages read most recently; older pages are let go so reading the whole Mushaf stays light. */
    private val pagesKept = 12

    val headerFont: SfntFont by lazy { SfntFont.fromTrueType(files.read("qul/QCF_SurahHeader_COLOR-Regular.ttf")) }
    val hafsFont: SfntFont by lazy { SfntFont.fromTrueType(files.read("kfgqpc/HafsSmart_08.ttf")) }

    @Synchronized
    fun pageFont(page: Int): SfntFont {
        fonts[page]?.let {
            fonts.remove(page)
            fonts[page] = it
            return it
        }
        val font = SfntFont.fromWoff2(files.read(MushafStore.pageFontPath(page)))
        fonts[page] = font
        while (fonts.size > pagesKept) {
            val oldest = fonts.keys.first()
            fonts.remove(oldest)
            tajweedColors.remove(oldest)
        }
        return font
    }

    /** A page's words at a font size in pixels, made the first time and kept for the most recent pages. */
    @Synchronized
    fun page(store: MushafStore, number: Int, fontSize: Float): PageGlyphs {
        val key = "$number@$fontSize"
        pages[key]?.let { return it }
        val font = pageFont(number)
        val colors = tajweedColors.getOrPut(number) { tajweedPalette(font) }
        val lines = store.page(number).lines.map { line ->
            (line.kind as? MushafLine.Kind.Ayah)?.words?.map { word ->
                glyph(font, WordLayout.of(word.glyph, font), fontSize, colors)
            }
        }
        val glyphs = PageGlyphs(fontSize, lines)
        pages[key] = glyphs
        while (pages.size > pagesKept * 2) pages.remove(pages.keys.first())
        return glyphs
    }

    /** The same, off the main thread. */
    suspend fun pageAsync(store: MushafStore, number: Int, fontSize: Float): PageGlyphs =
        withContext(Dispatchers.Default) { page(store, number, fontSize) }

    private val texts = HashMap<String, WordGlyph>()

    /**
     * A line in one of the text fonts (a surah header, the basmala) at a font size in pixels. It has its own lock: the
     * page being drawn shouldn't wait for another page being prepared in the background.
     */
    fun text(text: String, font: SfntFont, fontSize: Float): WordGlyph = synchronized(texts) {
        texts.getOrPut("${System.identityHashCode(font)}#$fontSize#$text") {
            glyph(font, WordLayout.ofText(text, font), fontSize, emptyArray())
        }
    }

    /**
     * Each palette entry's tajweed color, from the font's light palette (0) and dark palette (1); null for the
     * entries that are the text's own black, which stay in Aqra's ink.
     */
    private fun tajweedPalette(font: SfntFont): Array<IntArray?> {
        val palettes = font.palettes
        if (palettes.size < 2) return emptyArray()
        return Array(palettes[0].size) { entry ->
            val light = palettes[0][entry]
            val isText = (light shr 16 and 0xFF) < 0x20 && (light shr 8 and 0xFF) < 0x20 && (light and 0xFF) < 0x20
            if (isText) null else intArrayOf(light, palettes[1][entry])
        }
    }

    private fun glyph(font: SfntFont, layout: WordLayout, fontSize: Float, colors: Array<IntArray?>): WordGlyph {
        val scale = fontSize / font.unitsPerEm
        val ascent = font.ascender * scale
        val outline = layout.outline(font)
        val layers = if (colors.isEmpty()) emptyList() else layout.colorLayers(font).mapNotNull { (layer, entry) ->
            val color = colors.getOrNull(entry) ?: return@mapNotNull null
            TajweedLayer(layer.toPath(scale, ascent), color[0], color[1])
        }
        val bounds = outline.bounds()
        val inkBox = if (bounds == null) RectF() else RectF(bounds[0] * scale, ascent - bounds[3] * scale, bounds[2] * scale, ascent - bounds[1] * scale)
        return WordGlyph(
            outline = outline.toPath(scale, ascent),
            layers = layers,
            inkBox = inkBox,
            baseline = ascent,
            width = layout.width * scale,
            height = (font.ascender - font.descender + font.lineGap) * scale,
        )
    }
}

/** An outline in font units (y up) as a path in pixels (y down), its baseline [ascent] below the top. */
fun Outline.toPath(scale: Float, ascent: Float): Path {
    val path = Path()
    forEach(
        move = { x, y -> path.moveTo(x * scale, ascent - y * scale) },
        line = { x, y -> path.lineTo(x * scale, ascent - y * scale) },
        quad = { cx, cy, x, y -> path.quadTo(cx * scale, ascent - cy * scale, x * scale, ascent - y * scale) },
        close = { path.close() },
    )
    return path
}
