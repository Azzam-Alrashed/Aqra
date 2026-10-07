package com.azzamalrashed.aqra.quran

import com.azzamalrashed.aqra.TestQuran
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.max

/**
 * Checks the app's own font reader against CoreText, the engine the iOS app draws with: every glyph of the 604 page
 * fonts must have the same box and the same area, and every word the same glyphs, positions and width.
 *
 * The reference is written on a Mac by tools/coretext-reference.swift (see README.md); without it, this is skipped.
 */
class CoreTextReferenceTest {
    private val directory = File(System.getProperty("aqra.coretextDir").orEmpty())

    private fun near(a: Double, b: Double, tolerance: Double) = abs(a - b) <= tolerance

    @Test
    fun everyGlyphMatchesCoreText() {
        val file = File(directory, "glyphs.tsv")
        assumeTrue("No CoreText reference at $file", file.exists())
        var checked = 0
        val mismatches = ArrayList<String>()
        var expectedNonEmpty = HashMap<Int, MutableSet<Int>>()
        file.forEachLine { row ->
            val fields = row.split('\t')
            val page = fields[0].toInt()
            val glyph = fields[1].toInt()
            expectedNonEmpty.getOrPut(page) { HashSet() } += glyph
            val outline = TestQuran.pageFont(page).outline(glyph)
            val box = outline.bounds()
            val expected = fields.subList(2, 6).map { it.toDouble() }
            val area = fields[6].toDouble()
            val matches = box != null && (0 until 4).all { near(box[it].toDouble(), expected[it], 0.01) } &&
                near(outline.area(), area, max(1.0, abs(area) * 1e-6))
            if (!matches) mismatches += "page $page glyph $glyph: CoreText $expected area $area, Aqra ${box?.toList()} area ${outline.area()}"
            checked += 1
        }
        // And no glyph is drawn where CoreText draws none.
        for ((page, glyphs) in expectedNonEmpty) {
            val font = TestQuran.pageFont(page)
            for (glyph in 0 until font.glyphCount) {
                if (glyph !in glyphs && !font.outline(glyph).isEmpty) mismatches += "page $page glyph $glyph: CoreText draws nothing"
            }
        }
        println("Checked $checked glyphs against CoreText")
        assertEquals(mismatches.take(20).joinToString("\n"), 0, mismatches.size)
    }

    /** CoreText's ascent, descent and leading are the font's `hhea` values, which differ on some pages. */
    @Test
    fun everyPageFontHasCoreTextsMetrics() {
        val file = File(directory, "metrics.tsv")
        assumeTrue("No CoreText reference at $file", file.exists())
        file.forEachLine { row ->
            val (page, ascent, descent, leading) = row.split('\t')
            val font = TestQuran.pageFont(page.toInt())
            assertEquals("page $page", ascent.toDouble(), font.ascender.toDouble(), 0.05)
            assertEquals("page $page", descent.toDouble(), -font.descender.toDouble(), 0.05)
            assertEquals("page $page", leading.toDouble(), font.lineGap.toDouble(), 0.05)
        }
    }

    /** The basmala (Hafs Smart) and the 114 surah headers are laid out as CoreText lays them out. */
    @Test
    fun theTextLinesAreLaidOutAsCoreTextDoes() {
        val file = File(directory, "texts.tsv")
        assumeTrue("No CoreText reference at $file", file.exists())
        val hafs = SfntFont.fromTrueType(TestQuran.read("kfgqpc/HafsSmart_08.ttf"))
        val header = SfntFont.fromTrueType(TestQuran.read("qul/QCF_SurahHeader_COLOR-Regular.ttf"))
        val store = TestQuran.store
        var checked = 0
        file.forEachLine { row ->
            val fields = row.split('\t')
            val (font, text) = if (fields[0] == "basmala") hafs to store.basmala
                else header to store.surahHeaders.getValue(fields[0].removePrefix("surah-").toInt())
            assertEquals(fields[0], fields[1].toDouble(), font.ascender * 1.0, 0.05)
            assertEquals(fields[0], fields[2].toDouble(), -font.descender * 1.0, 0.05)
            val layout = WordLayout.ofText(text, font)
            assertEquals(fields[0], fields[3].toDouble(), layout.width.toDouble(), 0.01)
            // CoreText keeps an invisible placeholder (glyph 65535) for a direction mark; it draws nothing.
            val expected = fields[4].split(' ').map { it.split('@') }.filter { it[0] != "65535" }
            assertEquals(fields[0], expected.map { it[0].toInt() }, layout.glyphs.toList())
            assertEquals(fields[0], expected.map { it[1].toDouble() }, layout.positions.map { it.toDouble() })
            checked += 1
        }
        assertEquals(115, checked)
    }

