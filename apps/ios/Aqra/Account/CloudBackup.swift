import Foundation

/// How the student's progress is laid out in the account, and how a device's copy and the account's are merged.
/// Plain values only, with no Firebase, so every rule can be tested.
///
/// The account holds:
/// - `users/{uid}/memory/block-NN`: the memorized ayat in blocks of 256, each ayah as
///   `[since, stability, lastReviewed or -1, lapses, verified, learnedAt or -1, lastLapseAt or -1]`, dates in
///   seconds since 1970 (rows written before the plan have only the first five). An ayah unmarked on a device
///   leaves a tombstone in its place, `[removedAt, 0, -1, 0, 0, -1, -1]`: no app reads a row with a stability
///   of 0 as memorized, and the merge won't bring the ayah back from a copy that still holds it;
/// - `users/{uid}/revision/state`: the revision store's `Snapshot`, as JSON, beside `revisedDays` and
///   `completedDays` as arrays that are only ever added to, so a streak day one device wrote survives another's
///   write of the JSON;
/// - `users/{uid}/journey/state`: the plan, rewards and assessments (`Journey.Snapshot`), as JSON.
///
/// A device writes only the rows that changed since it last read the account, merged into each block, so two
/// devices writing different ayat of one block don't overwrite each other (see `CloudSync`).
enum CloudBackup {
    static let blockSize = 256
    static let blockCount = (MushafStore.ayahCount + blockSize - 1) / blockSize

    static func blockID(_ index: Int) -> String {
        "block-" + (index < 10 ? "0" : "") + String(index)
    }

    /// One block: each memorized ayah, by its number, as a row of numbers.
    typealias Block = [String: [Double]]

    /// What a device knows of the memorization: the ayat memorized, and those unmarked and when, kept so a merge
    /// doesn't bring an unmarked ayah back from a copy that still holds it.
    struct Memory: Equatable {
        var ayahs: [Int: AyahMemory] = [:]
        var removed: [Int: Date] = [:]

        static let empty = Memory()
    }

    // MARK: - Ayat

    /// Seconds since 1970 beyond which a number can't be a date this app wrote: it's a corrupt row.
    private static let farthestDate = 1e12

    static func encode(_ memory: AyahMemory) -> [Double] {
        [memory.since.timeIntervalSince1970, memory.stability, memory.lastReviewed?.timeIntervalSince1970 ?? -1,
         Double(memory.lapses), memory.verified ? 1 : 0, memory.learnedAt?.timeIntervalSince1970 ?? -1,
         memory.lastLapseAt?.timeIntervalSince1970 ?? -1]
    }

    /// The row left where an ayah was unmarked.
    static func tombstone(removedAt: Date) -> [Double] {
        [removedAt.timeIntervalSince1970, 0, -1, 0, 0, -1, -1]
    }

    /// A memorized ayah from its row; nil for a tombstone, a row too short to read, or one with numbers no app
    /// could have written (not finite, or far outside any date).
    static func decode(_ row: [Double]) -> AyahMemory? {
        guard row.count >= 5, row.allSatisfy(\.isFinite), row[1] > 0, row[1] <= 1e6,
              abs(row[0]) < farthestDate, abs(row[2]) < farthestDate, abs(row[3]) < 1e9 else { return nil }
        if row.count >= 7 { guard abs(row[5]) < farthestDate, abs(row[6]) < farthestDate else { return nil } }
        var memory = AyahMemory(since: Date(timeIntervalSince1970: row[0]), stability: row[1])
        memory.lastReviewed = row[2] < 0 ? nil : Date(timeIntervalSince1970: row[2])
        memory.lapses = max(Int(row[3]), 0)
        memory.verified = row[4] != 0
        if row.count >= 7 {
            memory.learnedAt = row[5] < 0 ? nil : Date(timeIntervalSince1970: row[5])
            memory.lastLapseAt = row[6] < 0 ? nil : Date(timeIntervalSince1970: row[6])
        }
        return memory
    }

    /// When an ayah was unmarked, from its tombstone; nil for any other row.
    static func removedAt(_ row: [Double]) -> Date? {
        guard row.count >= 2, row[0].isFinite, row[1] == 0, abs(row[0]) < farthestDate else { return nil }
        return Date(timeIntervalSince1970: row[0])
    }

