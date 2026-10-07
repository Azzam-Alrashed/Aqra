@preconcurrency import FirebaseFirestore
import Foundation
import Observation

/// Teachers and tasmee' sessions, through the account. For a student: the vetted teachers, the sessions booked,
/// and the tasmee' records teachers write into the account, which are applied to the progress on this device
/// as they arrive. For a teacher: their own sessions, the students in each, and recording what they heard.
///
/// The teacher never reads a student's progress. What the teacher heard goes into the student's account as a
/// record, and the student's own app applies it (see `TasmeeApply`) and marks it applied, so the device's copy
/// stays the one the app works from. See backend/README.md for the collections.
@MainActor @Observable
final class TasmeeStore {
    /// This account's teacher profile, when it has one (vetted or not).
    private(set) var teacherProfile: Teacher?
    var isTeacher: Bool { teacherProfile?.vetted == true }
    /// The sessions this student booked, soonest first.
    private(set) var bookings: [Booking] = []
    /// Those sessions as they are now, by id: a teacher may change or cancel one after it was booked.
    private(set) var bookedSessions: [String: TasmeeSession] = [:]
    /// A teacher's own sessions still to come, soonest first.
    private(set) var mySessions: [TasmeeSession] = []
    /// The vetted teachers, by name.
    private(set) var teachers: [Teacher] = []
    private(set) var isLoadingTeachers = false
    /// Tasmee' records applied to this device since launch, newest first.
    private(set) var recentlyApplied: [TasmeeRecord] = []
    /// Every tasmee' record in the account, newest first: what teachers and peers heard.
    private(set) var history: [TasmeeRecord] = []
    /// A teacher's students: everyone they've heard, most recently heard first.
    private(set) var myStudents: [StudentFile] = []
    /// The account's application to teach, if it made one.
    private(set) var application: TeacherApplication?
    var problem: AccountStore.Problem?
    /// The Mushaf, once loaded. A tasmee' can only be applied with it (which ayat each page holds).
    var mushaf: MushafStore? {
        didSet { applyPending() }
    }

    @ObservationIgnored private let memorization: MemorizationStore
    @ObservationIgnored private let revision: RevisionStore
    /// The account followed, or nil before one is attached.
    @ObservationIgnored private(set) var uid: String?
    @ObservationIgnored private var listeners: [any ListenerRegistration] = []
    @ObservationIgnored private var sessionsListener: (any ListenerRegistration)?
    @ObservationIgnored private var studentsListener: (any ListenerRegistration)?
    @ObservationIgnored private var bookedListener: (any ListenerRegistration)?
    @ObservationIgnored private var bookedIDs: [String] = []
    /// Records the account holds that haven't been applied on this device yet.
    @ObservationIgnored private var pending: [TasmeeRecord] = []
    /// The records already applied on this install, so none is applied twice while its mark is on its way.
    private static let appliedKey = "tasmee.applied"

    init(memorization: MemorizationStore, revision: RevisionStore) {
        self.memorization = memorization
        self.revision = revision
    }

    var database: Firestore { Firestore.firestore() }

    func user(_ uid: String) -> DocumentReference {
        database.collection("users").document(uid)
    }

    /// Firestore hands dates back as `Timestamp`s, also inside maps and lists; the values want `Date`s.
    nonisolated static func dated(_ data: [String: Any]) -> [String: Any] {
        data.mapValues(undated)
    }

    nonisolated private static func undated(_ value: Any) -> Any {
        switch value {
        case let timestamp as Timestamp: timestamp.dateValue()
        case let map as [String: Any]: map.mapValues(undated)
        case let list as [Any]: list.map(undated)
        default: value
        }
    }

    // MARK: - The account in use

