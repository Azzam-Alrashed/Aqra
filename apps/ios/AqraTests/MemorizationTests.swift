import Foundation
import Testing
@testable import Aqra

@MainActor
struct MemorizationStoreTests {
    @Test func marksTogglesAndCounts() {
        let memorization = MemorizationStore(fileURL: nil)
        memorization.toggle(ayah: 7)
        #expect(memorization.isMemorized(7) && memorization.count == 1)
        memorization.mark(0...6, memorized: true)
        #expect(memorization.count == 8)
        #expect(memorization.memorizedCount(in: 0...9) == 8)
        memorization.toggle(ayah: 7)
        #expect(!memorization.isMemorized(7))
        // Numbers outside the Quran's 6,236 ayat are ignored.
        memorization.mark([-1, MushafStore.ayahCount], memorized: true)
        #expect(memorization.count == 7)
        // Newly marked ayat start faint (a modest half-life, not yet revised) and unverified.
        let memory = memorization.memory(ofAyah: 0)
        #expect(memory?.stability == ReviewPolicy.standard.declaredStability && memory?.lastReviewed == nil && memory?.verified == false)
        #expect((memorization.strength(ofAyah: 0) ?? 1) < 0.2)
    }

    @Test func verifyingMarksOnlyMemorizedAyat() {
        let memorization = MemorizationStore(fileURL: nil)
        var changes = 0
        memorization.onChange = { changes += 1 }
        memorization.mark(10...12, memorized: true)
        memorization.verify([11, 12, 13])
        #expect(memorization.memory(ofAyah: 11)?.verified == true && memorization.memory(ofAyah: 12)?.verified == true)
        #expect(memorization.memory(ofAyah: 10)?.verified == false && !memorization.isMemorized(13))
        #expect(changes == 2)
        // Verifying what's already verified changes nothing.
        memorization.verify([11])
        #expect(changes == 2)
        // A stumble before the teacher takes the mark away.
        memorization.verify([11, 12], except: [12])
        #expect(memorization.memory(ofAyah: 11)?.verified == true && memorization.memory(ofAyah: 12)?.verified == false)
        #expect(changes == 3)
    }

    @Test func savesAndReloads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("memorization-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let memorization = MemorizationStore(fileURL: url)
        memorization.mark(100...120, memorized: true)
        memorization.saveNow()
        let reloaded = MemorizationStore(fileURL: url)
        #expect(reloaded.count == 21)
        #expect(reloaded.isMemorized(110) && !reloaded.isMemorized(121))
    }

    @Test func markingSessionMarksRangesAndPages() {
        let memorization = MemorizationStore(fileURL: nil)
        let session = MarkingSession(memorization: memorization)
        // A held press starts a range at an unmarked ayah, marking it; the next tap marks everything up to it.
        session.beginRange(at: 14)
        #expect(memorization.isMemorized(14) && session.rangeStart == 14)
        session.tap(10)
        #expect(memorization.memorizedCount(in: 10...14) == 5 && session.rangeStart == nil)
        // Starting on a marked ayah unmarks the range instead.
        session.beginRange(at: 12)
        session.tap(13)
        #expect(memorization.memorizedCount(in: 10...14) == 3)
        // Without a range, a tap toggles one ayah.
        session.tap(12)
        #expect(memorization.isMemorized(12))
        // A whole page: marks all of it unless it's all marked already, then unmarks it.
        session.toggle(10...14)
        #expect(memorization.memorizedCount(in: 10...14) == 5)
        session.toggle(10...14)
        #expect(memorization.memorizedCount(in: 10...14) == 0)
    }

    @Test func undoingAnUnmarkingRestoresTheRecordsExactly() {
        let memorization = MemorizationStore(fileURL: nil)
        let session = MarkingSession(memorization: memorization)
        memorization.mark(20...29, memorized: true)
        memorization.recordRevision(ayahs: 20...29, stumbled: [22], at: .now, policy: .standard)
        memorization.verify([23, 24])
        let before = memorization.ayahs

        // Marking offers nothing to undo.
        session.tap(30)
        #expect(session.unmarked.isEmpty)
        session.tap(30)

        // A tap: the ayah comes back with its revisions, stumble and teacher's mark.
        session.tap(22)
        #expect(session.unmarked.count == 1 && !memorization.isMemorized(22))
        session.undo()
        #expect(memorization.ayahs == before && session.unmarked.isEmpty)

        // A range that unmarks counts its first ayah, unmarked when the range began.
        session.beginRange(at: 21)
        #expect(session.unmarked.count == 1)
        session.tap(24)
        #expect(session.unmarked.count == 4 && memorization.memorizedCount(in: 20...29) == 6)
        session.undo()
        #expect(memorization.ayahs == before)

        // A whole page.
        session.toggle(20...29)
        #expect(session.unmarked.count == 10 && memorization.count == 0)
        session.undo()
        #expect(memorization.ayahs == before)

        // The undo expires, but an earlier unmarking's timer doesn't take a later one's.
        session.tap(25)
        let first = session.unmarkedVersion
        session.tap(26)
        session.expireUndo(version: first)
        #expect(session.unmarked.keys.sorted() == [26])
        session.expireUndo(version: session.unmarkedVersion)
        #expect(session.unmarked.isEmpty)
    }
}
