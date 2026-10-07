package com.azzamalrashed.aqra.tasmee

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.account.Problem
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.Preferences
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionStore
import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.SetOptions
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import java.util.Date
import java.util.UUID

/**
 * Teachers and tasmee' sessions, through the account. For a student: the vetted teachers, the sessions booked, and
 * the tasmee' records teachers and peers write into the account, which are applied to the progress on this device as
 * they arrive. For a teacher: their own sessions, the students in each, and recording what they heard.
 *
 * The teacher never reads a student's progress. What the teacher heard goes into the student's account as a record,
 * and the student's own app applies it (see [TasmeeApply]) and marks it applied, so the device's copy stays the one
 * the app works from. The documents are the iOS app's; see backend/README.md for the collections.
 */
class TasmeeStore(
    private val memorization: MemorizationStore,
    private val revision: RevisionStore,
    private val prefs: Preferences,
) {
    /** This account's teacher profile, when it has one (vetted or not). */
    var teacherProfile: Teacher? by mutableStateOf(null)
        private set
    val isTeacher: Boolean get() = teacherProfile?.vetted == true
    /** The sessions this student booked, soonest first. */
    var bookings: List<Booking> by mutableStateOf(emptyList())
        private set
    /** Those sessions as they are now, by id: a teacher may change or cancel one after it was booked. */
    var bookedSessions: Map<String, TasmeeSession> by mutableStateOf(emptyMap())
        private set
    /** A teacher's own sessions still to come, soonest first. */
    var mySessions: List<TasmeeSession> by mutableStateOf(emptyList())
        private set
    /** The vetted teachers, by name. */
    var teachers: List<Teacher> by mutableStateOf(emptyList())
        private set
    var isLoadingTeachers by mutableStateOf(false)
        private set
    /** Every tasmee' record in the account, newest first: what teachers and peers heard. */
    var history: List<TasmeeRecord> by mutableStateOf(emptyList())
        private set
    /** A teacher's students: everyone they've heard, most recently heard first. */
    var myStudents: List<StudentFile> by mutableStateOf(emptyList())
        private set
    /** The account's application to teach, if it made one. */
    var application: TeacherApplication? by mutableStateOf(null)
        private set
    var problem: Problem? by mutableStateOf(null)

    /** Called after each tasmee' is applied on this device (a teacher's stage test counts toward its stage). */
    var onApplied: ((TasmeeRecord) -> Unit)? = null

    /** The Mushaf, once loaded. A tasmee' can only be applied with it (which ayat each page holds). */
    var mushaf: MushafStore? = null
        set(value) {
            field = value
            applyPending()
        }

    /** The account followed, or null before one is attached. */
    var uid: String? = null
        private set
    private val listeners = ArrayList<ListenerRegistration>()
    private var sessionsListener: ListenerRegistration? = null
    private var studentsListener: ListenerRegistration? = null
    private var bookedListener: ListenerRegistration? = null
    private var bookedIds: List<String> = emptyList()
    /** Records the account holds that haven't been applied on this device yet. */
    private var pending: List<TasmeeRecord> = emptyList()

    val database: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    fun user(uid: String): DocumentReference = database.collection("users").document(uid)

    companion object {
        /** Firestore hands dates back as Timestamps, also inside maps and lists; the values want Moments. */
        fun dated(data: Map<String, Any?>?): Document = data.orEmpty().mapValues { undated(it.value) }

        private fun undated(value: Any?): Any? = when (value) {
            is Timestamp -> Moment.ofEpochSeconds(value.seconds + value.nanoseconds / 1e9)
            is Map<*, *> -> value.entries.associate { (key, item) -> key.toString() to undated(item) }
            is List<*> -> value.map(::undated)
            else -> value
        }

        /** The other way: Moments become Timestamps, for writing. */
        fun stamped(document: Document): Map<String, Any?> = document.mapValues { stampedValue(it.value) }

        private fun stampedValue(value: Any?): Any? = when (value) {
            is Moment -> Timestamp(Date(value.epochMillis))
            is Map<*, *> -> value.entries.associate { (key, item) -> key.toString() to stampedValue(item) }
            is List<*> -> value.map(::stampedValue)
            else -> value
        }

        /** Deletes documents in batches Firestore accepts. */
        suspend fun delete(references: List<DocumentReference>, database: FirebaseFirestore) {
            for (chunk in references.chunked(400)) {
                val batch = database.batch()
                chunk.forEach(batch::delete)
                batch.commit().await()
            }
        }
    }

    // MARK: - The account in use

    /** Follows the account: its teacher profile, its bookings, and the tasmee' records waiting to be applied. */
    fun attach(uid: String) {
        if (uid == this.uid) return
        detach()
        this.uid = uid
        val user = user(uid)

        listeners += database.collection("teachers").document(uid).addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            teacherProfile = snapshot.data?.let { Teacher.from(uid, dated(it)) }
            watchMySessions()
            watchMyStudents()
        }
        listeners += database.collection("teacherApplications").document(uid).addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            application = snapshot.data?.let { TeacherApplication.from(uid, dated(it)) }
        }
        listeners += user.collection("bookings").addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            bookings = snapshot.documents.mapNotNull { Booking.from(it.id, dated(it.data)) }.sortedBy { it.startsAt }
            watchBookedSessions()
        }
        // Every record, for the history; those not yet applied are applied on this device as they arrive.
        listeners += user.collection("tasmee").orderBy("at", Query.Direction.DESCENDING).limit(200).addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            val records = snapshot.documents.mapNotNull { TasmeeRecord.from(it.id, dated(it.data)) }
            history = records
            pending = records.filter { it.appliedAt == null }.sortedBy { it.at }
            applyPending()
        }
    }

    /** Stops following the account, before signing out or deleting it. */
    fun detach() {
        listeners.forEach { it.remove() }
        listeners.clear()
        sessionsListener?.remove(); sessionsListener = null
        studentsListener?.remove(); studentsListener = null
        bookedListener?.remove(); bookedListener = null
        bookedIds = emptyList()
        uid = null
        teacherProfile = null
        bookings = emptyList()
        bookedSessions = emptyMap()
        mySessions = emptyList()
        myStudents = emptyList()
        history = emptyList()
        application = null
        pending = emptyList()
        problem = null
    }

    private fun watchMySessions() {
        val uid = uid
        if (uid == null || !isTeacher) {
            sessionsListener?.remove(); sessionsListener = null
            mySessions = emptyList()
            return
        }
        if (sessionsListener != null) return
        sessionsListener = database.collection("sessions").whereEqualTo("teacherId", uid).addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            mySessions = snapshot.documents.mapNotNull { TasmeeSession.from(it.id, dated(it.data)) }.filter { it.isCurrent() }.sortedBy { it.startsAt }
        }
    }

    private fun watchMyStudents() {
        val uid = uid
        if (uid == null || !isTeacher) {
            studentsListener?.remove(); studentsListener = null
            myStudents = emptyList()
            return
        }
        if (studentsListener != null) return
        studentsListener = database.collection("teachers").document(uid).collection("students").addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            myStudents = snapshot.documents.mapNotNull { StudentFile.from(it.id, dated(it.data)) }.sortedByDescending { it.lastHeardAt }
        }
    }

    private fun watchBookedSessions() {
        val ids = bookings.map { it.id }.take(30)
        if (ids == bookedIds) return
        bookedIds = ids
        bookedListener?.remove(); bookedListener = null
        if (ids.isEmpty()) {
            bookedSessions = emptyMap()
            return
        }
        bookedListener = database.collection("sessions").whereIn(FieldPath.documentId(), ids).addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            bookedSessions = snapshot.documents.mapNotNull { TasmeeSession.from(it.id, dated(it.data)) }.associateBy { it.id }
        }
    }

    // MARK: - Bookings

    /** The booked session as it is now, or null until it's heard from (or when the teacher deleted it). */
    fun session(booking: Booking): TasmeeSession? = bookedSessions[booking.id]

    fun hasBooked(session: TasmeeSession): Boolean = bookings.any { it.id == session.id }

    /**
     * The bookings still ahead (through the session's day), soonest first; cancelled ones stay until then, so the
     * student learns of the cancellation.
     */
    val upcomingBookings: List<Booking>
        get() {
            val cutoff = Moment.now() + (-6 * 3_600.0)
            return bookings.filter { (session(it)?.startsAt ?: it.startsAt) > cutoff }
        }

    val nextBooking: Booking? get() = upcomingBookings.firstOrNull()

    // MARK: - Teachers and their sessions

    suspend fun loadTeachers() {
        if (uid == null) return
        isLoadingTeachers = teachers.isEmpty()
        try {
            val snapshot = database.collection("teachers").whereEqualTo("vetted", true).get().await()
            teachers = snapshot.documents.mapNotNull { Teacher.from(it.id, dated(it.data)) }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
            problem = null
        } catch (error: Exception) {
            problem = AccountStore.problem(error)
        } finally {
            isLoadingTeachers = false
        }
    }

    /** A teacher's sessions still open to booking, soonest first. */
    suspend fun upcomingSessions(teacherId: String): List<TasmeeSession> {
        val snapshot = database.collection("sessions").whereEqualTo("teacherId", teacherId).get().await()
        return snapshot.documents.mapNotNull { TasmeeSession.from(it.id, dated(it.data)) }.filter { it.isUpcoming() }.sortedBy { it.startsAt }
    }

    /**
     * Books a seat: the seat, this student's copy of the session and the seat count, in one transaction, so a session
     * never takes more students than it has seats.
     */
    suspend fun book(session: TasmeeSession, name: String, memorizedPages: Int, juzSummary: String?) {
        val uid = uid ?: return
        val seat = Seat(uid, name, memorizedPages = memorizedPages, juzSummary = juzSummary)
        val sessionRef = database.collection("sessions").document(session.id)
        val seatRef = sessionRef.collection("seats").document(uid)
        val bookingRef = user(uid).collection("bookings").document(session.id)
        database.runTransaction { transaction ->
            val live = transaction.get(sessionRef).data?.let { TasmeeSession.from(session.id, dated(it)) }
            if (live == null || !live.isUpcoming() || live.isFull) throw TasmeeError.SeatUnavailable
            transaction.set(seatRef, stamped(seat.document))
            transaction.set(bookingRef, stamped(Booking(session).document))
            transaction.update(sessionRef, "booked", FieldValue.increment(1))
            null
        }.await()
    }

    /** Gives a seat back: removes the seat and this student's copy, and lowers the count (unless the session is gone). */
    suspend fun cancelBooking(booking: Booking) {
        val uid = uid ?: return
        val sessionRef = database.collection("sessions").document(booking.id)
        val seatRef = sessionRef.collection("seats").document(uid)
        val bookingRef = user(uid).collection("bookings").document(booking.id)
        database.runTransaction { transaction ->
            val session = transaction.get(sessionRef)
            val seat = transaction.get(seatRef)
            if (session.exists() && seat.exists()) transaction.update(sessionRef, "booked", FieldValue.increment(-1))
            if (seat.exists()) transaction.delete(seatRef)
            transaction.delete(bookingRef)
            null
        }.await()
    }

    // MARK: - A teacher's side

    // A teacher's writes aren't waited for: Firestore keeps them while offline (a halaqah's mosque may have no
    // signal) and sends them when it can. What's refused is reported after the fact.

    fun createSession(startsAt: Moment, kind: TasmeeSession.Kind, place: String, seats: Int, auctionSeats: Int = 0, minBid: Int = 0) {
        val uid = uid ?: return
        val profile = teacherProfile ?: return
        val reference = database.collection("sessions").document()
        val auction = if (auctionSeats > 0) {
            TasmeeSession.Auction(auctionSeats, minBid, startsAt + (-TasmeeSession.BIDDING_CLOSES_BEFORE), TasmeeSession.Auction.State.OPEN)
        } else {
            null
        }
        val session = TasmeeSession(reference.id, uid, profile.name, startsAt, kind, if (kind == TasmeeSession.Kind.VIDEO) "" else place, seats,
            auction = auction)
        reference.set(stamped(session.document)).addOnFailureListener(::report)
    }

    /** A session as it changes. */
    fun session(id: String): Flow<TasmeeSession?> = callbackFlow {
        val registration = database.collection("sessions").document(id).addSnapshotListener { snapshot, _ ->
            trySend(snapshot?.data?.let { TasmeeSession.from(id, dated(it)) })
        }
        awaitClose { registration.remove() }
    }

    /** This student's bid in a session, as it stands. */
    fun myBid(sessionId: String): Flow<Bid?> = callbackFlow {
        val uid = uid ?: run { close(); return@callbackFlow }
        val registration = database.collection("sessions").document(sessionId).collection("bids").document(uid)
            .addSnapshotListener { snapshot, _ -> trySend(snapshot?.data?.let { Bid.from(uid, dated(it)) }) }
        awaitClose { registration.remove() }
    }

    /** Every bid in one of the teacher's sessions, best first. */
    fun bids(sessionId: String): Flow<List<Bid>> = callbackFlow {
        val registration = database.collection("sessions").document(sessionId).collection("bids").addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            trySend(Bid.ranked(snapshot.documents.mapNotNull { Bid.from(it.id, dated(it.data)) }))
        }
        awaitClose { registration.remove() }
    }

    /** Changes a session's time, place or seats. Students who booked see the change on their booking. */
    fun updateSession(session: TasmeeSession) {
        database.collection("sessions").document(session.id).update(stamped(session.editableDocument)).addOnFailureListener(::report)
    }

    fun cancelSession(session: TasmeeSession) {
        database.collection("sessions").document(session.id).update("status", TasmeeSession.Status.CANCELLED.raw).addOnFailureListener(::report)
    }

    /** Changes the teacher's name, city and line, as students see them. */
    fun updateTeacherProfile(name: String, city: String, line: String) {
        val uid = uid ?: return
        database.collection("teachers").document(uid).update(mapOf("name" to name, "city" to city, "line" to line)).addOnFailureListener(::report)
    }

    /** Keeps a write's failure, once the account answers. */
    private fun report(error: Exception) {
        problem = AccountStore.problem(error)
    }

    /** A session's booked seats, as they change. */
    fun seats(sessionId: String): Flow<List<Seat>> = callbackFlow {
        val registration = database.collection("sessions").document(sessionId).collection("seats").addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            trySend(snapshot.documents.mapNotNull { Seat.from(it.id, dated(it.data)) }.sortedBy { it.bookedAt })
        }
        awaitClose { registration.remove() }
    }

    /** What the teacher heard from one student, newest first, as it changes. */
    fun records(studentUid: String): Flow<List<TasmeeRecord>> = callbackFlow {
        val uid = uid ?: run { close(); return@callbackFlow }
        val registration = database.collection("teachers").document(uid).collection("students").document(studentUid)
            .collection("records").orderBy("at", Query.Direction.DESCENDING).limit(100)
            .addSnapshotListener { snapshot, _ ->
                snapshot ?: return@addSnapshotListener
                trySend(snapshot.documents.mapNotNull { TasmeeRecord.from(it.id, dated(it.data)) })
            }
        awaitClose { registration.remove() }
    }

    /** The teacher's private notes on a student. */
    fun saveNotes(notes: String, studentUid: String) {
        val uid = uid ?: return
        database.collection("teachers").document(uid).collection("students").document(studentUid)
            .set(mapOf("notes" to notes), SetOptions.merge()).addOnFailureListener(::report)
    }

    /**
     * Records what the teacher heard from a student, into the student's account; the student's app applies it. The
     * teacher keeps their own copy in the student's file, to look back at what they heard.
     */
    fun recordTasmee(seat: Seat, session: TasmeeSession, pages: List<Int>, stumbles: List<Int>, mistakes: List<Mistake> = emptyList(),
                     test: TasmeeRecord.StageTest? = null, at: Moment = Moment.now()) {
        val uid = uid ?: return
        val profile = teacherProfile ?: return
        val reference = user(seat.id).collection("tasmee").document()
        val record = TasmeeRecord(reference.id, teacherId = uid, teacherName = profile.name, sessionId = session.id, at = at,
            pages = pages.sorted(), stumbles = stumbles.sorted(), mistakes = mistakes.filter { it.type != MistakeType.MEMORIZATION }, test = test)
        reference.set(stamped(record.document)).addOnFailureListener(::report)
        val file = database.collection("teachers").document(uid).collection("students").document(seat.id)
        file.set(stamped(mapOf("name" to seat.name, "lastHeardAt" to at)), SetOptions.merge()).addOnFailureListener(::report)
        file.collection("records").document(record.id).set(stamped(record.document - "appliedAt")).addOnFailureListener(::report)
    }

    // MARK: - Applying what teachers heard

    /** Applies the records waiting, once the Mushaf is there, and marks each applied in the account. */
    private fun applyPending() {
        val mushaf = mushaf ?: return
        val uid = uid ?: return
        if (pending.isEmpty()) return
        val applied = prefs.appliedTasmee.toMutableList()
        for (record in pending) {
            if (record.id in applied) continue
            TasmeeApply.apply(record, memorization, revision) { mushaf.page(it).ayahs }
            applied += record.id
            onApplied?.invoke(record)
            // A client date, not a server timestamp: a pending server timestamp reads as null here and the record
            // would come round again.
            user(uid).collection("tasmee").document(record.id).update("appliedAt", Timestamp.now())
        }
        pending = emptyList()
        prefs.appliedTasmee = applied.takeLast(200)
    }

    // MARK: - Friends

    /** Creates a peer request for this student. Codes are random; if one is taken, another is tried. */
    suspend fun createPeerRequest(studentName: String?, startPage: Int?): PeerRequest {
        val uid = uid ?: throw TasmeeError.NotSignedIn
        repeat(5) {
            val request = PeerRequest(PeerRequest.randomCode(), uid, studentName, startPage)
            try {
                database.collection("peerRequests").document(request.id).set(stamped(request.document)).await()
                return request
            } catch (error: FirebaseFirestoreException) {
                // The code exists already (the rules refuse to overwrite it); try another.
                if (error.code != FirebaseFirestoreException.Code.PERMISSION_DENIED) throw error
            }
        }
        throw TasmeeError.CodeUnavailable
    }

    /** The request behind a code, if it exists and is still valid. */
    suspend fun peerRequest(code: String): PeerRequest? {
        val snapshot = database.collection("peerRequests").document(code).get().await()
        return snapshot.data?.let { PeerRequest.from(code, dated(it)) }?.takeIf { it.isValid() }
    }

    /**
     * Writes what this user heard from a friend into the friend's account; the friend's app applies it as a peer's
     * tasmee'. Queued while offline.
     */
    fun recordPeerTasmee(request: PeerRequest, listenerName: String?, pages: List<Int>, stumbles: List<Int>, mistakes: List<Mistake>) {
        val uid = uid ?: return
        val reference = user(request.studentUid).collection("tasmee").document()
        val record = TasmeeRecord(reference.id, TasmeeRecord.Kind.PEER, uid, listenerName.orEmpty(), request.id, Moment.now(),
            pages.sorted(), stumbles.sorted(), mistakes.filter { it.type != MistakeType.MEMORIZATION })
        reference.set(stamped(record.document)).addOnFailureListener(::report)
    }

    // MARK: - Teaching

    /** Sends the application, or changes it while it's still waiting for review. Firestore keeps it while offline. */
    fun submit(application: TeacherApplication) {
        val uid = uid ?: return
        val reference = database.collection("teacherApplications").document(uid)
        val updated = application.copy(status = TeacherApplication.Status.SUBMITTED, updatedAt = Moment.now())
        if (this.application == null) {
            reference.set(stamped(updated.document)).addOnFailureListener(::report)
        } else {
            reference.update(stamped(updated.document - setOf("status", "note", "createdAt"))).addOnFailureListener(::report)
        }
    }

    /** Uploads a copy of the ijazah and returns its path. [contentType] is `image/…` or `application/pdf`. */
    suspend fun uploadIjazah(data: ByteArray, contentType: String): String {
        val uid = uid ?: throw TasmeeError.NotSignedIn
        val ext = when (contentType) { "application/pdf" -> "pdf"; "image/png" -> "png"; else -> "jpg" }
        val path = TeacherApplication.filePath(uid, "${UUID.randomUUID().toString().uppercase()}.$ext")
        FirebaseStorage.getInstance().reference.child(path).putBytes(data, StorageMetadata.Builder().setContentType(contentType).build()).await()
        return path
    }

    /** Withdraws an application that is still waiting, with its uploads. */
    suspend fun withdrawApplication() {
        val uid = uid ?: return
        deleteFiles(uid)
        runCatching { database.collection("teacherApplications").document(uid).delete().await() }
    }

    /** Lets go of every upload the account made, as far as the storage can be reached. */
    private suspend fun deleteFiles(uid: String) {
        runCatching {
            val listing = FirebaseStorage.getInstance().reference.child("ijazahs/$uid").listAll().await()
            for (item in listing.items) runCatching { item.delete().await() }
        }
    }

    // MARK: - Deleting

    /**
     * Deletes what the account holds of the student's tasmee': bookings (giving the seats back), records and the inbox;
     * and of a teacher's: the files they kept on their students, and their application with its uploads.
     */
    suspend fun deleteAccountData(uid: String) {
        val user = user(uid)
        // Each booking goes in one write with its seat and the seat count, as the rules require.
        for (booking in user.collection("bookings").get().await().documents) {
            val batch = database.batch()
            val session = database.collection("sessions").document(booking.id)
            val seat = session.collection("seats").document(uid)
            if (seat.get().await().exists()) {
                batch.delete(seat)
                if (session.get().await().exists()) batch.update(session, "booked", FieldValue.increment(-1))
            }
            batch.delete(booking.reference)
            batch.commit().await()
        }
        val references = ArrayList<DocumentReference>()
        references += user.collection("tasmee").get().await().documents.map { it.reference }
        references += user.collection("inbox").get().await().documents.map { it.reference }
        for (student in database.collection("teachers").document(uid).collection("students").get().await().documents) {
            references += student.reference.collection("records").get().await().documents.map { it.reference }
            references += student.reference
        }
        // Uploads are let go of even if the storage can't be reached: the account's deletion mustn't hang on them.
        deleteFiles(uid)
        references += database.collection("teacherApplications").document(uid)
        delete(references, database)
    }
}

sealed class TasmeeError(message: String) : Exception(message) {
    /** The session filled up, was cancelled or began before the seat could be taken. */
    data object SeatUnavailable : TasmeeError("The seat isn't available")
    /** This needs an account, and none is attached yet. */
    data object NotSignedIn : TasmeeError("Not signed in")
    /** No free peer code could be found. */
    data object CodeUnavailable : TasmeeError("No code available")
}
