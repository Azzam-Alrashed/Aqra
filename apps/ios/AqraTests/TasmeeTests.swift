import Foundation
import Testing
@testable import Aqra

/// The tasmee' values and how a tasmee' is applied to the student's progress, without the network.
@MainActor
struct TasmeeTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400) }

    @Test func valuesSurviveTheirDocuments() {
        let teacher = Teacher(id: "t", name: "الشيخ أحمد", city: "الدمام", line: "إجازة", vetted: true)
        #expect(Teacher(id: "t", document: teacher.document) == teacher)
        #expect(Teacher(id: "t", document: ["city": "x"]) == nil)

        let session = TasmeeSession(id: "s", teacherId: "t", teacherName: "الشيخ أحمد", startsAt: day(1), place: "المسجد",
                                    seats: 5, booked: 2, status: .open, createdAt: day(0))
        #expect(TasmeeSession(id: "s", document: session.document) == session)
        #expect(session.document["kind"] as? String == "inPerson")
        // Firestore hands numbers back as Int64 or NSNumber.
        var document = session.document
        document["seats"] = Int64(5)
        document["booked"] = NSNumber(value: 2)
        #expect(TasmeeSession(id: "s", document: document) == session)
        document["status"] = "done"
        #expect(TasmeeSession(id: "s", document: document) == nil)
        #expect(session.seatsLeft == 3 && !session.isFull && session.isUpcoming(at: day(0)) && !session.isUpcoming(at: day(2)))
        var cancelled = session
        cancelled.status = .cancelled
        #expect(!cancelled.isUpcoming(at: day(0)) && !cancelled.isCurrent(at: day(0)))

        let seat = Seat(id: "alice", name: "Alice", bookedAt: day(0), memorizedPages: 40, juzSummary: "٣٠، ٢٩")
        #expect(Seat(id: "alice", document: seat.document) == seat)
        let bare = Seat(id: "bob", name: "Bob", bookedAt: day(0), memorizedPages: 0)
        #expect(bare.document["juzSummary"] == nil && Seat(id: "bob", document: bare.document) == bare)

        let booking = Booking(session)
        #expect(booking.id == "s" && booking.teacherName == "الشيخ أحمد" && booking.startsAt == day(1))
        #expect(Booking(id: "s", document: booking.document) == booking)

        let record = TasmeeRecord(id: "r", teacherId: "t", teacherName: "الشيخ أحمد", sessionId: "s", at: day(1),
                                  pages: [2, 3], stumbles: [8, 20])
        #expect(record.document["appliedAt"] is NSNull)
        #expect(TasmeeRecord(id: "r", document: record.document) == record)
        var applied = record
        applied.appliedAt = day(2)
        #expect(TasmeeRecord(id: "r", document: applied.document)?.appliedAt == day(2))
        var missing = record.document
        missing["pages"] = nil
        #expect(TasmeeRecord(id: "r", document: missing) == nil)
    }

    @Test func applyingATasmeeRecordsASheikhRevisionAndVerifies() {
        let policy = ReviewPolicy.standard
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        memorization.mark(7...11, memorized: true)
        revision.setDailyPages(2)
        revision.refreshPlan(memorizedPages: [2], now: day(5))

        // Page 2 holds ayat 7...20; the student memorized 7...11 and stumbled on 8 (and on 300, which isn't on
        // the page) before the sheikh on day 5.
        let record = TasmeeRecord(id: "r", teacherId: "t", teacherName: "x", sessionId: "s", at: day(5),
                                  pages: [2, 9], stumbles: [8, 300])
        TasmeeApply.apply(record, memorization: memorization, revision: revision) { $0 == 2 ? 7...20 : 500...520 }

        // One revision, the sheikh's, of page 2 with the stumble that was on it; page 9 had nothing memorized.
        #expect(revision.history.count == 1)
        #expect(revision.history.last?.source == .sheikh && revision.history.last?.stumbles == [8] && revision.history.last?.page == 2)
        // The stumbled ayah weakened and isn't verified; the clean ones grew by the sheikh's weight and are.
        #expect(memorization.memory(ofAyah: 8)?.lapses == 1 && memorization.memory(ofAyah: 8)?.verified == false)
        for ayah in [7, 9, 10, 11] {
            #expect(memorization.memory(ofAyah: ayah)?.verified == true)
            #expect(memorization.memory(ofAyah: ayah)?.stability == policy.declaredStability * (1 + (policy.growth - 1) * policy.sheikhWeight))
        }
        // Ayat the student never marked stay unmarked.
        #expect(memorization.memorizedCount(in: 12...20) == 0)
        // The page follows up tomorrow, the day counts, and today's plan item is checked off.
        #expect(revision.followUps[2]?.due == calendar.startOfDay(for: day(6)))
        #expect(revision.revisedDays.contains(calendar.startOfDay(for: day(5))))
        #expect(revision.plan?.items.first { $0.page == 2 }?.done == true)
    }

    @Test func recordsCarryTheirKindMistakesAndTest() {
        let record = TasmeeRecord(id: "r", teacherId: "t", teacherName: "x", sessionId: "s", at: day(1), pages: [2, 3],
                                  stumbles: [8, 20], mistakes: [Mistake(ayah: 20, type: .hesitation)],
                                  test: .init(stage: 10, allowedMistakesPerPage: 1))
        let decoded = TasmeeRecord(id: "r", document: record.document)
        #expect(decoded == record)
        #expect(decoded?.kind == .sheikh && record.document["kind"] as? String == "sheikh")
        #expect(record.mistakeType(of: 20) == .hesitation && record.mistakeType(of: 8) == .memorization)
        // Two mistakes over two pages, one allowed per page: passed. A third would fail it.
        #expect(record.passesTest == true)
        var failed = record
        failed.stumbles.append(25)
        #expect(failed.passesTest == false)
        // Records written before kinds existed are a sheikh's.
        var old = record.document
        old["kind"] = nil
        old["mistakes"] = nil
        old["test"] = nil
        #expect(TasmeeRecord(id: "r", document: old)?.kind == .sheikh)
        #expect(TasmeeRecord(id: "r", document: old)?.test == nil)
        #expect(TasmeeRecord(id: "r", document: old)?.passesTest == nil)
        // Sessions by video, and bookings of them.
        let call = TasmeeSession(id: "c", teacherId: "t", teacherName: "x", startsAt: day(1), kind: .video, place: "", seats: 3)
        #expect(TasmeeSession(id: "c", document: call.document)?.kind == .video)
        #expect(Booking(id: "c", document: Booking(call).document)?.kind == .video)
        var oldBooking = Booking(call).document
        oldBooking["kind"] = nil
        #expect(Booking(id: "c", document: oldBooking)?.kind == .inPerson)
    }

    @Test func aPeersTasmeeCountsAsAPeerRevisionAndNeverVerifies() {
        let policy = ReviewPolicy.standard
        let memorization = MemorizationStore(fileURL: nil)
        let revision = RevisionStore(fileURL: nil, calendar: calendar)
        memorization.mark(7...11, memorized: true)
        let record = TasmeeRecord(id: "p", kind: .peer, teacherId: "friend", teacherName: "", sessionId: "ABC234",
                                  at: day(5), pages: [2], stumbles: [8])
        TasmeeApply.apply(record, memorization: memorization, revision: revision) { _ in 7...20 }
        #expect(revision.history.last?.source == .peer && revision.history.last?.stumbles == [8])
        #expect(memorization.memory(ofAyah: 8)?.lapses == 1)
        for ayah in [7, 9, 10, 11] {
            #expect(memorization.memory(ofAyah: ayah)?.verified == false)
            #expect(memorization.memory(ofAyah: ayah)?.stability == policy.declaredStability * (1 + (policy.growth - 1) * policy.peerWeight))
        }
        #expect(policy.weight(of: .app) < policy.weight(of: .peer) && policy.weight(of: .peer) < policy.weight(of: .sheikh))
    }

    @Test func peerCodesAreShortClearAndRoundTrip() {
        for _ in 0..<50 {
            let code = PeerRequest.randomCode()
            #expect(PeerRequest.isWellFormed(code))
            #expect(!code.contains("O") && !code.contains("0") && !code.contains("I") && !code.contains("1"))
        }
        #expect(PeerRequest.normalize(" abc-234 ") == "ABC234")
        #expect(!PeerRequest.isWellFormed("ABC23") && !PeerRequest.isWellFormed("ABC2340") && !PeerRequest.isWellFormed("ABC0O4"))
        let request = PeerRequest(id: "ABC234", studentUid: "alice", studentName: "Alice", startPage: 582,
                                  createdAt: day(0), expiresAt: day(0).addingTimeInterval(PeerRequest.lifetime))
        #expect(PeerRequest(id: "ABC234", document: request.document) == request)
        #expect(PeerRequest.code(in: request.link) == "ABC234")
        #expect(PeerRequest.code(in: URL(string: "aqra://friend/ABC234")!) == nil)
        #expect(request.isValid(at: day(0)) && !request.isValid(at: day(1)))
        let unnamed = PeerRequest(id: "ABC234", studentUid: "alice", studentName: nil, createdAt: day(0), expiresAt: day(0))
        #expect(unnamed.document["studentName"] == nil && unnamed.document["startPage"] == nil)
    }

    @Test func anApplicationSurvivesItsDocumentAndKnowsWhenItsComplete() {
        var application = TeacherApplication(id: "alice", name: "أحمد", city: "الدمام", ijazahFrom: "الشيخ فلان",
                                             contact: "0500000000", createdAt: day(0), updatedAt: day(0))
        #expect(!application.isComplete)
        application.files = ["ijazahs/alice/a.jpg"]
        #expect(application.isComplete && application.canEdit)
        #expect(TeacherApplication(id: "alice", document: application.document) == application)
        application.status = .interview
        #expect(!application.canEdit)
        #expect(TeacherApplication.filePath(uid: "alice", name: "a.pdf") == "ijazahs/alice/a.pdf")
    }

    @Test func studentFilesReadTheirDocuments() {
        let file = StudentFile(id: "alice", document: ["name": "Alice", "lastHeardAt": day(2), "notes": "سورة الملك"])
        #expect(file?.name == "Alice" && file?.lastHeardAt == day(2) && file?.notes == "سورة الملك")
        #expect(StudentFile(id: "bob", document: ["notes": "x"]) == nil)
    }

    @Test func biddingClosesThreeHoursBeforeOrLateForASessionSoon() {
        let now = start
        /// How many minutes from now bidding closes, for a session starting in `minutes`.
        func closes(inMinutes minutes: Int) -> Int? {
            TasmeeStore.biddingClosesAt(startsAt: now.addingTimeInterval(Double(minutes) * 60), now: now)
                .map { Int(($0.timeIntervalSince(now) / 60).rounded()) }
        }
        // Far enough: three hours before.
        #expect(closes(inMinutes: 24 * 60) == 21 * 60)
        #expect(closes(inMinutes: 210) == 30)
        // Sooner, three hours before would leave under half an hour to bid: 30 minutes before instead.
        #expect(closes(inMinutes: 200) == 170)
        #expect(closes(inMinutes: 60) == 30)
        // Under an hour away: no auction.
        #expect(closes(inMinutes: 59) == nil)
    }

    @Test func auctionsSeatsAndBidsSurviveTheirDocuments() {
        let auction = TasmeeSession.Auction(seats: 3, minBid: 2, closesAt: day(1), state: .open)
        let session = TasmeeSession(id: "s", teacherId: "t", teacherName: "x", startsAt: day(1).addingTimeInterval(3 * 3_600),
                                    kind: .video, place: "", seats: 1, createdAt: day(0), auction: auction)
        let document = session.document
        #expect(document["auctionSeats"] as? Int == 3 && document["auctionState"] as? String == "open")
        #expect(document["auctionBids"] == nil && document["auctionFloor"] == nil)
        #expect(TasmeeSession(id: "s", document: document) == session)
        // The server's counts come back with it.
        var counted = document
        counted["auctionBids"] = Int64(3)
        counted["auctionFloor"] = NSNumber(value: 6)
        let read = TasmeeSession(id: "s", document: counted)?.auction
        #expect(read?.bids == 3 && read?.nextAtLeast == 6 && read?.isOpen(at: day(0)) == true && read?.isOpen(at: day(2)) == false)
        #expect(auction.nextAtLeast == 2)
        // A session without auctioned seats writes none of the fields.
        let plain = TasmeeSession(id: "p", teacherId: "t", teacherName: "x", startsAt: day(1), place: "y", seats: 2)
        #expect(plain.document["auctionSeats"] == nil && TasmeeSession(id: "p", document: plain.document)?.auction == nil)

        let seat = Seat(id: "bob", name: "Bob", bookedAt: day(0), memorizedPages: 10, paid: 5)
        #expect(Seat(id: "bob", document: seat.document.merging(["paid": 5]) { $1 })?.paid == 5)
        #expect(Seat(id: "bob", document: Seat(id: "bob", name: "Bob", memorizedPages: 1).document)?.paid == nil)

        let bid = Bid(id: "bob", document: ["name": "Bob", "amount": NSNumber(value: 4), "at": day(0), "status": "outbid",
                                            "memorizedPages": 12])
        #expect(bid?.amount == 4 && bid?.status == .outbid && bid?.memorizedPages == 12)
        #expect(Bid(id: "x", document: ["amount": 1, "status": "maybe"]) == nil)
        #expect(WalletStore.credits(of: "aqra.credits.30") == 30)
        #expect(CreditsFormat.credits(8) == 8.formatted() && CreditsFormat.credits(6.4) == 6.4.formatted(.number.precision(.fractionLength(2))))
    }
}
