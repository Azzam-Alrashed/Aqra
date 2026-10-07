import AVFoundation
import Foundation
import Observation

/// What each step of the journey earns, in one place so it can be tuned (docs/SRS.md, §3.7). Points are private:
/// they're the student's own encouragement, never a public rank.
struct RewardPolicy: Hashable, Sendable {
    var pageRevisedInApp = 2
    var pageRevisedOutside = 1
    var pageHeardByPeer = 3
    var pageHeardBySheikh = 5
    /// Per page's worth of new memorization (15 lines), at least `minPortionPoints`.
    var portionPerPage = 5
    var minPortionPoints = 2
    var wirdCompleted = 5
    var streakBonuses = [7: 20, 30: 50, 100: 100]
    var stagePassed = 100
    var challengeCompleted = 20

    static let standard = RewardPolicy()
}

/// Milestones of the journey, each earned once.
enum Achievement: String, Codable, CaseIterable, Hashable, Sendable {
    case firstRevision, firstWird, firstPortion, firstJuz, firstVerified, firstPeer
    case streak7, streak30, streak100
    case firstStage, fiveStages, wholeQuran

    var icon: String {
        switch self {
        case .firstRevision: "🌱"
        case .firstWird: "✅"
        case .firstPortion: "✍️"
        case .firstJuz: "📗"
        case .firstVerified: "🎓"
        case .firstPeer: "🤝"
        case .streak7: "🔥"
        case .streak30: "🌙"
        case .streak100: "💎"
        case .firstStage: "🪜"
        case .fiveStages: "⛰️"
        case .wholeQuran: "⭐️"
        }
    }
}

/// A goal the student sets themselves, for a week.
struct Challenge: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Hashable {
        /// Complete the whole wird on this many days.
        case wirdDays
        /// Revise this many pages.
        case pagesRevised
        /// Memorize this many lines of new portions.
        case linesMemorized
        /// Revise every day.
        case dailyRevision
    }

    var id = UUID()
    var kind: Kind
    var target: Int
    var start: Date
    var end: Date
    var completedAt: Date?

    /// The goals offered for a week.
    static let options: [(kind: Kind, target: Int)] = [
        (.wirdDays, 5), (.wirdDays, 7), (.pagesRevised, 30), (.pagesRevised, 100), (.linesMemorized, 30),
        (.linesMemorized, 60), (.dailyRevision, 7),
    ]
}

/// A moment to celebrate: points earned, an achievement, a stage passed, a challenge met.
struct Celebration: Identifiable, Equatable {
    enum Kind: Equatable {
        case points(Int)
        case achievement(Achievement)
        case stage(Int)
        case challenge(Challenge.Kind, Int)
    }

    let id = UUID()
    var kind: Kind
    var isBig: Bool {
        if case .points = kind { return false }
        return true
    }
}

/// Points, achievements and personal challenges: small, frequent rewards, private to the student. Kept on the
/// device and backed up with the rest of the journey.
@MainActor @Observable
final class RewardStore {
    struct Event: Codable, Hashable {
        var date: Date
        var points: Int
        var reason: String
    }

