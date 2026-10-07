import Foundation
import Testing
@testable import Aqra

/// The account backup's format and merge rules, without the network.
@MainActor
struct CloudSyncTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400) }

    private func memory(since: Int, reviewed: Int? = nil, stability: Double = 14, verified: Bool = false) -> AyahMemory {
        var memory = AyahMemory(since: day(since), stability: stability)
        memory.lastReviewed = reviewed.map(day)
        memory.lapses = 2
        memory.verified = verified
        return memory
    }

    @Test func ayatSurviveTheTripThroughBlocks() {
        let ayahs = [0: memory(since: 0), 255: memory(since: 1, reviewed: 3, verified: true),
                     256: memory(since: 2, stability: 33.5), 6235: memory(since: 4, reviewed: 9)]
        let blocks = CloudBackup.blocks(ayahs)
        #expect(blocks.count == CloudBackup.blockCount)
        #expect(blocks[0]?.count == 2 && blocks[1]?.count == 1 && blocks[24]?.count == 1 && blocks[5]?.isEmpty == true)
        #expect(CloudBackup.ayahs(in: blocks.values) == ayahs)
        // Rows that can't be read are skipped rather than failing the restore.
        #expect(CloudBackup.ayahs(in: [["7": [1, 2]], ["x": [1, 14, -1, 0, 0]], ["9000": [1, 14, -1, 0, 0]]]).isEmpty)
    }

    @Test func mergingKeepsEverythingMemorizedAndTheLatestRevision() {
        let local = [1: memory(since: 0, reviewed: 5, stability: 20), 2: memory(since: 0), 3: memory(since: 0, reviewed: 2, verified: true)]
        let remote = [1: memory(since: 0, reviewed: 8, stability: 40), 3: memory(since: 0, reviewed: 6), 4: memory(since: 1)]
        let merged = CloudBackup.merge(local, remote)
        #expect(Set(merged.keys) == [1, 2, 3, 4])
        #expect(merged[1]?.stability == 40)                                  // revised later on the account
        #expect(merged[3]?.lastReviewed == day(6) && merged[3]?.verified == true) // the teacher's mark is kept
        #expect(CloudBackup.merge(remote, local) == merged)
    }

    @Test func mergingTheRevisionRecordKeepsTheStreakAndHistoryOfBoth() {
        let a = RevisionRecord(date: day(1), page: 3, source: .app, stumbles: [])
        let b = RevisionRecord(date: day(2), page: 4, source: .outside, stumbles: [])
        let c = RevisionRecord(date: day(3), page: 5, source: .app, stumbles: [9])
        var local = RevisionStore.Snapshot(dailyPages: 4, rotationCursor: 10, history: [a, b], revisedDays: [day(1), day(2)], updatedAt: day(2))
        let remote = RevisionStore.Snapshot(dailyPages: 6, rotationCursor: 20, history: [b, c], revisedDays: [day(2), day(3)], updatedAt: day(3))
        var merged = CloudBackup.merge(local, remote)
        #expect(merged.dailyPages == 6 && merged.rotationCursor == 20)     // the account changed and revised more recently
        #expect(merged.revisedDays == [day(1), day(2), day(3)])
        #expect(merged.history == [a, b, c])
        // A daily amount chosen later on the device wins; the rotation still follows the latest revising.
        local.updatedAt = day(4)
        merged = CloudBackup.merge(local, remote)
        #expect(merged.dailyPages == 4 && merged.rotationCursor == 20 && merged.updatedAt == day(4))

        // A device just cleared (signed out, then in again) is newer but has nothing to offer: the account's
        // amount, place and history come back.
        var cleared = RevisionStore.Snapshot.empty
        cleared.updatedAt = day(9)
        merged = CloudBackup.merge(cleared, remote)
        #expect(merged.dailyPages == 6 && merged.rotationCursor == 20 && merged.history == [b, c])

        // A new install that hasn't changed anything yet takes the account's copy, even when neither is dated.
        var undated = remote
        undated.updatedAt = .distantPast
        merged = CloudBackup.merge(.empty, undated)
        #expect(merged.dailyPages == 6 && merged.rotationCursor == 20)
    }

    @Test func theRevisionRecordSurvivesItsJSON() throws {
        let revision = RevisionStore(fileURL: nil)
        revision.setDailyPages(5)
        revision.refreshPlan(memorizedPages: [1, 2, 3])
        let json = try CloudBackup.encode(revision.snapshot)
        #expect(CloudBackup.decodeRevision(json) == revision.snapshot)
    }

    @Test func restoringReplacesTheStoresAndReportsTheChange() {
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: nil)
        var changes = 0
        memorization.onChange = { changes += 1 }
        revision.onChange = { changes += 1 }

        memorization.replaceAll([7: memory(since: 0), 8: memory(since: 0)])
        let snapshot = RevisionStore.Snapshot(dailyPages: 3, rotationCursor: 50, revisedDays: [day(0)], updatedAt: day(0))
        revision.apply(snapshot)
        #expect(memorization.count == 2 && revision.dailyPages == 3 && revision.rotationCursor == 50)
        #expect(changes == 2)

        // Clearing the device on signing out.
        memorization.replaceAll([:])
        revision.apply(.empty)
        #expect(memorization.count == 0 && revision.dailyPages == nil && revision.revisedDays.isEmpty)
    }
}