    /** Every ayah's words in the Hafs Smart font, each set on its own (the stage tests), as CoreText lays them out. */
    @Test
    fun theAyatAreLaidOutInHafsSmartAsCoreTextDoes() {
        val file = File(directory, "ayat.tsv")
        assumeTrue("No CoreText reference at $file", file.exists())
        val hafs = SfntFont.fromTrueType(TestQuran.read("kfgqpc/HafsSmart_08.ttf"))
        val words = TestQuran.store.ayahTexts.map { it.split(' ') }
        val mismatches = ArrayList<String>()
        var checked = 0
        file.forEachLine { row ->
            val (ayah, word, width, placed) = row.split('\t')
            val text = words[ayah.toInt()][word.toInt()]
            val layout = WordLayout.ofText(text, hafs)
            // CoreText keeps an invisible placeholder (glyph 65535) for a direction mark; it draws nothing.
            val expected = placed.split(' ').map { it.split('@') }.filter { it[0] != "65535" }
            val same = kotlin.math.abs(width.toDouble() - layout.width) < 0.01 &&
                expected.map { it[0].toInt() } == layout.glyphs.toList() &&
                expected.map { it[1].toDouble() } == layout.positions.map { it.toDouble() } &&
                expected.all { it[2].toDouble() == 0.0 }
            if (!same && mismatches.size < 20) mismatches += "$ayah:$word ${layout.glyphs.toList()}@${layout.positions.toList()} w=${layout.width}"
            checked += 1
        }
        assertEquals(mismatches.joinToString(), 0, mismatches.size)
        assertEquals(words.sumOf { it.size }, checked)
    }

    @Test
    fun everyWordIsLaidOutAsCoreTextDoes() {
        val file = File(directory, "words.tsv")
        assumeTrue("No CoreText reference at $file", file.exists())
        val text = HashMap<Int, String>()
        for (page in 1..MushafStore.PAGE_COUNT) {
            // The words of each page, in the layout's order, which is the order of their ids.
            val ids = HashMap<Int, String>()
            for (line in TestQuran.store.page(page).lines) {
                (line.kind as? MushafLine.Kind.Ayah)?.words?.forEach { ids[ids.size] = it.glyph }
            }
            text.putAll(ids.mapKeys { (index, _) -> page * 1000 + index })
        }
        val mismatches = ArrayList<String>()
        var index = 0
        var lastPage = 0
        var checked = 0
        file.forEachLine { row ->
            val fields = row.split('\t')
            val page = fields[0].toInt()
            if (page != lastPage) { index = 0; lastPage = page }
            val word = text.getValue(page * 1000 + index++)
            val layout = WordLayout.of(word, TestQuran.pageFont(page))
            val expected = fields.getOrElse(3) { "" }.split(' ').filter { it.isNotEmpty() }.map {
                val (glyph, x) = it.split('@')
                glyph.toInt() to x.toDouble()
            }
            val actual = layout.glyphs.indices.map { layout.glyphs[it] to layout.positions[it].toDouble() }
            val same = near(layout.width.toDouble(), fields[2].toDouble(), 0.01) && expected.size == actual.size &&
                expected.zip(actual).all { (e, a) -> e.first == a.first && near(e.second, a.second, 0.01) }
            if (!same) mismatches += "page $page word ${fields[1]}: CoreText ${fields[2]} $expected, Aqra ${layout.width} $actual"
            checked += 1
        }
        println("Checked $checked words against CoreText")
        assertEquals(mismatches.take(20).joinToString("\n"), 0, mismatches.size)
    }
}
