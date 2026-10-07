package com.azzamalrashed.aqra.quran

import com.azzamalrashed.aqra.TestQuran
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** The Mushaf built from the shared data: the same checks as the iOS app's MushafStoreTests. */
class MushafStoreTest {
    private val store = TestQuran.store

    private fun ayahLines(page: Int) = store.page(page).lines.mapNotNull { it.kind as? MushafLine.Kind.Ayah }

    @Test
    fun pagesHaveFifteenLines() {
        for (number in 1..MushafStore.PAGE_COUNT) {
            val page = store.page(number)
            assertEquals(number, page.number)
            // Pages 1 and 2 (al-Fatiha and the start of al-Baqarah) are shorter in the Madinah Mushaf.
            assertEquals("page $number", if (number <= 2) 8 else 15, page.lines.size)
        }
    }

    @Test
    fun layoutHasEverySurahAndWord() {
        var surahs = 0
        var words = 0
        var ayahEnds = 0
        for (number in 1..MushafStore.PAGE_COUNT) {
            for (line in store.page(number).lines) {
                when (val kind = line.kind) {
                    is MushafLine.Kind.SurahName -> surahs += 1
                    is MushafLine.Kind.Ayah -> {
                        words += kind.words.size
                        ayahEnds += kind.words.count { it.isAyahEnd }
                        assertFalse("empty glyph on page $number line ${line.number}", kind.words.any { it.glyph.isEmpty() })
                    }
                    MushafLine.Kind.Basmala -> Unit
                }
            }
        }
        assertEquals(114, surahs)
        // 77,432 words plus 6,236 ayah-end markers, as in the QUL glyph data.
        assertEquals(83_668, words)
        assertEquals(6_236, ayahEnds)
    }

    @Serializable
    private class OfficialLine(val page: Int, val line_end: Int)

    /** The 1441H layout puts every ayah on the same page, and ends it on the same line, as the official data. */
    @Test
    fun everyAyahEndsWhereTheOfficialDataSays() {
        val json = Json { ignoreUnknownKeys = true }
        val official = json.decodeFromString<List<OfficialLine>>(File(TestQuran.directory, "kfgqpc/hafs_smart_v8.json").readText())
            .groupingBy { "${it.page}:${it.line_end}" }.eachCount()
        val layout = HashMap<String, Int>()
        for (number in 1..MushafStore.PAGE_COUNT) {
            for (line in store.page(number).lines) {
                val words = (line.kind as? MushafLine.Kind.Ayah)?.words ?: continue
                val ends = words.count { it.isAyahEnd }
                if (ends > 0) layout.merge("$number:${line.number}", ends, Int::plus)
            }
        }
        assertEquals(official, layout)
    }

    /** Words carry their ayah's topic section; the stand-in data's four gaps become sections of their own. */
    @Test
    fun wordsCarryTheirTopicSection() {
        val topics = HashSet<Int>()
        var without = 0
        for (number in 1..MushafStore.PAGE_COUNT) {
            for (line in ayahLines(number)) for (word in line.words) {
                if (word.topic != null) topics += word.topic!! else without += 1
            }
        }
        assertEquals(1_053, topics.size)
        assertEquals(0, without)
        // Page 2: al-Baqarah 1–5 is one section.
        val ayahTopics = ayahLines(2).flatMap { it.words }.filter { it.isAyahEnd }.map { it.topic }
        assertEquals(5, ayahTopics.size)
        assertEquals(1, ayahTopics.toSet().size)
    }

    /** Ayat are numbered 0 until 6236 in Quran order; juz', surahs and pages know which they hold. */
    @Test
    fun ayahNumbersAndRanges() {
        assertEquals(0..147, store.juzAyahs[1])
        assertEquals(564, store.juzAyahs[30]!!.count())
        var next = 0
        for (juz in 1..30) {
            val range = store.juzAyahs[juz]!!
            assertEquals("juz' $juz", next, range.first)
            next = range.last + 1
        }
        assertEquals(MushafStore.AYAH_COUNT, next)
        assertEquals(0..6, store.surahAyahs[1])
        assertEquals(286, store.surahAyahs[2]!!.count())
        assertEquals(MushafStore.AYAH_COUNT - 1, store.surahAyahs[114]!!.last)
        assertEquals(0..6, store.page(1).ayahs)
        assertEquals(7..11, store.page(2).ayahs)

        // Words run in Quran order, each inside its page's range.
        var previous = 0
        for (number in 1..MushafStore.PAGE_COUNT) {
            val page = store.page(number)
            for (line in ayahLines(number)) for (word in line.words) {
                assertTrue("page $number", word.ayah >= previous && word.ayah in page.ayahs)
                previous = word.ayah
            }
        }
    }

