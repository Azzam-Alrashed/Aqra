import Foundation
import Testing
@testable import Aqra

/// The Mushaf, loaded once for every test of the journey.
private let sharedStore = try? MushafStore()

/// A random number generator that always gives the same sequence, so tests are repeatable.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

/// The personal plan, the stages and their tests, rewards and the rotation's suggestions — with fixed dates and a
/// fixed calendar so every rule can be checked exactly.
@MainActor
struct JourneyTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// A Sunday.
    private let start = Date(timeIntervalSince1970: 1_800_144_000)
    private func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400 + 9 * 3_600) }

    private func store() throws -> MushafStore {
        try #require(sharedStore)
    }

    // MARK: - Portions

    @Test func portionsFollowTheOrderAndNeverLeaveASurahUnfinished() throws {
        let store = try store()
        let memorization = MemorizationStore(fileURL: nil)

        // From the end, starting from nothing: an-Nas, then al-Falaq, al-Ikhlas… each whole, until half a page — and
        // al-Ikhlas, with a single ayah left, is finished rather than left for tomorrow.
        let fromEnd = PlanStore.nextPortion(order: .fromEnd, dailyLines: 8, store: store, isMemorized: memorization.isMemorized)
        #expect(fromEnd.first == store.surahAyahs[114]?.lowerBound)
        #expect(store.lines(of: fromEnd) >= 7.5 && store.lines(of: fromEnd) <= 13)
        try checkWholeSurahsUntilTheLast(fromEnd, store: store, memorization: memorization)
        #expect(fromEnd.last == store.surahAyahs[112]?.upperBound)

        // From the beginning: al-Fatiha, then al-Baqarah from its first ayah.
        let fromStart = PlanStore.nextPortion(order: .fromStart, dailyLines: 15, store: store, isMemorized: memorization.isMemorized)
        #expect(fromStart.first == 0)
        #expect(fromStart.contains(7) && store.lines(of: fromStart) >= 14.9)
        try checkWholeSurahsUntilTheLast(fromStart, store: store, memorization: memorization)

        // What's memorized is skipped: with al-Fatiha and the first ten ayat of al-Baqarah known, it goes on from 2:11.
        memorization.mark(0...16, memorized: true)
        let next = PlanStore.nextPortion(order: .fromStart, dailyLines: 4, store: store, isMemorized: memorization.isMemorized)
        #expect(next.first == 17 && next.allSatisfy { !memorization.isMemorized($0) })
        #expect(store.reference(ofAyah: next[0]) == (2, 11))
        // An ayah already memorized inside the surah ends the portion there.
        memorization.mark([20], memorized: true)
        let stopped = PlanStore.nextPortion(order: .fromStart, dailyLines: 23, store: store, isMemorized: memorization.isMemorized)
        #expect(stopped == [17, 18, 19])
    }

    /// Every surah in a portion is taken from its first unmemorized ayah, and all but the last are finished.
    private func checkWholeSurahsUntilTheLast(_ portion: [Int], store: MushafStore, memorization: MemorizationStore) throws {
        let surahs = portion.map { store.surah(ofAyah: $0) }
        var seen: [Int] = []
        for surah in surahs where seen.last != surah { seen.append(surah) }
        for (index, surah) in seen.enumerated() {
            let ayat = portion.filter { store.surah(ofAyah: $0) == surah }
            let range = try #require(store.surahAyahs[surah])
            #expect(ayat == Array(ayat[0]...ayat[ayat.count - 1]), "surah \(surah) is contiguous")
            if index < seen.count - 1 { #expect(ayat.last == range.upperBound, "surah \(surah) is finished") }
        }
    }

    @Test func memorizingAPortionStartsItsLifeInTheRevisionEngine() throws {
        let store = try store()
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let plan = PlanStore(fileURL: nil, calendar: calendar)
        var logged: [Portion] = []
        plan.onPortion = { logged.append($0) }
        plan.setPlan(MemorizationPlan(dailyLines: 8, studyDays: [1, 2, 3, 4, 5, 7], order: .fromStart), now: day(0))
        #expect(plan.history.count == 1)

        guard case .due(let portion) = plan.today(memorization: memorization, store: store, now: day(0)) else {
            Issue.record("A portion is due on a study day")
            return
        }
        // The student memorized only the first part of it.
        let part = Array(portion.prefix(3))
        let recorded = try #require(plan.record(planned: portion, memorized: part, store: store, memorization: memorization,
                                                revision: revision, now: day(0)))
        #expect(recorded.memorized == part && recorded.planned == portion)
        #expect(recorded.plannedLines > recorded.actualLines && recorded.actualLines > 0)
        #expect(logged == [recorded])
        for ayah in part {
            let memory = try #require(memorization.memory(ofAyah: ayah))
            #expect(memory.learnedAt == day(0) && memory.stability == plan.policy.newStability)
        }
        // Its page comes back for follow-up tomorrow.
        #expect(revision.followUps[1]?.due == calendar.startOfDay(for: day(1)))
        // Done for today; tomorrow the plan goes on from where the student stopped.
        guard case .done = plan.today(memorization: memorization, store: store, now: day(0)) else {
            Issue.record("Today's portion is done")
            return
        }
        guard case .due(let tomorrow) = plan.today(memorization: memorization, store: store, now: day(1)) else {
            Issue.record("Tomorrow's portion is due")
            return
        }
        #expect(tomorrow.first == portion[3])
        // Friday (day 5) is a rest day; paused, there's nothing at all.
        guard case .restDay(let next) = plan.today(memorization: memorization, store: store, now: day(5)) else {
            Issue.record("Friday is a rest day")
            return
        }
        #expect(next == calendar.startOfDay(for: day(6)))
        var paused = try #require(plan.plan)
        paused.paused = true
        plan.setPlan(paused, now: day(2))
        #expect(plan.today(memorization: memorization, store: store, now: day(2)) == nil)
        #expect(plan.history.count == 2)
    }

    @Test func theCompletionDateFollowsThePlanThenTheRecentPace() throws {
        let store = try store()
        let memorization = MemorizationStore(fileURL: nil)
        let everyDay = MemorizationPlan(dailyLines: 15, studyDays: Set(1...7), order: .fromEnd)
        let remaining = PlanStore.remainingLines(memorization: memorization, store: store)
        #expect(remaining > 8_000 && remaining < 9_200)

        // A page a day, every day: as many days as there are pages' worth of lines.
        let date = try #require(PlanStore.estimate(everyDay, remainingLines: 150, pace: nil, from: day(0), calendar: calendar))
        #expect(date == calendar.startOfDay(for: day(9)))
        // One day a week takes seven times as long; a slower pace, longer still.
        var sundays = everyDay
        sundays.studyDays = [1]
        #expect(PlanStore.estimate(sundays, remainingLines: 150, pace: nil, from: day(0), calendar: calendar) == calendar.startOfDay(for: day(63)))
        #expect(PlanStore.estimate(everyDay, remainingLines: 150, pace: 7.5, from: day(0), calendar: calendar) == calendar.startOfDay(for: day(19)))
        #expect(PlanStore.estimate(everyDay, remainingLines: 0, pace: nil, from: day(0)) == nil)

        // The recent pace counts once seven study days have passed: three portions of 10 lines over ten days.
        let plan = PlanStore(fileURL: nil, calendar: calendar)
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        plan.setPlan(everyDay, now: day(0))
        #expect(plan.recentPace(now: day(3)) == nil)
        for portionDay in [0, 4, 8] {
            guard case .due(let portion) = plan.today(memorization: memorization, store: store, now: day(portionDay)) else { continue }
            plan.record(planned: portion, memorized: portion, store: store, memorization: memorization, revision: revision, now: day(portionDay))
        }
        let pace = try #require(plan.recentPace(now: day(9)))
        let lines = plan.portions.reduce(0) { $0 + $1.actualLines }
        #expect(abs(pace - lines / 9) < 0.001)
    }

    // MARK: - Stages and mastery

    @Test func stagesMeasureMemorizedMasteredAndVerified() throws {
        let store = try store()
        let memorization = MemorizationStore(fileURL: nil)
        #expect(Curriculum.juz(ofStage: 1) == 1...3 && Curriculum.juz(ofStage: 10) == 28...30)
        #expect(Curriculum.stage(ofJuz: 30) == 10 && Curriculum.stage(ofJuz: 4) == 2)
        let last = StageProgress(stage: 10, store: store, memorization: memorization)
        #expect(last.ayahs.upperBound == MushafStore.ayahCount - 1 && last.ayahs.lowerBound == store.juzAyahs[28]?.lowerBound)

        // Mastery: established for two months, with no stumble since the last clean revision.
        var memory = AyahMemory(since: day(0), stability: 70)
        #expect(memory.isMastered())
        memory = memory.revised(stumbled: true, at: day(10), policy: .standard)
        #expect(!memory.isMastered())
        memory.stability = 80
        #expect(!memory.isMastered())
        memory = memory.revised(stumbled: false, at: day(40), policy: .standard)
        #expect(memory.isMastered() && memory.lastLapseAt == day(10))
        #expect(!AyahMemory(since: day(0)).isMastered())

        let range = try #require(store.surahAyahs[114])
        memorization.replaceAll(Dictionary(uniqueKeysWithValues: range.map { ($0, AyahMemory(since: day(0), stability: 90)) }))
        memorization.verify(range)
        let progress = StageProgress(stage: 10, store: store, memorization: memorization)
        #expect(progress.memorized == range.count && progress.mastered == range.count && progress.verified == range.count)
    }

    @Test func aStageTestAsksAboutWhatsMemorized() throws {
        let store = try store()
        let memorization = MemorizationStore(fileURL: nil)
        var generator = SeededGenerator(state: 7)
        #expect(TestQuestion.test(stage: 10, count: 10, store: store, memorization: memorization, using: &generator).isEmpty)
        let stage = StageProgress(stage: 10, store: store, memorization: memorization).ayahs
        memorization.mark(stage, memorized: true)
        let questions = TestQuestion.test(stage: 10, count: 10, store: store, memorization: memorization, using: &generator)
        #expect(questions.count == 10)
        #expect(questions.contains { $0.kind == .nextAyah } && questions.contains { $0.kind == .whichSurah })
        #expect(Set(questions.map(\.ayah)).count == 10)
        for question in questions {
            #expect(question.options.count == 4 && Set(question.options).count == 4 && question.options.contains(question.answer))
            #expect(stage.contains(question.ayah))
            switch question.kind {
            case .nextAyah:
                #expect(question.answer == question.ayah + 1)
                #expect(store.surah(ofAyah: question.ayah) == store.surah(ofAyah: question.answer))
                #expect(question.options.allSatisfy { stage.contains($0) })
            case .whichSurah:
                #expect(question.answer == store.surah(ofAyah: question.ayah))
                #expect(question.options.allSatisfy { (1...114).contains($0) })
            }
        }
        // Every question's ayah has its text, as published.
        #expect(questions.allSatisfy { !store.ayahTexts[$0.ayah].isEmpty })
    }

    @Test func aStageIsPassedOnceEveryRequirementIsMet() throws {
        let store = try store()
        let memorization = MemorizationStore(fileURL: nil)
        let assessments = AssessmentStore(fileURL: nil)
        var passedStages: [Int] = []
        assessments.onPass = { passedStages.append($0) }
        let stage = StageProgress(stage: 10, store: store, memorization: memorization).ayahs
        memorization.replaceAll(Dictionary(uniqueKeysWithValues: stage.map { ($0, AyahMemory(since: day(0), stability: 90)) }))

        var status = assessments.status(of: 10, store: store, memorization: memorization, now: day(1))
        #expect(status.isMet(.memorized) && status.isMet(.mastered) && !status.isMet(.test) && !status.isMet(.sheikh))
        #expect(status.canTakeTest(at: day(1)))

        // A failed test waits a day before it can be taken again.
        assessments.record(AssessmentStore.TestResult(stage: 10, date: day(1), questions: 10, correct: 6))
        status = assessments.status(of: 10, store: store, memorization: memorization, now: day(1))
        #expect(!status.testPassed && !status.canTakeTest(at: day(1)) && status.bestScore == 0.6)
        #expect(assessments.status(of: 10, store: store, memorization: memorization, now: day(2)).canTakeTest(at: day(2)))
        assessments.record(AssessmentStore.TestResult(stage: 10, date: day(2), questions: 10, correct: 9))
        #expect(assessments.checkPasses(store: store, memorization: memorization, now: day(2)).isEmpty)

        // A teacher's test with too many mistakes doesn't count; within the allowance, it does — once.
        let failed = TasmeeRecord(id: "t1", teacherId: "t", teacherName: "x", sessionId: "s", at: day(3), pages: [600],
                                  stumbles: [6200, 6201], test: .init(stage: 10, allowedMistakesPerPage: 1))
        assessments.record(failed)
        #expect(assessments.checkPasses(store: store, memorization: memorization, now: day(3)).isEmpty)
        let passed = TasmeeRecord(id: "t2", teacherId: "t", teacherName: "x", sessionId: "s", at: day(4), pages: [600, 601],
                                  stumbles: [6200], test: .init(stage: 10, allowedMistakesPerPage: 1))
        assessments.record(passed)
        assessments.record(passed)
        #expect(assessments.sheikhTests.count == 2)
        #expect(assessments.checkPasses(store: store, memorization: memorization, now: day(4)) == [10])
        #expect(passedStages == [10] && assessments.passes[10] == day(4))
        #expect(assessments.checkPasses(store: store, memorization: memorization, now: day(5)).isEmpty)

        // The current stage: the one holding the next portion, else the latest memorized, else the first not passed.
        #expect(AssessmentStore.currentStage(nextAyah: 300, memorization: memorization, store: store, passes: [:]) == 1)
        #expect(AssessmentStore.currentStage(nextAyah: nil, memorization: MemorizationStore(fileURL: nil), store: store,
                                             passes: [1: day(0)]) == 2)
    }

    // MARK: - Rewards

    @Test func rewardsFollowTheRevisingAndTheMemorizing() throws {
        let store = try store()
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        let rewards = RewardStore(fileURL: nil, calendar: calendar)
        let plan = PlanStore(fileURL: nil, calendar: calendar)
        revision.onRecord = { rewards.revised($0, revision: revision, now: $0.date) }
        memorization.mark(7...20, memorized: true)
        revision.setDailyPages(2)

        // Day one: two pages, the whole wird — points for each, the wird's bonus once, and the first achievements.
        revision.refreshPlan(memorizedPages: [2, 3], now: day(0))
        revision.record(page: 2, ayahs: [7, 8], stumbles: [], source: .app, memorization: memorization, now: day(0))
        #expect(rewards.points == rewards.policy.pageRevisedInApp)
        #expect(rewards.achievements[.firstRevision] == day(0) && rewards.achievements[.firstWird] == nil)
        revision.record(page: 3, ayahs: [12], stumbles: [], source: .outside, memorization: memorization, now: day(0))
        #expect(revision.completedDays.contains(calendar.startOfDay(for: day(0))))
        #expect(rewards.points == rewards.policy.pageRevisedInApp + rewards.policy.pageRevisedOutside + rewards.policy.wirdCompleted)
        #expect(rewards.achievements[.firstWird] != nil)
        // A sheikh's clean page, a peer's page.
        let before = rewards.points
        revision.record(page: 2, ayahs: [7], stumbles: [], source: .sheikh, memorization: memorization, now: day(0))
        revision.record(page: 2, ayahs: [7], stumbles: [], source: .peer, memorization: memorization, now: day(0))
        #expect(rewards.points == before + rewards.policy.pageHeardBySheikh + rewards.policy.pageHeardByPeer)
        #expect(rewards.achievements[.firstVerified] != nil && rewards.achievements[.firstPeer] != nil)

        // Seven days in a row: the streak's bonus, once.
        for n in 1...6 {
            revision.refreshPlan(memorizedPages: [2, 3], now: day(n))
            revision.record(page: 2, ayahs: [7], stumbles: [], source: .app, memorization: memorization, now: day(n))
        }
        #expect(rewards.achievements[.streak7] == day(6))
        #expect(rewards.events.filter { $0.points >= rewards.policy.streakBonuses[7]! }.count == 1)

        // A challenge met within its week.
        rewards.start(.dailyRevision, target: 7, now: day(0))
        rewards.checkChallenges(revision: revision, plan: plan, now: day(6))
        #expect(rewards.challenges.first?.completedAt == day(6))
        #expect(rewards.progress(of: try #require(rewards.challenges.first), revision: revision, plan: plan) == 7)

        // A portion: points by its length, at least the minimum.
        let points = rewards.points
        rewards.memorized(Portion(date: day(7), planned: [0], memorized: [0], plannedLines: 1, actualLines: 1),
                          memorization: memorization, store: store, now: day(7))
        #expect(rewards.points == points + rewards.policy.minPortionPoints)
        #expect(rewards.achievements[.firstPortion] == day(7))
    }

    @Test func celebrationsTakeTurns() {
        let rewards = RewardStore(fileURL: nil, calendar: calendar)
        rewards.passedStage(3, totalPassed: 5, now: day(0))
        // The stage, then the two achievements it brought, one after another.
        var kinds: [Celebration.Kind] = []
        while let celebration = rewards.celebration {
            kinds.append(celebration.kind)
            rewards.finishCelebration()
        }
        #expect(kinds.count == 3)
        #expect(kinds.contains(.stage(3)) && kinds.contains(.achievement(.firstStage)) && kinds.contains(.achievement(.fiveStages)))
        #expect(rewards.points == rewards.policy.stagePassed)
    }

    // MARK: - The rotation learns

    @Test func pagesThatKeepSlippingAreSuggestedUntilAnswered() throws {
        let store = try store()
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        memorization.mark(0...200, memorized: true)
        UserDefaults.standard.removeObject(forKey: "rotation.dismissed")
        #expect(RotationAdvisor.suggestions(store: store, memorization: memorization, revision: revision, now: day(0)).isEmpty)

        // Page 20 stumbled on in two revisions this month, its follow-up then done with.
        revision.record(page: 20, ayahs: Array(store.page(20).ayahs), stumbles: [store.page(20).ayahs.lowerBound],
                        source: .app, memorization: memorization, now: day(0))
        revision.record(page: 20, ayahs: Array(store.page(20).ayahs), stumbles: [store.page(20).ayahs.lowerBound],
                        source: .app, memorization: memorization, now: day(2))
        for (offset, n) in [3, 6, 13].enumerated() {
            _ = offset
            revision.record(page: 20, ayahs: Array(store.page(20).ayahs), stumbles: [], source: .app, memorization: memorization, now: day(n))
        }
        #expect(revision.followUps[20] == nil)
        #expect(RotationAdvisor.suggestions(store: store, memorization: memorization, revision: revision, now: day(14)) == [20])

        // Dismissed, it rests a fortnight; taken, it's back in follow-up from tomorrow.
        RotationAdvisor.dismiss([20], now: day(14))
        #expect(RotationAdvisor.suggestions(store: store, memorization: memorization, revision: revision, now: day(15)).isEmpty)
        UserDefaults.standard.removeObject(forKey: "rotation.dismissed")
        RotationAdvisor.accept([20], revision: revision, now: day(15))
        #expect(revision.followUps[20]?.due == calendar.startOfDay(for: day(16)))
        #expect(RotationAdvisor.suggestions(store: store, memorization: memorization, revision: revision, now: day(15)).isEmpty)
    }

    // MARK: - Backup

    @Test func theJourneySurvivesTheBackupAndMerges() throws {
        // Ayat keep when they were learned and last stumbled on; rows from before still read.
        var memory = AyahMemory(since: day(0), stability: 20, learnedAt: day(0))
        memory.lastLapseAt = day(3)
        #expect(CloudBackup.decode(CloudBackup.encode(memory)) == memory)
        let old = try #require(CloudBackup.decode([1_800_000_000, 14, -1, 0, 1]))
        #expect(old.learnedAt == nil && old.lastLapseAt == nil && old.verified)

        let a = Portion(date: day(1), planned: [1], memorized: [1], plannedLines: 1, actualLines: 1)
        let b = Portion(date: day(2), planned: [2], memorized: [2], plannedLines: 1, actualLines: 1)
        let plan = MemorizationPlan(dailyLines: 8, studyDays: [1], order: .fromEnd)
        let local = PlanStore.Snapshot(plan: plan, portions: [a], history: [PlanChange(date: day(0), plan: plan)], updatedAt: day(1))
        var changed = plan
        changed.dailyLines = 15
        let remote = PlanStore.Snapshot(plan: changed, portions: [a, b], history: [PlanChange(date: day(0), plan: plan), PlanChange(date: day(2), plan: changed)],
                                        updatedAt: day(2))
        let merged = PlanStore.Snapshot.merge(local, remote)
        #expect(merged.plan == changed && merged.portions == [a, b] && merged.history.count == 2)

        var mine = RewardStore.Snapshot(points: 30, achievements: [.firstRevision: day(3)], updatedAt: day(3))
        mine.challenges = [Challenge(kind: .wirdDays, target: 5, start: day(0), end: day(7))]
        let theirs = RewardStore.Snapshot(points: 50, achievements: [.firstRevision: day(1), .firstPortion: day(2)], updatedAt: day(2))
        let rewards = RewardStore.Snapshot.merge(mine, theirs)
        #expect(rewards.points == 50 && rewards.achievements == [.firstRevision: day(1), .firstPortion: day(2)] && rewards.challenges.count == 1)

        let snapshot = Journey.Snapshot(plan: merged, rewards: rewards, assessments: .init(passes: [3: day(4)]))
        let json = try CloudBackup.encode(snapshot)
        #expect(CloudBackup.decodeJourney(json) == snapshot)
        #expect(Journey.Snapshot.merge(snapshot, .init(assessments: .init(passes: [3: day(2), 4: day(5)]))).assessments.passes == [3: day(2), 4: day(5)])
    }
}
