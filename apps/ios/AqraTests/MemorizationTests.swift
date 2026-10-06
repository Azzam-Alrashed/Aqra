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
        // Newly marked ayat start faint and unverified.
        #expect(memorization.memory(ofAyah: 0)?.strength == 0 && memorization.memory(ofAyah: 0)?.verified == false)
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

    @Test func markingSessionPaintsAndTogglesRanges() {
        let memorization = MemorizationStore(fileURL: nil)
        let session = MarkingSession(memorization: memorization)
        // Dragging from an unmarked ayah marks everything from where it started to where it is.
        session.paint(10)
        session.paint(14)
        session.endPaint()
        #expect(memorization.memorizedCount(in: 10...14) == 5)
        // Dragging from a marked ayah unmarks.
        session.paint(12)
        session.paint(13)
        session.endPaint()
        #expect(memorization.memorizedCount(in: 10...14) == 3)
        // A whole page: marks all of it unless it's all marked already, then unmarks it.
        session.toggle(10...14)
        #expect(memorization.memorizedCount(in: 10...14) == 5)
        session.toggle(10...14)
        #expect(memorization.memorizedCount(in: 10...14) == 0)
    }
}