    /// Every block, by its index, empty where nothing is memorized or unmarked.
    static func blocks(_ memory: Memory) -> [Int: Block] {
        var blocks = Dictionary(uniqueKeysWithValues: (0..<blockCount).map { ($0, Block()) })
        for (ayah, removedAt) in memory.removed where (0..<MushafStore.ayahCount).contains(ayah) {
            blocks[ayah / blockSize, default: [:]][String(ayah)] = tombstone(removedAt: removedAt)
        }
        for (ayah, record) in memory.ayahs where (0..<MushafStore.ayahCount).contains(ayah) {
            blocks[ayah / blockSize, default: [:]][String(ayah)] = encode(record)
        }
        return blocks
    }

    static func blocks(_ ayahs: [Int: AyahMemory]) -> [Int: Block] {
        blocks(Memory(ayahs: ayahs))
    }

    /// The ayat held in some blocks, and the tombstones; rows that can't be read are skipped.
    static func memory(in blocks: some Sequence<Block>) -> Memory {
        var memory = Memory()
        for block in blocks {
            for (key, row) in block {
                guard let ayah = Int(key), (0..<MushafStore.ayahCount).contains(ayah) else { continue }
                if let record = decode(row) {
                    memory.ayahs[ayah] = record
                } else if let removedAt = removedAt(row) {
                    memory.removed[ayah] = removedAt
                }
            }
        }
        return memory
    }

    static func ayahs(in blocks: some Sequence<Block>) -> [Int: AyahMemory] {
        memory(in: blocks).ayahs
    }

    // MARK: - Merging

    /// Two records of one ayah as one. The record revised later wins (one never revised ranks lowest; a tie goes
    /// to the one known longer, then the firmer); the memorization is kept from its earliest date on either
    /// side, as is when it was learned; every stumble counts; and a teacher's confirmation holds unless the
    /// other copy stumbled on the ayah after it.
    static func merge(_ a: AyahMemory, _ b: AyahMemory) -> AyahMemory {
        let (aReviewed, bReviewed) = (a.lastReviewed ?? .distantPast, b.lastReviewed ?? .distantPast)
        let aWins = aReviewed != bReviewed ? aReviewed > bReviewed
            : a.since != b.since ? a.since < b.since
            : a.stability >= b.stability
        let (winner, loser) = aWins ? (a, b) : (b, a)
        var merged = winner
        merged.since = min(a.since, b.since)
        merged.learnedAt = [a.learnedAt, b.learnedAt].compactMap { $0 }.min()
        merged.lapses = max(a.lapses, b.lapses)
        merged.lastLapseAt = [a.lastLapseAt, b.lastLapseAt].compactMap { $0 }.max()
        func stillVerified(_ side: AyahMemory, against other: AyahMemory) -> Bool {
            guard side.verified else { return false }
            guard let stumble = other.lastLapseAt else { return true }
            return stumble <= (side.lastReviewed ?? side.since)
        }
        merged.verified = stillVerified(winner, against: loser) || stillVerified(loser, against: winner)
        return merged
    }

    /// The ayat memorized on either side, each merged by `merge(_:_:)`; an ayah unmarked on one side after the
    /// other last touched it stays unmarked, and one marked again after it was unmarked comes back.
    static func merge(_ local: Memory, _ remote: Memory) -> Memory {
        var merged = Memory()
        let ayahs = Set(local.ayahs.keys).union(remote.ayahs.keys).union(local.removed.keys).union(remote.removed.keys)
        for ayah in ayahs {
            let sides = [local.ayahs[ayah], remote.ayahs[ayah]].compactMap { $0 }
            let record: AyahMemory? = sides.count == 2 ? merge(sides[0], sides[1]) : sides.first
            let removedAt = [local.removed[ayah], remote.removed[ayah]].compactMap { $0 }.max()
            if let record, let removedAt, removedAt > sides.map(lastTouch).max()! {
                merged.removed[ayah] = removedAt
            } else if let record {
                merged.ayahs[ayah] = record
            } else if let removedAt {
                merged.removed[ayah] = removedAt
            }
        }
        return merged
    }

    static func merge(_ local: [Int: AyahMemory], _ remote: [Int: AyahMemory]) -> [Int: AyahMemory] {
        merge(Memory(ayahs: local), Memory(ayahs: remote)).ayahs
    }

    /// The last moment anything happened to a record: it was marked, learned, revised or stumbled on.
    private static func lastTouch(_ memory: AyahMemory) -> Date {
        [memory.since, memory.lastReviewed, memory.learnedAt, memory.lastLapseAt].compactMap { $0 }.max()!
    }

