import Foundation

// The tasmee' side of the account as plain values, with no Firebase: teachers, their sessions, the seats booked
// in them, a student's copy of a booking, and the record of a tasmee' heard. Each reads itself from a Firestore
// document's fields (dates already turned into `Date`) and writes itself back the same way, so every rule can be
// tested. See backend/README.md for the collections.

/// A vetted teacher, as shown in the public list.
struct Teacher: Identifiable, Hashable {
    let id: String
    var name: String
    var city: String
    /// One line about the teacher: their ijazah, their riwayah, their halaqah.
    var line: String
    var vetted: Bool

    init(id: String, name: String, city: String = "", line: String = "", vetted: Bool = true) {
        self.id = id
        self.name = name
        self.city = city
        self.line = line
        self.vetted = vetted
    }

    init?(id: String, document: [String: Any]) {
        guard let name = document.string("name") else { return nil }
        self.init(id: id, name: name, city: document.string("city") ?? "", line: document.string("line") ?? "",
                  vetted: document.bool("vetted") ?? false)
    }

    var document: [String: Any] {
        ["name": name, "city": city, "line": line, "vetted": vetted]
    }
}

/// A tasmee' session a teacher holds, in person or by video, with a limited number of seats.
struct TasmeeSession: Identifiable, Hashable {
    enum Status: String { case open, cancelled }

    /// In person, at a place; or by video, in the session's own call.
    enum Kind: String { case inPerson, video }

    let id: String
    var teacherId: String
    var teacherName: String
    var startsAt: Date
    var kind: Kind
    /// Where it's held, for a session in person; empty for a video session.
    var place: String
    /// The free seats, booked first come first served.
    var seats: Int
    var booked: Int
    var status: Status
    var createdAt: Date
    /// Seats won by bidding, beside the free ones (none when zero).
    var auction: Auction?

    /// A session's auctioned seats: they start free; once all are held, each new bid must beat the lowest.
    struct Auction: Hashable {
        enum State: String { case open, settled, cancelled, refunded }

        var seats: Int
        var minBid: Int
        var closesAt: Date
        var state: State
        /// Written by the server: the active bids, what the next bid must reach, and the seats won.
        var bids = 0
        var floor: Int?
        var won = 0

        func isOpen(at date: Date = .now) -> Bool { state == .open && date < closesAt }
        /// What a new bid must reach now.
        var nextAtLeast: Int { floor ?? minBid }
    }

    init(id: String, teacherId: String, teacherName: String, startsAt: Date, kind: Kind = .inPerson, place: String,
         seats: Int, booked: Int = 0, status: Status = .open, createdAt: Date = .now, auction: Auction? = nil) {
        self.id = id
        self.teacherId = teacherId
        self.teacherName = teacherName
        self.startsAt = startsAt
        self.kind = kind
        self.place = place
        self.seats = seats
        self.booked = booked
        self.status = status
        self.createdAt = createdAt
        self.auction = auction
    }

    init?(id: String, document: [String: Any]) {
        guard let teacherId = document.string("teacherId"), let startsAt = document.date("startsAt"),
              let seats = document.int("seats"), let status = document.string("status").flatMap(Status.init) else { return nil }
        var auction: Auction?
        if let auctionSeats = document.int("auctionSeats"), auctionSeats > 0, let closesAt = document.date("biddingClosesAt") {
            auction = Auction(seats: auctionSeats, minBid: document.int("minBid") ?? 0, closesAt: closesAt,
                              state: document.string("auctionState").flatMap(Auction.State.init) ?? .open,
                              bids: document.int("auctionBids") ?? 0, floor: document.int("auctionFloor"),
                              won: document.int("auctionWon") ?? 0)
        }
        self.init(id: id, teacherId: teacherId, teacherName: document.string("teacherName") ?? "", startsAt: startsAt,
                  kind: document.string("kind").flatMap(Kind.init) ?? .inPerson, place: document.string("place") ?? "",
                  seats: seats, booked: document.int("booked") ?? 0, status: status,
                  createdAt: document.date("createdAt") ?? .distantPast, auction: auction)
    }

