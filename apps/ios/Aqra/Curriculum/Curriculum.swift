import Foundation

/// The rules of the stages, in one place so they can be tuned after trying them (docs/SRS.md, §3.7).
struct StagePolicy: Hashable, Sendable {
    /// An ayah is mastered once its half-life reaches this many days and its last revision was clean.
    var masteryStability = 60.0
    /// The share of a stage's ayat that must be memorized to pass it.
    var requiredMemorized = 1.0
    /// The share of a stage's ayat that must be mastered to pass it.
    var requiredMastered = 0.8
    /// The in-app test: how many questions, and the share answered right to pass.
    var testQuestions = 10
    var testPassScore = 0.8
    /// How long after a failed test it can be taken again.
    var retestCooldown: TimeInterval = 24 * 3_600
    /// Whether passing a stage needs a sheikh's test.
    var sheikhTestRequired = true
    /// A sheikh's test passes with at most this many mistakes per page heard; the teacher can change it per test.
    var allowedMistakesPerPage = 1

    static let standard = StagePolicy()
}

/// The curriculum's fixed structure (from the Etqan reference): ten stages of three juz' each. Stage k holds juz'
/// 3k−2…3k, and it's the k-th of the ten stairs drawn on the home.
enum Curriculum {
    static let stageCount = 10
    static let juzPerStage = 3

    static func juz(ofStage stage: Int) -> ClosedRange<Int> {
        let stage = min(max(stage, 1), stageCount)
        return (stage - 1) * juzPerStage + 1...stage * juzPerStage
    }

    static func stage(ofJuz juz: Int) -> Int {
        (min(max(juz, 1), 30) - 1) / juzPerStage + 1
    }
}

/// How far a stage has come: its ayat memorized, mastered and verified.
struct StageProgress: Hashable {
    var stage: Int
    var ayahs: ClosedRange<Int>
    var memorized: Int
    var mastered: Int
    var verified: Int

    var total: Int { ayahs.count }
    var memorizedShare: Double { Double(memorized) / Double(max(total, 1)) }
    var masteredShare: Double { Double(mastered) / Double(max(total, 1)) }
    var verifiedShare: Double { Double(verified) / Double(max(total, 1)) }

    @MainActor
    init(stage: Int, store: MushafStore, memorization: MemorizationStore, policy: StagePolicy = .standard) {
        let juz = Curriculum.juz(ofStage: stage)
        let first = store.juzAyahs[juz.lowerBound]?.lowerBound ?? 0
        let last = store.juzAyahs[juz.upperBound]?.upperBound ?? first
        self.stage = stage
        ayahs = first...last
        memorized = memorization.memorizedCount(in: ayahs)
        mastered = memorization.masteredCount(in: ayahs, policy: policy)
        verified = memorization.verifiedCount(in: ayahs)
    }
}

/// What passing a stage asks, and how far each is met.
struct StageStatus: Hashable {
    enum Requirement: String, CaseIterable, Hashable {
        case memorized, mastered, test, sheikh
    }

    var progress: StageProgress
    var testPassed: Bool
    /// The best in-app test score, if the test was taken.
    var bestScore: Double?
    var sheikhPassed: Bool
    var passedAt: Date?
    /// When a failed test can be taken again; nil when it can be taken now.
    var retestAt: Date?
    var policy: StagePolicy

    func isMet(_ requirement: Requirement) -> Bool {
        switch requirement {
        case .memorized: progress.memorizedShare >= policy.requiredMemorized - 0.000_1
        case .mastered: progress.masteredShare >= policy.requiredMastered - 0.000_1
        case .test: testPassed
        case .sheikh: !policy.sheikhTestRequired || sheikhPassed
        }
    }

    var requirements: [Requirement] {
        Requirement.allCases.filter { $0 != .sheikh || policy.sheikhTestRequired }
    }

    var meetsAll: Bool { Requirement.allCases.allSatisfy(isMet) }
    var isPassed: Bool { passedAt != nil }
    /// The in-app test can be taken once the stage is memorized, and not again too soon after failing.
    func canTakeTest(at date: Date = .now) -> Bool {
        isMet(.memorized) && (retestAt.map { date >= $0 } ?? true)
    }
}

/// A question of a stage's in-app test. Ayat are shown in the Complex's own text and font, as published.
struct TestQuestion: Hashable, Identifiable {
    enum Kind: String, Codable, Hashable {
        /// Which ayah comes after this one?
        case nextAyah
        /// Which surah is this ayah from?
        case whichSurah
    }

    var id: Int
    var kind: Kind
    /// The ayah asked about.
    var ayah: Int
    /// For `nextAyah`, ayat; for `whichSurah`, surah numbers.
    var options: [Int]
    var answer: Int

