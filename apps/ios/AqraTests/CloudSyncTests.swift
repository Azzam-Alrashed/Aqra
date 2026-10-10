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
        let memorization = MemorizationStore(fileURL: nil)
        memorization.mark([7], memorized: true)
        revision.setDailyPages(5)
        revision.refreshPlan(memorizedPages: [1, 2, 3])
        revision.record(page: 2, ayahs: [7], stumbles: [], source: .sheikh, memorization: memorization)
        let json = try CloudBackup.encode(revision.snapshot)
        let decoded = CloudBackup.decodeRevision(json)
        #expect(decoded == revision.snapshot)
        #expect(decoded?.history.last?.source == .sheikh)
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

    // MARK: - Merging across devices

    @Test func mergePrefersRevisedRecordOverFreshDeclaration() {
        // A hafiz on a new phone declares the juz' again (dated now, never revised), then signs in: months of
        // revision in the account win, and the memorization is dated from its earliest declaration.
        let history = memory(since: 0, reviewed: 60, stability: 80, verified: true)
        let fresh = AyahMemory(since: day(90))
        for merged in [CloudBackup.merge(fresh, history), CloudBackup.merge(history, fresh)] {
            #expect(merged.stability == 80 && merged.lastReviewed == day(60) && merged.verified && merged.lapses == 2)
            #expect(merged.since == day(0))
        }
        // Neither revised: the earlier declaration is the record, still dated from the earliest.
        let early = AyahMemory(since: day(1)), late = AyahMemory(since: day(5), stability: 30)
        #expect(CloudBackup.merge(early, late).stability == 14 && CloudBackup.merge(late, early).since == day(1))
        // When it was learned as a new portion is kept from whichever side knows.
        var learned = memory(since: 3, reviewed: 4)
        learned.learnedAt = day(3)
        #expect(CloudBackup.merge(learned, memory(since: 3, reviewed: 9)).learnedAt == day(3))
    }

    @Test func mergeDropsVerifiedAfterALaterStumble() {
        // Verified by a sheikh on one device (day 10), then stumbled on with the other device (day 20).
        var verified = memory(since: 0, reviewed: 10, stability: 40, verified: true)
        verified.lapses = 0
        var stumbled = memory(since: 0, reviewed: 20, stability: 12)
        stumbled.lapses = 1
        stumbled.lastLapseAt = day(20)
        let merged = CloudBackup.merge(verified, stumbled)
        #expect(!merged.verified && merged.lastLapseAt == day(20) && merged.lapses == 1)
        #expect(CloudBackup.merge(stumbled, verified) == merged)
        // A stumble before the teacher heard it clean doesn't take the mark away.
        stumbled.lastLapseAt = day(5)
        stumbled.lastReviewed = day(5)
        #expect(CloudBackup.merge(verified, stumbled).verified)
        // A device that never saw the tasmee' revised later, clean: the mark holds.
        #expect(CloudBackup.merge(verified, memory(since: 0, reviewed: 30, stability: 50)).verified)
    }

    @Test func mergeKeepsFollowUpsOfBothSides() {
        let a = RevisionRecord(date: day(1), page: 3, source: .app, stumbles: [7])
        let b = RevisionRecord(date: day(2), page: 9, source: .app, stumbles: [8])
        let local = RevisionStore.Snapshot(followUps: [3: .init(due: day(2), step: 0), 5: .init(due: day(4), step: 1)],
                                           plan: DayPlan(day: day(2), items: [PlanItem(page: 3, kind: .followUp, done: true), PlanItem(page: 4, kind: .rotation)]),
                                           history: [a], revisedDays: [day(1)], updatedAt: day(1))
        let remote = RevisionStore.Snapshot(followUps: [5: .init(due: day(6), step: 2), 9: .init(due: day(3), step: 0)],
                                            plan: DayPlan(day: day(2), items: [PlanItem(page: 3, kind: .followUp), PlanItem(page: 4, kind: .rotation, done: true)]),
                                            history: [b], revisedDays: [day(2)], updatedAt: day(2))
        let merged = CloudBackup.merge(local, remote)
        // Page by page: both sides' pages, each at its later date.
        #expect(merged.followUps == [3: .init(due: day(2), step: 0), 5: .init(due: day(6), step: 2), 9: .init(due: day(3), step: 0)])
        // The same day's plan: a page done on either device is done.
        #expect(merged.plan?.items.map(\.done) == [true, true])
        #expect(CloudBackup.merge(remote, local).followUps == merged.followUps)
    }

    @Test func unmarkedAyatStayUnmarkedAcrossDevices() {
        // Unmarked on the phone (day 5) after the account last touched the ayah (revised day 3): it stays gone.
        let phone = CloudBackup.Memory(ayahs: [1: memory(since: 0)], removed: [2: day(5)])
        let account = CloudBackup.Memory(ayahs: [1: memory(since: 0), 2: memory(since: 0, reviewed: 3)])
        var merged = CloudBackup.merge(phone, account)
        #expect(merged.ayahs.keys.sorted() == [1] && merged.removed == [2: day(5)])
        #expect(CloudBackup.merge(account, phone) == merged)
        // Marked again on the tablet after that (day 7): it's back, and the tombstone goes.
        let tablet = CloudBackup.Memory(ayahs: [2: AyahMemory(since: day(7))])
        merged = CloudBackup.merge(merged, tablet)
        #expect(merged.ayahs[2]?.since == day(7) && merged.removed.isEmpty)
        // Tombstones travel through the blocks, and no app reads one as memorized.
        let blocks = CloudBackup.blocks(phone)
        #expect(blocks[0]?["2"] == CloudBackup.tombstone(removedAt: day(5)))
        #expect(CloudBackup.decode(CloudBackup.tombstone(removedAt: day(5))) == nil)
        #expect(CloudBackup.memory(in: blocks.values) == phone)
    }

    @Test func decodeRejectsNonFiniteRows() {
        let good: [Double] = [day(0).timeIntervalSince1970, 14, -1, 0, 0, -1, -1]
        #expect(CloudBackup.decode(good) != nil)
        for (index, bad) in [(0, Double.nan), (1, .infinity), (2, -.infinity), (3, .nan), (3, 1e300), (0, 1e300), (5, .nan), (6, .infinity)] {
            var row = good
            row[index] = bad
            #expect(CloudBackup.decode(row) == nil, "row[\(index)] = \(bad)")
            #expect(CloudBackup.removedAt(row) == nil)
        }
        #expect(CloudBackup.removedAt([Double.nan, 0]) == nil && CloudBackup.removedAt([1e300, 0]) == nil)
        // A file that says so is read as a fresh declaration rather than crashing a screen later.
        let json = #"{"since": 0, "stability": "nan"}"#.replacingOccurrences(of: "\"nan\"", with: "-1e400")
        let decoded = try? JSONDecoder().decode(AyahMemory.self, from: Data(json.utf8))
        #expect(decoded.map { $0.stability.isFinite && $0.stability > 0 } ?? true)
    }

    @Test func strengthLevelHandlesNaN() {
        // A corrupt record's strength can't crash the page: it draws as the faintest shade.
        #expect(TopicHighlight(topic: 0, strength: .nan).level == 0)
        #expect(TopicHighlight(topic: 0, strength: .infinity).level == 0)
        #expect(TopicHighlight(topic: 0, strength: 0.5).level == 2 && TopicHighlight(topic: 0, strength: 1).level == 4)
    }

    /// What this app writes holds the shapes the Android app reads: a dictionary keyed by an enum goes out as a flat
    /// list (name, date, name, date), one keyed by a number as an object, and a set as a list.
    @MainActor
    @Test func writesTheJourneyAsTheAndroidAppReadsIt() throws {
        var rewards = RewardStore.Snapshot(points: 3, achievements: [.firstRevision: day(1)], updatedAt: day(1))
        rewards.events = [RewardStore.Event(date: day(1), points: 2, reason: "page")]
        let plan = PlanStore.Snapshot(plan: MemorizationPlan(dailyLines: 8, studyDays: [1, 2], order: .fromEnd), updatedAt: day(1))
        let assessments = AssessmentStore.Snapshot(passes: [1: day(1)], updatedAt: day(1))
        let reading = ReadingStore.Snapshot(bookmark: .init(page: 3, placedAt: day(1)), updatedAt: day(1))
        let json = try CloudBackup.encode(Journey.Snapshot(plan: plan, rewards: rewards, assessments: assessments, reading: reading))
        let seconds = Int(day(1).timeIntervalSinceReferenceDate)   // a whole number of seconds is written without ".0"
        #expect(json.contains("\"achievements\":[\"firstRevision\",\(seconds)]"), Comment(rawValue: json))
        #expect(json.contains("\"passes\":{\"1\":\(seconds)}"), Comment(rawValue: json))
        #expect(json.contains("\"studyDays\":[") && json.contains("\"order\":\"fromEnd\"") && !json.contains("null"), Comment(rawValue: json))
        #expect(json.contains("\"reading\":{\"bookmark\":{\"page\":3,\"placedAt\":\(seconds)}"), Comment(rawValue: json))
        #expect(CloudBackup.decodeJourney(json) == Journey.Snapshot(plan: plan, rewards: rewards, assessments: assessments, reading: reading))
    }

    @Test func readsTheRevisionRecordTheAndroidAppWrites() throws {
        // As the Android app's serializer writes it (kotlinx.serialization): optional keys left out, no nulls,
        // and a key or value this version doesn't know.
        let android = """
        {"rotationCursor":13,"followUps":{"11":{"due":821779200.0,"step":0},"300":{"due":821692800.0}},\
        "plan":{"day":821692800.0,"items":[{"page":11,"kind":"followUp","done":true},{"page":12,"kind":"rotation"},{"page":13,"kind":"later"}]},\
        "history":[{"date":821696461.5,"page":11,"source":"sheikh","stumbles":[100,101]},{"date":821696462.0,"page":12},{"page":9}],\
        "revisedDays":[821692800.0],"updatedAt":821692800.123456,"mood":"calm"}
        """
        let decoded = try #require(CloudBackup.decodeRevision(android))
        let day = Date(timeIntervalSinceReferenceDate: 821_692_800)
        #expect(decoded.dailyPages == nil && decoded.rotationCursor == 13)
        #expect(decoded.followUps == [11: .init(due: Date(timeIntervalSinceReferenceDate: 821_779_200), step: 0), 300: .init(due: day, step: 0)])
        // A kind this version doesn't know reads as a rotation page: the page is kept rather than lost.
        #expect(decoded.plan == DayPlan(day: day, items: [PlanItem(page: 11, kind: .followUp, done: true), PlanItem(page: 12, kind: .rotation),
                                                          PlanItem(page: 13, kind: .rotation)]))
        #expect(decoded.history == [RevisionRecord(date: Date(timeIntervalSinceReferenceDate: 821_696_461.5), page: 11, source: .sheikh, stumbles: [100, 101]),
                                    RevisionRecord(date: Date(timeIntervalSinceReferenceDate: 821_696_462), page: 12, source: .app, stumbles: [])])
        #expect(decoded.revisedDays == [day] && decoded.completedDays == nil)
        // The bare record a fresh Android install writes.
        #expect(CloudBackup.decodeRevision(#"{"rotationCursor":1,"followUps":{},"history":[],"revisedDays":[],"updatedAt":-63114076800.0}"#) == .empty)
    }

    @Test func readsTheJourneyTheAndroidAppWrites() throws {
        let android = """
        {"plan":{"plan":{"dailyLines":8,"studyDays":[1,2,3,4,5,7],"order":"fromEnd","paused":false},\
        "portions":[{"id":"6B5D2E0A-2A3B-4C0D-9E8F-000000000001","date":821692800.0,"planned":[1,2],"memorized":[1],"plannedLines":2.0,"actualLines":1.0},{"date":1.0}],\
        "history":[{"date":821692800.0,"plan":{"dailyLines":8,"studyDays":[1],"order":"fromStart","paused":false}}],"updatedAt":821692800.0},\
        "rewards":{"points":12,"events":[{"date":821692800.0,"points":2,"reason":"page"}],"achievements":{"firstRevision":821692800.0,"ascended":1.0},\
        "challenges":[],"updatedAt":821692800.0},\
        "assessments":{"results":[{"id":"6B5D2E0A-2A3B-4C0D-9E8F-000000000002","stage":1,"date":821692800.0,"questions":10,"correct":9}],\
        "sheikhTests":[],"passes":{"1":821692800.0},"updatedAt":821692800.0},\
        "reading":{"bookmark":{"page":3,"placedAt":821692800.0},"updatedAt":821692800.0},"extra":{"a":1}}
        """
        let decoded = try #require(CloudBackup.decodeJourney(android))
        let day = Date(timeIntervalSinceReferenceDate: 821_692_800)
        #expect(decoded.plan.plan?.dailyLines == 8 && decoded.plan.portions.count == 1 && decoded.plan.history.count == 1)
        #expect(decoded.rewards.points == 12 && decoded.rewards.events.count == 1)
        #expect(decoded.rewards.achievements == [.firstRevision: day])   // the unknown achievement is passed over
        #expect(decoded.assessments.results.first?.correct == 9 && decoded.assessments.passes == [1: day])
        #expect(decoded.reading?.bookmark == .init(page: 3, placedAt: day))
        // Missing parts are empty, not fatal, and an unreadable ribbon is left out rather than losing the rest.
        let unreadableRibbon = CloudBackup.decodeJourney(#"{"rewards":{"points":3},"reading":{"bookmark":{"page":"three"}}}"#)
        #expect(unreadableRibbon?.rewards.points == 3 && unreadableRibbon?.reading == nil)
        #expect(CloudBackup.decodeJourney(#"{"rewards":{"points":3}}"#)?.rewards.points == 3)
        #expect(CloudBackup.decodeJourney(#"{"rewards":{"points":3}}"#)?.plan == .empty)
    }

    // MARK: - The backup's orchestration, with a fake store

    @Test func secondDeviceLaunchDoesNotOverwriteANewerAccountCopy() async throws {
        let account = FakeCloudStore()
        // The tablet has revised page 1's ayah on day 8 and backed it up.
        let tablet = Device(store: account, id: "tablet")
        tablet.memorization.replaceAll([1: memory(since: 0, reviewed: 8, stability: 40), 2: memory(since: 0)])
        await tablet.sync.attach(uid: "u")
        try await tablet.sync.upload()
        #expect(account.writes.count == 1)

        // The phone holds an older copy (page 1's ayah revised on day 5) and launches later: the account's copy
        // is merged in, and only what the phone adds (ayah 3) is written.
        let phone = Device(store: account, id: "phone")
        phone.memorization.replaceAll([1: memory(since: 0, reviewed: 5, stability: 20), 3: memory(since: 1)])
        await phone.sync.attach(uid: "u")
        try await phone.sync.upload()
        #expect(phone.memorization.memory(ofAyah: 1)?.stability == 40)
        #expect(Set(phone.memorization.ayahs.keys) == [1, 2, 3])
        let accountMemory = CloudBackup.memory(in: account.blocks(uid: "u").values)
        #expect(accountMemory.ayahs[1]?.stability == 40 && Set(accountMemory.ayahs.keys) == [1, 2, 3])
        #expect(account.writes.last?.rows == [0: ["3": CloudBackup.encode(memory(since: 1))]])
        #expect(account.lastWriter == "phone")

        // The tablet comes back to the foreground: another device wrote, so it merges, and has nothing to add.
        await tablet.sync.syncIfChanged()
        try await tablet.sync.upload()
        #expect(Set(tablet.memorization.ayahs.keys) == [1, 2, 3])
        #expect(account.writes.count == 2)
        // Nothing changed since the phone wrote: the next foreground reads one document and stops.
        let reads = account.fetches
        await phone.sync.syncIfChanged()
        #expect(account.fetches == reads)
    }

    @Test func restoredBackupWithStaleFilesMergesInsteadOfOverwriting() async throws {
        // A phone restored from a device backup brings back old files (ayah 1 at its declared strength) and the
        // same sign-in; meanwhile the account has months of revision. The merge, done in every session, keeps
        // the revision; nothing is written that the account doesn't already hold.
        let account = FakeCloudStore()
        account.seed(uid: "u", ayahs: [1: memory(since: 0, reviewed: 60, stability: 80), 2: memory(since: 0, reviewed: 61, stability: 90)])
        let phone = Device(store: account, id: "phone")
        phone.memorization.replaceAll([1: memory(since: 0)])
        await phone.sync.attach(uid: "u")
        try await phone.sync.upload()
        #expect(phone.memorization.memory(ofAyah: 1)?.stability == 80 && phone.memorization.count == 2)
        #expect(account.writes.isEmpty)
        #expect(CloudBackup.memory(in: account.blocks(uid: "u").values).ayahs[1]?.stability == 80)
    }

    @Test func undecodableRemoteRevisionIsNotOverwritten() async throws {
        // A newer app wrote a revision record this version can't read: it's left alone, while the memory still syncs.
        let account = FakeCloudStore()
        account.seed(uid: "u", ayahs: [1: memory(since: 0)], revisionJSON: "{not json")
        let phone = Device(store: account, id: "phone")
        phone.revision.setDailyPages(7)
        phone.memorization.replaceAll([5: memory(since: 2)])
        await phone.sync.attach(uid: "u")
        try await phone.sync.upload()
        #expect(account.revisionJSON(uid: "u") == "{not json")
        #expect(Set(CloudBackup.memory(in: account.blocks(uid: "u").values).ayahs.keys) == [1, 5])
    }

    @Test func unreadableLocalFileDoesNotWipeTheAccount() async throws {
        // The memorization file on the device can't be read: it's set aside, the account's copy is restored,
        // and nothing empty is written over it.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("memorization-\(UUID().uuidString).json")
        try Data("{\"version\": 3, \"ayahs\": [{\"ayah\": \"seven\"}]}".utf8).write(to: url)
        let memorization = MemorizationStore(fileURL: url)
        #expect(memorization.loadFailed && memorization.count == 0)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let aside = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .filter { $0.hasPrefix(url.lastPathComponent + ".corrupt-") }
        #expect(aside.count == 1)

        let account = FakeCloudStore()
        account.seed(uid: "u", ayahs: [1: memory(since: 0, reviewed: 3), 2: memory(since: 0)])
        let phone = Device(store: account, id: "phone", memorization: memorization)
        await phone.sync.attach(uid: "u")
        try await phone.sync.upload()
        #expect(memorization.count == 2 && account.writes.isEmpty)
        // And while the account can't be reached, nothing is written either.
        let offline = FakeCloudStore()
        offline.isOffline = true
        let empty = Device(store: offline, id: "x", memorization: MemorizationStore(fileURL: nil))
        await empty.sync.attach(uid: "u")
        await #expect(throws: CloudSyncError.self) { try await empty.sync.upload() }
        #expect(offline.writes.isEmpty)
    }

    @Test func aTasmeeAppliedOnOneDeviceReachesTheOther() async throws {
        // The phone applies a sheikh's tasmee' of page 1 (ayat 0...6): clean but ayah 3, verified. The tablet,
        // which never saw the record, gets the strengths, the mark and the sheikh's revision from the account.
        let account = FakeCloudStore()
        let phone = Device(store: account, id: "phone")
        let tablet = Device(store: account, id: "tablet")
        let ayahs = Dictionary(uniqueKeysWithValues: (0...6).map { ($0, memory(since: 0, stability: 14)) })
        phone.memorization.replaceAll(ayahs)
        tablet.memorization.replaceAll(ayahs)
        await phone.sync.attach(uid: "u")
        try await phone.sync.upload()
        await tablet.sync.attach(uid: "u")

        let record = TasmeeRecord(id: "r1", teacherId: "t", teacherName: "Sheikh", sessionId: "s", at: day(2), pages: [1], stumbles: [3])
        TasmeeApply.apply(record, memorization: phone.memorization, revision: phone.revision) { _ in 0...6 }
        try await phone.sync.upload()
        await tablet.sync.syncIfChanged()
        #expect(tablet.memorization.memory(ofAyah: 0)?.verified == true)
        #expect(tablet.memorization.memory(ofAyah: 3)?.verified == false)
        #expect(tablet.memorization.memory(ofAyah: 3)?.lapses == phone.memorization.memory(ofAyah: 3)?.lapses)
        #expect(tablet.memorization.memory(ofAyah: 0)?.stability == phone.memorization.memory(ofAyah: 0)?.stability)
        #expect(tablet.revision.history.last?.source == .sheikh && tablet.revision.revisedDays.count == 1)
    }

    @Test func deletingTheAccountStopsUploadsFirst() async throws {
        let account = FakeCloudStore()
        let phone = Device(store: account, id: "phone")
        phone.memorization.replaceAll([1: memory(since: 0)])
        await phone.sync.attach(uid: "u")
        try await phone.sync.upload()
        // A change just before the deletion: its upload, due in two seconds, never happens.
        phone.memorization.mark([2], memorized: true)
        phone.sync.stopUploads()
        try await phone.sync.deleteAccountData(uid: "u")
        try await phone.sync.upload()
        try await Task.sleep(for: .milliseconds(50))
        #expect(account.blocks(uid: "u").isEmpty)
        #expect(account.events.last == .delete)
        // Had the deletion failed, the backups would go on.
        phone.sync.resumeUploads()
        try await Task.sleep(for: .milliseconds(100))
        #expect(account.events.last == .write)
    }

    @Test func waitingForTheServerGivesUpWhenItNeverAnswers() async throws {
        // Like a Firestore write while offline: it answers only once the server has it, and ignores cancelling.
        let pending = Pending()
        let start = Date.now
        await #expect(throws: CloudSyncError.self) {
            try await withServerTimeout(.milliseconds(200)) {
                try await withCheckedThrowingContinuation { pending.continuation = $0 }
            }
        }
        #expect(Date.now.timeIntervalSince(start) < 2)
        pending.continuation?.resume()

        // An answer in time is passed on.
        #expect(try await withServerTimeout(.seconds(5)) { 7 } == 7)
    }
}

