import Foundation
import Observation

/// The rules of the personal plan, in one place so they can be tuned after trying them (docs/SRS.md, §3.7).
struct PlanPolicy: Hashable, Sendable {
    /// The daily amounts offered, in lines of the 15-line page: from ¼ page up to 2½ pages, a quarter at a time.
    var amountOptions = [4, 8, 11, 15, 19, 23, 26, 30, 34, 38]
    var defaultAmount = 8
    /// Calendar weekdays (1 is Sunday, 7 Saturday): every day but Friday.
    var defaultStudyDays: Set<Int> = [1, 2, 3, 4, 5, 7]
    /// The half-life a newly memorized ayah starts at: short, so it's faint and comes back soon.
    var newStability = 2.0
    /// The recent pace is measured over this many days, once this many study days have passed in them.
    var paceWindowDays = 28
    var minPaceDays = 7

    static let standard = PlanPolicy()
}

/// How the student memorizes new portions: how much a day, on which days, and in which order.
struct MemorizationPlan: Codable, Hashable {
    enum Order: String, Codable, CaseIterable {
        /// From the end of the Mushaf: an-Nas, then the surahs before it, each from its first ayah (juz' ʿAmma first).
        case fromEnd
        /// From the beginning: al-Fatiha, al-Baqarah, and on.
        case fromStart
    }

    /// The daily amount, in lines of the page.
    var dailyLines: Int
    /// Calendar weekdays (1 is Sunday).
    var studyDays: Set<Int>
    var order: Order
    var paused = false
}

/// One day's new memorization: what the plan proposed and what the student actually memorized, kept apart.
struct Portion: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var planned: [Int]
    var memorized: [Int]
    var plannedLines: Double
    var actualLines: Double
}

/// A change to the plan, kept so the plan's past isn't lost.
struct PlanChange: Codable, Hashable {
    var date: Date
    /// The plan from that date; nil when it was turned off.
    var plan: MemorizationPlan?
}

/// What the plan asks of today.
enum TodayPortion: Hashable {
    /// Today's portion, to memorize.
    case due([Int])
    /// Memorized already today.
    case done(Portion)
    /// Not a study day; the next one.
    case restDay(next: Date)
    /// Everything is memorized.
    case complete
}

