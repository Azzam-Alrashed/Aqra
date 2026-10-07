package com.azzamalrashed.aqra.tasmee

import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionStore
import java.security.SecureRandom

// The tasmee' side of the account as plain values, with no Firebase: teachers, their sessions, the seats booked in
// them, a student's copy of a booking, and the record of a tasmee' heard. Each reads itself from a Firestore
// document's fields (dates already turned into Moments) and writes itself back the same way, so every rule can be
// tested. The iOS app reads and writes the same documents; see backend/README.md for the collections.

/** A document's fields, with dates as [Moment]s (the store converts Firestore's timestamps both ways). */
typealias Document = Map<String, Any?>

private fun Document.string(key: String): String? = this[key] as? String
private fun Document.bool(key: String): Boolean? = this[key] as? Boolean
private fun Document.moment(key: String): Moment? = this[key] as? Moment
/** Firestore hands numbers back as Long or Double; either reads as a number. */
private fun Document.int(key: String): Int? = (this[key] as? Number)?.toInt()
private fun Document.ints(key: String): List<Int>? = (this[key] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }

/** A vetted teacher, as shown in the public list. */
data class Teacher(
    val id: String,
    val name: String,
    val city: String = "",
    /** One line about the teacher: their ijazah, their riwayah, their halaqah. */
    val line: String = "",
    val vetted: Boolean = true,
) {
    companion object {
        fun from(id: String, document: Document): Teacher? {
            val name = document.string("name") ?: return null
            return Teacher(id, name, document.string("city").orEmpty(), document.string("line").orEmpty(), document.bool("vetted") ?: false)
        }
    }

    val document: Document get() = mapOf("name" to name, "city" to city, "line" to line, "vetted" to vetted)

    /** The teacher's city and line, or null when they wrote neither. */
    val about: String? get() = listOf(city, line).filter { it.isNotEmpty() }.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

/** A tasmee' session a teacher holds, in person or by video, with a limited number of seats. */
data class TasmeeSession(
    val id: String,
    val teacherId: String,
    val teacherName: String,
    val startsAt: Moment,
    val kind: Kind = Kind.IN_PERSON,
    /** Where it's held, for a session in person; empty for a video session. */
    val place: String,
    /** The free seats, booked first come first served. */
    val seats: Int,
    val booked: Int = 0,
    val status: Status = Status.OPEN,
    val createdAt: Moment = Moment.now(),
    /** Seats won by bidding, beside the free ones (none when null). */
    val auction: Auction? = null,
) {
    enum class Status(val raw: String) { OPEN("open"), CANCELLED("cancelled") }

    /** A session's auctioned seats: they start free; once all are held, each new bid must beat the lowest. */
    data class Auction(
        val seats: Int,
        val minBid: Int,
        val closesAt: Moment,
        val state: State,
        /** Written by the server: the active bids, what the next bid must reach, and the seats won. */
        val bids: Int = 0,
        val floor: Int? = null,
        val won: Int = 0,
    ) {
        enum class State(val raw: String) { OPEN("open"), SETTLED("settled"), CANCELLED("cancelled"), REFUNDED("refunded") }

        fun isOpen(at: Moment = Moment.now()) = state == State.OPEN && at < closesAt
        /** What a new bid must reach now. */
        val nextAtLeast: Int get() = floor ?: minBid
    }

    /** In person, at a place; or by video, in the session's own call. */
    enum class Kind(val raw: String) { IN_PERSON("inPerson"), VIDEO("video") }

    companion object {
        fun from(id: String, document: Document): TasmeeSession? {
            val teacherId = document.string("teacherId") ?: return null
            val startsAt = document.moment("startsAt") ?: return null
            val seats = document.int("seats") ?: return null
            val status = Status.entries.firstOrNull { it.raw == document.string("status") } ?: return null
            val auctionSeats = document.int("auctionSeats") ?: 0
            val closesAt = document.moment("biddingClosesAt")
            val auction = if (auctionSeats > 0 && closesAt != null) {
                Auction(auctionSeats, document.int("minBid") ?: 0, closesAt,
                    Auction.State.entries.firstOrNull { it.raw == document.string("auctionState") } ?: Auction.State.OPEN,
                    document.int("auctionBids") ?: 0, document.int("auctionFloor"), document.int("auctionWon") ?: 0)
            } else {
                null
            }
            return TasmeeSession(
                id, teacherId, document.string("teacherName").orEmpty(), startsAt,
                Kind.entries.firstOrNull { it.raw == document.string("kind") } ?: Kind.IN_PERSON,
                document.string("place").orEmpty(), seats, document.int("booked") ?: 0, status,
                document.moment("createdAt") ?: Moment.DISTANT_PAST, auction,
            )
        }

        /** How long before a session its auction closes (the server's policy, mirrored). */
        const val BIDDING_CLOSES_BEFORE = 3 * 3_600.0
    }

    /** The fields the teacher writes; the server keeps the auction's own counts. */
    val document: Document get() = buildMap {
        put("teacherId", teacherId)
        put("teacherName", teacherName)
        put("startsAt", startsAt)
        put("place", place)
        put("seats", seats)
        put("booked", booked)
        put("kind", kind.raw)
        put("status", status.raw)
        put("createdAt", createdAt)
        auction?.let {
            put("auctionSeats", it.seats)
            put("minBid", it.minBid)
            put("biddingClosesAt", it.closesAt)
            put("auctionState", it.state.raw)
        }
    }

    /** The fields a teacher may change after creating it. */
    val editableDocument: Document get() = mapOf("startsAt" to startsAt, "place" to place, "seats" to seats)

    val seatsLeft: Int get() = (seats - booked).coerceAtLeast(0)
    val isFull: Boolean get() = booked >= seats

    /** Whether it can still be booked: open and not yet started. */
    fun isUpcoming(at: Moment = Moment.now()) = status == Status.OPEN && startsAt > at

    /** Whether it's worth showing: not cancelled, and not long over (a session is shown through its day). */
    fun isCurrent(at: Moment = Moment.now()) = status == Status.OPEN && startsAt > at + (-6 * 3_600.0)
}

/** A student's booked seat in a session, with what they've memorized so the teacher can choose what to hear. */
data class Seat(
    /** The student's uid. */
    val id: String,
    val name: String,
    val bookedAt: Moment = Moment.now(),
    val memorizedPages: Int,
    /** The juz' memorized in full, as the student's app describes them, or null when none is. */
    val juzSummary: String? = null,
    /** The credits paid for a seat won by bidding; null for a free seat. */
    val paid: Int? = null,
) {
    companion object {
        fun from(id: String, document: Document): Seat? {
            val name = document.string("name") ?: return null
            val bookedAt = document.moment("bookedAt") ?: return null
            return Seat(id, name, bookedAt, document.int("memorizedPages") ?: 0, document.string("juzSummary"), document.int("paid"))
        }
    }

    val document: Document get() = buildMap {
        put("name", name)
        put("bookedAt", bookedAt)
        put("memorizedPages", memorizedPages)
        juzSummary?.let { put("juzSummary", it) }
    }
}

/** A student's own copy of a session they booked, kept in their account so the home can show it. */
data class Booking(
    /** The session's id. */
    val id: String,
    val teacherId: String,
    val teacherName: String,
    val startsAt: Moment,
    val kind: TasmeeSession.Kind = TasmeeSession.Kind.IN_PERSON,
    val place: String,
) {
    constructor(session: TasmeeSession) : this(session.id, session.teacherId, session.teacherName, session.startsAt, session.kind, session.place)

    companion object {
        fun from(id: String, document: Document): Booking? {
            val teacherId = document.string("teacherId") ?: return null
            val startsAt = document.moment("startsAt") ?: return null
            return Booking(
                id, teacherId, document.string("teacherName").orEmpty(), startsAt,
                TasmeeSession.Kind.entries.firstOrNull { it.raw == document.string("kind") } ?: TasmeeSession.Kind.IN_PERSON,
                document.string("place").orEmpty(),
            )
        }
    }

    val document: Document get() = mapOf(
        "teacherId" to teacherId, "teacherName" to teacherName, "startsAt" to startsAt, "kind" to kind.raw, "place" to place,
    )
}

/** A bid for an auctioned seat, written by the server: who, how much, and where it stands. */
data class Bid(
    /** The bidder's uid. */
    val id: String,
    val name: String,
    val amount: Int,
    val at: Moment,
    val status: Status,
    val memorizedPages: Int = 0,
    val juzSummary: String? = null,
) {
    enum class Status(val raw: String) { ACTIVE("active"), OUTBID("outbid"), WON("won"), RELEASED("released") }

    companion object {
        fun from(id: String, document: Document): Bid? {
            val amount = document.int("amount") ?: return null
            val status = Status.entries.firstOrNull { it.raw == document.string("status") } ?: return null
            return Bid(id, document.string("name").orEmpty(), amount, document.moment("at") ?: Moment.DISTANT_PAST, status,
                document.int("memorizedPages") ?: 0, document.string("juzSummary"))
        }

        /** Bids best first: those holding or winning a seat, then by amount, then the earlier. */
        fun ranked(bids: List<Bid>): List<Bid> = bids.sortedWith(
            compareBy<Bid> { if (it.status == Status.ACTIVE || it.status == Status.WON) 0 else 1 }.thenByDescending { it.amount }.thenBy { it.at },
        )
    }
}

/**
 * How a teacher classifies a stumble. A plain tap records a memorization error; the rest are chosen by pressing and
 * holding the ayah.
 */
enum class MistakeType(val raw: String) {
    /** A wrong or missing word. */
    MEMORIZATION("memorization"),
    /** The student couldn't go on. */
    FORGETTING("forgetting"),
    /** The listener had to prompt (تلقين). */
    PROMPTING("prompting"),
    /** The student hesitated before getting it right. */
    HESITATION("hesitation"),
    /** A clear error in the Arabic (لحن جلي). */
    LAHN("lahn"),
    /** A tajweed rule not observed. */
    TAJWEED("tajweed"),
}

/** A stumble with its type. */
data class Mistake(val ayah: Int, val type: MistakeType)

/**
 * A tasmee' a student recited to a teacher or a peer: the pages heard and the ayat stumbled on. The listener writes
 * it into the student's account; the student's app applies it to the progress on the device and marks it applied.
 */
data class TasmeeRecord(
    val id: String,
    val kind: Kind = Kind.SHEIKH,
    /** The listener: the teacher, or the peer. */
    val teacherId: String,
    val teacherName: String,
    /** The session it was heard in, or the peer request's code. */
    val sessionId: String,
    val at: Moment,
    val pages: List<Int>,
    val stumbles: List<Int>,
    /** The stumbles' types, where the listener gave them; a stumble without one is a memorization error. */
    val mistakes: List<Mistake> = emptyList(),
    val test: StageTest? = null,
    val appliedAt: Moment? = null,
) {
    /** Who heard it: a vetted teacher in one of their sessions, or a peer with the student's code. */
    enum class Kind(val raw: String) { SHEIKH("sheikh"), PEER("peer") }

    /** A teacher's test of a stage: it counts when its mistakes are within the allowed number per page heard. */
    data class StageTest(val stage: Int, val allowedMistakesPerPage: Int)

    companion object {
        fun from(id: String, document: Document): TasmeeRecord? {
            val teacherId = document.string("teacherId") ?: return null
            val sessionId = document.string("sessionId") ?: return null
            val at = document.moment("at") ?: return null
            val pages = document.ints("pages") ?: return null
            val stumbles = document.ints("stumbles") ?: return null
            val mistakes = (document["mistakes"] as? List<*>).orEmpty().mapNotNull { entry ->
                val map = entry as? Map<*, *> ?: return@mapNotNull null
                val ayah = (map["ayah"] as? Number)?.toInt() ?: return@mapNotNull null
                val type = MistakeType.entries.firstOrNull { it.raw == map["type"] } ?: return@mapNotNull null
                Mistake(ayah, type)
            }
            val test = (document["test"] as? Map<*, *>)?.let { map ->
                val stage = (map["stage"] as? Number)?.toInt() ?: return@let null
                val allowed = (map["allowedMistakesPerPage"] as? Number)?.toInt() ?: return@let null
                StageTest(stage, allowed)
            }
            return TasmeeRecord(
                id, Kind.entries.firstOrNull { it.raw == document.string("kind") } ?: Kind.SHEIKH, teacherId,
                document.string("teacherName").orEmpty(), sessionId, at, pages, stumbles, mistakes, test, document.moment("appliedAt"),
            )
        }
    }

    /** The fields as written: `appliedAt` is null, not missing, so the student's app can tell it's waiting. */
    val document: Document get() = buildMap {
        put("kind", kind.raw)
        put("teacherId", teacherId)
        put("teacherName", teacherName)
        put("sessionId", sessionId)
        put("at", at)
        put("pages", pages)
        put("stumbles", stumbles)
        put("appliedAt", appliedAt)
        if (mistakes.isNotEmpty()) put("mistakes", mistakes.map { mapOf("ayah" to it.ayah, "type" to it.type.raw) })
        test?.let { put("test", mapOf("stage" to it.stage, "allowedMistakesPerPage" to it.allowedMistakesPerPage)) }
    }

    /** Each stumble's type: the one the listener chose, or a memorization error. */
    fun mistakeType(ayah: Int): MistakeType = mistakes.firstOrNull { it.ayah == ayah }?.type ?: MistakeType.MEMORIZATION

    /** Whether a stage test passed: no more mistakes than allowed per page heard. */
    val passesTest: Boolean? get() = test?.let { stumbles.size <= it.allowedMistakesPerPage * pages.toSet().size.coerceAtLeast(1) }
}

/** How a tasmee' changes the progress on the student's device. */
object TasmeeApply {
    /**
     * Each page heard is recorded as a revision of its memorized ayat, by a sheikh or a peer: the stumbled ones
     * weaken, the rest grow by the listener's weight. Only a sheikh's tasmee' verifies: the clean ayat get the mark
     * and the stumbled ones lose it. Ayat the student never marked as memorized are left alone: the student owns the
     * map of what they know. [pageAyahs] gives the ayat of a page (from the Mushaf).
     */
    fun apply(record: TasmeeRecord, memorization: MemorizationStore, revision: RevisionStore, pageAyahs: (Int) -> IntRange) {
        val stumbles = record.stumbles.toSet()
        for (page in record.pages.toSet().sorted()) {
            if (page !in 1..MushafStore.PAGE_COUNT) continue
            val memorized = pageAyahs(page).filter(memorization::isMemorized)
            if (memorized.isEmpty()) continue
            val pageStumbles = stumbles.intersect(memorized.toSet())
            revision.record(
                page, memorized, pageStumbles,
                if (record.kind == TasmeeRecord.Kind.PEER) RevisionRecord.Source.PEER else RevisionRecord.Source.SHEIKH,
                memorization, now = record.at,
            )
            if (record.kind == TasmeeRecord.Kind.SHEIKH) memorization.verify(memorized, except = pageStumbles)
        }
    }
}

/**
 * A student's invitation to a friend to hear their tasmee': a short code, shown as text and as a QR code, valid for
 * half an hour. The friend's app writes what they heard into the student's account, as a peer's tasmee'.
 */
data class PeerRequest(
    /** The code: six characters that can't be mistaken for one another. */
    val id: String,
    val studentUid: String,
    /** The student's name as shown to the friend, or null for an anonymous student. */
    val studentName: String?,
    /** Where the friend's Mushaf opens: the student's next page to revise. */
    val startPage: Int? = null,
    val createdAt: Moment = Moment.now(),
    val expiresAt: Moment = Moment.now() + LIFETIME,
) {
    companion object {
        const val ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        const val CODE_LENGTH = 6
        /** How long a code stays valid. The rules accept at most 31 minutes. */
        const val LIFETIME = 30 * 60.0

        private val random = SecureRandom()

        fun from(id: String, document: Document): PeerRequest? {
            val studentUid = document.string("studentUid") ?: return null
            val createdAt = document.moment("createdAt") ?: return null
            val expiresAt = document.moment("expiresAt") ?: return null
            return PeerRequest(id, studentUid, document.string("studentName"), document.int("startPage"), createdAt, expiresAt)
        }

        fun randomCode(): String = String(CharArray(CODE_LENGTH) { ALPHABET[random.nextInt(ALPHABET.length)] })

        /** A code as typed: upper-cased, without spaces or dashes. */
        fun normalize(typed: String): String = typed.uppercase().filter { !it.isWhitespace() && it != '-' }

        fun isWellFormed(code: String): Boolean = code.length == CODE_LENGTH && code.all { it in ALPHABET }

        /** The code in a link (`aqra://peer/CODE`), if it's one. */
        fun code(host: String?, lastPathSegment: String?): String? {
            if (host != "peer") return null
            val code = normalize(lastPathSegment.orEmpty())
            return if (isWellFormed(code)) code else null
        }

        fun code(link: String): String? {
            val match = Regex("^aqra://([^/]+)/([^/?#]+)").find(link) ?: return null
            return code(match.groupValues[1], match.groupValues[2])
        }
    }

    val document: Document get() = buildMap {
        put("studentUid", studentUid)
        put("createdAt", createdAt)
        put("expiresAt", expiresAt)
        studentName?.let { put("studentName", it) }
        startPage?.let { put("startPage", it) }
    }

    fun isValid(at: Moment = Moment.now()) = expiresAt > at

    /** The link a QR code carries: the camera opens it in Aqra. */
    val link: String get() = "aqra://peer/$id"
}

/**
 * A teacher's file on one student: kept by the teacher, from what they themselves heard. It never holds the student's
 * own progress, which only the student's app reads.
 */
data class StudentFile(
    /** The student's uid. */
    val id: String,
    val name: String,
    val lastHeardAt: Moment,
    /** The teacher's private notes. */
    val notes: String = "",
) {
    companion object {
        fun from(id: String, document: Document): StudentFile? {
            val name = document.string("name") ?: return null
            return StudentFile(id, name, document.moment("lastHeardAt") ?: Moment.DISTANT_PAST, document.string("notes").orEmpty())
        }
    }
}

/**
 * An application to teach on Aqra: who the teacher is, from whom they hold their ijazah, and a copy of it. The vetting
 * team reviews it, interviews the teacher, and approves or declines it; only an administrator can make a teacher.
 */
data class TeacherApplication(
    /** The applicant's uid. */
    val id: String,
    val name: String,
    val city: String = "",
    /** One line students will read: the ijazah, the halaqah, the experience. */
    val line: String = "",
    val riwayah: String = "حفص عن عاصم",
    /** The sheikh who granted the ijazah. */
    val ijazahFrom: String = "",
    /** The chain, the date, anything else about it. */
    val ijazahDetails: String = "",
    /** How the team can reach the applicant for the interview: a phone number or an email. */
    val contact: String = "",
    /** Copies of the ijazah in the account's storage. */
    val files: List<String> = emptyList(),
    val status: Status = Status.SUBMITTED,
    /** The team's note: what's next, or why it was declined. */
    val note: String = "",
    val createdAt: Moment = Moment.now(),
    val updatedAt: Moment = Moment.now(),
) {
    enum class Status(val raw: String) {
        /** Waiting for review; the applicant can still change it. */
        SUBMITTED("submitted"),
        /** Reviewed; the team will be in touch for the interview. */
        INTERVIEW("interview"),
        APPROVED("approved"),
        REJECTED("rejected"),
    }

    companion object {
        /** The largest upload accepted, as the storage rules say. */
        const val MAX_FILE_SIZE = 10 * 1024 * 1024

        fun filePath(uid: String, name: String) = "ijazahs/$uid/$name"

        fun from(id: String, document: Document): TeacherApplication? {
            val name = document.string("name") ?: return null
            val status = Status.entries.firstOrNull { it.raw == document.string("status") } ?: return null
            return TeacherApplication(
                id, name, document.string("city").orEmpty(), document.string("line").orEmpty(), document.string("riwayah").orEmpty(),
                document.string("ijazahFrom").orEmpty(), document.string("ijazahDetails").orEmpty(), document.string("contact").orEmpty(),
                (document["files"] as? List<*>)?.filterIsInstance<String>().orEmpty(), status, document.string("note").orEmpty(),
                document.moment("createdAt") ?: Moment.DISTANT_PAST, document.moment("updatedAt") ?: Moment.DISTANT_PAST,
            )
        }
    }

    /** The fields the applicant writes. */
    val document: Document get() = mapOf(
        "name" to name, "city" to city, "line" to line, "riwayah" to riwayah, "ijazahFrom" to ijazahFrom,
        "ijazahDetails" to ijazahDetails, "contact" to contact, "files" to files, "status" to status.raw, "note" to note,
        "createdAt" to createdAt, "updatedAt" to updatedAt,
    )

    /** Whether the applicant has given what the team needs to review it. */
    val isComplete: Boolean get() = listOf(name, city, riwayah, ijazahFrom, contact).all { it.isNotBlank() } && files.isNotEmpty()

    val canEdit: Boolean get() = status == Status.SUBMITTED

    fun trimmed() = copy(
        name = name.trim(), city = city.trim(), line = line.trim(), riwayah = riwayah.trim(), ijazahFrom = ijazahFrom.trim(),
        ijazahDetails = ijazahDetails.trim(), contact = contact.trim(),
    )
}