    /// The fields the teacher writes; the server keeps the auction's own counts.
    var document: [String: Any] {
        var document: [String: Any] = [
            "teacherId": teacherId, "teacherName": teacherName, "startsAt": startsAt, "place": place, "seats": seats,
            "booked": booked, "kind": kind.rawValue, "status": status.rawValue, "createdAt": createdAt,
        ]
        if let auction {
            document["auctionSeats"] = auction.seats
            document["minBid"] = auction.minBid
            document["biddingClosesAt"] = auction.closesAt
            document["auctionState"] = auction.state.rawValue
        }
        return document
    }

    /// The fields a teacher may change after creating it.
    var editableDocument: [String: Any] {
        ["startsAt": startsAt, "place": place, "seats": seats]
    }

    var seatsLeft: Int { max(seats - booked, 0) }
    var isFull: Bool { booked >= seats }

    /// Whether it can still be booked: open and not yet started.
    func isUpcoming(at date: Date = .now) -> Bool { status == .open && startsAt > date }

    /// Whether it's worth showing: not cancelled, and not long over (a session is shown through its day).
    func isCurrent(at date: Date = .now) -> Bool { status == .open && startsAt > date.addingTimeInterval(-6 * 3_600) }
}

/// A student's booked seat in a session, with what they've memorized so the teacher can choose what to hear.
struct Seat: Identifiable, Hashable {
    /// The student's uid.
    let id: String
    var name: String
    var bookedAt: Date
    var memorizedPages: Int
    /// The juz' memorized in full, as the student's app describes them, or nil when none is.
    var juzSummary: String?
    /// The credits paid for a seat won by bidding; nil for a free seat.
    var paid: Int?

    init(id: String, name: String, bookedAt: Date = .now, memorizedPages: Int, juzSummary: String? = nil, paid: Int? = nil) {
        self.id = id
        self.name = name
        self.bookedAt = bookedAt
        self.memorizedPages = memorizedPages
        self.juzSummary = juzSummary
        self.paid = paid
    }

    init?(id: String, document: [String: Any]) {
        guard let name = document.string("name"), let bookedAt = document.date("bookedAt") else { return nil }
        self.init(id: id, name: name, bookedAt: bookedAt, memorizedPages: document.int("memorizedPages") ?? 0,
                  juzSummary: document.string("juzSummary"), paid: document.int("paid"))
    }

    var document: [String: Any] {
        var document: [String: Any] = ["name": name, "bookedAt": bookedAt, "memorizedPages": memorizedPages]
        if let juzSummary { document["juzSummary"] = juzSummary }
        return document
    }
}

/// A student's own copy of a session they booked, kept in their account so the home can show it.
struct Booking: Identifiable, Hashable {
    /// The session's id.
    let id: String
    var teacherId: String
    var teacherName: String
    var startsAt: Date
    var kind: TasmeeSession.Kind
    var place: String

    init(id: String, teacherId: String, teacherName: String, startsAt: Date, kind: TasmeeSession.Kind = .inPerson,
         place: String) {
        self.id = id
        self.teacherId = teacherId
        self.teacherName = teacherName
        self.startsAt = startsAt
        self.kind = kind
        self.place = place
    }

    init(_ session: TasmeeSession) {
        self.init(id: session.id, teacherId: session.teacherId, teacherName: session.teacherName,
                  startsAt: session.startsAt, kind: session.kind, place: session.place)
    }

    init?(id: String, document: [String: Any]) {
        guard let teacherId = document.string("teacherId"), let startsAt = document.date("startsAt") else { return nil }
        self.init(id: id, teacherId: teacherId, teacherName: document.string("teacherName") ?? "", startsAt: startsAt,
                  kind: document.string("kind").flatMap(TasmeeSession.Kind.init) ?? .inPerson,
                  place: document.string("place") ?? "")
    }

