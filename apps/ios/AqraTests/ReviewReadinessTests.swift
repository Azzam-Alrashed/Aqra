import Foundation
import Testing
@testable import Aqra

/// A camera turned off in a call shows the person's initial, never the last frame it sent.
struct CallTileTests {
    @Test func aCameraTurnedOffShowsTheInitial() {
        #expect(RemoteCameraTile.shown(isMuted: true, isSubscribed: true, hasVideoTrack: true) == .initial)
    }

    @Test func aCameraOnShowsTheVideo() {
        #expect(RemoteCameraTile.shown(isMuted: false, isSubscribed: true, hasVideoTrack: true) == .video)
    }

    @Test func aCameraNotYetArrivedShowsTheInitial() {
        #expect(RemoteCameraTile.shown(isMuted: false, isSubscribed: false, hasVideoTrack: true) == .initial)
        #expect(RemoteCameraTile.shown(isMuted: false, isSubscribed: true, hasVideoTrack: false) == .initial)
    }
}

/// A first launch with no connection gets its account once the phone is back online.
struct AnonymousSignInRetryTests {
    @Test func triesSoonThenFurtherApartUpToAMinute() {
        let delays = (1...7).map { AnonymousSignInRetry.delay(afterAttempt: $0) }
        #expect(delays == [.seconds(5), .seconds(10), .seconds(20), .seconds(40), .seconds(60), .seconds(60), .seconds(60)])
    }

    @Test func neverWaitsLongerThanAMinute() {
        #expect(AnonymousSignInRetry.delay(afterAttempt: 1_000) == .seconds(60))
        #expect(AnonymousSignInRetry.delay(afterAttempt: 0) == .seconds(5))
    }
}

/// A Mushaf that can't load tells the student what to do, in their language, never a developer's instruction.
struct MushafLoadErrorTests {
    @Test func missingFontsSayToReinstall() throws {
        let error = MushafStore.LoadError.missingPageFonts(found: 12)
        let shown = try #require(error.errorDescription)
        #expect(shown.contains("12") && shown.contains("604"))
        #expect(!shown.contains("scripts/"))
        #expect(error.localizedDescription == shown)
        // The developer's own wording stays for the log.
        #expect(error.description.contains("scripts/fetch-mushaf-fonts.sh"))
    }

    @Test func everyLoadErrorHasStudentFacingCopy() {
        let errors: [MushafStore.LoadError] = [.missingResource("qul/qpc-v4.json"), .missingPageFonts(found: 0), .database("open")]
        for error in errors {
            #expect(error.errorDescription?.contains("install it again") == true, "\(error)")
        }
    }
}

/// A call that isn't open yet says the day it opens, not only «a quarter of an hour before».
struct CallOpeningTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return calendar
    }()

    private static func day(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func saysTheDayItOpens() {
        let now = Self.day(13, 22)
        func opening(_ date: Date) -> CallOpening { CallOpening.day(of: date, from: now, calendar: Self.calendar) }
        #expect(opening(Self.day(13, 23, 45)) == .today)
        #expect(opening(Self.day(14, 0, 15)) == .tomorrow)
        #expect(opening(Self.day(19, 20)) == .thisWeek)
        #expect(opening(Self.day(20, 20)) == .later)
        // Already open or past: today, never a day before it.
        #expect(opening(Self.day(13, 8)) == .today)
    }
}

/// MetricKit's diagnostics stay on the phone, the newest few kept.
struct DiagnosticsTests {
    @Test func keepsOnlyTheNewest() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        for day in 1...5 {
            try Diagnostics.save(Data("{\"day\":\(day)}".utf8), endingAt: Date(timeIntervalSince1970: Double(day) * 86_400), in: folder, kept: 3)
        }
        let kept = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try String(decoding: Data(contentsOf: $0), as: UTF8.self) }
        #expect(kept == ["{\"day\":3}", "{\"day\":4}", "{\"day\":5}"])
    }

    @Test func summarizesWhatItHolds() {
        #expect(Diagnostics.summary(crashes: 1, hangs: 2, cpu: 0, disk: 0) == "1 crash, 2 hangs")
        #expect(Diagnostics.summary(crashes: 0, hangs: 0, cpu: 0, disk: 0) == "nothing")
    }
}

/// Blocking someone hides them on this device, and lasts; a report carries what the team needs, in bounds.
@MainActor
struct SafetyTests {
    private static func defaults() -> UserDefaults {
        let name = "safety-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func blockingLastsAndUnblockingUndoesIt() {
        let defaults = Self.defaults()
        let safety = SafetyStore(defaults: defaults)
        let teacher = PersonRef(uid: "t1", name: "الشيخ أحمد", context: .teacher)
        safety.block(teacher)
        safety.block(teacher)
        #expect(safety.blocked.count == 1)
        #expect(SafetyStore(defaults: defaults).isBlocked("t1"))
        safety.unblock("t1")
        #expect(!SafetyStore(defaults: defaults).isBlocked("t1"))
    }

    @Test func aReportHoldsWhatTheRulesTake() {
        let person = PersonRef(uid: "s1", name: String(repeating: "ن", count: 150), context: .call, contextId: "session-1")
        let report = PersonReport(person: person, reason: .abuse, note: "  " + String(repeating: "x", count: 1_200) + "  ")
        let document = report.document(reporter: "me")
        #expect(document["reporter"] as? String == "me")
        #expect(document["subject"] as? String == "s1")
        #expect(document["context"] as? String == "call")
        #expect(document["contextId"] as? String == "session-1")
        #expect(document["reason"] as? String == "abuse")
        #expect((document["subjectName"] as? String)?.count == 100)
        #expect((document["note"] as? String)?.count == PersonReport.noteLimit)
        #expect(Set(document.keys) == ["reporter", "subject", "subjectName", "context", "contextId", "reason", "note", "createdAt"])
    }

    @Test func anEmptyNoteIsLeftOut() {
        let report = PersonReport(person: PersonRef(uid: "f1", name: "", context: .friend), reason: .spam, note: "   ")
        #expect(report.document(reporter: "me")["note"] == nil)
        #expect(report.document(reporter: "me")["contextId"] == nil)
    }
}
