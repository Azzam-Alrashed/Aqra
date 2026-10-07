package com.azzamalrashed.aqra.mushaf

import com.azzamalrashed.aqra.TestQuran
import com.azzamalrashed.aqra.quran.MushafLine
import com.azzamalrashed.aqra.quran.WordLayout
import com.azzamalrashed.aqra.revision.cycleDays
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Where words sit on a page, and which ayah a tap lands on: the same checks as the iOS app's. */
class PageLayoutTest {
    private val store = TestQuran.store

    /** A page's words' widths in dp at the page's font size, as the page view measures them. */
    private fun widths(page: Int, metrics: PageMetrics): (Int) -> List<Float>? {
        val font = TestQuran.pageFont(page)
        return { line ->
            (store.page(page).lines[line].kind as? MushafLine.Kind.Ayah)?.words?.map {
                WordLayout.of(it.glyph, font).width * metrics.fontSize / font.unitsPerEm
            }
        }
    }

    @Test
    fun findsTheAyahUnderAPoint() {
        val metrics = PageMetrics(402f, 874f)
        val page = store.page(2)
        val top = metrics.linesTop(page.lines.size)
        val left = metrics.textLeft
        val widths = widths(2, metrics)
        // Line 3 opens al-Baqarah 1 (ayah 7, after al-Fatiha's seven) at its right end.
        assertEquals(7, ayahAt(left + metrics.textWidth - 4, top + 2.5f * metrics.lineHeight, page, metrics, widths))
        // The last line, al-Baqarah 5, is centered: a point in its empty left margin takes the nearest word.
        assertEquals(11, ayahAt(left + 2, top + 7.5f * metrics.lineHeight, page, metrics, widths))
        // The surah header and the basmala hold no ayah.
        assertNull(ayahAt(402f / 2, top + 0.5f * metrics.lineHeight, page, metrics, widths))
        assertNull(ayahAt(402f / 2, top + 1.5f * metrics.lineHeight, page, metrics, widths))
    }

    /** A justified line fills the line exactly; a centered one keeps the word gap and sits in the middle. */
    @Test
    fun linesAreJustifiedOrCentered() {
        val lefts = AyahLineLayout.lefts(listOf(10f, 20f, 30f), 100f, centered = false, wordSpacing = 5f)
        // Right to left: the first word ends at the right edge, the last starts at the left edge.
        assertEquals(90f, lefts[0], 1e-4f)
        assertEquals(0f, lefts[2], 1e-4f)
        val centered = AyahLineLayout.lefts(listOf(10f, 20f), 100f, centered = true, wordSpacing = 5f)
        assertEquals(57.5f, centered[0], 1e-4f)
        assertEquals(32.5f, centered[1], 1e-4f)
        // A zero-width mark takes no gap of its own.
        val withMark = AyahLineLayout.lefts(listOf(10f, 0f, 20f), 100f, centered = false, wordSpacing = 5f)
        assertEquals(withMark[0], withMark[1], 1e-4f)
    }

    @Test
    fun aFullRevisionCycleTakesTheMemorizedPagesOverTheDailyAmount() {
        assertEquals(30, cycleDays(300, 10))
        assertEquals(1, cycleDays(0, 5))
        assertEquals(21, cycleDays(41, 2))
    }
}
