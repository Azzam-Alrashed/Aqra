import Foundation
import Observation

/// What the student has memorized of one ayah, and how firmly.
struct AyahMemory: Codable, Hashable {
    /// The memorization's half-life in days: how long until the chance of recalling it falls to half.
    /// It starts modest for declared ayat, grows with each clean revision and shrinks with each stumble.
    var stability: Double
    /// The last revision, or nil if it hasn't been revised in Aqra yet (then `since` counts instead).
    var lastReviewed: Date?
    /// How many times it was stumbled on in revision.
    var lapses = 0
    /// Whether a teacher has confirmed it in a tasmee'.
    var verified = false
    var since: Date
    /// When it was memorized in Aqra as a new portion; nil for an ayah the student declared they already knew.
    var learnedAt: Date?
    /// The last stumble on it, if any: it's mastered only once a clean revision has come after it.
    var lastLapseAt: Date?

    init(since: Date, stability: Double = ReviewPolicy.standard.declaredStability, learnedAt: Date? = nil) {
        self.since = since
        self.stability = stability
        self.learnedAt = learnedAt
    }

    /// Whether it's mastered: established to the stage policy's mastery half-life, with no stumble since its last
    /// clean revision.
    func isMastered(policy: StagePolicy = .standard) -> Bool {
        guard stability >= policy.masteryStability else { return false }
        guard let lastLapseAt else { return true }
        return (lastReviewed ?? since) > lastLapseAt
    }

    /// How strong it is now, from 0 to 1: how established it is (its stability, up to the policy's mature level)
    /// times how fresh it is (the chance of recalling it after the days since it was last revised).
    /// A just-declared ayah is faint, clean revisions brighten it, and time without revision fades it.
    func strength(at date: Date, policy: ReviewPolicy = .standard) -> Double {
        let days = max(date.timeIntervalSince(lastReviewed ?? since) / 86_400, 0)
        let recall = pow(2, -days / max(stability, 0.1))
        return min(stability / policy.matureStability, 1) * recall
    }

    /// The memory after a revision: a clean one strengthens it (more so the longer it waited), a stumble weakens it.
    /// - Parameter weight: how much the evidence counts; a sheikh's tasmee' grows the memory more than
    ///   self-revision. A stumble is a stumble whoever heard it.
    func revised(stumbled: Bool, at date: Date, policy: ReviewPolicy, weight: Double = 1) -> AyahMemory {
        var next = self
        if stumbled {
            next.stability = max(stability * policy.lapseFactor, policy.minStability)
            next.lapses += 1
            next.lastLapseAt = max(date, lastLapseAt ?? date)
        } else {
            // Revising again before it has had time to slip strengthens it less (the spacing effect). The first
            // revision of a declared ayah counts in full: it was memorized long before, when isn't known.
            let days = max(date.timeIntervalSince(lastReviewed ?? since) / 86_400, 0)
            let spacing = lastReviewed == nil ? 1 : min(max(days / max(stability, 0.1), 0.1), 1)
            next.stability = min(stability * (1 + (policy.growth - 1) * spacing * weight), policy.maxStability)
        }
        // A tasmee' can arrive after a later revision; the last revision never moves backwards.
        next.lastReviewed = max(date, lastReviewed ?? date)
        return next
    }

    // Files from before revision existed (version 1) hold only `strength`, `verified` and `since`; files from before
    // the plan don't say when an ayah was learned or last stumbled on.
    private enum CodingKeys: String, CodingKey { case stability, lastReviewed, lapses, verified, since, learnedAt, lastLapseAt }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        since = try container.decode(Date.self, forKey: .since)
        stability = try container.decodeIfPresent(Double.self, forKey: .stability) ?? ReviewPolicy.standard.declaredStability
        lastReviewed = try container.decodeIfPresent(Date.self, forKey: .lastReviewed)
        lapses = try container.decodeIfPresent(Int.self, forKey: .lapses) ?? 0
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? false
        learnedAt = try container.decodeIfPresent(Date.self, forKey: .learnedAt)
        lastLapseAt = try container.decodeIfPresent(Date.self, forKey: .lastLapseAt)
    }
}

