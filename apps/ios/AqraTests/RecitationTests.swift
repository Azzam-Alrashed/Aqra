import Foundation
import Testing
@testable import Aqra

private let sharedStore = try? MushafStore()

/// Following a recitation: the official Imla'i text matched to the Mushaf's words, and the tracker that places what
/// the model heard among them. The model itself isn't run here; its output is given as text.
struct RecitationTests {
    private var store: MushafStore {
        get throws { try #require(sharedStore) }
    }

    /// An ayah's number in the Quran (0..<6236) from its surah and number in the surah.
    private func ayah(_ surah: Int, _ number: Int) throws -> Int {
        let store = try store
        return try #require((0..<MushafStore.ayahCount).first { store.reference(ofAyah: $0) == (surah, number) })
    }

    // MARK: - The text

    @Test func everyAyahHasOneRecitedWordForEachWordOfTheMushaf() throws {
        let store = try store
        for ayah in 0..<MushafStore.ayahCount {
            let words = RecitationText.words(ofAyah: store.ayahPlainTexts[ayah], mushafWords: store.ayahWordCounts[ayah])
            #expect(words.count == store.ayahWordCounts[ayah], "ayah \(store.reference(ofAyah: ayah))")
            #expect(!words.contains(""), "ayah \(store.reference(ofAyah: ayah))")
        }
    }

    @Test func plainWordsTheMushafJoinsAreJoined() throws {
        let store = try store
        func words(_ surah: Int, _ number: Int) throws -> [String] {
            let index = try ayah(surah, number)
            return RecitationText.words(ofAyah: store.ayahPlainTexts[index], mushafWords: store.ayahWordCounts[index])
        }
        // «أَوَلَا يَعۡلَمُونَ»: one word in the Mushaf.
        #expect(try words(2, 77).prefix(2) == ["اولا", "يعلمون"])
        // al-A'raf 7:88: «أَوۡ لَتَعُودُنَّ» stays two words, «أَوَلَوۡ كُنَّا» is joined.
        let araf = try words(7, 88)
        #expect(araf.contains("او") && araf.contains("لتعودن") && araf.contains("اولو"))
        // at-Tawbah 9:126: «أَوَلَا يَرَوۡنَ» is joined, «مَرَّةً أَوۡ مَرَّتَيۡنِ» isn't.
        let tawbah = try words(9, 126)
        #expect(tawbah.first == "اولا" && tawbah.contains("او"))
        // «هَٰٓأَنتُمۡ» and «إِلۡيَاسِينَ».
        #expect(try words(3, 66).first == "هاانتم")
        #expect(try words(37, 130) == ["سلام", "علي", "الياسين"])
    }

    @Test func normalizingLeavesOnlyTheLetters() {
        #expect(RecitationText.normalize("الْحَمْدُ") == "الحمد")
        #expect(RecitationText.normalize("إِيَّاكَ") == "اياك")
        #expect(RecitationText.normalize("الصَّلَوٰةَ") == "الصلوه")
        #expect(RecitationText.normalizedWords("مَالِكِ يَوْمِ الدِّينِ") == ["مالك", "يوم", "الدين"])
    }

    // MARK: - Following al-Fatiha

    /// Al-Fatiha's page, every ayah covered, as the model writes the ayat (with tashkeel).
    private func fatiha() throws -> (tracker: RecitationTracker, ayat: [String]) {
        let store = try store
        let ayahs = Array(0...6)
        let tracker = RecitationTracker(page: store.page(1), ayahs: ayahs, store: store)
        let heard = [
            "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ",
            "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ",
            "الرَّحْمَنِ الرَّحِيمِ",
            "مَالِكِ يَوْمِ الدِّينِ",
            "إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ",
            "اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ",
            "صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ",
        ]
        return (tracker, heard)
    }

    @Test func aCleanRecitationRevealsEverythingWithoutStumbles() throws {
        var (tracker, ayat) = try fatiha()
        #expect(tracker.words.count == 29)
        for ayah in ayat { tracker.hear(ayah, final: true) }
        #expect(tracker.isComplete)
        #expect(tracker.stumbles.isEmpty)
    }

    @Test func wordsRevealAsTheyreRecitedAndSettleAtThePause() throws {
        var (tracker, ayat) = try fatiha()
        tracker.hear(ayat[0], final: true)
        tracker.hear("الْحَمْدُ لِلَّهِ", final: false)
        #expect(tracker.reached == 6 && tracker.cursor == 4)
        tracker.hear(ayat[1], final: true)
        #expect(tracker.cursor == 8 && tracker.stumbles.isEmpty)
    }

    @Test func aSkippedAyahIsAStumble() throws {
        var (tracker, ayat) = try fatiha()
        for (index, ayah) in ayat.enumerated() where index != 3 { tracker.hear(ayah, final: true) }
        #expect(tracker.isComplete)
        #expect(tracker.stumbles == [3: [.memorization]])
    }

    @Test func aMissedWordIsAStumble() throws {
        var (tracker, ayat) = try fatiha()
        for ayah in ayat.prefix(4) { tracker.hear(ayah, final: true) }
        tracker.hear("إِيَّاكَ نَعْبُدُ نَسْتَعِينُ", final: true)
        #expect(tracker.stumbles == [4: [.memorization]])
    }

    @Test func anAyahFromElsewhereIsAStumbleOnTheAyahExpected() throws {
        var (tracker, ayat) = try fatiha()
        for ayah in ayat.prefix(5) { tracker.hear(ayah, final: true) }
        // al-Mulk 67:2 in place of «اهدنا الصراط المستقيم»
        tracker.hear("الَّذِي خَلَقَ الْمَوْتَ وَالْحَيَاةَ لِيَبْلُوَكُمْ أَيُّكُمْ أَحْسَنُ عَمَلًا", final: true)
        tracker.hear(ayat[6], final: true)
        #expect(tracker.isComplete)
        #expect(tracker.stumbles == [5: [.memorization]])
    }

    @Test func goingBackAWordAfterABreathIsFineButGoingBackFurtherIsAStumble() throws {
        var (tracker, ayat) = try fatiha()
        for ayah in ayat.prefix(6) { tracker.hear(ayah, final: true) }
        tracker.hear("صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ", final: true)
        // Starting again from «عليهم» after a breath, as reciters do.
        tracker.hear("عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ", final: true)
        #expect(tracker.stumbles.isEmpty)
        // Back to the start of the ayah to correct.
        tracker.hear(ayat[6], final: true)
        #expect(tracker.stumbles == [6: [.hesitation]])
        #expect(tracker.isComplete)
    }

    @Test func aPromptShowsTheNextWordAndCountsAsPrompting() throws {
        var (tracker, ayat) = try fatiha()
        for ayah in ayat.prefix(5) { tracker.hear(ayah, final: true) }
        tracker.hear("اهْدِنَا", final: true)
        #expect(tracker.isMidAyah)
        tracker.prompt()
        #expect(tracker.prompted == [18] && tracker.words[18].text == "الصراط")
        tracker.hear("الْمُسْتَقِيمَ", final: true)
        tracker.hear(ayat[6], final: true)
        #expect(tracker.isComplete)
        #expect(tracker.stumbles == [5: [.prompting]])
    }

    @Test func noiseAndFragmentsChangeNothing() throws {
        var (tracker, ayat) = try fatiha()
        tracker.hear(ayat[0], final: true)
        tracker.hear("ض", final: true)
        tracker.hear("", final: true)
        #expect(tracker.cursor == 4 && tracker.stumbles.isEmpty)
    }

    @Test func theIstiadhaAndABasmalaBeforeASurahArentStumbles() throws {
        let store = try store
        let ikhlas = try ayah(112, 1)
        var tracker = RecitationTracker(page: store.page(604), ayahs: Array(ikhlas..<ikhlas + 15), store: store)
        tracker.hear("أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ قُلْ هُوَ اللَّهُ أَحَدٌ", final: true)
        tracker.hear("اللَّهُ الصَّمَدُ لَمْ يَلِدْ وَلَمْ يُولَدْ وَلَمْ يَكُنْ لَهُ كُفُوًا أَحَدٌ", final: true)
        tracker.hear("بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ", final: true)
        tracker.hear("قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ", final: true)
        #expect(tracker.stumbles.isEmpty)
        #expect(tracker.cursor == 19)
        // Al-Fatiha's basmala is its first ayah, and is heard as one.
        var fatiha = RecitationTracker(page: store.page(1), ayahs: Array(0...6), store: store)
        fatiha.hear("بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ", final: true)
        #expect(fatiha.cursor == 4)
    }

    @Test func repeatingThePromptedWordAndCarryingOnIsClean() throws {
        let store = try store
        let nas = try ayah(114, 1)
        var tracker = RecitationTracker(page: store.page(604), ayahs: Array(nas..<nas + 6), store: store)
        for heard in ["قُلْ أَعُوذُ بِرَبِّ النَّاسِ", "مَلِكِ النَّاسِ", "إِلَهِ النَّاسِ", "مِنْ شَرِّ الْوَسْوَاسِ"] {
            tracker.hear(heard, final: true)
        }
        tracker.prompt()
        // The student says the prompted word again, the model adding a short word that isn't there.
        tracker.hear("فِي الْخَنَّاسِ", final: true)
        tracker.hear("الَّذِي يُوَسْوِسُ فِي صُدُورِ النَّاسِ", final: true)
        tracker.hear("مِنَ الْجِنَّةِ وَالنَّاسِ", final: true)
        #expect(tracker.isComplete)
        #expect(tracker.stumbles == [nas + 3: [.prompting]])
    }

    // MARK: - Words the model and the Mushaf split differently

    @Test func aJoinedWordMatchesWhetherTheModelJoinsItOrNot() throws {
        let store = try store
        let index = try ayah(2, 77)
        let page = store.page(store.page(ofAyah: index))
        for heard in ["أَوَلَا يَعْلَمُونَ أَنَّ اللَّهَ يَعْلَمُ مَا يُسِرُّونَ وَمَا يُعْلِنُونَ",
                      "أَوَ لَا يَعْلَمُونَ أَنَّ اللَّهَ يَعْلَمُ مَا يُسِرُّونَ وَمَا يُعْلِنُونَ"] {
            var tracker = RecitationTracker(page: page, ayahs: [index], store: store)
            tracker.hear(heard, final: true)
            #expect(tracker.isComplete && tracker.stumbles.isEmpty, "\(heard)")
        }
    }
}
