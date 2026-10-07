package com.azzamalrashed.aqra.mushaf

import com.azzamalrashed.aqra.quran.MushafLine
import com.azzamalrashed.aqra.quran.MushafPage
import kotlin.math.floor
import kotlin.math.min

/**
 * Where everything sits on a page of a given size, in dp. The page view and its gestures both use it, so a tap lands
 * on exactly the ayah drawn under it. The same numbers as the iOS app's.
 */
class PageMetrics(val width: Float, val height: Float) {
    companion object {
        /** The words of a full 1441H line add up to at most 17 em in the QCF V4 fonts; leave room for the word gaps. */
        const val LINE_WIDTH_IN_EM = 17.4f
        /** A surah header glyph is 3.3 em wide. */
        const val HEADER_WIDTH_IN_EM = 3.303f
        const val LINES_PER_PAGE = 15f
        /** The header and footer bands. */
        const val CHROME = 30f
    }

    private val roomy = width > 600
    val margin = if (roomy) 40f else 14f
    val textWidth = min(width - margin * 2, 620f)
    /** Clears the top corner on a wide window. */
    val topInset = if (roomy) 26f else 0f
    val lineHeight = (height - CHROME * 2 - topInset) / LINES_PER_PAGE
    val fontSize = min(textWidth / LINE_WIDTH_IN_EM, lineHeight / 1.6f)
    val wordSpacing: Float get() = fontSize * 0.25f

    /** The text block's left edge: it's centered when the page is wider than a line. */
    val textLeft: Float get() = (width - textWidth) / 2

    /** The top of the first line. Pages with fewer than 15 lines (the first two) center them in the text block. */
    fun linesTop(count: Int): Float = topInset + CHROME + (LINES_PER_PAGE - count) * lineHeight / 2
}

/**
 * How the words of a line are spaced, like the printed page: spread to fill the line, or together in the middle on a
 * centered line.
 */
object AyahLineLayout {
    /**
     * Each word's left edge from the line's left edge, given the words' widths in reading order (right to left). A
     * word of zero width is a mark that belongs over the word before it (a pause sign in Ghafir 40:77), so it takes
     * no gap of its own.
     */
    fun lefts(widths: List<Float>, lineWidth: Float, centered: Boolean, wordSpacing: Float): FloatArray {
        val total = widths.sum()
        val gaps = (widths.count { it > 0 } - 1).coerceAtLeast(0).toFloat()
        val justified = !centered && gaps > 0
        val spacing = if (justified) (lineWidth - total) / gaps else wordSpacing
        var x = (if (justified) lineWidth else (lineWidth + total + spacing * gaps) / 2) + spacing
        return FloatArray(widths.size) { i ->
            val width = widths[i]
            if (width > 0) x -= spacing
            x -= width
            x
        }
    }
}

/**
 * The ayah under a point (in dp, from the page's top left) on a page of the given size: the word on that line whose
 * box holds the point, or the nearest one. Null off the ayah lines (headers, the basmala and the margins).
 * [widths] gives each word's width in dp on a line, from the page's glyphs.
 */
fun ayahAt(x: Float, y: Float, page: MushafPage, metrics: PageMetrics, widths: (lineIndex: Int) -> List<Float>?): Int? {
    val top = metrics.linesTop(page.lines.size)
    val index = floor((y - top) / metrics.lineHeight).toInt()
    if (index !in page.lines.indices) return null
    val kind = page.lines[index].kind as? MushafLine.Kind.Ayah ?: return null
    val lineWidths = widths(index) ?: return null
    val lefts = AyahLineLayout.lefts(lineWidths, metrics.textWidth, kind.centered, metrics.wordSpacing)
    val local = x - metrics.textLeft
    fun distance(i: Int): Float {
        val left = lefts[i]
        val right = left + lineWidths[i]
        return if (local < left) left - local else if (local > right) local - right else 0f
    }
    val nearest = kind.words.indices.filter { lineWidths[it] > 0 }.minByOrNull(::distance) ?: return null
    return kind.words[nearest].ayah
}