/// The personal memorization plan: the daily new portion, its log (planned and actual), the plan's history, and
/// the expected completion date. Kept on the device and backed up with the rest of the journey.
@MainActor @Observable
final class PlanStore {
    let policy: PlanPolicy
    private(set) var plan: MemorizationPlan?
    private(set) var portions: [Portion] = []
    private(set) var history: [PlanChange] = []
    private(set) var updatedAt = Date.distantPast
    /// Called after every change, so the backup can follow.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called after a portion is memorized, so rewards can follow.
    @ObservationIgnored var onPortion: ((Portion) -> Void)?

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let calendar: Calendar

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("plan.json")
    }

    init(fileURL: URL? = PlanStore.defaultURL, policy: PlanPolicy = .standard, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.policy = policy
        self.calendar = calendar
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        plan = snapshot.plan
        portions = snapshot.portions
        history = snapshot.history
        updatedAt = snapshot.updatedAt
    }

    // MARK: - The plan

    /// Sets (or changes) the plan, keeping the change in its history.
    func setPlan(_ plan: MemorizationPlan?, now: Date = .now) {
        guard plan != self.plan else { return }
        var plan = plan
        if var chosen = plan {
            chosen.dailyLines = min(max(chosen.dailyLines, 1), 45)
            if chosen.studyDays.isEmpty { chosen.studyDays = policy.defaultStudyDays }
            plan = chosen
        }
        self.plan = plan
        history.append(PlanChange(date: now, plan: plan))
        save()
    }

    /// The order that continues what the student already knows: from the beginning when their memorization runs
    /// from al-Baqarah, otherwise from the end (where most begin).
    static func suggestedOrder(memorization: MemorizationStore, store: MushafStore) -> MemorizationPlan.Order {
        let first = store.juzAyahs[1].map { memorization.memorizedCount(in: $0) } ?? 0
        let last = store.juzAyahs[30].map { memorization.memorizedCount(in: $0) } ?? 0
        return first > last ? .fromStart : .fromEnd
    }

    func isStudyDay(_ date: Date) -> Bool {
        guard let plan else { return false }
        return plan.studyDays.contains(calendar.component(.weekday, from: date))
    }

    /// Whether a new portion is still due today: a study day of an active plan, none recorded yet today, and
    /// something left to memorize.
    func isPortionDue(memorization: MemorizationStore, now: Date = .now) -> Bool {
        guard let plan, !plan.paused, isStudyDay(now), memorization.count < MushafStore.ayahCount else { return false }
        let day = calendar.startOfDay(for: now)
        return !portions.contains { calendar.startOfDay(for: $0.date) == day }
    }

    // MARK: - Today

    /// The next portion in the plan's order: the next ayat not yet memorized, about the daily amount, ending at an
    /// ayah's end. It moves on to the next surah in the order only once the current one is finished.
    static func nextPortion(order: MemorizationPlan.Order, dailyLines: Int, store: MushafStore,
                            isMemorized: (Int) -> Bool) -> [Int] {
        let surahs = order == .fromStart ? Array(1...114) : Array((1...114).reversed())
        let target = Double(max(dailyLines, 1))
        var portion: [Int] = []
        var lines = 0.0
        for surah in surahs {
            guard let range = store.surahAyahs[surah], let first = range.first(where: { !isMemorized($0) }) else { continue }
            var ayah = first
            while ayah <= range.upperBound, !isMemorized(ayah) {
                let length = store.ayahLines[ayah]
                // A long ayah that would run far past the amount waits for tomorrow, once there's enough for today.
                if !portion.isEmpty, lines >= target * 0.5, lines + length > target * 1.5 { return portion }
                portion.append(ayah)
                lines += length
                if lines >= target - 0.05 {
                    // A surah with only a little left is finished today rather than left for tomorrow.
                    var rest = ayah + 1
                    var restLines = 0.0
                    while rest <= range.upperBound, !isMemorized(rest) {
                        restLines += store.ayahLines[rest]
                        rest += 1
                    }
                    if rest > range.upperBound, restLines > 0, restLines <= target * 0.25 {
                        portion += Array(ayah + 1...range.upperBound)
                    }
                    return portion
                }
                ayah += 1
            }
            // An ayah already memorized inside the surah ends the portion; a finished surah leads to the next.
            if ayah <= range.upperBound, !portion.isEmpty { return portion }
        }
        return portion
    }

    /// The first ayah of the plan's next portion, whatever today's state (due, done, a rest day, paused); nil
    /// without a plan or when everything is memorized.
    func nextAyah(memorization: MemorizationStore, store: MushafStore) -> Int? {
        guard let plan else { return nil }
        return Self.nextPortion(order: plan.order, dailyLines: plan.dailyLines, store: store,
                                isMemorized: memorization.isMemorized).first
    }

    func today(memorization: MemorizationStore, store: MushafStore, now: Date = .now) -> TodayPortion? {
        guard let plan, !plan.paused else { return nil }
        let day = calendar.startOfDay(for: now)
        if let done = portions.last(where: { calendar.startOfDay(for: $0.date) == day }) { return .done(done) }
        guard memorization.count < MushafStore.ayahCount else { return .complete }
        guard isStudyDay(now) else { return .restDay(next: nextStudyDay(after: day)) }
        let portion = Self.nextPortion(order: plan.order, dailyLines: plan.dailyLines, store: store,
                                       isMemorized: memorization.isMemorized)
        return portion.isEmpty ? .complete : .due(portion)
    }

    private func nextStudyDay(after day: Date) -> Date {
        var next = date(day, plus: 1)
        for _ in 0..<7 where !isStudyDay(next) { next = date(next, plus: 1) }
        return next
    }

    // MARK: - «تم الحفظ»

    /// Records today's portion: the ayat memorized (all of the proposal, or the first part of it) start their
    /// life in the revision engine — faint, and back for follow-up tomorrow.
    @discardableResult
    func record(planned: [Int], memorized: [Int], store: MushafStore, memorization: MemorizationStore,
                revision: RevisionStore, now: Date = .now) -> Portion? {
        // Kept in the order memorized (the plan's), not sorted: from the end, an-Nas comes before al-Falaq.
        let memorized = memorized.filter { !memorization.isMemorized($0) }
        guard !memorized.isEmpty else { return nil }
        memorization.learn(memorized, at: now, stability: policy.newStability)
        var pages = Set<Int>()
        for ayah in memorized {
            let page = store.page(ofAyah: ayah)
            pages.insert(page)
            // An ayah that runs onto the next page is on both.
            if page < MushafStore.pageCount, store.page(page + 1).ayahs.lowerBound == ayah { pages.insert(page + 1) }
        }
        revision.followUp(pages: pages, now: now)
        let portion = Portion(date: now, planned: planned, memorized: memorized, plannedLines: store.lines(of: planned),
                              actualLines: store.lines(of: memorized))
        portions.append(portion)
        save()
        onPortion?(portion)
        return portion
    }

    // MARK: - The completion date

    /// Lines memorized per study day lately, once enough study days have passed to tell; nil until then.
    func recentPace(now: Date = .now) -> Double? {
        // Since the plan was last turned on: the earliest change in the run of changes that kept it on.
        var started: Date?
        for change in history.reversed() {
            guard change.plan != nil else { break }
            started = change.date
        }
        guard let plan, let started else { return nil }
        let today = calendar.startOfDay(for: now)
        let windowStart = max(calendar.startOfDay(for: started), date(today, plus: -policy.paceWindowDays))
        let doneToday = portions.contains { calendar.startOfDay(for: $0.date) == today }
        var studyDays = 0
        var day = windowStart
        while day < today || (day == today && doneToday) {
            if plan.studyDays.contains(calendar.component(.weekday, from: day)) { studyDays += 1 }
            day = date(day, plus: 1)
        }
        guard studyDays >= policy.minPaceDays else { return nil }
        let lines = portions.filter { $0.date >= windowStart }.reduce(0) { $0 + $1.actualLines }
        return lines / Double(studyDays)
    }

    /// When the whole Quran would be memorized at the recent pace (or the plan's, until there's a pace to go by).
    func completionDate(memorization: MemorizationStore, store: MushafStore, now: Date = .now) -> Date? {
        guard let plan, !plan.paused else { return nil }
        let today = calendar.startOfDay(for: now)
        let doneToday = portions.contains { calendar.startOfDay(for: $0.date) == today }
        return Self.estimate(plan, remainingLines: Self.remainingLines(memorization: memorization, store: store),
                             pace: recentPace(now: now), from: doneToday ? date(today, plus: 1) : today, calendar: calendar)
    }

    /// The lines not yet memorized.
    static func remainingLines(memorization: MemorizationStore, store: MushafStore) -> Double {
        (0..<MushafStore.ayahCount).reduce(0.0) { memorization.isMemorized($1) ? $0 : $0 + store.ayahLines[$1] }
    }

    /// The study day on which the remaining lines would be done, at a pace (lines per study day) or the plan's own.
    static func estimate(_ plan: MemorizationPlan, remainingLines: Double, pace: Double?, from start: Date,
                         calendar: Calendar = .current) -> Date? {
        guard remainingLines > 0, !plan.studyDays.isEmpty else { return nil }
        let pace = max(pace ?? Double(plan.dailyLines), 0.5)
        var needed = Int((remainingLines / pace).rounded(.up))
        var day = calendar.startOfDay(for: start)
        // Fifty years at most: past that the date says nothing useful.
        for _ in 0..<18_300 {
            if plan.studyDays.contains(calendar.component(.weekday, from: day)) {
                needed -= 1
                if needed <= 0 { return day }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        return nil
    }

    /// Lines memorized in the last days, for the progress screen.
    func lines(inLast days: Int, now: Date = .now) -> Double {
        let start = date(calendar.startOfDay(for: now), plus: -(days - 1))
        return portions.filter { $0.date >= start }.reduce(0) { $0 + $1.actualLines }
    }

    private func date(_ day: Date, plus days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: day) ?? day.addingTimeInterval(Double(days) * 86_400)
    }

    // MARK: - Backup

    struct Snapshot: Codable, Equatable {
        var plan: MemorizationPlan?
        var portions: [Portion] = []
        var history: [PlanChange] = []
        var updatedAt = Date.distantPast

        static let empty = Snapshot()

        init(plan: MemorizationPlan? = nil, portions: [Portion] = [], history: [PlanChange] = [], updatedAt: Date = .distantPast) {
            self.plan = plan
            self.portions = portions
            self.history = history
            self.updatedAt = updatedAt
        }

        // The account's copy may come from the Android app or a newer version: a key missing, unknown or
        // unreadable never loses the rest.
        private enum CodingKeys: String, CodingKey { case plan, portions, history, updatedAt }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            plan = container.decodeOrNil(MemorizationPlan.self, forKey: .plan)
            portions = container.decodeLossy([Portion].self, forKey: .portions)
            history = container.decodeLossy([PlanChange].self, forKey: .history)
            updatedAt = container.decodeOr(Date.self, forKey: .updatedAt, .distantPast)
        }

        /// Both copies as one: the plan most recently changed, and the portions and history of both.
        static func merge(_ local: Snapshot, _ remote: Snapshot) -> Snapshot {
            var merged = remote.updatedAt >= local.updatedAt ? remote : local
            var seen = Set<UUID>()
            merged.portions = (local.portions + remote.portions).sorted { $0.date < $1.date }.filter { seen.insert($0.id).inserted }
            var changes = Set<PlanChange>()
            merged.history = (local.history + remote.history).sorted { $0.date < $1.date }.filter { changes.insert($0).inserted }
            merged.updatedAt = max(local.updatedAt, remote.updatedAt)
            return merged
        }
    }

    var snapshot: Snapshot {
        Snapshot(plan: plan, portions: portions, history: history, updatedAt: updatedAt)
    }

    func apply(_ snapshot: Snapshot) {
        guard snapshot != self.snapshot else { return }
        plan = snapshot.plan
        portions = snapshot.portions
        history = snapshot.history
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