/// The ayat the student has memorized, numbered 0..<6236 in Quran order, kept on the device and backed up to the
/// student's account (see `CloudSync`).
@MainActor @Observable
final class MemorizationStore {
    private(set) var ayahs: [Int: AyahMemory] = [:]
    /// Called after every change, so the backup can follow.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    /// The file the records live in: Application Support/memorization.json.
    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("memorization.json")
    }

    /// Loads the records from `fileURL`, or keeps them in memory only when it's nil (previews and snapshots).
    init(fileURL: URL? = MemorizationStore.defaultURL) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        ayahs = Dictionary(file.ayahs.map { ($0.ayah, $0.memory) }, uniquingKeysWith: { first, _ in first })
    }

    var count: Int { ayahs.count }

    func memory(ofAyah ayah: Int) -> AyahMemory? { ayahs[ayah] }

    func isMemorized(_ ayah: Int) -> Bool { ayahs[ayah] != nil }

    /// How many ayat of a range are memorized.
    func memorizedCount(in range: ClosedRange<Int>) -> Int {
        range.reduce(0) { $0 + (ayahs[$1] == nil ? 0 : 1) }
    }

    /// The share of the Quran memorized, counting every juz' equally (a juz' is a twentieth of the Mushaf's pages,
    /// whatever its number of ayat) and a juz' memorized in part by the share of its ayat.
    func quranShare(in store: MushafStore) -> Double {
        quranShare(in: store) { memorizedCount(in: $0) }
    }

    /// A share of the Quran by another count of a range's ayat (mastered, verified), every juz' counted equally as in
    /// `quranShare(in:)`, so the shares can be set side by side.
    func quranShare(in store: MushafStore, counting count: (ClosedRange<Int>) -> Int) -> Double {
        (1...30).reduce(0.0) { total, juz in
            guard let range = store.juzAyahs[juz] else { return total }
            return total + Double(count(range)) / Double(range.count)
        } / 30
    }

    /// The average strength of everything memorized, from 0 to 1; nil when nothing is memorized.
    func averageStrength(at date: Date = .now, policy: ReviewPolicy = .standard) -> Double? {
        guard !ayahs.isEmpty else { return nil }
        return ayahs.values.reduce(0) { $0 + $1.strength(at: date, policy: policy) } / Double(ayahs.count)
    }

    /// How strong an ayah's memorization is now, or nil if it isn't memorized.
    func strength(ofAyah ayah: Int, at date: Date = .now, policy: ReviewPolicy = .standard) -> Double? {
        ayahs[ayah]?.strength(at: date, policy: policy)
    }

    /// Records a revision of memorized ayat: the stumbled ones weaken, the rest grow stronger (by `weight`, see
    /// `AyahMemory.revised`). Ayat that aren't memorized are left alone.
    func recordRevision(ayahs revised: some Sequence<Int>, stumbled: Set<Int>, at date: Date, policy: ReviewPolicy,
                        weight: Double = 1) {
        var changed = false
        for ayah in revised {
            guard let memory = ayahs[ayah] else { continue }
            ayahs[ayah] = memory.revised(stumbled: stumbled.contains(ayah), at: date, policy: policy, weight: weight)
            changed = true
        }
        if changed {
            scheduleSave()
            saveNow()
        }
    }

    /// A teacher heard these ayat in a tasmee': the memorized ones among them are marked verified, except the
    /// stumbled ones, which lose the mark until a teacher hears them clean again.
    func verify(_ heard: some Sequence<Int>, except stumbled: Set<Int> = []) {
        var changed = false
        for ayah in heard {
            let verified = !stumbled.contains(ayah)
            guard var memory = ayahs[ayah], memory.verified != verified else { continue }
            memory.verified = verified
            ayahs[ayah] = memory
            changed = true
        }
        if changed {
            scheduleSave()
            saveNow()
        }
    }

    func toggle(ayah: Int) {
        mark([ayah], memorized: !isMemorized(ayah))
    }

    /// Replaces everything memorized: restoring from the account, or clearing the device on signing out.
    func replaceAll(_ memories: [Int: AyahMemory]) {
        guard memories != ayahs else { return }
        ayahs = memories.filter { (0..<MushafStore.ayahCount).contains($0.key) }
        scheduleSave()
        saveNow()
    }

    /// Marks ayat as newly memorized in Aqra (a portion of the plan): they start at the plan's short half-life, so
    /// they're faint and come back soon. Ayat already memorized keep what's known about them.
    func learn(_ learned: some Sequence<Int>, at date: Date = .now, stability: Double) {
        var changed = false
        for ayah in learned where (0..<MushafStore.ayahCount).contains(ayah) && !isMemorized(ayah) {
            ayahs[ayah] = AyahMemory(since: date, stability: stability, learnedAt: date)
            changed = true
        }
        if changed {
            scheduleSave()
            saveNow()
        }
    }

    /// The memorized ayat that are mastered (see `AyahMemory.isMastered`), counted in a range.
    func masteredCount(in range: ClosedRange<Int>, policy: StagePolicy = .standard) -> Int {
        range.reduce(0) { $0 + (ayahs[$1]?.isMastered(policy: policy) == true ? 1 : 0) }
    }

    /// The memorized ayat a teacher verified, counted in a range.
    func verifiedCount(in range: ClosedRange<Int>) -> Int {
        range.reduce(0) { $0 + (ayahs[$1]?.verified == true ? 1 : 0) }
    }

    /// Marks ayat as memorized (keeping what's already known about them) or as not memorized.
    /// - Returns: the records of the ayat it unmarked, so the unmarking can be undone.
    @discardableResult
    func mark(_ range: some Sequence<Int>, memorized: Bool) -> [Int: AyahMemory] {
        var removed: [Int: AyahMemory] = [:]
        var changed = false
        for ayah in range where (0..<MushafStore.ayahCount).contains(ayah) && isMemorized(ayah) != memorized {
            if !memorized { removed[ayah] = ayahs[ayah] }
            ayahs[ayah] = memorized ? AyahMemory(since: .now) : nil
            changed = true
        }
        if changed { scheduleSave() }
        return removed
    }

    /// Puts records back exactly as they were (undoing an unmarking), over whatever the ayat hold now.
    func restore(_ records: [Int: AyahMemory]) {
        guard !records.isEmpty else { return }
        for (ayah, memory) in records where (0..<MushafStore.ayahCount).contains(ayah) {
            ayahs[ayah] = memory
        }
        scheduleSave()
    }

    // MARK: - Saving

    private struct File: Codable {
        struct Record: Codable {
            var ayah: Int
            var memory: AyahMemory
        }
        var version = 2
        var ayahs: [Record]
    }

    /// Writes shortly after the last change, so marking many ayat at once writes once.
    private func scheduleSave() {
        onChange?()
        guard let fileURL else { return }
        pendingSave?.cancel()
        let file = File(ayahs: ayahs.sorted { $0.key < $1.key }.map { File.Record(ayah: $0.key, memory: $0.value) })
        pendingSave = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            Self.write(file, to: fileURL)
        }
    }

    /// Writes any change still waiting to be saved, right away.
    func saveNow() {
        guard let fileURL, pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        Self.write(File(ayahs: ayahs.sorted { $0.key < $1.key }.map { File.Record(ayah: $0.key, memory: $0.value) }), to: fileURL)
    }

    private static func write(_ file: File, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(file).write(to: url, options: .atomic)
    }
}

