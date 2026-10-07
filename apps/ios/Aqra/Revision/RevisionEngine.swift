import Foundation
import Observation

/// Every rule of revision in one place, so they can be tuned after trying them, not buried in the code.
/// See docs/REVISION.md.
struct ReviewPolicy: Codable, Hashable, Sendable {
    /// The half-life, in days, given to ayat the student declares they already know.
    var declaredStability = 14.0
    /// How much a clean revision multiplies the half-life, when it comes after the memory has had time to slip.
    var growth = 2.5
    /// What a stumble multiplies the half-life by.
    var lapseFactor = 0.3
    var minStability = 1.0
    var maxStability = 365.0
    /// The half-life at which a memorization counts as fully established (full color).
    var matureStability = 90.0
    /// After a stumble, the page comes back after these many days, one after another, while it stays clean.
    var followUpDays = [1, 3, 7]
    /// How much more a clean revision counts when a sheikh heard it in a tasmee', compared with self-revision.
    /// Provisional, see docs/REVISION.md.
    var sheikhWeight = 1.5
    /// A peer's tasmee' sits between self-revision and a sheikh's. Provisional, see docs/REVISION.md.
    var peerWeight = 1.25

    static let standard = ReviewPolicy()

    /// The weight of a revision's evidence: self-revision, in or outside the app, counts once; a peer's more,
    /// and a sheikh's more still.
    func weight(of source: RevisionRecord.Source) -> Double {
        switch source {
        case .app, .outside: 1
        case .peer: peerWeight
        case .sheikh: sheikhWeight
        }
    }

    /// A daily amount that goes through everything memorized in about a month.
    static func suggestedDailyPages(memorizedPages: Int) -> Int {
        min(max(Int((Double(memorizedPages) / 30).rounded(.up)), 2), 20)
    }
}

/// One page revised: when, how, and which of its ayat the student stumbled on.
struct RevisionRecord: Codable, Hashable {
    /// Who heard the revision: the student alone, in the app or outside it, a peer, or a sheikh in a tasmee'.
    enum Source: String, Codable { case app, outside, peer, sheikh }

    var date: Date
    var page: Int
    var source: Source
    var stumbles: [Int]
}

/// A page in today's plan.
struct PlanItem: Codable, Hashable, Identifiable {
    enum Kind: String, Codable {
        /// It was stumbled on recently and comes back to be made firm.
        case followUp
        /// Its turn has come in the rotation through everything memorized.
        case rotation
    }

    var page: Int
    var kind: Kind
    var done = false
    var id: Int { page }
}

/// Today's plan. It's fixed once made, so it doesn't shift while the student works through it.
struct DayPlan: Codable, Hashable {
    var day: Date
    var items: [PlanItem]

    var doneCount: Int { items.filter(\.done).count }
    var isComplete: Bool { !items.isEmpty && items.allSatisfy(\.done) }
}

/// The revision plan and its record, kept on the device.
///
/// Each day the plan takes, in order: pages due for follow-up after a stumble, then the next pages of the
/// rotation through everything memorized, in Mushaf order, up to the daily amount. The rotation only moves on
/// when its pages are revised, so missed days don't pile up: tomorrow starts where the student stopped.
@MainActor @Observable
final class RevisionStore {
    struct FollowUp: Codable, Hashable {
        var due: Date
        /// Which of the policy's follow-up intervals it's on.
        var step: Int
    }