    /// Both revision records as one:
    /// - the rotation's place and today's plan come from the side that revised most recently, since they follow
    ///   the revising (a device just cleared or newly installed has none to offer); a page of that plan done on
    ///   the other side counts as done;
    /// - the follow-ups are those of both sides, page by page, each at its later due date;
    /// - the daily amount is the most recent choice made on either side;
    /// - the days revised and the history are those of both.
    /// Ties go to the account's copy.
    static func merge(_ local: RevisionStore.Snapshot, _ remote: RevisionStore.Snapshot) -> RevisionStore.Snapshot {
        func lastRevision(_ snapshot: RevisionStore.Snapshot) -> Date {
            max(snapshot.history.map(\.date).max() ?? .distantPast, snapshot.revisedDays.max() ?? .distantPast)
        }
        let localRevised = lastRevision(local), remoteRevised = lastRevision(remote)
        let revisedLast = remoteRevised > localRevised || (remoteRevised == localRevised && remote.updatedAt >= local.updatedAt)
        var merged = revisedLast ? remote : local
        let other = revisedLast ? local : remote
        let (newer, older) = remote.updatedAt >= local.updatedAt ? (remote, local) : (local, remote)
        merged.dailyPages = newer.dailyPages ?? older.dailyPages
        merged.followUps = local.followUps.merging(remote.followUps) { mine, theirs in mine.due >= theirs.due ? mine : theirs }
        if var plan = merged.plan, let otherPlan = other.plan, plan.day == otherPlan.day {
            let doneElsewhere = Set(otherPlan.items.filter(\.done).map(\.page))
            for index in plan.items.indices where doneElsewhere.contains(plan.items[index].page) {
                plan.items[index].done = true
            }
            merged.plan = plan
        }
        merged.revisedDays = Set(local.revisedDays).union(remote.revisedDays).sorted()
        let completed = Set(local.completedDays ?? []).union(remote.completedDays ?? [])
        merged.completedDays = completed.isEmpty ? nil : completed.sorted()
        var seen = Set<RevisionRecord>()
        merged.history = (local.history + remote.history)
            .sorted { $0.date < $1.date }
            .filter { seen.insert($0).inserted }
            .suffix(1_000)
            .map { $0 }
        merged.updatedAt = max(local.updatedAt, remote.updatedAt)
        return merged
    }

    // MARK: - The revision record

    static func encode(_ snapshot: RevisionStore.Snapshot) throws -> String {
        String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    }

    static func decodeRevision(_ json: String) -> RevisionStore.Snapshot? {
        try? JSONDecoder().decode(RevisionStore.Snapshot.self, from: Data(json.utf8))
    }

    // MARK: - The rest of the journey

    @MainActor
    static func encode(_ snapshot: Journey.Snapshot) throws -> String {
        String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
    }

    @MainActor
    static func decodeJourney(_ json: String) -> Journey.Snapshot? {
        try? JSONDecoder().decode(Journey.Snapshot.self, from: Data(json.utf8))
    }
}

// MARK: - Reading what another app wrote

/// The account's records are written by this app, by the Android app, and by versions of either yet to come.
/// Reading them never fails on a key that's missing or unknown, and an element that can't be read is skipped
/// rather than losing the whole record.
extension KeyedDecodingContainer {
    /// The elements of an array that can be read; the rest are skipped. An absent key is an empty array.
    func decodeLossy<T: Decodable>(_ type: [T].Type, forKey key: Key) -> [T] {
        guard contains(key), var container = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var elements: [T] = []
        while !container.isAtEnd {
            if (try? container.decodeNil()) == true { continue }
            if let element = try? container.decode(T.self) {
                elements.append(element)
            } else if (try? container.decode(SkippedElement.self)) == nil {
                break
            }
        }
        return elements
    }

    /// A value, or its default when the key is missing or holds something else.
    func decodeOr<T: Decodable>(_ type: T.Type, forKey key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }

    /// A value that may be absent; something unreadable counts as absent.
    func decodeOrNil<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }
}

/// Reads any one JSON value, so an element that can't be understood is passed over.
private struct SkippedElement: Decodable {
    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), !container.decodeNil() {
            if (try? container.decode(String.self)) != nil { return }
            if (try? container.decode(Double.self)) != nil { return }
            if (try? container.decode(Bool.self)) != nil { return }
            if (try? container.decode([SkippedElement].self)) != nil { return }
            if (try? container.decode([String: SkippedElement].self)) != nil { return }
        }
    }
}