    var document: [String: Any] {
        ["teacherId": teacherId, "teacherName": teacherName, "startsAt": startsAt, "kind": kind.rawValue, "place": place]
    }
}

/// A bid for an auctioned seat, written by the server: who, how much, and where it stands.
struct Bid: Identifiable, Hashable {
    enum Status: String { case active, outbid, won, released }

    /// The bidder's uid.
    let id: String
    var name: String
    var amount: Int
    var at: Date
    var status: Status
    var memorizedPages: Int
    var juzSummary: String?

    init(id: String, name: String, amount: Int, at: Date, status: Status, memorizedPages: Int = 0, juzSummary: String? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.at = at
        self.status = status
        self.memorizedPages = memorizedPages
        self.juzSummary = juzSummary
    }

    init?(id: String, document: [String: Any]) {
        guard let amount = document.int("amount"), let status = document.string("status").flatMap(Status.init) else { return nil }
        self.init(id: id, name: document.string("name") ?? "", amount: amount, at: document.date("at") ?? .distantPast,
                  status: status, memorizedPages: document.int("memorizedPages") ?? 0, juzSummary: document.string("juzSummary"))
    }
}

/// How a teacher classifies a stumble. A plain tap records a memorization error; the rest are chosen by pressing
/// and holding the ayah. Weights, if any, live in the stage policy (see docs/SRS.md, open issue A-11).
enum MistakeType: String, CaseIterable, Codable, Hashable, Sendable {
    /// A wrong or missing word.
    case memorization
    /// The student couldn't go on.
    case forgetting
    /// The listener had to prompt (تلقين).
    case prompting
    /// The student hesitated before getting it right.
    case hesitation
    /// A clear error in the Arabic (لحن جلي).
    case lahn
    /// A tajweed rule not observed.
    case tajweed
}

/// A stumble with its type.
struct Mistake: Codable, Hashable, Sendable {
    var ayah: Int
    var type: MistakeType
}

/// A tasmee' a student recited to a teacher or a peer: the pages heard and the ayat stumbled on. The listener writes
/// it into the student's account; the student's app applies it to the progress on the device and marks it applied.
struct TasmeeRecord: Identifiable, Hashable {
    /// Who heard it: a vetted teacher in one of their sessions, or a peer with the student's code.
    enum Kind: String { case sheikh, peer }

    /// A teacher's test of a stage: the tasmee' counts toward passing it when its mistakes are within the allowed
    /// number per page heard.
    struct StageTest: Hashable {
        var stage: Int
        var allowedMistakesPerPage: Int
    }

    let id: String
    var kind: Kind
    /// The listener: the teacher, or the peer.
    var teacherId: String
    var teacherName: String
    /// The session it was heard in, or the peer request's code.
    var sessionId: String
    var at: Date
    var pages: [Int]
    var stumbles: [Int]
    /// The stumbles' types, where the listener gave them; a stumble without one is a memorization error.
    var mistakes: [Mistake]
    var test: StageTest?
    var appliedAt: Date?

    init(id: String, kind: Kind = .sheikh, teacherId: String, teacherName: String, sessionId: String, at: Date,
         pages: [Int], stumbles: [Int], mistakes: [Mistake] = [], test: StageTest? = nil, appliedAt: Date? = nil) {
        self.id = id
        self.kind = kind
        self.teacherId = teacherId
        self.teacherName = teacherName
        self.sessionId = sessionId
        self.at = at
        self.pages = pages
        self.stumbles = stumbles
        self.mistakes = mistakes
        self.test = test
        self.appliedAt = appliedAt
    }