    let policy: RewardPolicy
    private(set) var points = 0
    /// The latest points earned, newest last.
    private(set) var events: [Event] = []
    private(set) var achievements: [Achievement: Date] = [:]
    private(set) var challenges: [Challenge] = []
    private(set) var updatedAt = Date.distantPast
    /// What's being celebrated now, shown over the app for a moment.
    var celebration: Celebration?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var celebrationQueue: [Celebration] = []

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("rewards.json")
    }

    init(fileURL: URL? = RewardStore.defaultURL, policy: RewardPolicy = .standard, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.policy = policy
        self.calendar = calendar
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        points = snapshot.points
        events = snapshot.events
        achievements = snapshot.achievements
        challenges = snapshot.challenges
        updatedAt = snapshot.updatedAt
    }

    // MARK: - Earning

    /// A page revised: points by who heard it, achievements, the wird completed, the streak's milestones.
    func revised(_ record: RevisionRecord, revision: RevisionStore, now: Date = .now) {
        let earned: Int
        switch record.source {
        case .app: earned = policy.pageRevisedInApp
        case .outside: earned = policy.pageRevisedOutside
        case .peer: earned = policy.pageHeardByPeer
        case .sheikh: earned = record.stumbles.isEmpty ? policy.pageHeardBySheikh : policy.pageRevisedInApp
        }
        var total = earned
        var reasons = ["page"]
        earn(.firstRevision, at: now)
        if record.source == .peer { earn(.firstPeer, at: now) }
        if record.source == .sheikh && record.stumbles.isEmpty { earn(.firstVerified, at: now) }
        let day = calendar.startOfDay(for: now)
        if revision.completedDays.contains(day), !events.contains(where: { $0.reason == "wird" && calendar.isDate($0.date, inSameDayAs: now) }) {
            total += policy.wirdCompleted
            reasons.append("wird")
            earn(.firstWird, at: now)
        }
        let streak = revision.streak(now: now)
        for (days, bonus) in policy.streakBonuses where streak >= days {
            let achievement: Achievement = days >= 100 ? .streak100 : days >= 30 ? .streak30 : .streak7
            if achievements[achievement] == nil {
                total += bonus
                earn(achievement, at: now)
            }
        }
        add(total, reason: reasons.last ?? "page", at: now)
    }

    /// A new portion memorized.
    func memorized(_ portion: Portion, memorization: MemorizationStore, store: MushafStore, now: Date = .now) {
        let earned = max(Int((portion.actualLines / 15 * Double(policy.portionPerPage)).rounded()), policy.minPortionPoints)
        earn(.firstPortion, at: now)
        noteMemorization(memorization: memorization, store: store, now: now)
        add(earned, reason: "portion", at: now)
    }

    /// Milestones of what's memorized: a whole juz', the whole Quran.
    func noteMemorization(memorization: MemorizationStore, store: MushafStore, now: Date = .now) {
        if (1...30).contains(where: { juz in store.juzAyahs[juz].map { memorization.memorizedCount(in: $0) == $0.count } ?? false }) {
            earn(.firstJuz, at: now)
        }
        if memorization.count == MushafStore.ayahCount { earn(.wholeQuran, at: now) }
    }

    func passedStage(_ stage: Int, totalPassed: Int, now: Date = .now) {
        earn(.firstStage, at: now)
        if totalPassed >= 5 { earn(.fiveStages, at: now) }
        celebrate(Celebration(kind: .stage(stage)))
        add(policy.stagePassed, reason: "stage", at: now, celebrating: false)
    }

    private func earn(_ achievement: Achievement, at date: Date) {
        guard achievements[achievement] == nil else { return }
        achievements[achievement] = date
        celebrate(Celebration(kind: .achievement(achievement)))
        save()
    }

    private func add(_ earned: Int, reason: String, at date: Date, celebrating: Bool = true) {
        guard earned > 0 else { return }
        points += earned
        events.append(Event(date: date, points: earned, reason: reason))
        if events.count > 500 { events.removeFirst(events.count - 500) }
        if celebrating { celebrate(Celebration(kind: .points(earned))) }
        save()
    }

    /// Points earned since a date.
    func points(since date: Date) -> Int {
        events.filter { $0.date >= date }.reduce(0) { $0 + $1.points }
    }

    // MARK: - Celebrating

    private func celebrate(_ celebration: Celebration) {
        // A big moment replaces the points it came with; several big ones take turns.
        if self.celebration == nil || (self.celebration?.isBig == false && celebration.isBig) {
            self.celebration = celebration
        } else if celebration.isBig {
            celebrationQueue.append(celebration)
        }
    }

    /// The celebration on screen is done; the next one waiting, if any, takes its place.
    func finishCelebration() {
        celebration = celebrationQueue.isEmpty ? nil : celebrationQueue.removeFirst()
    }

    // MARK: - Challenges

    /// A challenge set for the coming week, from today.
    func start(_ kind: Challenge.Kind, target: Int, now: Date = .now) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        challenges.append(Challenge(kind: kind, target: target, start: start, end: end))
        save()
    }

    func remove(_ challenge: Challenge) {
        challenges.removeAll { $0.id == challenge.id }
        save()
    }

    /// The challenges still running, and those finished in the last week.
    func activeChallenges(now: Date = .now) -> [Challenge] {
        challenges.filter { $0.end > now || ($0.completedAt.map { now.timeIntervalSince($0) < 7 * 86_400 } ?? false) }
    }

    /// How far a challenge has come, from what the student did in its week.
    func progress(of challenge: Challenge, revision: RevisionStore, plan: PlanStore) -> Int {
        let inWeek = { (date: Date) in date >= challenge.start && date < challenge.end }
        switch challenge.kind {
        case .wirdDays: return revision.completedDays.filter(inWeek).count
        case .pagesRevised: return revision.history.filter { inWeek($0.date) }.count
        case .linesMemorized: return Int(plan.portions.filter { inWeek($0.date) }.reduce(0) { $0 + $1.actualLines }.rounded(.down))
        case .dailyRevision: return revision.revisedDays.filter(inWeek).count
        }
    }

    /// Marks challenges just met, and celebrates them.
    func checkChallenges(revision: RevisionStore, plan: PlanStore, now: Date = .now) {
        var changed = false
        for index in challenges.indices where challenges[index].completedAt == nil && challenges[index].end > now {
            let challenge = challenges[index]
            if progress(of: challenge, revision: revision, plan: plan) >= challenge.target {
                challenges[index].completedAt = now
                celebrate(Celebration(kind: .challenge(challenge.kind, challenge.target)))
                points += policy.challengeCompleted
                events.append(Event(date: now, points: policy.challengeCompleted, reason: "challenge"))
                changed = true
            }
        }
        if changed { save() }
    }

    // MARK: - Backup

    struct Snapshot: Codable, Equatable {
        var points = 0
        var events: [Event] = []
        var achievements: [Achievement: Date] = [:]
        var challenges: [Challenge] = []
        var updatedAt = Date.distantPast

        static let empty = Snapshot()

        /// Both copies as one: the larger total (points only grow), every achievement at its earliest, and the
        /// challenges of both.
        static func merge(_ local: Snapshot, _ remote: Snapshot) -> Snapshot {
            var events = Set<Event>()
            var ids = Set<UUID>()
            return Snapshot(
                points: max(local.points, remote.points),
                events: (local.events + remote.events).sorted { $0.date < $1.date }.filter { events.insert($0).inserted }.suffix(500).map { $0 },
                achievements: local.achievements.merging(remote.achievements) { min($0, $1) },
                challenges: (remote.updatedAt >= local.updatedAt ? remote.challenges + local.challenges : local.challenges + remote.challenges)
                    .filter { ids.insert($0.id).inserted }.sorted { $0.start < $1.start },
                updatedAt: max(local.updatedAt, remote.updatedAt))
        }
    }

    var snapshot: Snapshot {
        Snapshot(points: points, events: events, achievements: achievements, challenges: challenges, updatedAt: updatedAt)
    }

    func apply(_ snapshot: Snapshot) {
        guard snapshot != self.snapshot else { return }
        points = snapshot.points
        events = snapshot.events
        achievements = snapshot.achievements
        challenges = snapshot.challenges
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

/// The reward chime: two soft bell-like notes, made here rather than bundled, played only when the ringer is on.
@MainActor
enum Chime {
    private static var player: AVAudioPlayer?

    static func play(big: Bool) {
        guard UserDefaults.standard.object(forKey: "sounds.on") as? Bool ?? true else { return }
        // Ambient: silent with the ring/silent switch, and mixed with whatever else is playing.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let notes: [(frequency: Double, start: Double)] = big
            ? [(659.25, 0), (783.99, 0.12), (1046.5, 0.24)] // E5, G5, C6
            : [(783.99, 0), (1046.5, 0.1)]                 // G5, C6
        player = try? AVAudioPlayer(data: wave(notes: notes, length: big ? 1.1 : 0.7))
        player?.volume = 0.35
        player?.play()
    }

    /// A 16-bit mono WAV of soft decaying sine notes.
    private static func wave(notes: [(frequency: Double, start: Double)], length: Double) -> Data {
        let rate = 44_100.0
        let count = Int(length * rate)
        var samples = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / rate
            var value = 0.0
            for note in notes where time >= note.start {
                let t = time - note.start
                let envelope = min(t / 0.008, 1) * exp(-t * 5)
                value += envelope * (sin(2 * .pi * note.frequency * t) + 0.3 * sin(4 * .pi * note.frequency * t))
            }
            samples[index] = Int16(max(min(value * 0.3, 1), -1) * Double(Int16.max))
        }
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        let bytes = UInt32(count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes).littleEndian)
        data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16).littleEndian)
        append(UInt16(1).littleEndian); append(UInt16(1).littleEndian)
        append(UInt32(rate).littleEndian); append(UInt32(rate * 2).littleEndian)
        append(UInt16(2).littleEndian); append(UInt16(16).littleEndian)
        data.append(contentsOf: Array("data".utf8)); append(bytes.littleEndian)
        samples.forEach { append($0.littleEndian) }
        return data
    }
}
