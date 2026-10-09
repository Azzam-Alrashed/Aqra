package com.azzamalrashed.aqra.recitation

import com.azzamalrashed.aqra.TestQuran
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.tasmee.MistakeType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Following a recitation: the official Imla'i text matched to the Mushaf's words, and the tracker that places what the
 * model heard among them. The model itself isn't run here; its output is given as text. The same cases as iOS.
 */
class RecitationTest {
    private val store get() = TestQuran.store

    /** An ayah's number in the Quran (0 until 6236) from its surah and number in the surah. */
    private fun ayah(surah: Int, number: Int): Int = (0 until MushafStore.AYAH_COUNT).first { store.reference(it) == surah to number }

    private fun words(surah: Int, number: Int): List<String> {
        val index = ayah(surah, number)
        return RecitationText.wordsOfAyah(store.ayahPlainTexts[index], store.ayahWordCounts[index])
    }

    // The text

    @Test
    fun everyAyahHasOneRecitedWordForEachWordOfTheMushaf() {
        for (ayah in 0 until MushafStore.AYAH_COUNT) {
            val words = RecitationText.wordsOfAyah(store.ayahPlainTexts[ayah], store.ayahWordCounts[ayah])
            assertEquals("ayah ${store.reference(ayah)}", store.ayahWordCounts[ayah], words.size)
            assertFalse("ayah ${store.reference(ayah)}", words.contains(""))
        }
    }

    @Test
    fun plainWordsTheMushafJoinsAreJoined() {
        assertEquals(listOf("اولا", "يعلمون"), words(2, 77).take(2))
        val araf = words(7, 88)
        assertTrue("او" in araf && "لتعودن" in araf && "اولو" in araf)
        val tawbah = words(9, 126)
        assertTrue(tawbah.first() == "اولا" && "او" in tawbah)
        assertEquals("هاانتم", words(3, 66).first())
        assertEquals(listOf("سلام", "علي", "الياسين"), words(37, 130))
    }

    @Test
    fun normalizingLeavesOnlyTheLetters() {
        assertEquals("الحمد", RecitationText.normalize("الْحَمْدُ"))
        assertEquals("اياك", RecitationText.normalize("إِيَّاكَ"))
        assertEquals("الصلوه", RecitationText.normalize("الصَّلَوٰةَ"))
        assertEquals(listOf("مالك", "يوم", "الدين"), RecitationText.normalizedWords("مَالِكِ يَوْمِ الدِّينِ"))
    }

    // Following al-Fatiha

    private val fatihaHeard = listOf(
        "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ",
        "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ",
        "الرَّحْمَنِ الرَّحِيمِ",
        "مَالِكِ يَوْمِ الدِّينِ",
        "إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ",
        "اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ",
        "صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ",
    )

    private fun fatiha() = RecitationTracker.forPage(store.page(1), (0..6).toList(), store)

    @Test
    fun aCleanRecitationRevealsEverythingWithoutStumbles() {
        val tracker = fatiha()
        assertEquals(29, tracker.words.size)
        fatihaHeard.forEach { tracker.hear(it, final = true) }
        assertTrue(tracker.isComplete)
        assertTrue(tracker.stumbles.isEmpty())
    }

    @Test
    fun wordsRevealAsTheyreRecitedAndSettleAtThePause() {
        val tracker = fatiha()
        tracker.hear(fatihaHeard[0], final = true)
        tracker.hear("الْحَمْدُ لِلَّهِ", final = false)
        assertEquals(6, tracker.reached)
        assertEquals(4, tracker.cursor)
        tracker.hear(fatihaHeard[1], final = true)
        assertEquals(8, tracker.cursor)
        assertTrue(tracker.stumbles.isEmpty())
    }

    @Test
    fun aSkippedAyahIsAStumble() {
        val tracker = fatiha()
        fatihaHeard.forEachIndexed { index, heard -> if (index != 3) tracker.hear(heard, final = true) }
        assertTrue(tracker.isComplete)
        assertEquals(mapOf(3 to setOf(MistakeType.MEMORIZATION)), tracker.stumbles)
    }

    @Test
    fun aMissedWordIsAStumble() {
        val tracker = fatiha()
        fatihaHeard.take(4).forEach { tracker.hear(it, final = true) }
        tracker.hear("إِيَّاكَ نَعْبُدُ نَسْتَعِينُ", final = true)
        assertEquals(mapOf(4 to setOf(MistakeType.MEMORIZATION)), tracker.stumbles)
    }

    @Test
    fun anAyahFromElsewhereIsAStumbleOnTheAyahExpected() {
        val tracker = fatiha()
        fatihaHeard.take(5).forEach { tracker.hear(it, final = true) }
        tracker.hear("الَّذِي خَلَقَ الْمَوْتَ وَالْحَيَاةَ لِيَبْلُوَكُمْ أَيُّكُمْ أَحْسَنُ عَمَلًا", final = true)
        tracker.hear(fatihaHeard[6], final = true)
        assertTrue(tracker.isComplete)
        assertEquals(mapOf(5 to setOf(MistakeType.MEMORIZATION)), tracker.stumbles)
    }

