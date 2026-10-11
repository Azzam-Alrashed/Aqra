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

    @Test func aLongPauseNoPromptAnsweredIsAHesitation() throws {
        var (tracker, ayat) = try fatiha()
        for ayah in ayat.prefix(6) { tracker.hear(ayah, final: true) }
        // Between two ayat it's only a breath.
        tracker.hesitated()
        #expect(tracker.stumbles.isEmpty)
        tracker.hear("صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ", final: true)
        tracker.hesitated()
        tracker.hear("غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ", final: true)
        #expect(tracker.isComplete)
        #expect(tracker.stumbles == [6: [.hesitation]])
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

    // MARK: - The model's files

    @Test func aChecksumMismatchIsNotInstalled() throws {
        let manager = FileManager.default
        let temp = manager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try manager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: temp) }
        let archive = temp.appending(path: "model.aar")
        let folder = temp.appending(path: "model", directoryHint: .isDirectory)
        // Not the archive that was published: its checksum doesn't match, so it's thrown away, not unpacked.
        try Data("not the model".utf8).write(to: archive)
        #expect(throws: RecitationModel.ModelError.checksum) {
            try RecitationModel.verifyAndInstall(archive: archive, expecting: RecitationModel.checksum, into: folder)
        }
        #expect(!RecitationModel.isInstalled(at: folder))
        #expect(!manager.fileExists(atPath: folder.path))
        #expect(!manager.fileExists(atPath: archive.path))
        // The checksum matches, but what's inside isn't a model: not installed either.
        try Data("not the model".utf8).write(to: archive)
        #expect(throws: RecitationModel.ModelError.incomplete) {
            try RecitationModel.verifyAndInstall(archive: archive, expecting: try RecitationModel.sha256(of: archive), into: folder)
        }
        #expect(!RecitationModel.isInstalled(at: folder))
        #expect(!manager.fileExists(atPath: folder.path))
        // The checksum is SHA-256.
        let abc = temp.appending(path: "abc")
        try Data("abc".utf8).write(to: abc)
        #expect(try RecitationModel.sha256(of: abc) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(RecitationModel.checksum.count == 64)
    }

    @Test func oldVersionsAndPartialInstallsAreCleanedUp() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: root) }
        for folder in ["whisper-test-2", "whisper-test-1", "whisper-test-2.partial"] {
            try manager.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
        for file in ["whisper-test-2.aar", "whisper-test-2.resume", "whisper-test-1.aar", "whisper-test-1.resume"] {
            try Data("x".utf8).write(to: root.appending(path: file))
        }
        RecitationModel.cleanUp(in: root, keeping: "whisper-test-2")
        let left = try manager.contentsOfDirectory(atPath: root.path).sorted()
        #expect(left == ["whisper-test-2", "whisper-test-2.aar", "whisper-test-2.resume"])
    }

    // MARK: - The listener

    /// Words as tones: word i is a square wave of amplitude 0.1 + 0.02·i for `secondsPerWord`, then two frames of
    /// silence; a second of silence closes the recording. `decode` reads the words a stretch holds, in order.
    private struct Tones: Sendable {
        let words: [String]
        let samples: [Float]

        init(words: [String], secondsPerWord: Double) {
            self.words = words
            let perWord = Int(secondsPerWord * 16_000)
            let gap = 2 * 480
            var out = [Float](repeating: 0, count: words.count * (perWord + gap) + 16_000)
            var at = 0
            for i in words.indices {
                let amplitude = 0.1 + 0.02 * Float(i)
                for n in 0..<perWord { out[at + n] = n % 2 == 0 ? amplitude : -amplitude }
                at += perWord + gap
            }
            samples = out
        }

        /// The recording of some of the words.
        func samples(of range: Range<Int>, secondsPerWord: Double) -> [Float] {
            let perWord = Int(secondsPerWord * 16_000) + 2 * 480
            let end = range.upperBound == words.count ? samples.count : range.upperBound * perWord
            return Array(samples[range.lowerBound * perWord..<end])
        }

        func indices(in stretch: [Float]) -> [Int] {
            Set(stretch.map(abs).filter { $0 > 0 }.map { Int((($0 - 0.1) / 0.02).rounded()) }).sorted()
        }

        @Sendable func decode(_ stretch: [Float]) -> String {
            indices(in: stretch).map { words[$0] }.joined(separator: " ")
        }
    }

    /// Everything at once on the first drain, as if the whole recording had just been said.
    private final class AllAtOnce: RecitationAudioSource {
        var started = false
        var stopped = false
        private var samples: [Float]

        init(_ samples: [Float]) {
            self.samples = samples
        }

        func start() throws { started = true }
        func stop() { stopped = true }
        func drain() -> [Float] {
            defer { samples = [] }
            return samples
        }
    }

    /// Holds back the fake model's loading until it's opened.
    private actor Gate {
        private var opened = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func open() {
            opened = true
            for continuation in waiting { continuation.resume() }
            waiting.removeAll()
        }
    }

    /// A model that reads the words off the recording's tones; its loading can be held back.
    private final class FakeHearing: RecitationHearing, @unchecked Sendable {
        private let lock = NSLock()
        private var loaded = false
        private var stretches: [[Float]] = []
        private let decode: @Sendable ([Float]) -> String
        private let gate: Gate?

        init(gate: Gate? = nil, decode: @escaping @Sendable ([Float]) -> String = { _ in "" }) {
            self.gate = gate
            self.decode = decode
        }

        var isLoaded: Bool { lock.withLock { loaded } }
        var heard: [[Float]] { lock.withLock { stretches } }

        func load() async throws {
            await gate?.wait()
            lock.withLock { loaded = true }
        }

        func transcribe(_ samples: [Float]) async throws -> String {
            lock.withLock { stretches.append(samples) }
            return decode(samples)
        }

        func unload() async {
            lock.withLock { loaded = false }
        }
    }

    /// Waits for the listener's tasks to get somewhere, up to a few seconds.
    @MainActor private func until(_ what: String, _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting for \(what)")
                return
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @MainActor private func ports(_ source: @escaping @MainActor () -> any RecitationAudioSource, _ hearing: FakeHearing) -> RecitationListener.Ports {
        RecitationListener.Ports(requestMicrophone: { true }, hearing: hearing, audio: source)
    }

    @Test @MainActor func stoppingWhilePreparingLeavesTheMicOff() async throws {
        let store = try store
        let session = RevisionSession(page: 1, ayahs: Array(0...6))
        // «توقّف» while «يستعدّ للاستماع…»: the model finishes loading afterwards, and the microphone stays off.
        let gate = Gate()
        let source = AllAtOnce([])
        let hearing = FakeHearing(gate: gate)
        let listener = RecitationListener(session: session, store: store, ports: ports({ source }, hearing))
        listener.start()
        #expect(listener.phase == .preparing)
        try await Task.sleep(for: .milliseconds(50))
        listener.pause()
        #expect(listener.phase == .paused)
        await gate.open()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!source.started)
        #expect(listener.phase == .paused)
        // Resuming loads the model, then listens.
        listener.resume()
        try await until("listening") { listener.phase == .listening }
        #expect(source.started)
        listener.pause()
        #expect(source.stopped)
        // The same when the wird is left while the model loads: the listener is let go, and nothing turns the
        // microphone on afterwards.
        let secondGate = Gate()
        let secondSource = AllAtOnce([])
        var left: RecitationListener? = RecitationListener(session: session, store: store, ports: ports({ secondSource }, FakeHearing(gate: secondGate)))
        left?.start()
        try await Task.sleep(for: .milliseconds(50))
        left = nil
        await secondGate.open()
        try await Task.sleep(for: .milliseconds(100))
        #expect(!secondSource.started)
    }

    @Test @MainActor func anInterruptionPausesWithoutStumbles() async throws {
        let store = try store
        // Al-Fatiha, word by word; a phone call comes after its fourth ayah.
        let words = (0...6).flatMap { RecitationText.words(ofAyah: store.ayahPlainTexts[$0], mushafWords: store.ayahWordCounts[$0]) }
        #expect(words.count == 29)
        let tones = Tones(words: words, secondsPerWord: 0.5)
        // Its first four ayat (13 words), then a second's quiet before the call.
        let firstPart = AllAtOnce(tones.samples(of: 0..<13, secondsPerWord: 0.5) + [Float](repeating: 0, count: 16_000))
        let secondPart = AllAtOnce(tones.samples(of: 13..<29, secondsPerWord: 0.5))
        var sources = [firstPart, secondPart]
        let hearing = FakeHearing(decode: tones.decode)
        let session = RevisionSession(page: 1, ayahs: Array(0...6))
        let listener = RecitationListener(session: session, store: store, ports: ports({ sources.removeFirst() }, hearing))
        listener.start()
        try await until("the first part") { session.revealed >= 4 }
        #expect(session.stumbles.isEmpty)
        // The call: listening pauses and the microphone goes off, without a stumble for the silence.
        listener.audioSessionInterrupted(began: true, shouldResume: false)
        #expect(listener.phase == .paused)
        #expect(firstPart.stopped)
        try await Task.sleep(for: .milliseconds(300))
        #expect(session.stumbles.isEmpty && session.prompts.isEmpty)
        // The call ends: listening carries on, and the rest of the page is followed cleanly.
        listener.audioSessionInterrupted(began: false, shouldResume: true)
        #expect(listener.phase == .listening)
        #expect(secondPart.started)
        try await until("the page") { session.isComplete }
        #expect(session.stumbles.isEmpty && session.prompts.isEmpty)
        // An interruption the student didn't pause for is the only one that resumes by itself.
        listener.pause()
        listener.audioSessionInterrupted(began: false, shouldResume: true)
        #expect(listener.phase == .paused)
    }

    @Test @MainActor func aLongAyahIsTrackedAcrossWindows() async throws {
        let store = try store
        // al-Mulk 67:3, recited slowly: longer than the model's window, so it's heard in two stretches.
        let index = try ayah(67, 3)
        let words = RecitationText.words(ofAyah: store.ayahPlainTexts[index], mushafWords: store.ayahWordCounts[index])
        #expect(words.count >= 12)
        let tones = Tones(words: words, secondsPerWord: 2)
        #expect(tones.samples.count > 24 * 16_000)
        let source = AllAtOnce(tones.samples)
        let hearing = FakeHearing(decode: tones.decode)
        let session = RevisionSession(page: store.page(ofAyah: index), ayahs: [index])
        let listener = RecitationListener(session: session, store: store, ports: ports({ source }, hearing))
        listener.start()
        try await until("the ayah") { session.isComplete }
        // Settled in two stretches or more, each within the window, cut between two words: no word is heard twice
        // or in half.
        let heard = hearing.heard
        #expect(heard.count >= 2)
        for stretch in heard { #expect(stretch.count <= RecitationListener.longestStretch * 16_000) }
        #expect(heard.flatMap { tones.indices(in: $0) } == Array(words.indices))
        #expect(tones.indices(in: heard.first ?? []).count >= 8)
        // Followed to the end, without a stumble.
        #expect(session.isComplete)
        #expect(session.stumbles.isEmpty)
        listener.pause()
        #expect(source.stopped)
    }
}

