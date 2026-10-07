import Foundation

/// The far lane learns: pages that keep slipping — stumbled on in more than one revision lately, or faint while
/// the rest is strong — are suggested for extra follow-up, and the student approves or dismisses each suggestion
/// (docs/REVISION.md, open question 3).
@MainActor
enum RotationAdvisor {
    /// A page stumbled on in at least this many revisions in the window is slipping.
    static let stumbledRevisions = 2
    static let window: TimeInterval = 30 * 86_400
    /// A page this faint is slipping when the memorization as a whole is at least `strongAverage`.
    static let faint = 0.35
    static let strongAverage = 0.5
    /// A dismissed suggestion comes back no sooner than this.
    static let snooze: TimeInterval = 14 * 86_400
    private static let dismissedKey = "rotation.dismissed"

    static func suggestions(store: MushafStore, memorization: MemorizationStore, revision: RevisionStore,
                            now: Date = .now, limit: Int = 3) -> [Int] {
        let pages = RevisionStore.memorizedPages(in: store, memorization: memorization)
        guard pages.count >= 5 else { return [] }
        let dismissed = dismissedUntil()
        let planned = Set(revision.plan?.items.map(\.page) ?? [])
        var stumbled: [Int: Int] = [:]
        for record in revision.history where now.timeIntervalSince(record.date) < window && !record.stumbles.isEmpty {
            stumbled[record.page, default: 0] += 1
        }
        let strengths = Dictionary(uniqueKeysWithValues: pages.map { page in
            let ayahs = store.page(page).ayahs.compactMap { memorization.strength(ofAyah: $0, at: now) }
            return (page, ayahs.isEmpty ? 1 : ayahs.reduce(0, +) / Double(ayahs.count))
        })
        let overall = strengths.values.reduce(0, +) / Double(max(strengths.count, 1))
        return pages
            .filter { page in
                revision.followUps[page] == nil && !planned.contains(page) && (dismissed[page] ?? .distantPast) <= now
                    && ((stumbled[page] ?? 0) >= stumbledRevisions || ((strengths[page] ?? 1) < faint && overall >= strongAverage))
            }
            .sorted { ((stumbled[$0] ?? 0), -(strengths[$0] ?? 1)) > ((stumbled[$1] ?? 0), -(strengths[$1] ?? 1)) }
            .prefix(limit)
            .sorted()
    }

    /// The student took the suggestion: the pages come back for follow-up from tomorrow.
    static func accept(_ pages: [Int], revision: RevisionStore, now: Date = .now) {
        revision.followUp(pages: pages, now: now)
    }

    /// The student dismissed it: the pages aren't suggested again for a while.
    static func dismiss(_ pages: [Int], now: Date = .now) {
        var dismissed = UserDefaults.standard.dictionary(forKey: dismissedKey) as? [String: Double] ?? [:]
        for page in pages { dismissed[String(page)] = now.addingTimeInterval(snooze).timeIntervalSince1970 }
        dismissed = dismissed.filter { $0.value > now.timeIntervalSince1970 }
        UserDefaults.standard.set(dismissed, forKey: dismissedKey)
    }

    private static func dismissedUntil() -> [Int: Date] {
        let stored = UserDefaults.standard.dictionary(forKey: dismissedKey) as? [String: Double] ?? [:]
        return Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in Int(key).map { ($0, Date(timeIntervalSince1970: value)) } })
    }
}