    @Test
    fun goingBackAWordAfterABreathIsFineButGoingBackFurtherIsAStumble() {
        val tracker = fatiha()
        fatihaHeard.take(6).forEach { tracker.hear(it, final = true) }
        tracker.hear("صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ", final = true)
        tracker.hear("عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ", final = true)
        assertTrue(tracker.stumbles.isEmpty())
        tracker.hear(fatihaHeard[6], final = true)
        assertEquals(mapOf(6 to setOf(MistakeType.HESITATION)), tracker.stumbles)
        assertTrue(tracker.isComplete)
    }

    @Test
    fun aPromptShowsTheNextWordAndCountsAsPrompting() {
        val tracker = fatiha()
        fatihaHeard.take(5).forEach { tracker.hear(it, final = true) }
        tracker.hear("اهْدِنَا", final = true)
        assertTrue(tracker.isMidAyah)
        tracker.prompt()
        assertEquals(setOf(18), tracker.prompted)
        assertEquals("الصراط", tracker.words[18].text)
        tracker.hear("الْمُسْتَقِيمَ", final = true)
        tracker.hear(fatihaHeard[6], final = true)
        assertTrue(tracker.isComplete)
        assertEquals(mapOf(5 to setOf(MistakeType.PROMPTING)), tracker.stumbles)
    }

    @Test
    fun aLongPauseNoPromptAnsweredIsAHesitation() {
        val tracker = fatiha()
        fatihaHeard.take(6).forEach { tracker.hear(it, final = true) }
        // Between two ayat it's only a breath.
        tracker.hesitated()
        assertTrue(tracker.stumbles.isEmpty())
        tracker.hear("صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ", final = true)
        tracker.hesitated()
        tracker.hear("غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ", final = true)
        assertTrue(tracker.isComplete)
        assertEquals(mapOf(6 to setOf(MistakeType.HESITATION)), tracker.stumbles)
    }

    @Test
    fun noiseAndFragmentsChangeNothing() {
        val tracker = fatiha()
        tracker.hear(fatihaHeard[0], final = true)
        tracker.hear("ض", final = true)
        tracker.hear("", final = true)
        assertEquals(4, tracker.cursor)
        assertTrue(tracker.stumbles.isEmpty())
    }

    @Test
    fun theIstiadhaAndABasmalaBeforeASurahArentStumbles() {
        val ikhlas = ayah(112, 1)
        val tracker = RecitationTracker.forPage(store.page(604), (ikhlas until ikhlas + 15).toList(), store)
        tracker.hear("أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ قُلْ هُوَ اللَّهُ أَحَدٌ", final = true)
        tracker.hear("اللَّهُ الصَّمَدُ لَمْ يَلِدْ وَلَمْ يُولَدْ وَلَمْ يَكُنْ لَهُ كُفُوًا أَحَدٌ", final = true)
        tracker.hear("بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ", final = true)
        tracker.hear("قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ", final = true)
        assertTrue(tracker.stumbles.isEmpty())
        assertEquals(19, tracker.cursor)
        val opening = fatiha()
        opening.hear("بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ", final = true)
        assertEquals(4, opening.cursor)
    }

    @Test
    fun repeatingThePromptedWordAndCarryingOnIsClean() {
        val nas = ayah(114, 1)
        val tracker = RecitationTracker.forPage(store.page(604), (nas until nas + 6).toList(), store)
        listOf("قُلْ أَعُوذُ بِرَبِّ النَّاسِ", "مَلِكِ النَّاسِ", "إِلَهِ النَّاسِ", "مِنْ شَرِّ الْوَسْوَاسِ").forEach { tracker.hear(it, final = true) }
        tracker.prompt()
        tracker.hear("فِي الْخَنَّاسِ", final = true)
        tracker.hear("الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ", final = true)
        tracker.hear("مِنَ الْجِنَّةِ وَالنَّاسِ", final = true)
        assertTrue(tracker.isComplete)
        assertEquals(mapOf(nas + 3 to setOf(MistakeType.PROMPTING)), tracker.stumbles)
    }

    // Words the model and the Mushaf split differently

    @Test
    fun aJoinedWordMatchesWhetherTheModelJoinsItOrNot() {
        val index = ayah(2, 77)
        val page = store.page(store.pageOfAyah(index))
        for (heard in listOf(
            "أَوَلَا يَعْلَمُونَ أَنَّ اللَّهَ يَعْلَمُ مَا يُسِرُّونَ وَمَا يُعْلِنُونَ",
            "أَوَ لَا يَعْلَمُونَ أَنَّ اللَّهَ يَعْلَمُ مَا يُسِرُّونَ وَمَا يُعْلِنُونَ",
        )) {
            val tracker = RecitationTracker.forPage(page, listOf(index), store)
            tracker.hear(heard, final = true)
            assertTrue(heard, tracker.isComplete && tracker.stumbles.isEmpty())
        }
    }
}