    /// A stage's test: questions on its memorized ayat, alternating kinds, each with four choices. Empty when the
    /// stage has too little memorized to ask about.
    @MainActor
    static func test(stage: Int, count: Int, store: MushafStore, memorization: MemorizationStore,
                     using generator: inout some RandomNumberGenerator) -> [TestQuestion] {
        let progress = StageProgress(stage: stage, store: store, memorization: memorization)
        let memorized = progress.ayahs.filter { memorization.isMemorized($0) }
        guard memorized.count >= 4 else { return [] }
        // An ayah with its next one, both memorized and in the same surah.
        let followed = memorized.filter { ayah in
            ayah + 1 <= progress.ayahs.upperBound && memorization.isMemorized(ayah + 1)
                && store.surah(ofAyah: ayah) == store.surah(ofAyah: ayah + 1)
        }
        let surahs = Array(Set(memorized.map { store.surah(ofAyah: $0) })).sorted()
        var questions: [TestQuestion] = []
        var used = Set<Int>()
        for index in 0..<count {
            let wantsNext = index % 2 == 0 && followed.count >= 1
            if wantsNext, let ayah = followed.filter({ !used.contains($0) }).randomElement(using: &generator) {
                used.insert(ayah)
                let others = memorized.filter { $0 != ayah && $0 != ayah + 1 }.shuffled(using: &generator).prefix(3)
                guard others.count == 3 else { continue }
                let options = (Array(others) + [ayah + 1]).shuffled(using: &generator)
                questions.append(TestQuestion(id: index, kind: .nextAyah, ayah: ayah, options: options, answer: ayah + 1))
            } else if let ayah = memorized.filter({ !used.contains($0) }).randomElement(using: &generator) {
                used.insert(ayah)
                let surah = store.surah(ofAyah: ayah)
                // Other surahs of the stage first, then the surahs nearest it.
                var pool = surahs.filter { $0 != surah }.shuffled(using: &generator)
                var distance = 1
                while pool.count < 3, distance < 114 {
                    for candidate in [surah - distance, surah + distance] where (1...114).contains(candidate) && !pool.contains(candidate) {
                        pool.append(candidate)
                    }
                    distance += 1
                }
                let options = (Array(pool.prefix(3)) + [surah]).shuffled(using: &generator)
                questions.append(TestQuestion(id: index, kind: .whichSurah, ayah: ayah, options: options, answer: surah))
            }
        }
        return questions
    }
}

/// The record of the stages: in-app test results, the sheikh's stage tests heard, and the stages passed. Kept on
/// the device and backed up with the rest of the journey.
@MainActor @Observable
final class AssessmentStore {
    struct TestResult: Codable, Hashable, Identifiable {
        var id = UUID()
        var stage: Int
        var date: Date
        var questions: Int
        var correct: Int
        var score: Double { Double(correct) / Double(max(questions, 1)) }
    }

    /// A teacher's test of a stage, from a tasmee' record.
    struct SheikhTest: Codable, Hashable, Identifiable {
        /// The tasmee' record's id.
        var id: String
        var stage: Int
        var date: Date
        var teacherName: String
        var passed: Bool
    }