    init?(id: String, document: [String: Any]) {
        guard let teacherId = document.string("teacherId"), let sessionId = document.string("sessionId"),
              let at = document.date("at"), let pages = document.ints("pages"), let stumbles = document.ints("stumbles") else { return nil }
        let mistakes = (document["mistakes"] as? [[String: Any]] ?? []).compactMap { entry -> Mistake? in
            guard let ayah = (entry["ayah"] as? NSNumber)?.intValue,
                  let type = (entry["type"] as? String).flatMap(MistakeType.init) else { return nil }
            return Mistake(ayah: ayah, type: type)
        }
        let test = (document["test"] as? [String: Any]).flatMap { test -> StageTest? in
            guard let stage = (test["stage"] as? NSNumber)?.intValue,
                  let allowed = (test["allowedMistakesPerPage"] as? NSNumber)?.intValue else { return nil }
            return StageTest(stage: stage, allowedMistakesPerPage: allowed)
        }
        self.init(id: id, kind: document.string("kind").flatMap(Kind.init) ?? .sheikh, teacherId: teacherId,
                  teacherName: document.string("teacherName") ?? "", sessionId: sessionId, at: at, pages: pages,
                  stumbles: stumbles, mistakes: mistakes, test: test, appliedAt: document.date("appliedAt"))
    }

    /// The fields as written: `appliedAt` is null, not missing, so the student's app can tell it's waiting.
    var document: [String: Any] {
        var document: [String: Any] = [
            "kind": kind.rawValue, "teacherId": teacherId, "teacherName": teacherName, "sessionId": sessionId, "at": at,
            "pages": pages, "stumbles": stumbles, "appliedAt": appliedAt ?? NSNull(),
        ]
        if !mistakes.isEmpty {
            document["mistakes"] = mistakes.map { ["ayah": $0.ayah, "type": $0.type.rawValue] as [String: Any] }
        }
        if let test {
            document["test"] = ["stage": test.stage, "allowedMistakesPerPage": test.allowedMistakesPerPage]
        }
        return document
    }

    /// Each stumble's type: the one the listener chose, or a memorization error.
    func mistakeType(of ayah: Int) -> MistakeType {
        mistakes.first { $0.ayah == ayah }?.type ?? .memorization
    }

    /// Whether a stage test passed: no more mistakes than allowed per page heard.
    var passesTest: Bool? {
        guard let test else { return nil }
        return stumbles.count <= test.allowedMistakesPerPage * max(Set(pages).count, 1)
    }
}

/// How a tasmee' changes the progress on the student's device.
enum TasmeeApply {
    /// Each page heard is recorded as a revision of its memorized ayat, by a sheikh or a peer: the stumbled ones
    /// weaken, the rest grow by the listener's weight. Only a sheikh's tasmee' verifies: the clean ayat get the
    /// mark and the stumbled ones lose it. Ayat the student never marked as memorized are left alone: the student
    /// owns the map of what they know.
    /// - Parameter pageAyahs: the ayat of a page (from the Mushaf; a closure so this stays testable).
    @MainActor
    static func apply(_ record: TasmeeRecord, memorization: MemorizationStore, revision: RevisionStore,
                      pageAyahs: (Int) -> ClosedRange<Int>) {
        let stumbles = Set(record.stumbles)
        for page in Set(record.pages).sorted() where (1...MushafStore.pageCount).contains(page) {
            let memorized = pageAyahs(page).filter { memorization.isMemorized($0) }
            guard !memorized.isEmpty else { continue }
            let pageStumbles = stumbles.intersection(memorized)
            revision.record(page: page, ayahs: memorized, stumbles: pageStumbles,
                            source: record.kind == .peer ? .peer : .sheikh, memorization: memorization, now: record.at)
            if record.kind == .sheikh {
                memorization.verify(memorized, except: pageStumbles)
            }
        }
    }
}

// MARK: - Reading Firestore fields

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? { self[key] as? String }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
    func date(_ key: String) -> Date? { self[key] as? Date }
    /// Firestore hands numbers back as `Int64` or `NSNumber`; either reads as a number.
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func ints(_ key: String) -> [Int]? {
        guard let values = self[key] as? [Any] else { return nil }
        return values.compactMap { ($0 as? NSNumber)?.intValue }
    }
}