    let policy: ReviewPolicy
    /// The pages to revise each day, or nil until the student chooses (a suggestion is used meanwhile).
    private(set) var dailyPages: Int?
    /// The page the rotation continues from.
    private(set) var rotationCursor = 1
    private(set) var followUps: [Int: FollowUp] = [:]
    private(set) var plan: DayPlan?
    private(set) var history: [RevisionRecord] = []
    /// The days on which at least one page was revised, kept apart from the history so a long streak isn't cut
    /// short when old records are dropped.
    private(set) var revisedDays: Set<Date> = []
    /// The days on which the whole of that day's wird was revised.
    private(set) var completedDays: Set<Date> = []
    /// When any of it last changed, to tell which copy is newer when merging with the account's.
    private(set) var updatedAt = Date.distantPast
    /// Called after every change, so the backup can follow.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called after each page is recorded, so rewards can follow.
    @ObservationIgnored var onRecord: ((RevisionRecord) -> Void)?

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let calendar: Calendar

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("revision.json")
    }

    /// Loads the record from `fileURL`, or keeps it in memory only when it's nil (previews, snapshots and tests).
    init(fileURL: URL? = RevisionStore.defaultURL, policy: ReviewPolicy = .standard, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.policy = policy
        self.calendar = calendar
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return }
        dailyPages = file.dailyPages
        rotationCursor = file.rotationCursor
        followUps = Dictionary(file.followUps.map { ($0.page, FollowUp(due: $0.due, step: $0.step)) }, uniquingKeysWith: { first, _ in first })
        plan = file.plan
        history = file.history
        revisedDays = Set(file.revisedDays ?? file.history.map { calendar.startOfDay(for: $0.date) })
        completedDays = Set(file.completedDays ?? [])
        // Files from before backups were kept don't say when they changed; the file's own date does.
        updatedAt = file.updatedAt
            ?? (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
    }

    // MARK: - Backup

    /// Everything the store keeps, as one value: what's backed up to the account and restored from it.
    struct Snapshot: Codable, Equatable {
        var dailyPages: Int?
        var rotationCursor = 1
        var followUps: [Int: FollowUp] = [:]
        var plan: DayPlan?
        var history: [RevisionRecord] = []
        var revisedDays: [Date] = []
        /// Missing from backups made before it was kept.
        var completedDays: [Date]? = nil
        var updatedAt = Date.distantPast

        static let empty = Snapshot()
    }

    var snapshot: Snapshot {
        Snapshot(dailyPages: dailyPages, rotationCursor: rotationCursor, followUps: followUps, plan: plan,
                 history: history, revisedDays: revisedDays.sorted(),
                 completedDays: completedDays.isEmpty ? nil : completedDays.sorted(), updatedAt: updatedAt)
    }

    /// Replaces everything with a snapshot: restoring from the account, or clearing the device on signing out.
    func apply(_ snapshot: Snapshot) {
        guard snapshot != self.snapshot else { return }
        dailyPages = snapshot.dailyPages.map { min(max($0, 1), 40) }
        rotationCursor = min(max(snapshot.rotationCursor, 1), MushafStore.pageCount)
        followUps = snapshot.followUps
        plan = snapshot.plan
        history = Array(snapshot.history.suffix(1_000))
        revisedDays = Set(snapshot.revisedDays)
        completedDays = Set(snapshot.completedDays ?? [])
        save()
    }

    /// The daily amount in effect: the student's choice, or the suggestion for what they've memorized.
    func effectiveDailyPages(memorizedPages: Int) -> Int {
        dailyPages ?? ReviewPolicy.suggestedDailyPages(memorizedPages: memorizedPages)
    }

    func setDailyPages(_ pages: Int) {
        dailyPages = min(max(pages, 1), 40)
        save()
    }

    /// The pages that hold any memorized ayah, in Mushaf order.
    static func memorizedPages(in store: MushafStore, memorization: MemorizationStore) -> [Int] {
        (1...MushafStore.pageCount).filter { memorization.memorizedCount(in: store.page($0).ayahs) > 0 }
    }

    // MARK: - Today's plan

    /// Makes today's plan if there isn't one for today yet (or if the one there was empty), and drops pages that
    /// are no longer memorized from it.
    func refreshPlan(memorizedPages: [Int], now: Date = .now) {
        let day = calendar.startOfDay(for: now)
        let memorized = Set(memorizedPages)
        if var plan, plan.day == day, !plan.items.isEmpty {
            let kept = plan.items.filter { $0.done || memorized.contains($0.page) }
            if kept != plan.items {
                plan.items = kept
                self.plan = plan
                save()
            }
            return
        }

        let amount = effectiveDailyPages(memorizedPages: memorizedPages.count)
        // Pages due for follow-up come first, the most overdue first; at least one rotation page always follows.
        let due = followUps
            .filter { $0.value.due <= day && memorized.contains($0.key) }
            .sorted { ($0.value.due, $0.key) < ($1.value.due, $1.key) }
            .prefix(max(amount - 1, 1))
            .map { PlanItem(page: $0.key, kind: .followUp) }

        // Then the rotation, from where it stopped, wrapping round to the start of what's memorized.
        let ordered = memorizedPages.sorted()
        let start = ordered.firstIndex { $0 >= rotationCursor } ?? 0
        let wrapped = ordered.isEmpty ? [] : Array(ordered[start...] + ordered[..<start])
        let taken = Set(due.map(\.page))
        let rotation = wrapped
            .filter { !taken.contains($0) }
            .prefix(max(amount - due.count, 1))
            .map { PlanItem(page: $0, kind: .rotation) }

        plan = DayPlan(day: day, items: due + rotation)
        save()
    }

    // MARK: - Recording

    /// Records a revised page: updates its memorized ayat, its follow-up and the rotation, and checks it off today.
    /// - Parameters:
    ///   - ayahs: the page's memorized ayat (the ones the revision covered).
    ///   - stumbles: those the student stumbled on.
    ///   - source: who heard it; a sheikh's tasmee' counts more (see `ReviewPolicy.weight(of:)`).
    func record(page: Int, ayahs: [Int], stumbles: Set<Int>, source: RevisionRecord.Source,
                memorization: MemorizationStore, now: Date = .now) {
        memorization.recordRevision(ayahs: ayahs, stumbled: stumbles, at: now, policy: policy, weight: policy.weight(of: source))
        let day = calendar.startOfDay(for: now)

        // A stumble brings the page back tomorrow; clean follow-ups space out until the page leaves follow-up.
        if !stumbles.isEmpty {
            followUps[page] = FollowUp(due: date(day, plus: policy.followUpDays.first ?? 1), step: 0)
        } else if let followUp = followUps[page] {
            let next = followUp.step + 1
            followUps[page] = next < policy.followUpDays.count
                ? FollowUp(due: date(day, plus: policy.followUpDays[next]), step: next)
                : nil
        }

        if var plan, plan.day == day, let index = plan.items.firstIndex(where: { $0.page == page }) {
            plan.items[index].done = true
            self.plan = plan
            if plan.isComplete { completedDays.insert(day) }
            // The rotation moves past the leading run of revised rotation pages, so a page skipped today
            // (or revised out of order) is still first tomorrow.
            var cursor = rotationCursor
            for item in plan.items where item.kind == .rotation {
                guard item.done else { break }
                cursor = item.page % MushafStore.pageCount + 1
            }
            rotationCursor = cursor
        }

        revisedDays.insert(day)
        let entry = RevisionRecord(date: now, page: page, source: source, stumbles: stumbles.sorted())
        history.append(entry)
        if history.count > 1_000 { history.removeFirst(history.count - 1_000) }
        save()
        onRecord?(entry)
    }

    /// Brings pages back for follow-up from tomorrow, as after a stumble: a portion just memorized, or pages the
    /// student chose to strengthen. A page already due sooner keeps its date.
    func followUp(pages: some Sequence<Int>, now: Date = .now) {
        let due = date(calendar.startOfDay(for: now), plus: policy.followUpDays.first ?? 1)
        var changed = false
        for page in Set(pages) where (1...MushafStore.pageCount).contains(page) {
            if let existing = followUps[page], existing.due <= due { continue }
            followUps[page] = FollowUp(due: due, step: 0)
            changed = true
        }
        if changed { save() }
    }

    // MARK: - Streak

    /// The days in a row, up to today, on which the student revised. Today not being revised yet doesn't break
    /// it: until the day ends, the streak counts back from yesterday.
    func streak(now: Date = .now) -> Int {
        var day = calendar.startOfDay(for: now)
        if !revisedDays.contains(day) { day = date(day, plus: -1) }
        var count = 0
        while revisedDays.contains(day) {
            count += 1
            day = date(day, plus: -1)
        }
        return count
    }

    /// Whether the student revised on each of the last `count` days, oldest first, ending today.
    func recentDays(_ count: Int = 7, now: Date = .now) -> [Bool] {
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().map { revisedDays.contains(date(today, plus: -$0)) }
    }

    private func date(_ day: Date, plus days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: day) ?? day.addingTimeInterval(Double(days) * 86_400)
    }

    // MARK: - Saving

    private struct File: Codable {
        struct FollowUpRecord: Codable {
            var page: Int
            var due: Date
            var step: Int
        }
        var version = 1
        var dailyPages: Int?
        var rotationCursor: Int
        var followUps: [FollowUpRecord]
        var plan: DayPlan?
        var history: [RevisionRecord]
        /// Missing from files written before the streak was kept; it's then rebuilt from the history.
        var revisedDays: [Date]?
        var completedDays: [Date]?
        var updatedAt: Date?
    }

    private func save() {
        updatedAt = .now
        onChange?()
        guard let fileURL else { return }
        let file = File(
            dailyPages: dailyPages, rotationCursor: rotationCursor,
            followUps: followUps.sorted { $0.key < $1.key }.map { File.FollowUpRecord(page: $0.key, due: $0.value.due, step: $0.value.step) },
            plan: plan, history: history, revisedDays: revisedDays.sorted(), completedDays: completedDays.sorted(),
            updatedAt: updatedAt
        )
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(file).write(to: fileURL, options: .atomic)
    }
}