/// A call left waiting by a test, answered once the test has seen what it needed.
@MainActor
private final class Pending {
    var continuation: CheckedContinuation<Void, Error>?
}

/// One device: its stores and its backup, all in memory.
@MainActor
private struct Device {
    let memorization: MemorizationStore
    let revision: RevisionStore
    let sync: CloudSync

    init(store: FakeCloudStore, id: String, memorization: MemorizationStore = MemorizationStore(fileURL: nil)) {
        self.memorization = memorization
        revision = RevisionStore(fileURL: nil)
        sync = CloudSync(memorization: memorization, revision: revision, store: store, installID: id)
    }
}

/// The account's documents, kept in memory and merged as Firestore merges them: a block's rows written over the
/// ones it holds, the day arrays only added to.
@MainActor
private final class FakeCloudStore: CloudStore {
    enum Event: Equatable { case fetch, write, delete }

    private var blocks: [String: [Int: CloudBackup.Block]] = [:]
    private var revisions: [String: (json: String?, revisedDays: [Double], completedDays: [Double])] = [:]
    private var journeys: [String: String] = [:]
    private(set) var writers: [String: String] = [:]
    private(set) var writes: [CloudWrite] = []
    private(set) var events: [Event] = []
    private(set) var fetches = 0
    var isOffline = false

