import Foundation

/// The rest of the student's journey beside what's memorized and the revision record: the personal plan, the
/// rewards and the stages' assessments. Backed up together as one document, `users/{uid}/journey/state`.
@MainActor
final class Journey {
    let plan: PlanStore
    let rewards: RewardStore
    let assessments: AssessmentStore
    let reading: ReadingStore

    init(plan: PlanStore, rewards: RewardStore, assessments: AssessmentStore, reading: ReadingStore = ReadingStore(fileURL: nil)) {
        self.plan = plan
        self.rewards = rewards
        self.assessments = assessments
        self.reading = reading
    }

    /// Called after any of them changes, so the backup can follow.
    var onChange: (() -> Void)? {
        didSet {
            plan.onChange = onChange
            rewards.onChange = onChange
            assessments.onChange = onChange
            reading.onChange = onChange
        }
    }

    struct Snapshot: Codable, Equatable {
        var plan = PlanStore.Snapshot.empty
        var rewards = RewardStore.Snapshot.empty
        var assessments = AssessmentStore.Snapshot.empty
        /// Missing from backups made before the ribbon existed.
        var reading: ReadingStore.Snapshot?

        static let empty = Snapshot()

        init(plan: PlanStore.Snapshot = .empty, rewards: RewardStore.Snapshot = .empty, assessments: AssessmentStore.Snapshot = .empty,
             reading: ReadingStore.Snapshot? = nil) {
            self.plan = plan
            self.rewards = rewards
            self.assessments = assessments
            self.reading = reading
        }

        // The account's copy may come from the Android app or a newer version: a part missing or unreadable
        // never loses the others.
        private enum CodingKeys: String, CodingKey { case plan, rewards, assessments, reading }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            plan = container.decodeOr(PlanStore.Snapshot.self, forKey: .plan, .empty)
            rewards = container.decodeOr(RewardStore.Snapshot.self, forKey: .rewards, .empty)
            assessments = container.decodeOr(AssessmentStore.Snapshot.self, forKey: .assessments, .empty)
            reading = container.decodeOrNil(ReadingStore.Snapshot.self, forKey: .reading)
        }

        static func merge(_ local: Snapshot, _ remote: Snapshot) -> Snapshot {
            let reading = ReadingStore.Snapshot.merge(local.reading ?? .empty, remote.reading ?? .empty)
            return Snapshot(plan: .merge(local.plan, remote.plan), rewards: .merge(local.rewards, remote.rewards),
                            assessments: .merge(local.assessments, remote.assessments),
                            reading: reading == .empty ? nil : reading)
        }
    }

    var snapshot: Snapshot {
        let reading = reading.snapshot
        return Snapshot(plan: plan.snapshot, rewards: rewards.snapshot, assessments: assessments.snapshot,
                        reading: reading == .empty ? nil : reading)
    }

    func apply(_ snapshot: Snapshot) {
        plan.apply(snapshot.plan)
        rewards.apply(snapshot.rewards)
        assessments.apply(snapshot.assessments)
        reading.apply(snapshot.reading ?? .empty)
    }
}

/// Where the reader stopped: a ribbon (فاصل) they place in the Mushaf, which browsing, revising and marking never
/// move. Kept on the device and backed up with the rest of the journey.
@MainActor @Observable
final class ReadingStore {
    struct Bookmark: Codable, Hashable {
        var page: Int
        var placedAt: Date
    }

    private(set) var bookmark: Bookmark?
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let fileURL: URL?

    static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("reading.json")
    }

    init(fileURL: URL? = ReadingStore.defaultURL) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        bookmark = snapshot.bookmark
        updatedAt = snapshot.updatedAt
    }

    /// Places the ribbon on a page, or moves it there.
    func place(on page: Int, at date: Date = .now) {
        guard (1...MushafStore.pageCount).contains(page), bookmark?.page != page else { return }
        bookmark = Bookmark(page: page, placedAt: date)
        save()
    }

    func remove() {
        guard bookmark != nil else { return }
        bookmark = nil
        save()
    }

    struct Snapshot: Codable, Equatable {
        var bookmark: Bookmark?
        /// When the ribbon was last placed or taken away, so a removal on one device isn't undone by another's copy.
        var updatedAt = Date.distantPast

        static let empty = Snapshot()

        /// The more recent choice wins: a ribbon placed later, or a later removal.
        static func merge(_ local: Snapshot, _ remote: Snapshot) -> Snapshot {
            remote.updatedAt > local.updatedAt ? remote : local
        }
    }

    @ObservationIgnored private var updatedAt = Date.distantPast

    var snapshot: Snapshot { Snapshot(bookmark: bookmark, updatedAt: max(updatedAt, bookmark?.placedAt ?? .distantPast)) }

    func apply(_ snapshot: Snapshot) {
        guard snapshot != self.snapshot else { return }
        bookmark = snapshot.bookmark.flatMap { (1...MushafStore.pageCount).contains($0.page) ? $0 : nil }
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
