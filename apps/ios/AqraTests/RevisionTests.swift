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

    @Test func aSheikhsTasmeeCountsMoreThanSelfRevision() {
        let policy = ReviewPolicy.standard
        #expect(policy.weight(of: .app) == 1 && policy.weight(of: .outside) == 1)
        #expect(policy.weight(of: .sheikh) == policy.sheikhWeight && policy.sheikhWeight > 1)

        let declared = AyahMemory(since: start)
        let heard = declared.revised(stumbled: false, at: day(14), policy: policy, weight: policy.sheikhWeight)
        #expect(heard.stability == policy.declaredStability * (1 + (policy.growth - 1) * policy.sheikhWeight))
        #expect(heard.stability > declared.revised(stumbled: false, at: day(14), policy: policy).stability)

        // A stumble is a stumble, whoever heard it.
        let stumbled = heard.revised(stumbled: true, at: day(20), policy: policy, weight: policy.sheikhWeight)
        #expect(stumbled.stability == heard.stability * policy.lapseFactor && stumbled.lapses == 1)

        // A tasmee' applied after a later self-revision never moves the last revision backwards.
        let later = declared.revised(stumbled: false, at: day(20), policy: policy)
        let backdated = later.revised(stumbled: false, at: day(14), policy: policy, weight: policy.sheikhWeight)
        #expect(backdated.lastReviewed == day(20) && backdated.stability > later.stability)
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
        #expect(revision.followUps[11]?.due == CalendarDay(day(4), in: calendar))
        revision.record(page: 11, ayahs: [110], stumbles: [], source: .app, memorization: memorization, now: day(4))
        #expect(revision.followUps[11]?.due == CalendarDay(day(11), in: calendar))
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
        #expect(reloaded.streak(now: day(0)) == 1)
    }

    // MARK: - Streak

    @Test func streakCountsDaysInARow() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let memorization = MemorizationStore(fileURL: nil)
        #expect(revision.streak(now: day(0)) == 0)
        for n in [0, 1, 2] {
            revision.record(page: 1, ayahs: [0], stumbles: [], source: .outside, memorization: memorization, now: day(n))
        }
        #expect(revision.streak(now: day(2)) == 3)
        // Today not revised yet: the streak still stands, counted from yesterday, until the day ends.
        #expect(revision.streak(now: day(3)) == 3)
        // A whole day missed breaks it.
        #expect(revision.streak(now: day(4)) == 0)
        revision.record(page: 1, ayahs: [0], stumbles: [], source: .app, memorization: memorization, now: day(4))
        #expect(revision.streak(now: day(4)) == 1)
        // The last seven days, oldest first, ending today.
        #expect(revision.recentDays(7, now: day(4)) == [false, false, true, true, true, false, true])
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

    /// «تعثّرتُ هنا» reveals the next ayah already marked as a stumble; past the last ayah it does nothing.
    /// «تم» on a partly revealed page records the ayat revealed, or all of them when the student counts the rest.
    @Test func doneCountsOnlyTheRevealedAyatUnlessTheRestIsCounted() {
        let session = RevisionSession(page: 2, ayahs: [7, 8, 9, 10])
        session.revealNext()
        session.stumbleOnNext()
        #expect(session.revisedAyahs(countingRest: false) == [7, 8])
        #expect(session.revisedAyahs(countingRest: true) == [7, 8, 9, 10])
        session.revealAll()
        #expect(session.revisedAyahs(countingRest: false) == [7, 8, 9, 10])
    }

    /// «أين وصلت في مراجعتك؟»: the rotation continues from the page chosen; today's plan is made again from it unless
    /// some of it is already revised.
    @Test func rotationStartsWhereChosen() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let memorization = MemorizationStore(fileURL: nil)
        let pages = Array(1...40)
        revision.setDailyPages(3)
        revision.refreshPlan(memorizedPages: pages, now: day(0))
        #expect(revision.plan?.items.map(\.page) == [1, 2, 3])
        revision.setRotationStart(page: 30)
        revision.refreshPlan(memorizedPages: pages, now: day(0))
        #expect(revision.plan?.items.map(\.page) == [30, 31, 32])
        // With a page already revised, today's plan stays; the rotation still moves from the chosen place.
        revision.record(page: 30, ayahs: [], stumbles: [], source: .app, memorization: memorization, now: day(0))
        revision.setRotationStart(page: 10)
        revision.refreshPlan(memorizedPages: pages, now: day(0))
        #expect(revision.plan?.items.map(\.page) == [30, 31, 32] && revision.rotationCursor == 10)
        revision.refreshPlan(memorizedPages: pages, now: day(1))
        #expect(revision.plan?.items.first?.page == 10)
    }

    /// A page revised outside today's wird (logged from the Mushaf) counts: its ayat, the day, the history and its
    /// follow-up; today's plan and the rotation stay as they were.
    @Test func outsideRevisionOfAnyPageIsRecorded() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let memorization = MemorizationStore(fileURL: nil)
        memorization.mark(500...510, memorized: true)
        revision.setDailyPages(2)
        revision.refreshPlan(memorizedPages: [1, 2, 3, 80], now: day(0))
        let before = revision.plan
        revision.record(page: 80, ayahs: Array(500...505), stumbles: [502], source: .outside, memorization: memorization, now: day(0))
        #expect(revision.history.last == RevisionRecord(date: day(0), page: 80, source: .outside, stumbles: [502]))
        #expect(revision.revisedDays.contains(CalendarDay(day(0), in: calendar)))
        #expect(memorization.memory(ofAyah: 500)?.lastReviewed == day(0) && memorization.memory(ofAyah: 502)?.lapses == 1)
        #expect(revision.followUps[80]?.due == CalendarDay(day(1), in: calendar))
        #expect(revision.plan == before && revision.rotationCursor == 1)
    }

    /// متين / متوسط / يحتاج مراجعة at setup: declared ayat start at the policy's half-life for it; an ayah already
    /// revised, or memorized in Aqra, keeps what's been measured.
    @Test func firmnessSetsStartingStability() {
        let policy = ReviewPolicy.standard
        let memorization = MemorizationStore(fileURL: nil)
        memorization.mark(0...9, memorized: true)
        memorization.recordRevision(ayahs: [9], stumbled: [], at: day(0), policy: policy)
        memorization.learn([20], at: day(0), stability: 2)
        memorization.setFirmness(.firm, of: 0...4, policy: policy)
        memorization.setFirmness(.weak, of: 5...9, policy: policy)
        memorization.setFirmness(.firm, of: [20], policy: policy)
        #expect((0...4).allSatisfy { memorization.memory(ofAyah: $0)?.stability == policy.firmStability })
        #expect((5...8).allSatisfy { memorization.memory(ofAyah: $0)?.stability == policy.weakStability })
        #expect(memorization.memory(ofAyah: 9)?.stability == policy.declaredStability * policy.growth)
        #expect(memorization.memory(ofAyah: 20)?.stability == 2)
        #expect(policy.stability(for: .middling) == policy.declaredStability)
    }

    // MARK: - Days, time zones and the clock

    private func zoned(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    /// A moment given as the time on the clock in a time zone.
    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, in zone: String) -> Date {
        zoned(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("revision-\(UUID().uuidString).json")
    }

    /// Earlier versions kept a day as the device's local midnight; it reads back as the same calendar day, in a zone
    /// ahead of UTC, one behind it, and on a day whose midnight the clocks skipped.
    @Test func daysWrittenAsLocalMidnightReadBackAsTheSameDay() throws {
        for (zone, month, date) in [("Asia/Riyadh", 3, 12), ("America/New_York", 3, 12), ("Africa/Cairo", 4, 24), ("Europe/London", 3, 29)] {
            let calendar = zoned(zone)
            let noon = at(2026, month, date, 12, in: zone)
            #expect(CalendarDay(stored: calendar.startOfDay(for: noon)) == CalendarDay(noon, in: calendar), Comment(rawValue: zone))
            #expect(CalendarDay(noon, in: calendar).description == String(format: "2026-%02d-%02d", month, date))
        }
        // A whole file from before: its days, its plan's day and its follow-up's day.
        let riyadh = zoned("Asia/Riyadh")
        let midnight = riyadh.startOfDay(for: at(2026, 3, 12, 12, in: "Asia/Riyadh")).timeIntervalSinceReferenceDate
        let url = temporaryURL()
        try Data("""
        {"version":1,"rotationCursor":3,"followUps":[{"page":9,"due":\(midnight + 86_400),"step":0}],
        "plan":{"day":\(midnight),"items":[{"page":1,"kind":"rotation","done":true}]},"history":[],
        "revisedDays":[\(midnight - 86_400),\(midnight)],"completedDays":[\(midnight)]}
        """.utf8).write(to: url)
        let revision = RevisionStore(fileURL: url, calendar: riyadh)
        let today = CalendarDay(at(2026, 3, 12, 20, in: "Asia/Riyadh"), in: riyadh)
        #expect(revision.plan?.day == today && revision.followUps[9]?.due == today.adding(1))
        #expect(revision.revisedDays == [today.adding(-1), today] && revision.completedDays == [today])
        #expect(revision.streak(now: at(2026, 3, 12, 20, in: "Asia/Riyadh")) == 2)
    }

    /// Three evenings revised in Riyadh, then a flight to London: the streak is still there, the same evening and
    /// the next morning.
    @Test func streakSurvivesATimeZoneChange() {
        let url = temporaryURL()
        let memorization = MemorizationStore(fileURL: nil)
        let riyadh = RevisionStore(fileURL: url, calendar: zoned("Asia/Riyadh"))
        for date in 10...12 {
            riyadh.record(page: 1, ayahs: [], stumbles: [], source: .app, memorization: memorization,
                          now: at(2026, 3, date, 21, in: "Asia/Riyadh"))
        }
        #expect(riyadh.streak(now: at(2026, 3, 12, 22, in: "Asia/Riyadh")) == 3)
        let london = RevisionStore(fileURL: url, calendar: zoned("Europe/London"))
        #expect(london.streak(now: at(2026, 3, 12, 19, 30, in: "Europe/London")) == 3)
        #expect(london.recentDays(3, now: at(2026, 3, 12, 19, 30, in: "Europe/London")) == [true, true, true])
        #expect(london.streak(now: at(2026, 3, 13, 8, in: "Europe/London")) == 3)
    }

    /// Today's plan, made in Riyadh with a page done, is the same plan after landing in London that day.
    @Test func planSurvivesRelaunchInAnotherZoneOnTheSameDay() {
        let url = temporaryURL()
        let memorization = MemorizationStore(fileURL: nil)
        let pages = [1, 2, 3, 4, 5]
        let riyadh = RevisionStore(fileURL: url, calendar: zoned("Asia/Riyadh"))
        riyadh.setDailyPages(3)
        riyadh.refreshPlan(memorizedPages: pages, now: at(2026, 3, 12, 9, in: "Asia/Riyadh"))
        riyadh.record(page: 1, ayahs: [], stumbles: [], source: .app, memorization: memorization,
                      now: at(2026, 3, 12, 10, in: "Asia/Riyadh"))
        let london = RevisionStore(fileURL: url, calendar: zoned("Europe/London"))
        london.refreshPlan(memorizedPages: pages, now: at(2026, 3, 12, 15, in: "Europe/London"))
        #expect(london.plan?.items.map(\.page) == [1, 2, 3] && london.plan?.doneCount == 1)
    }

    /// In Cairo the clocks go forward at midnight on Friday 24 April 2026, so that day starts at 01:00. A revision
    /// every evening from the 20th to the 27th is a streak of eight.
    @Test func streakCrossesAMidnightDSTGap() {
        let cairo = zoned("Africa/Cairo")
        #expect(cairo.component(.hour, from: cairo.startOfDay(for: at(2026, 4, 24, 12, in: "Africa/Cairo"))) == 1)
        let revision = RevisionStore(fileURL: nil, calendar: cairo)
        let memorization = MemorizationStore(fileURL: nil)
        for date in 20...27 {
            revision.record(page: 1, ayahs: [], stumbles: [], source: .app, memorization: memorization,
                            now: at(2026, 4, date, 20, in: "Africa/Cairo"))
        }
        #expect(revision.streak(now: at(2026, 4, 27, 21, in: "Africa/Cairo")) == 8)
        #expect(revision.recentDays(8, now: at(2026, 4, 27, 21, in: "Africa/Cairo")).allSatisfy { $0 })
    }

    /// A stumble just before the clocks go forward at midnight brings the page back the next calendar day.
    @Test func followUpSetOnADSTDayIsDueTheNextDay() {
        let cairo = zoned("Africa/Cairo")
        let revision = RevisionStore(fileURL: nil, calendar: cairo)
        let memorization = MemorizationStore(fileURL: nil)
        revision.record(page: 5, ayahs: [], stumbles: [40], source: .app, memorization: memorization,
                        now: at(2026, 4, 23, 23, 30, in: "Africa/Cairo"))
        #expect(revision.followUps[5]?.due == CalendarDay(at(2026, 4, 24, 12, in: "Africa/Cairo"), in: cairo))
        revision.refreshPlan(memorizedPages: [5, 6], now: at(2026, 4, 24, 1, 5, in: "Africa/Cairo"))
        #expect(revision.plan?.items.first == PlanItem(page: 5, kind: .followUp))
    }

    /// A wird carried on past midnight: each page recorded is checked off and the wird moves on, the wird counts
    /// for the day it was made, and the next plan continues the rotation.
    @Test func recordingAfterMidnightMovesTheWirdOn() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let memorization = MemorizationStore(fileURL: nil)
        let pages = [10, 11, 12, 13]
        revision.setDailyPages(3)
        revision.refreshPlan(memorizedPages: pages, now: day(0))
        revision.record(page: 10, ayahs: [], stumbles: [], source: .app, memorization: memorization, now: day(0))
        let afterMidnight = calendar.startOfDay(for: day(1)).addingTimeInterval(10 * 60)
        revision.record(page: 11, ayahs: [], stumbles: [], source: .app, memorization: memorization, now: afterMidnight)
        #expect(revision.plan?.items.map(\.done) == [true, true, false])
        #expect(revision.plan?.items.first { !$0.done }?.page == 12)
        revision.record(page: 12, ayahs: [], stumbles: [], source: .app, memorization: memorization, now: afterMidnight)
        #expect(revision.completedDays == [CalendarDay(day(0), in: calendar)])
        #expect(revision.revisedDays == [CalendarDay(day(0), in: calendar), CalendarDay(day(1), in: calendar)])
        #expect(revision.rotationCursor == 13)
        revision.refreshPlan(memorizedPages: pages, now: afterMidnight)
        #expect(revision.plan?.day == CalendarDay(day(1), in: calendar) && revision.plan?.items.first?.page == 13)
    }

    /// Revising a page again the same day it was stumbled on doesn't move its follow-up on: the step waits for
    /// its day.
    @Test func cleanRevisionBeforeDueDoesNotAdvanceAFollowUp() {
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let memorization = MemorizationStore(fileURL: nil)
        revision.record(page: 7, ayahs: [], stumbles: [70], source: .app, memorization: memorization, now: day(0))
        revision.record(page: 7, ayahs: [], stumbles: [], source: .app, memorization: memorization,
                        now: day(0).addingTimeInterval(2 * 3_600))
        #expect(revision.followUps[7] == .init(due: CalendarDay(day(1), in: calendar), step: 0))
        revision.record(page: 7, ayahs: [], stumbles: [], source: .app, memorization: memorization, now: day(1))
        #expect(revision.followUps[7] == .init(due: CalendarDay(day(4), in: calendar), step: 1))
        // A late revision, after the day it was due, still moves it on.
        revision.record(page: 7, ayahs: [], stumbles: [], source: .app, memorization: memorization, now: day(9))
        #expect(revision.followUps[7] == .init(due: CalendarDay(day(16), in: calendar), step: 2))
    }

    /// A teacher's phone a day ahead, or a device whose clock ran ahead: what they wrote counts from now.
    @Test func futureDatedRevisionIsClampedToNow() {
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        memorization.mark(7...8, memorized: true)
        let record = TasmeeRecord(id: "r", teacherId: "t", teacherName: "x", sessionId: "s", at: day(6), pages: [2], stumbles: [])
        TasmeeApply.apply(record, memorization: memorization, revision: revision, now: day(5)) { _ in 7...8 }
        #expect(memorization.memory(ofAyah: 7)?.lastReviewed == day(5) && revision.history.last?.date == day(5))

        var ahead = AyahMemory(since: day(0))
        ahead.lastReviewed = day(40)
        ahead.lastLapseAt = day(40)
        let merged = CloudBackup.merge(CloudBackup.Memory(ayahs: [9: ahead]), CloudBackup.Memory(removed: [10: day(40)]), now: day(5))
        #expect(merged.ayahs[9]?.lastReviewed == day(5) && merged.ayahs[9]?.lastLapseAt == day(5) && merged.removed[10] == day(5))
    }

    /// The first revision of an ayah memorized in Aqra is spaced from when it was learned: right away it grows a
    /// little, after the follow-up's wait it grows in full. A declared ayah's first revision still counts in full.
    @Test func firstRevisionOfALearnedAyahIsSpaced() {
        let policy = ReviewPolicy.standard
        let learned = AyahMemory(since: start, stability: 2, learnedAt: start)
        #expect(learned.revised(stumbled: false, at: start.addingTimeInterval(3_600), policy: policy).stability < 2 * 1.2)
        #expect(learned.revised(stumbled: false, at: day(2), policy: policy).stability == 2 * policy.growth)
        #expect(AyahMemory(since: start).revised(stumbled: false, at: start, policy: policy).stability
                == policy.declaredStability * policy.growth)
    }

    @Test func stumblingOnTheNextAyahRevealsItMarked() {
        let session = RevisionSession(page: 2, ayahs: [7, 8, 9])
        session.revealNext()
        session.stumbleOnNext()
        #expect(session.revealed == 2 && session.stumbles == [8])
        session.stumbleOnNext()
        #expect(session.isComplete && session.stumbles == [8, 9])
        session.stumbleOnNext()
        #expect(session.revealed == 3 && session.stumbles == [8, 9])
        // A tap on a revealed ayah still clears its stumble.
        session.tap(9)
        #expect(session.stumbles == [8])
    }
}