    var lastWriter: String? { writers["u"] }

    func seed(uid: String, ayahs: [Int: AyahMemory], revisionJSON: String? = nil) {
        blocks[uid] = CloudBackup.blocks(ayahs).filter { !$0.value.isEmpty }
        if let revisionJSON { revisions[uid] = (revisionJSON, [], []) }
    }

    func blocks(uid: String) -> [Int: CloudBackup.Block] { blocks[uid] ?? [:] }
    func revisionJSON(uid: String) -> String? { revisions[uid]?.json }

    func lastWriter(uid: String) async throws -> String? {
        if isOffline { throw CloudSyncError.timedOut }
        return writers[uid]
    }

    func fetchProgress(uid: String) async throws -> CloudProgress {
        if isOffline { throw CloudSyncError.timedOut }
        fetches += 1
        events.append(.fetch)
        let revision = revisions[uid]
        return CloudProgress(blocks: blocks[uid] ?? [:], revisionJSON: revision?.json, revisedDays: revision?.revisedDays ?? [],
                             completedDays: revision?.completedDays ?? [], journeyJSON: journeys[uid])
    }

    func write(uid: String, _ write: CloudWrite) async throws {
        if isOffline { throw CloudSyncError.timedOut }
        writes.append(write)
        events.append(.write)
        writers[uid] = write.writer
        for (index, rows) in write.rows {
            blocks[uid, default: [:]][index, default: [:]].merge(rows) { _, new in new }
        }
        if let json = write.revisionJSON {
            var revision = revisions[uid] ?? (nil, [], [])
            revision.json = json
            revision.revisedDays += write.revisedDays.filter { !revision.revisedDays.contains($0) }
            revision.completedDays += write.completedDays.filter { !revision.completedDays.contains($0) }
            revisions[uid] = revision
        }
        if let json = write.journeyJSON { journeys[uid] = json }
    }

    func deleteProgress(uid: String) async throws {
        if isOffline { throw CloudSyncError.timedOut }
        events.append(.delete)
        blocks[uid] = nil
        revisions[uid] = nil
        journeys[uid] = nil
    }
}
