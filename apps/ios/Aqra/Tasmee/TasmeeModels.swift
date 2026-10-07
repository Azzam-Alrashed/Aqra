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

/// An in-person tasmee' session a teacher holds, with a limited number of seats.
struct TasmeeSession: Identifiable, Hashable {
    enum Status: String { case open, cancelled }

    let id: String
    var teacherId: String
    var teacherName: String
    var startsAt: Date
    var place: String
    var seats: Int
    var booked: Int
    var status: Status
    var createdAt: Date

    init(id: String, teacherId: String, teacherName: String, startsAt: Date, place: String, seats: Int,
         booked: Int = 0, status: Status = .open, createdAt: Date = .now) {
        self.id = id
        self.teacherId = teacherId
        self.teacherName = teacherName
        self.startsAt = startsAt
        self.place = place
        self.seats = seats
        self.booked = booked
        self.status = status
        self.createdAt = createdAt
    }

    init?(id: String, document: [String: Any]) {
        guard let teacherId = document.string("teacherId"), let startsAt = document.date("startsAt"),
              let seats = document.int("seats"), let status = document.string("status").flatMap(Status.init) else { return nil }
        self.init(id: id, teacherId: teacherId, teacherName: document.string("teacherName") ?? "", startsAt: startsAt,
                  place: document.string("place") ?? "", seats: seats, booked: document.int("booked") ?? 0, status: status,
                  createdAt: document.date("createdAt") ?? .distantPast)
    }

    var document: [String: Any] {
        ["teacherId": teacherId, "teacherName": teacherName, "startsAt": startsAt, "place": place, "seats": seats,
         "booked": booked, "kind": "inPerson", "status": status.rawValue, "createdAt": createdAt]
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

    init(id: String, name: String, bookedAt: Date = .now, memorizedPages: Int, juzSummary: String? = nil) {
        self.id = id
        self.name = name
        self.bookedAt = bookedAt
        self.memorizedPages = memorizedPages
        self.juzSummary = juzSummary
    }

    init?(id: String, document: [String: Any]) {
        guard let name = document.string("name"), let bookedAt = document.date("bookedAt") else { return nil }
        self.init(id: id, name: name, bookedAt: bookedAt, memorizedPages: document.int("memorizedPages") ?? 0,
                  juzSummary: document.string("juzSummary"))
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
    var place: String

    init(id: String, teacherId: String, teacherName: String, startsAt: Date, place: String) {
        self.id = id
        self.teacherId = teacherId
        self.teacherName = teacherName
        self.startsAt = startsAt
        self.place = place
    }

    init(_ session: TasmeeSession) {
        self.init(id: session.id, teacherId: session.teacherId, teacherName: session.teacherName,
                  startsAt: session.startsAt, place: session.place)
    }

    init?(id: String, document: [String: Any]) {
        guard let teacherId = document.string("teacherId"), let startsAt = document.date("startsAt") else { return nil }
        self.init(id: id, teacherId: teacherId, teacherName: document.string("teacherName") ?? "", startsAt: startsAt,
                  place: document.string("place") ?? "")
    }

    var document: [String: Any] {
        ["teacherId": teacherId, "teacherName": teacherName, "startsAt": startsAt, "place": place]
    }
}

/// A tasmee' a student recited to a teacher: the pages heard and the ayat stumbled on. The teacher writes it
/// into the student's account; the student's app applies it to the progress on the device and marks it applied.
struct TasmeeRecord: Identifiable, Hashable {
    let id: String
    var teacherId: String
    var teacherName: String
    var sessionId: String
    var at: Date
    var pages: [Int]
    var stumbles: [Int]
    var appliedAt: Date?

    init(id: String, teacherId: String, teacherName: String, sessionId: String, at: Date, pages: [Int], stumbles: [Int],
         appliedAt: Date? = nil) {
        self.id = id
        self.teacherId = teacherId
        self.teacherName = teacherName
        self.sessionId = sessionId
        self.at = at
        self.pages = pages
        self.stumbles = stumbles
        self.appliedAt = appliedAt
    }

    init?(id: String, document: [String: Any]) {
        guard let teacherId = document.string("teacherId"), let sessionId = document.string("sessionId"),
              let at = document.date("at"), let pages = document.ints("pages"), let stumbles = document.ints("stumbles") else { return nil }
        self.init(id: id, teacherId: teacherId, teacherName: document.string("teacherName") ?? "", sessionId: sessionId, at: at,
                  pages: pages, stumbles: stumbles, appliedAt: document.date("appliedAt"))
    }

    /// The fields as written: `appliedAt` is null, not missing, so the student's app can query for it.
    var document: [String: Any] {
        ["teacherId": teacherId, "teacherName": teacherName, "sessionId": sessionId, "at": at, "pages": pages,
         "stumbles": stumbles, "appliedAt": appliedAt ?? NSNull()]
    }
}

/// How a tasmee' changes the progress on the student's device.
enum TasmeeApply {
    /// Each page heard is recorded as a sheikh's revision of its memorized ayat: the stumbled ones weaken and
    /// lose their verified mark, the rest grow by the sheikh's weight and are marked verified. Ayat the student
    /// never marked as memorized are left alone: the student owns the map of what they know.
    /// - Parameter pageAyahs: the ayat of a page (from the Mushaf; a closure so this stays testable).
    @MainActor
    static func apply(_ record: TasmeeRecord, memorization: MemorizationStore, revision: RevisionStore,
                      pageAyahs: (Int) -> ClosedRange<Int>) {
        let stumbles = Set(record.stumbles)
        for page in Set(record.pages).sorted() where (1...MushafStore.pageCount).contains(page) {
            let memorized = pageAyahs(page).filter { memorization.isMemorized($0) }
            guard !memorized.isEmpty else { continue }
            let pageStumbles = stumbles.intersection(memorized)
            revision.record(page: page, ayahs: memorized, stumbles: pageStumbles, source: .sheikh,
                            memorization: memorization, now: record.at)
            memorization.verify(memorized, except: pageStumbles)
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
