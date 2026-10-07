import Foundation

/// How the student's progress is laid out in the account, and how a device's copy and the account's are merged.
/// Plain values only, with no Firebase, so every rule can be tested.
///
/// The account holds:
/// - `users/{uid}/memory/block-NN`: the memorized ayat in blocks of 256, each ayah as
///   `[since, stability, lastReviewed or -1, lapses, verified, learnedAt or -1, lastLapseAt or -1]`, dates in
///   seconds since 1970 (rows written before the plan have only the first five);
/// - `users/{uid}/revision/state`: the revision store's `Snapshot`, as JSON;
/// - `users/{uid}/journey/state`: the plan, rewards and assessments (`Journey.Snapshot`), as JSON.
enum CloudBackup {
    static let blockSize = 256
    static let blockCount = (MushafStore.ayahCount + blockSize - 1) / blockSize

    static func blockID(_ index: Int) -> String {
        "block-" + (index < 10 ? "0" : "") + String(index)
    }

    /// One block: each memorized ayah, by its number, as a row of numbers.
    typealias Block = [String: [Double]]

    // MARK: - Ayat

    static func encode(_ memory: AyahMemory) -> [Double] {
        [memory.since.timeIntervalSince1970, memory.stability, memory.lastReviewed?.timeIntervalSince1970 ?? -1,
         Double(memory.lapses), memory.verified ? 1 : 0, memory.learnedAt?.timeIntervalSince1970 ?? -1,
         memory.lastLapseAt?.timeIntervalSince1970 ?? -1]
    }

    static func decode(_ row: [Double]) -> AyahMemory? {
        guard row.count >= 5, row[1] > 0 else { return nil }
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

    /// Every block, by its index, empty where nothing is memorized.
    static func blocks(_ ayahs: [Int: AyahMemory]) -> [Int: Block] {
        var blocks = Dictionary(uniqueKeysWithValues: (0..<blockCount).map { ($0, Block()) })
        for (ayah, memory) in ayahs where (0..<MushafStore.ayahCount).contains(ayah) {
            blocks[ayah / blockSize, default: [:]][String(ayah)] = encode(memory)
        }
        return blocks
    }

    /// The ayat held in some blocks; rows that can't be read are skipped.
    static func ayahs(in blocks: some Sequence<Block>) -> [Int: AyahMemory] {
        var ayahs: [Int: AyahMemory] = [:]
        for block in blocks {
            for (key, row) in block {
                guard let ayah = Int(key), (0..<MushafStore.ayahCount).contains(ayah), let memory = decode(row) else { continue }
                ayahs[ayah] = memory
            }
        }
        return ayahs
    }

    // MARK: - Merging

    /// The ayat memorized on either side. Where both have an ayah, the one revised more recently wins, and a
    /// teacher's confirmation on either side is kept.
    static func merge(_ local: [Int: AyahMemory], _ remote: [Int: AyahMemory]) -> [Int: AyahMemory] {
        local.merging(remote) { mine, theirs in
            var newer = (theirs.lastReviewed ?? theirs.since) > (mine.lastReviewed ?? mine.since) ? theirs : mine
            newer.verified = mine.verified || theirs.verified
            return newer
        }
    }

    /// Both revision records as one:
    /// - the rotation's place, the follow-ups and today's plan come from the side that revised most recently,
    ///   since they follow the revising (a device just cleared or newly installed has none to offer);
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
        let (newer, older) = remote.updatedAt >= local.updatedAt ? (remote, local) : (local, remote)
        merged.dailyPages = newer.dailyPages ?? older.dailyPages
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