    @Test
    fun referencesAndPagesOfAyat() {
        assertEquals(1 to 1, store.reference(0))
        assertEquals(2 to 1, store.reference(7))
        assertEquals(2 to 255, store.reference(7 + 254))
        assertEquals(114 to 6, store.reference(MushafStore.AYAH_COUNT - 1))
        assertEquals(1, store.pageOfAyah(0))
        assertEquals(2, store.pageOfAyah(7))
        assertEquals(3, store.pageOfAyah(12))
        assertEquals(604, store.pageOfAyah(MushafStore.AYAH_COUNT - 1))
        for (ayah in 0 until MushafStore.AYAH_COUNT step 37) {
            val page = store.pageOfAyah(ayah)
            assertTrue("ayah $ayah", ayah in store.page(page).ayahs)
            if (page > 1) assertTrue("ayah $ayah", store.page(page - 1).ayahs.last < ayah)
        }
    }

    @Test
    fun indexCoversEverySurahAndJuz() {
        assertEquals(114, store.surahHeaders.size)
        assertEquals(114, store.surahStartPages.size)
        assertEquals(1, store.surahStartPages[1])
        assertEquals(2, store.surahStartPages[2])
        assertEquals(604, store.surahStartPages[114])
        assertEquals(30, store.juzStartPages.size)
        assertEquals(1, store.juzStartPages[1])
        assertEquals(582, store.juzStartPages[30])
    }

    @Test
    fun surahNamesAndBasmalaComeFromOfficialData() {
        assertEquals(114, store.surahNames.size)
        assertEquals("البَقَرَة", store.surahNames[2])
        assertEquals(4, store.basmala.split(" ").size)
    }

    @Test
    fun findsTheSurahAndJuzOfAnyPage() {
        assertEquals(1, store.surahOf(1))
        assertEquals(2, store.surahOf(49))
        assertEquals(3, store.surahOf(50))
        assertEquals(27, store.surahOf(384))
        assertEquals(28, store.surahOf(385))
        assertEquals(114, store.surahOf(604))
        assertEquals(1, store.juzOf(1))
        assertEquals(20, store.juzOf(385))
        assertEquals(30, store.juzOf(604))
    }

    /** TalkBack reads each page from the official plain text, one entry per ayah on the page. */
    @Test
    fun pagesCarryTheirAyatAsPlainText() {
        assertEquals(7, store.page(1).spokenAyat.size)
        assertTrue(store.page(1).spokenAyat.first().startsWith("بسم الله الرحمن الرحيم"))
        assertEquals(6_236, (1..MushafStore.PAGE_COUNT).sumOf { store.page(it).spokenAyat.size })
    }

    /** A build without the page fonts must explain itself instead of drawing missing glyphs. */
    @Test
    fun explainsMissingPageFonts() {
        val empty = object : QuranFiles by TestQuran {
            override fun exists(path: String) = !path.startsWith("qcf4/") && TestQuran.exists(path)
        }
        val error = runCatching { MushafStore(empty) }.exceptionOrNull()
        assertTrue(error is MushafStore.LoadError.MissingPageFonts)
        assertEquals(0, (error as MushafStore.LoadError.MissingPageFonts).found)
        assertTrue(error.message!!.contains("fetch-mushaf-fonts.sh"))
    }

    @Test
    fun loadsQuickly() {
        val start = System.nanoTime()
        assertNotNull(MushafStore(TestQuran))
        val elapsed = (System.nanoTime() - start) / 1_000_000
        println("MushafStore load time: $elapsed ms")
        assertTrue(elapsed < 5_000)
        assertNull(null)
    }
}
