import Foundation
import Testing
@testable import Aqra

/// The revision engine, with fixed dates and a fixed calendar so every rule can be checked exactly.
@MainActor
struct RevisionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400) }

    // MARK: - Ayah strength

    @Test func strengthFadesWithTimeAndGrowsWithRevision() {
        let policy = ReviewPolicy.standard
        let declared = AyahMemory(since: start)
        // Declared: faint, and fainter after a month without revision.
        #expect(declared.strength(at: start) < 0.2)
        #expect(declared.strength(at: day(30)) < declared.strength(at: start))

        // A clean revision after two weeks lengthens the half-life by the full growth; a stumble shortens it.
        let clean = declared.revised(stumbled: false, at: day(14), policy: policy)
        #expect(clean.stability == policy.declaredStability * policy.growth)
        #expect(clean.strength(at: day(14)) > declared.strength(at: day(14)))
        let stumbled = clean.revised(stumbled: true, at: day(20), policy: policy)
        #expect(stumbled.stability == clean.stability * policy.lapseFactor && stumbled.lapses == 1)

        // The first revision of a declared ayah counts in full, even on the day it was declared.
        #expect(declared.revised(stumbled: false, at: start, policy: policy).stability == clean.stability)

        // Revising again right away strengthens it only a little (the spacing effect).
        let rushed = clean.revised(stumbled: false, at: day(14), policy: policy)
        #expect(rushed.stability < clean.stability * 1.2)

        // Three well-spaced clean revisions make it fully established.
        var memory = declared
        for revision in [14, 50, 140] { memory = memory.revised(stumbled: false, at: day(revision), policy: policy) }
        #expect(memory.strength(at: day(140)) > 0.99)
    }

    @Test func oldMemorizationFilesStillLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("memorization-v1-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let v1 = #"{"version":1,"ayahs":[{"ayah":5,"memory":{"strength":0,"verified":false,"since":800000000}}]}"#
        try Data(v1.utf8).write(to: url)
        let memorization = MemorizationStore(fileURL: url)
        #expect(memorization.isMemorized(5))
        #expect(memorization.memory(ofAyah: 5)?.stability == ReviewPolicy.standard.declaredStability)
    }

    // MARK: - Today's plan

    @Test func planTakesFollowUpsFirstThenTheRotation() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let memorization = MemorizationStore(fileURL: nil)
        revision.setDailyPages(3)
        let pages = [10, 11, 12, 13, 14, 20]
        revision.refreshPlan(memorizedPages: pages, now: day(0))
        #expect(revision.plan?.items.map(\.page) == [10, 11, 12])
        #expect(revision.plan?.items.allSatisfy { $0.kind == .rotation } == true)

        // A stumble on page 11 brings it back tomorrow, ahead of the rotation, which continues after page 12.
        revision.record(page: 10, ayahs: [100], stumbles: [], source: .app, memorization: memorization, now: day(0))
        revision.record(page: 11, ayahs: [110], stumbles: [110], source: .app, memorization: memorization, now: day(0))
        revision.record(page: 12, ayahs: [120], stumbles: [], source: .outside, memorization: memorization, now: day(0))
        #expect(revision.plan?.isComplete == true)
        revision.refreshPlan(memorizedPages: pages, now: day(1))
        #expect(revision.plan?.items.map(\.page) == [11, 13, 14])
        #expect(revision.plan?.items.first?.kind == .followUp)

        // Clean follow-ups space out (3 days, then 7) and then leave follow-up.
        revision.record(page: 11, ayahs: [110], stumbles: [], source: .app, memorization: memorization, now: day(1))
        #expect(revision.followUps[11]?.due == calendar.startOfDay(for: day(4)))
        revision.record(page: 11, ayahs: [110], stumbles: [], source: .app, memorization: memorization, now: day(4))
        #expect(revision.followUps[11]?.due == calendar.startOfDay(for: day(11)))
        revision.record(page: 11, ayahs: [110], stumbles: [], source: .app, memorization: memorization, now: day(11))
        #expect(revision.followUps[11] == nil)
    }

    @Test func missedDaysDontPileUpAndTheRotationWraps() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let memorization = MemorizationStore(fileURL: nil)
        revision.setDailyPages(2)
        let pages = [1, 2, 3, 4, 5]
        revision.refreshPlan(memorizedPages: pages, now: day(0))
        revision.record(page: 1, ayahs: [0], stumbles: [], source: .app, memorization: memorization, now: day(0))
        revision.record(page: 2, ayahs: [7], stumbles: [], source: .app, memorization: memorization, now: day(0))

        // Three days missed: the plan is still two pages, continuing where the student stopped.
        revision.refreshPlan(memorizedPages: pages, now: day(4))
        #expect(revision.plan?.items.map(\.page) == [3, 4])

        // A page skipped today stays first tomorrow, even if a later one was revised.
        revision.record(page: 4, ayahs: [20], stumbles: [], source: .app, memorization: memorization, now: day(4))
        revision.refreshPlan(memorizedPages: pages, now: day(5))
        #expect(revision.plan?.items.map(\.page) == [3, 4])
        revision.record(page: 3, ayahs: [15], stumbles: [], source: .app, memorization: memorization, now: day(5))
        revision.record(page: 4, ayahs: [20], stumbles: [], source: .app, memorization: memorization, now: day(5))

        // The rotation wraps from the last memorized page back to the first.
        revision.refreshPlan(memorizedPages: pages, now: day(6))
        #expect(revision.plan?.items.map(\.page) == [5, 1])
    }

    @Test func planStaysFixedWithinTheDay() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        revision.setDailyPages(2)
        revision.refreshPlan(memorizedPages: [50, 51, 52], now: day(0))
        // Memorizing more during the day doesn't reshuffle today's plan; unmarking a page drops it.
        revision.refreshPlan(memorizedPages: [40, 50, 51, 52], now: day(0).addingTimeInterval(3_600))
        #expect(revision.plan?.items.map(\.page) == [50, 51])
        revision.refreshPlan(memorizedPages: [40, 51, 52], now: day(0).addingTimeInterval(7_200))
        #expect(revision.plan?.items.map(\.page) == [51])
        // Nothing memorized: an empty plan, made again as soon as something is.
        let empty = RevisionStore(fileURL: nil, calendar: calendar)
        empty.refreshPlan(memorizedPages: [], now: day(0))
        #expect(empty.plan?.items.isEmpty == true)
        empty.refreshPlan(memorizedPages: [7], now: day(0))
        #expect(empty.plan?.items.map(\.page) == [7])
    }

    @Test func revisionUpdatesTheAyatOfThePage() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let memorization = MemorizationStore(fileURL: nil)
        memorization.mark(0...6, memorized: true)
        let before = memorization.memory(ofAyah: 3)!.stability
        revision.record(page: 1, ayahs: Array(0...6), stumbles: [3], source: .app, memorization: memorization,
                        now: Date.now.addingTimeInterval(14 * 86_400))
        #expect(memorization.memory(ofAyah: 3)!.stability < before)
        #expect(memorization.memory(ofAyah: 2)!.stability > before)
        #expect(revision.history.last?.stumbles == [3])
    }

    @Test func recordSavesAndReloads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("revision-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: url, calendar: calendar)
        revision.setDailyPages(4)
        revision.refreshPlan(memorizedPages: [3, 4, 5], now: day(0))
        revision.record(page: 3, ayahs: [15], stumbles: [15], source: .app, memorization: memorization, now: day(0))
        let reloaded = RevisionStore(fileURL: url, calendar: calendar)
        #expect(reloaded.dailyPages == 4)
        #expect(reloaded.plan?.items.first { $0.page == 3 }?.done == true)
        #expect(reloaded.followUps[3] != nil)
        #expect(reloaded.history.count == 1)
    }

    // MARK: - A page's revision

    @Test func sessionRevealsInOrderAndMarksStumbles() {
        let session = RevisionSession(page: 2, ayahs: [7, 8, 9])
        #expect(session.isVeiled(7) && session.isVeiled(9))
        session.tap(nil)                   // anywhere: reveals the first
        #expect(!session.isVeiled(7) && session.isVeiled(8))
        session.tap(9)                     // a veiled ayah: reveals the next
        #expect(!session.isVeiled(8))
        session.tap(7)                     // a revealed ayah: marks a stumble, and a second tap clears it
        #expect(session.stumbles == [7])
        session.tap(7)
        #expect(session.stumbles.isEmpty)
        session.revealAll()
        #expect(session.isComplete && !session.isVeiled(9))
        #expect(!session.covers(40) && !session.isVeiled(40))
    }

    @Test func suggestedDailyAmountCoversAboutAMonth() {
        #expect(ReviewPolicy.suggestedDailyPages(memorizedPages: 20) == 2)
        #expect(ReviewPolicy.suggestedDailyPages(memorizedPages: 300) == 10)
        #expect(ReviewPolicy.suggestedDailyPages(memorizedPages: 604) == 20)
        #expect(DailyAmountView.cycleDays(memorizedPages: 300, amount: 10) == 30)
    }
}