/// Revising one page: its memorized ayat are veiled and revealed one at a time, and the student marks the
/// ones they stumbled on.
@MainActor @Observable
final class RevisionSession {
    let page: Int
    /// The page's memorized ayat, in order: the ones this revision covers.
    let ayahs: [Int]
    /// How many of them are revealed, from the first.
    private(set) var revealed = 0
    private(set) var stumbles: Set<Int> = []

    init(page: Int, ayahs: [Int]) {
        self.page = page
        self.ayahs = ayahs
    }

    var isComplete: Bool { revealed >= ayahs.count }

    /// Whether an ayah is covered by this revision.
    func covers(_ ayah: Int) -> Bool { ayahs.contains(ayah) }

    /// Whether an ayah is still veiled.
    func isVeiled(_ ayah: Int) -> Bool {
        guard let index = ayahs.firstIndex(of: ayah) else { return false }
        return index >= revealed
    }

    /// A tap on a revealed ayah marks or unmarks a stumble on it; any other tap reveals the next ayah.
    func tap(_ ayah: Int?) {
        if let ayah, covers(ayah), !isVeiled(ayah) {
            if stumbles.contains(ayah) { stumbles.remove(ayah) } else { stumbles.insert(ayah) }
        } else {
            revealNext()
        }
    }

    func revealNext() {
        revealed = min(revealed + 1, ayahs.count)
    }

    func revealAll() {
        revealed = ayahs.count
    }

    /// Marks an ayah as stumbled on, whatever it was (a listener classifying the stumble).
    func markStumble(_ ayah: Int) {
        guard covers(ayah) else { return }
        stumbles.insert(ayah)
    }

    func clearStumble(_ ayah: Int) {
        stumbles.remove(ayah)
    }
}