    let policy: StagePolicy
    private(set) var results: [TestResult] = []
    private(set) var sheikhTests: [SheikhTest] = []
    /// Each stage passed, and when.
    private(set) var passes: [Int: Date] = [:]
    private(set) var updatedAt = Date.distantPast
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when a stage is passed, so it can be celebrated.
    @ObservationIgnored var onPass: ((Int) -> Void)?
    @ObservationIgnored private let fileURL: URL?

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("assessments.json")
    }

    init(fileURL: URL? = AssessmentStore.defaultURL, policy: StagePolicy = .standard) {
        self.fileURL = fileURL
        self.policy = policy
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        results = snapshot.results
        sheikhTests = snapshot.sheikhTests
        passes = snapshot.passes
        updatedAt = snapshot.updatedAt
    }

    func status(of stage: Int, store: MushafStore, memorization: MemorizationStore, now: Date = .now) -> StageStatus {
        let stageResults = results.filter { $0.stage == stage }
        let passedTest = stageResults.contains { $0.score >= policy.testPassScore - 0.000_1 }
        let lastFailed = stageResults.last.flatMap { $0.score < policy.testPassScore ? $0.date : nil }
        let retestAt = lastFailed.map { $0.addingTimeInterval(policy.retestCooldown) }.flatMap { $0 > now ? $0 : nil }
        return StageStatus(progress: StageProgress(stage: stage, store: store, memorization: memorization, policy: policy),
                           testPassed: passedTest, bestScore: stageResults.map(\.score).max(),
                           sheikhPassed: sheikhTests.contains { $0.stage == stage && $0.passed },
                           passedAt: passes[stage], retestAt: passedTest ? nil : retestAt, policy: policy)
    }

    /// The stage the student is in, steady through the day: the one holding the plan's next portion (whether
    /// today's is due, done or a rest day), else the one of the latest ayah memorized in Aqra (marking what was
    /// already known doesn't move it), else the first stage not yet passed.
    static func currentStage(nextAyah: Int?, memorization: MemorizationStore, store: MushafStore,
                             passes: [Int: Date]) -> Int {
        if let nextAyah { return Curriculum.stage(ofJuz: store.juz(ofAyah: nextAyah)) }
        let learned = memorization.ayahs.compactMap { ayah, memory in memory.learnedAt.map { (ayah, $0) } }
        if let latest = learned.max(by: { ($0.1, $0.0) < ($1.1, $1.0) }), memorization.count < MushafStore.ayahCount {
            return Curriculum.stage(ofJuz: store.juz(ofAyah: latest.0))
        }
        return (1...Curriculum.stageCount).first { passes[$0] == nil } ?? Curriculum.stageCount
    }

    func record(_ result: TestResult) {
        results.append(result)
        save()
    }

    /// Keeps a teacher's stage test from a tasmee' record, once.
    func record(_ record: TasmeeRecord) {
        guard let test = record.test, let passed = record.passesTest, !sheikhTests.contains(where: { $0.id == record.id }) else { return }
        sheikhTests.append(SheikhTest(id: record.id, stage: test.stage, date: record.at, teacherName: record.teacherName, passed: passed))
        save()
    }

    /// Marks every stage whose requirements are all met as passed (once), and returns those just passed.
    @discardableResult
    func checkPasses(store: MushafStore, memorization: MemorizationStore, now: Date = .now) -> [Int] {
        var passed: [Int] = []
        for stage in 1...Curriculum.stageCount where passes[stage] == nil {
            if status(of: stage, store: store, memorization: memorization, now: now).meetsAll {
                passes[stage] = now
                passed.append(stage)
            }
        }
        if !passed.isEmpty {
            save()
            passed.forEach { onPass?($0) }
        }
        return passed
    }

    // MARK: - Backup

    struct Snapshot: Codable, Equatable {
        var results: [TestResult] = []
        var sheikhTests: [SheikhTest] = []
        var passes: [Int: Date] = [:]
        var updatedAt = Date.distantPast

        static let empty = Snapshot()

        init(results: [TestResult] = [], sheikhTests: [SheikhTest] = [], passes: [Int: Date] = [:], updatedAt: Date = .distantPast) {
            self.results = results
            self.sheikhTests = sheikhTests
            self.passes = passes
            self.updatedAt = updatedAt
        }

        // The account's copy may come from the Android app or a newer version: a key missing, unknown or
        // unreadable never loses the rest.
        private enum CodingKeys: String, CodingKey { case results, sheikhTests, passes, updatedAt }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            results = container.decodeLossy([TestResult].self, forKey: .results)
            sheikhTests = container.decodeLossy([SheikhTest].self, forKey: .sheikhTests)
            passes = container.decodeOr([Int: Date].self, forKey: .passes, [:])
            updatedAt = container.decodeOr(Date.self, forKey: .updatedAt, .distantPast)
        }

        /// Both copies as one: every result and test of both, and each stage passed at its earliest.
        static func merge(_ local: Snapshot, _ remote: Snapshot) -> Snapshot {
            var ids = Set<UUID>()
            var tests = Set<String>()
            return Snapshot(
                results: (local.results + remote.results).sorted { $0.date < $1.date }.filter { ids.insert($0.id).inserted },
                sheikhTests: (local.sheikhTests + remote.sheikhTests).sorted { $0.date < $1.date }.filter { tests.insert($0.id).inserted },
                passes: local.passes.merging(remote.passes) { min($0, $1) },
                updatedAt: max(local.updatedAt, remote.updatedAt))
        }
    }

    var snapshot: Snapshot {
        Snapshot(results: results, sheikhTests: sheikhTests, passes: passes, updatedAt: updatedAt)
    }

    func apply(_ snapshot: Snapshot) {
        guard snapshot != self.snapshot else { return }
        results = snapshot.results
        sheikhTests = snapshot.sheikhTests
        passes = snapshot.passes
        updatedAt = snapshot.updatedAt
        save(touching: false)
    }

    private func save(touching: Bool = true) {
        if touching { updatedAt = .now }
        onChange?()
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }
}