/// The Mushaf's marking mode. A tap marks or unmarks one ayah. Pressing and holding an ayah starts a range:
/// the next tap, on any page, marks every ayah from there to it (or unmarks them, when the first was marked).
@MainActor @Observable
final class MarkingSession {
    let memorization: MemorizationStore
    /// Where a range started, while it waits for its last ayah.
    private(set) var rangeStart: Int?
    /// «حدّد نطاقًا» was pressed: the next tap starts a range rather than toggling an ayah.
    private(set) var choosingRangeStart = false
    /// What the last unmarking removed, kept for a moment so it can be undone: an unmarked ayah loses its strength,
    /// its revisions and a teacher's mark. Empty when there's nothing to undo.
    private(set) var unmarked: [Int: AyahMemory] = [:]
    /// Changes with each unmarking, so its undo expires on time and not a later one's.
    private(set) var unmarkedVersion = 0
    @ObservationIgnored private var rangeMarks = true

    init(memorization: MemorizationStore) {
        self.memorization = memorization
    }

    func tap(_ ayah: Int) {
        if choosingRangeStart {
            choosingRangeStart = false
            beginRange(at: ayah)
        } else if let start = rangeStart {
            // A range that unmarks is one unmarking with its first ayah, unmarked when it began.
            note(memorization.mark(min(start, ayah)...max(start, ayah), memorized: rangeMarks), continuing: !rangeMarks)
            rangeStart = nil
        } else {
            note(memorization.mark([ayah], memorized: !memorization.isMemorized(ayah)))
        }
    }

    /// Starts a range at an ayah, marking it (or unmarking it, if it was marked) right away.
    func beginRange(at ayah: Int) {
        rangeMarks = !memorization.isMemorized(ayah)
        note(memorization.mark([ayah], memorized: rangeMarks))
        rangeStart = ayah
    }

    /// «حدّد نطاقًا»: the next ayah tapped starts a range, and the one after ends it.
    func chooseRange() {
        choosingRangeStart = true
        rangeStart = nil
    }

    func cancelRange() {
        rangeStart = nil
        choosingRangeStart = false
    }

    /// Marks every ayah of the given pages, or unmarks them when they're all already marked.
    func toggle(_ ayahs: ClosedRange<Int>) {
        note(memorization.mark(ayahs, memorized: memorization.memorizedCount(in: ayahs) < ayahs.count))
    }

    /// Puts back what the last unmarking removed, exactly as it was.
    func undo() {
        memorization.restore(unmarked)
        unmarked = [:]
    }

    /// The undo is offered for a moment only; a later unmarking keeps its own.
    func expireUndo(version: Int) {
        if version == unmarkedVersion { unmarked = [:] }
    }

    private func note(_ removed: [Int: AyahMemory], continuing: Bool = false) {
        if continuing {
            unmarked.merge(removed) { first, _ in first }
        } else {
            unmarked = removed
        }
        unmarkedVersion += 1
    }
}
