package com.azzamalrashed.aqra.quran

import com.azzamalrashed.aqra.TestQuran
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The page fonts as the app reads them: every word has a glyph, an outline and its tajweed colors. */
class PageFontTest {
    private val store = TestQuran.store

    /** Every word's characters have glyphs in its own page font, so no word can draw as a missing-glyph box. */
    @Test
    fun everyWordHasItsGlyphs() {
        for (page in 1..MushafStore.PAGE_COUNT) {
            val font = TestQuran.pageFont(page)
            for (line in store.page(page).lines) {
                val words = (line.kind as? MushafLine.Kind.Ayah)?.words ?: continue
                for (word in words) {
                    val glyphs = word.glyph.codePoints().toArray().map(font::glyph)
                    assertFalse("page $page line ${line.number}", glyphs.isEmpty() || 0 in glyphs)
                }
            }
        }
    }

    /**
     * Every word has an outline to draw, and every page has tajweed colors to tint it with. Only one word has no
     * width of its own: the pause sign after word 4 of Ghafir 40:77, page 475 line 14.
     */
    @Test
    fun everyWordHasAnOutlineAndEveryPageHasTajweed() {
        val zeroWidth = ArrayList<String>()
        for (page in 1..MushafStore.PAGE_COUNT) {
            val font = TestQuran.pageFont(page)
            var colored = 0
            for (line in store.page(page).lines) {
                val words = (line.kind as? MushafLine.Kind.Ayah)?.words ?: continue
                for (word in words) {
                    val layout = WordLayout.of(word.glyph, font)
                    assertFalse("page $page line ${line.number}", layout.outline(font).isEmpty)
                    if (layout.colorLayers(font).isNotEmpty()) colored += 1
                    if (layout.width <= 0f) zeroWidth += "$page:${line.number}"
                }
            }
            assertTrue("page $page has no tajweed colors", colored > 0)
        }
        assertEquals(listOf("475:14"), zeroWidth)
    }

    /** The page fonts carry their own light and dark tajweed palettes; Aqra reads them rather than hardcoding colors. */
    @Test
    fun pageFontsCarryTajweedPalettes() {
        for (page in listOf(1, 300, 604)) {
            val font = TestQuran.pageFont(page)
            assertEquals("page $page", 6, font.palettes.size)
            assertEquals("page $page", 16, font.palettes[0].size)
            assertEquals("page $page: entry 0 is the black ink", 0x000000, font.palettes[0][0])
            assertTrue("page $page", font.colorLayers.isNotEmpty())
        }
    }

    /** Every page font has 2,500 units per em; its ascent and descent, which vary a little, are checked against CoreText. */
    @Test
    fun pageFontsShareTheirEm() {
        for (page in 1..MushafStore.PAGE_COUNT) assertEquals(2500, TestQuran.pageFont(page).unitsPerEm)
    }
}