/// Until listening is tried with real voices, the stumbles it hears are suggestions: recorded only once the student
/// keeps them in the page's summary (docs/SRS.md REV-18).
@MainActor
struct HeardStumbleTests {
    @Test func heardStumblesAreSuggestionsUntilKept() {
        let session = RevisionSession(page: 1, ayahs: [0, 1, 2, 3])
        session.revealAll()
        session.markStumble(1, kinds: [.hesitation])
        session.tap(3)
        #expect(session.stumbles == [1, 3])
        #expect(session.recordedStumbles == [3])
        session.keepHeard(1, true)
        #expect(session.recordedStumbles == [1, 3])
        session.keepHeard(1, false)
        #expect(session.recordedStumbles == [3])
    }

    @Test func theStudentsOwnMarkStaysTheirs() {
        let session = RevisionSession(page: 1, ayahs: [0, 1, 2])
        session.revealAll()
        session.tap(2)
        session.markStumble(2, kinds: [.memorization])
        #expect(session.recordedStumbles == [2])
        // A heard one the student marks by hand is theirs too, and one they take back is gone.
        session.markStumble(0, kinds: [.prompting])
        session.markStumble(0)
        #expect(session.recordedStumbles == [0, 2])
        session.tap(0)
        #expect(session.recordedStumbles == [2])
        #expect(!session.heard.contains(0))
    }
}