    /// Follows the account: its teacher profile, its bookings, and the tasmee' records waiting to be applied.
    func attach(uid: String) {
        guard uid != self.uid else { return }
        detach()
        self.uid = uid
        let user = user(uid)

        listeners.append(database.collection("teachers").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                self.teacherProfile = snapshot.data().flatMap { Teacher(id: uid, document: Self.dated($0)) }
                self.watchMySessions()
                self.watchMyStudents()
            }
        })

        listeners.append(database.collection("teacherApplications").document(uid).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                self.application = snapshot.data().flatMap { TeacherApplication(id: uid, document: Self.dated($0)) }
            }
        })

        listeners.append(user.collection("bookings").addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                self.bookings = snapshot.documents
                    .compactMap { Booking(id: $0.documentID, document: Self.dated($0.data())) }
                    .sorted { $0.startsAt < $1.startsAt }
                self.watchBookedSessions()
            }
        })

        // Every record, for the history; those not yet applied are applied on this device as they arrive.
        listeners.append(user.collection("tasmee").order(by: "at", descending: true).limit(to: 200).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                let records = snapshot.documents.compactMap { TasmeeRecord(id: $0.documentID, document: Self.dated($0.data())) }
                self.history = records
                self.pending = records.filter { $0.appliedAt == nil }.sorted { $0.at < $1.at }
                self.applyPending()
            }
        })
    }

    /// Stops following the account, before signing out or deleting it.
    func detach() {
        for listener in listeners { listener.remove() }
        listeners = []
        sessionsListener?.remove()
        sessionsListener = nil
        studentsListener?.remove()
        studentsListener = nil
        bookedListener?.remove()
        bookedListener = nil
        bookedIDs = []
        uid = nil
        teacherProfile = nil
        bookings = []
        bookedSessions = [:]
        mySessions = []
        myStudents = []
        history = []
        application = nil
        pending = []
        problem = nil
    }

    private func watchMySessions() {
        guard let uid, isTeacher else {
            sessionsListener?.remove()
            sessionsListener = nil
            mySessions = []
            return
        }
        guard sessionsListener == nil else { return }
        sessionsListener = database.collection("sessions").whereField("teacherId", isEqualTo: uid).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                self.mySessions = snapshot.documents
                    .compactMap { TasmeeSession(id: $0.documentID, document: Self.dated($0.data())) }
                    .filter { $0.isCurrent() }
                    .sorted { $0.startsAt < $1.startsAt }
            }
        }
    }

    private func watchMyStudents() {
        guard let uid, isTeacher else {
            studentsListener?.remove()
            studentsListener = nil
            myStudents = []
            return
        }
        guard studentsListener == nil else { return }
        studentsListener = database.collection("teachers").document(uid).collection("students")
            .addSnapshotListener { [weak self] snapshot, _ in
                MainActor.assumeIsolated {
                    guard let self, let snapshot else { return }
                    self.myStudents = snapshot.documents
                        .compactMap { StudentFile(id: $0.documentID, document: Self.dated($0.data())) }
                        .sorted { $0.lastHeardAt > $1.lastHeardAt }
                }
            }
    }

    private func watchBookedSessions() {
        let ids = Array(bookings.map(\.id).prefix(30))
        guard ids != bookedIDs else { return }
        bookedIDs = ids
        bookedListener?.remove()
        bookedListener = nil
        guard !ids.isEmpty else {
            bookedSessions = [:]
            return
        }
        bookedListener = database.collection("sessions").whereField(FieldPath.documentID(), in: ids).addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                let sessions = snapshot.documents.compactMap { TasmeeSession(id: $0.documentID, document: Self.dated($0.data())) }
                self.bookedSessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            }
        }
    }

    // MARK: - Bookings

    /// The booked session as it is now, or nil until it's heard from (or when the teacher deleted it).
    func session(of booking: Booking) -> TasmeeSession? { bookedSessions[booking.id] }

    /// Whether a session is booked by this student.
    func hasBooked(_ session: TasmeeSession) -> Bool { bookings.contains { $0.id == session.id } }

    /// The bookings still ahead (through the session's day), soonest first; cancelled ones stay until then, so
    /// the student learns of the cancellation.
    var upcomingBookings: [Booking] {
        bookings.filter { booking in
            session(of: booking).map { $0.startsAt > Date.now.addingTimeInterval(-6 * 3_600) }
                ?? (booking.startsAt > Date.now.addingTimeInterval(-6 * 3_600))
        }
    }

    var nextBooking: Booking? { upcomingBookings.first }

    // MARK: - Teachers and their sessions

    func loadTeachers() async {
        guard uid != nil else { return }
        isLoadingTeachers = teachers.isEmpty
        defer { isLoadingTeachers = false }
        do {
            let snapshot = try await database.collection("teachers").whereField("vetted", isEqualTo: true).getDocuments()
            teachers = snapshot.documents
                .compactMap { Teacher(id: $0.documentID, document: Self.dated($0.data())) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            problem = nil
        } catch {
            problem = AccountStore.problem(for: error)
        }
    }

    /// A teacher's sessions still open to booking, soonest first.
    func upcomingSessions(of teacherId: String) async throws -> [TasmeeSession] {
        let snapshot = try await database.collection("sessions").whereField("teacherId", isEqualTo: teacherId).getDocuments()
        return snapshot.documents
            .compactMap { TasmeeSession(id: $0.documentID, document: Self.dated($0.data())) }
            .filter { $0.isUpcoming() }
            .sorted { $0.startsAt < $1.startsAt }
    }

    /// Books a seat: the seat, this student's copy of the session and the seat count, in one transaction, so a
    /// session never takes more students than it has seats.
    func book(_ session: TasmeeSession, name: String, memorizedPages: Int, juzSummary: String?) async throws {
        guard let uid else { return }
        let seat = Seat(id: uid, name: name, memorizedPages: memorizedPages, juzSummary: juzSummary)
        try await Self.takeSeat(seat, in: session)
    }

    // The transactions run off the main actor, so their closures only hold values made here.
    nonisolated private static func takeSeat(_ seat: Seat, in session: TasmeeSession) async throws {
        let database = Firestore.firestore()
        let sessionRef = database.collection("sessions").document(session.id)
        let seatRef = sessionRef.collection("seats").document(seat.id)
        let bookingRef = database.collection("users").document(seat.id).collection("bookings").document(session.id)
        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let current = try transaction.getDocument(sessionRef)
                guard let data = current.data(), let live = TasmeeSession(id: session.id, document: dated(data)),
                      live.isUpcoming(), !live.isFull else {
                    errorPointer?.pointee = TasmeeError.seatUnavailable as NSError
                    return nil
                }
                transaction.setData(seat.document, forDocument: seatRef)
                transaction.setData(Booking(session).document, forDocument: bookingRef)
                transaction.updateData(["booked": FieldValue.increment(Int64(1))], forDocument: sessionRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
            }
            return nil
        }
    }

    /// Gives a seat back: removes the seat and this student's copy, and lowers the count (unless the teacher
    /// has deleted the session meanwhile).
    func cancelBooking(_ booking: Booking) async throws {
        guard let uid else { return }
        try await Self.giveBackSeat(of: uid, in: booking.id)
    }

    nonisolated private static func giveBackSeat(of uid: String, in sessionId: String) async throws {
        let database = Firestore.firestore()
        let sessionRef = database.collection("sessions").document(sessionId)
        let seatRef = sessionRef.collection("seats").document(uid)
        let bookingRef = database.collection("users").document(uid).collection("bookings").document(sessionId)
        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let session = try transaction.getDocument(sessionRef)
                let seat = try transaction.getDocument(seatRef)
                if session.exists && seat.exists {
                    transaction.updateData(["booked": FieldValue.increment(Int64(-1))], forDocument: sessionRef)
                }
                if seat.exists { transaction.deleteDocument(seatRef) }
                transaction.deleteDocument(bookingRef)
            } catch let error as NSError {
                errorPointer?.pointee = error
            }
            return nil
        }
    }

    // MARK: - A teacher's side

    // A teacher's writes aren't waited for: Firestore keeps them while offline (a halaqah's mosque may have no
    // signal) and sends them when it can. What's refused is reported after the fact.

    func createSession(startsAt: Date, kind: TasmeeSession.Kind, place: String, seats: Int) {
        guard let uid, let profile = teacherProfile else { return }
        let reference = database.collection("sessions").document()
        let session = TasmeeSession(id: reference.documentID, teacherId: uid, teacherName: profile.name, startsAt: startsAt,
                                    kind: kind, place: kind == .video ? "" : place, seats: seats)
        reference.setData(session.document, completion: report)
    }

    /// Changes a session's time, place or seats. Students who booked see the change on their booking.
    func updateSession(_ session: TasmeeSession) {
        database.collection("sessions").document(session.id).updateData(session.editableDocument, completion: report)
    }

    func cancelSession(_ session: TasmeeSession) {
        database.collection("sessions").document(session.id)
            .updateData(["status": TasmeeSession.Status.cancelled.rawValue], completion: report)
    }

    /// Changes the teacher's name, city and line, as students see them.
    func updateTeacherProfile(name: String, city: String, line: String) {
        guard let uid else { return }
        database.collection("teachers").document(uid).updateData(
            ["name": name, "city": city, "line": line], completion: report)
    }

    // MARK: - A teacher's students

    /// What the teacher heard from one student, newest first, as it changes.
    func records(of studentUid: String) -> AsyncStream<[TasmeeRecord]> {
        AsyncStream { continuation in
            guard let uid else {
                continuation.finish()
                return
            }
            let registration = database.collection("teachers").document(uid).collection("students").document(studentUid)
                .collection("records").order(by: "at", descending: true).limit(to: 100)
                .addSnapshotListener { snapshot, _ in
                    guard let snapshot else { return }
                    continuation.yield(snapshot.documents.compactMap { TasmeeRecord(id: $0.documentID, document: Self.dated($0.data())) })
                }
            let listener = ListenerBox(registration)
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    /// The teacher's private notes on a student.
    func saveNotes(_ notes: String, for studentUid: String) {
        guard let uid else { return }
        database.collection("teachers").document(uid).collection("students").document(studentUid)
            .setData(["notes": notes], merge: true, completion: report)
    }

    /// Keeps a write's failure, once the account answers.
    nonisolated func report(_ error: Error?) {
        guard let error else { return }
        MainActor.assumeIsolated { problem = AccountStore.problem(for: error) }
    }

    /// A session's booked seats, as they change, until the stream is dropped.
    func seats(of sessionId: String) -> AsyncStream<[Seat]> {
        AsyncStream { continuation in
            let registration = database.collection("sessions").document(sessionId).collection("seats").addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let seats = snapshot.documents
                    .compactMap { Seat(id: $0.documentID, document: Self.dated($0.data())) }
                    .sorted { $0.bookedAt < $1.bookedAt }
                continuation.yield(seats)
            }
            let listener = ListenerBox(registration)
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    /// Records what the teacher heard from a student, into the student's account; the student's app applies it.
    /// The teacher keeps their own copy in the student's file, so they can look back at what they heard.
    func recordTasmee(for seat: Seat, in session: TasmeeSession, pages: [Int], stumbles: [Int], mistakes: [Mistake] = [],
                      test: TasmeeRecord.StageTest? = nil, at date: Date = .now) {
        guard let uid, let profile = teacherProfile else { return }
        let reference = user(seat.id).collection("tasmee").document()
        let record = TasmeeRecord(id: reference.documentID, teacherId: uid, teacherName: profile.name, sessionId: session.id,
                                  at: date, pages: pages.sorted(), stumbles: stumbles.sorted(),
                                  mistakes: mistakes.filter { $0.type != .memorization }, test: test)
        reference.setData(record.document, completion: report)
        let file = database.collection("teachers").document(uid).collection("students").document(seat.id)
        file.setData(["name": seat.name, "lastHeardAt": date], merge: true, completion: report)
        var copy = record.document
        copy["appliedAt"] = nil
        file.collection("records").document(record.id).setData(copy, completion: report)
    }

    // MARK: - Applying what teachers heard

    /// Applies the records waiting, once the Mushaf is there, and marks each applied in the account.
    private func applyPending() {
        guard let mushaf, let uid, !pending.isEmpty else { return }
        var applied = UserDefaults.standard.stringArray(forKey: Self.appliedKey) ?? []
        for record in pending where !applied.contains(record.id) {
            TasmeeApply.apply(record, memorization: memorization, revision: revision) { mushaf.page($0).ayahs }
            applied.append(record.id)
            recentlyApplied.insert(record, at: 0)
            // A client date, not a server timestamp: a pending server timestamp reads as null here and the
            // record would come round again.
            user(uid).collection("tasmee").document(record.id).updateData(["appliedAt": Date()])
        }
        pending = []
        UserDefaults.standard.set(Array(applied.suffix(200)), forKey: Self.appliedKey)
    }

    // MARK: - Deleting

    /// Deletes what the account holds of the student's tasmee': bookings (giving the seats back), records and the
    /// inbox; and of a teacher's: the files they kept on their students, and their application with its uploads.
    func deleteAccountData(uid: String) async throws {
        let user = user(uid)
        // Each booking goes in one write with its seat and the seat count, as the rules require.
        let bookings = try await user.collection("bookings").getDocuments()
        for booking in bookings.documents {
            let batch = database.batch()
            let session = database.collection("sessions").document(booking.documentID)
            let seat = session.collection("seats").document(uid)
            if try await seat.getDocument().exists {
                batch.deleteDocument(seat)
                if try await session.getDocument().exists {
                    batch.updateData(["booked": FieldValue.increment(Int64(-1))], forDocument: session)
                }
            }
            batch.deleteDocument(booking.reference)
            try await batch.commit()
        }

        var references = try await user.collection("tasmee").getDocuments().documents.map(\.reference)
        references += try await user.collection("inbox").getDocuments().documents.map(\.reference)
        let students = try await database.collection("teachers").document(uid).collection("students").getDocuments()
        for student in students.documents {
            references += try await student.reference.collection("records").getDocuments().documents.map(\.reference)
            references.append(student.reference)
        }
        // Uploads are let go of even if the storage can't be reached: the account's deletion mustn't hang on them.
        await TeacherApplication.deleteFiles(of: uid)
        references.append(database.collection("teacherApplications").document(uid))
        try await Self.delete(references, in: database)
    }

    /// Deletes documents in batches, within Firestore's limit of writes per batch.
    nonisolated static func delete(_ references: [DocumentReference], in database: Firestore) async throws {
        for start in stride(from: 0, to: references.count, by: 400) {
            let batch = database.batch()
            for reference in references[start..<min(start + 400, references.count)] {
                batch.deleteDocument(reference)
            }
            try await batch.commit()
        }
    }
}

enum TasmeeError: Error {
    /// The session filled up, was cancelled or began before the seat could be taken.
    case seatUnavailable
    /// This needs an account, and none is attached yet.
    case notSignedIn
    /// No free peer code could be found.
    case codeUnavailable
}

/// Carries a listener into a stream's termination handler.
private final class ListenerBox: @unchecked Sendable {
    private let registration: any ListenerRegistration

    init(_ registration: any ListenerRegistration) {
        self.registration = registration
    }

    func remove() {
        registration.remove()
    }
}
