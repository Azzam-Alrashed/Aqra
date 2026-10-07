package com.azzamalrashed.aqra.social

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.account.AccountStore
import com.azzamalrashed.aqra.account.Problem
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.tasmee.Document
import com.azzamalrashed.aqra.tasmee.PeerRequest
import com.azzamalrashed.aqra.tasmee.TasmeeError
import com.azzamalrashed.aqra.tasmee.TasmeeStore
import com.azzamalrashed.aqra.tasmee.TasmeeStore.Companion.dated
import com.azzamalrashed.aqra.tasmee.TasmeeStore.Companion.stamped
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.ListenerRegistration
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import java.text.Collator
import java.time.ZoneId

// Friends and competitions as plain values, with no Firebase: each reads itself from a Firestore document's fields
// (dates already turned into Moments) and writes itself back the same way, so every rule can be tested. The iOS app
// reads and writes the same documents; see backend/README.md for the collections.

/** An invitation to be friends: a short code (and link) valid for a week. */
data class FriendInvite(
    /** The code: six characters from the same clear alphabet as a peer's tasmee' code. */
    val id: String,
    val ownerUid: String,
    val ownerName: String,
    val createdAt: Moment = Moment.now(),
    val expiresAt: Moment = Moment.now() + LIFETIME,
) {
    companion object {
        const val LIFETIME = 7 * 86_400.0

        fun from(id: String, document: Document): FriendInvite? {
            val ownerUid = document["ownerUid"] as? String ?: return null
            val expiresAt = document["expiresAt"] as? Moment ?: return null
            return FriendInvite(id, ownerUid, document["ownerName"] as? String ?: "", document["createdAt"] as? Moment ?: Moment.DISTANT_PAST, expiresAt)
        }
    }

    val document: Document get() = mapOf("ownerUid" to ownerUid, "ownerName" to ownerName, "createdAt" to createdAt, "expiresAt" to expiresAt)

    fun isValid(at: Moment = Moment.now()) = expiresAt > at

    val link: String get() = "aqra://friend/$id"
}

/** Two friends. The document's id is their two uids, sorted, joined by "_". */
data class Friendship(
    val id: String,
    val members: List<String>,
    val names: Map<String, String>,
    val createdAt: Moment = Moment.now(),
) {
    companion object {
        fun id(a: String, b: String): String = if (a < b) "${a}_$b" else "${b}_$a"

        fun from(id: String, document: Document): Friendship? {
            val members = (document["members"] as? List<*>)?.filterIsInstance<String>()?.takeIf { it.size == 2 } ?: return null
            val names = (document["names"] as? Map<*, *>).orEmpty().entries.mapNotNull { (key, value) ->
                if (key is String && value is String) key to value else null
            }.toMap()
            return Friendship(id, members, names, document["createdAt"] as? Moment ?: Moment.DISTANT_PAST)
        }
    }

    fun document(inviteCode: String): Document = mapOf("members" to members, "names" to names, "inviteCode" to inviteCode, "createdAt" to createdAt)

    /** The other friend, seen from one of them: their uid and name. */
    fun friend(of: String): Pair<String, String> {
        val other = members.firstOrNull { it != of } ?: of
        return other to (names[other] ?: "")
    }
}

/** A competition: a race among friends, a group khatmah, or a teacher's competition among their students. */
data class Competition(
    val id: String,
    val kind: Kind,
    val title: String,
    val metric: Metric,
    val ownerUid: String,
    val ownerName: String,
    val startsAt: Moment,
    val endsAt: Moment,
    val memberUids: List<String>,
    val createdAt: Moment = Moment.now(),
) {
    enum class Kind(val raw: String, val icon: String) { FRIENDS("friends", "🏁"), KHATMAH("khatmah", "📚"), TEACHER("teacher", "🎓") }

    /** What the race counts. A khatmah counts parts; a teacher's competition, the pages the teacher heard clean. */
    enum class Metric(val raw: String) {
        PAGES_REVISED("pagesRevised"), DAYS_REVISED("daysRevised"), AYAT_MEMORIZED("ayatMemorized"), PARTS("parts"), CLEAN_PAGES("cleanPages"),
    }

    companion object {
        fun from(id: String, document: Document): Competition? {
            val kind = Kind.entries.firstOrNull { it.raw == document["kind"] } ?: return null
            val metric = Metric.entries.firstOrNull { it.raw == document["metric"] } ?: return null
            val ownerUid = document["ownerUid"] as? String ?: return null
            val startsAt = document["startsAt"] as? Moment ?: return null
            val endsAt = document["endsAt"] as? Moment ?: return null
            val memberUids = (document["memberUids"] as? List<*>)?.filterIsInstance<String>() ?: return null
            return Competition(id, kind, document["title"] as? String ?: "", metric, ownerUid, document["ownerName"] as? String ?: "",
                startsAt, endsAt, memberUids, document["createdAt"] as? Moment ?: Moment.DISTANT_PAST)
        }
    }

    val document: Document get() = mapOf(
        "kind" to kind.raw, "title" to title, "metric" to metric.raw, "ownerUid" to ownerUid, "ownerName" to ownerName,
        "startsAt" to startsAt, "endsAt" to endsAt, "memberUids" to memberUids, "createdAt" to createdAt,
    )

    fun isRunning(at: Moment = Moment.now()) = startsAt <= at && at < endsAt
}

/** A member's standing in a competition. */
data class CompetitionMember(
    /** The member's uid. */
    val id: String,
    val name: String,
    val score: Int,
) {
    companion object {
        fun from(id: String, document: Document) =
            CompetitionMember(id, document["name"] as? String ?: "", (document["score"] as? Number)?.toInt() ?: 0)

        /** Members by score, highest first; ties share a rank and are ordered by name. */
        fun ranked(members: List<CompetitionMember>): List<Pair<Int, CompetitionMember>> {
            val sorted = members.sortedWith(compareByDescending<CompetitionMember> { it.score }.thenBy { it.name })
            val result = ArrayList<Pair<Int, CompetitionMember>>()
            sorted.forEachIndexed { index, member ->
                val rank = if (index > 0 && sorted[index - 1].score == member.score) result[index - 1].first else index + 1
                result += rank to member
            }
            return result
        }
    }
}

/** One of a group khatmah's thirty parts. */
data class KhatmahPart(
    /** The juz', 1…30. */
    val id: Int,
    val claimedBy: String? = null,
    val claimedName: String = "",
    val done: Boolean = false,
) {
    companion object {
        fun from(id: String, document: Document): KhatmahPart? {
            val juz = id.toIntOrNull() ?: return null
            return KhatmahPart(juz, document["claimedBy"] as? String, document["claimedName"] as? String ?: "", document["done"] as? Boolean ?: false)
        }
    }

    val document: Document get() = mapOf("claimedBy" to claimedBy, "claimedName" to claimedName, "done" to done)
}

/** A friends' race's score, from what the student did within its dates. */
object CompetitionScore {
    fun score(
        metric: Competition.Metric,
        start: Moment,
        end: Moment,
        memorization: MemorizationStore,
        revision: RevisionStore,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Int {
        fun within(date: Moment) = date >= start && date < end
        return when (metric) {
            Competition.Metric.PAGES_REVISED -> revision.history.count { within(it.date) }
            Competition.Metric.DAYS_REVISED -> {
                // Days revised are kept as the start of each day: the first day counts whatever hour the race began.
                val firstDay = start.startOfDay(zone)
                revision.revisedDays.count { it >= firstDay && it < end }
            }
            Competition.Metric.AYAT_MEMORIZED -> memorization.ayahs.values.count { memory -> memory.learnedAt?.let(::within) ?: false }
            Competition.Metric.PARTS, Competition.Metric.CLEAN_PAGES -> 0
        }
    }
}

/**
 * Friends and competitions, through the account: the friends this account has, the competitions it's in, and the
 * student's own score in each race among friends, reported from what they did on this device. A teacher's
 * competitions are scored by the server from the teacher's own records. See backend/README.md.
 */
class SocialStore(private val memorization: MemorizationStore, private val revision: RevisionStore) {
    var friendships: List<Friendship> by mutableStateOf(emptyList())
        private set
    var competitions: List<Competition> by mutableStateOf(emptyList())
        private set
    var problem: Problem? by mutableStateOf(null)

    var uid: String? = null
        private set
    private val listeners = ArrayList<ListenerRegistration>()
    /** The scores last reported, by competition, so an unchanged score isn't written again. */
    private val reported = HashMap<String, Int>()

    private val database: FirebaseFirestore get() = FirebaseFirestore.getInstance()

    /** The friends, by name: their uid and name. */
    val friends: List<Pair<String, String>>
        get() {
            val uid = uid ?: return emptyList()
            val collator = Collator.getInstance()
            return friendships.map { it.friend(uid) }.sortedWith { a, b -> collator.compare(a.second, b.second) }
        }

    // MARK: - The account in use

    fun attach(uid: String) {
        if (uid == this.uid) return
        detach()
        this.uid = uid
        listeners += database.collection("friendships").whereArrayContains("members", uid).addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            friendships = snapshot.documents.mapNotNull { Friendship.from(it.id, dated(it.data)) }
        }
        listeners += database.collection("competitions").whereArrayContains("memberUids", uid).addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            val now = Moment.now()
            competitions = snapshot.documents.mapNotNull { Competition.from(it.id, dated(it.data)) }
                .sortedWith(compareBy<Competition> { if (it.endsAt > now) 0 else 1 }.thenBy { it.endsAt })
        }
    }

    fun detach() {
        listeners.forEach { it.remove() }
        listeners.clear()
        uid = null
        friendships = emptyList()
        competitions = emptyList()
        reported.clear()
        problem = null
    }

    // MARK: - Friends

    /** Creates an invitation for this account, valid for a week. */
    suspend fun createInvite(name: String): FriendInvite {
        val uid = uid ?: throw TasmeeError.NotSignedIn
        repeat(5) {
            val invite = FriendInvite(PeerRequest.randomCode(), uid, name)
            try {
                database.collection("friendInvites").document(invite.id).set(stamped(invite.document)).await()
                return invite
            } catch (error: FirebaseFirestoreException) {
                // The code exists already (the rules refuse to overwrite it); try another.
                if (error.code != FirebaseFirestoreException.Code.PERMISSION_DENIED) throw error
            }
        }
        throw TasmeeError.CodeUnavailable
    }

    suspend fun invite(code: String): FriendInvite? {
        val snapshot = database.collection("friendInvites").document(code).get().await()
        return snapshot.data?.let { FriendInvite.from(code, dated(it)) }?.takeIf { it.isValid() }
    }

    /** Accepts an invitation: the two become friends. */
    suspend fun accept(invite: FriendInvite, name: String) {
        val uid = uid ?: return
        if (invite.ownerUid == uid) return
        val friendship = Friendship(Friendship.id(uid, invite.ownerUid), listOf(invite.ownerUid, uid),
            mapOf(invite.ownerUid to invite.ownerName, uid to name))
        database.collection("friendships").document(friendship.id).set(stamped(friendship.document(invite.id))).await()
    }

    fun remove(friendUid: String) {
        val uid = uid ?: return
        database.collection("friendships").document(Friendship.id(uid, friendUid)).delete().addOnFailureListener(::report)
    }

    // MARK: - Competitions

    /**
     * Starts a competition with some friends (or, for a teacher, some of their students); a khatmah is made with its
     * thirty parts, free to claim.
     */
    suspend fun start(kind: Competition.Kind, title: String, metric: Competition.Metric, days: Int, ownerName: String, members: List<String>) {
        val uid = uid ?: throw TasmeeError.NotSignedIn
        val zone = ZoneId.systemDefault()
        val start = Moment.now().startOfDay(zone)
        val end = start.plusDays(days.toLong(), zone)
        val reference = database.collection("competitions").document()
        val competition = Competition(reference.id, kind, title, metric, uid, ownerName, start, end, listOf(uid) + members.filter { it != uid })
        val batch = database.batch()
        batch.set(reference, stamped(competition.document))
        if (kind == Competition.Kind.KHATMAH) {
            for (juz in 1..30) batch.set(reference.collection("parts").document(juz.toString()), stamped(KhatmahPart(juz).document))
        }
        batch.commit().await()
    }

    /** Leaves a competition: this member's standing goes with them. */
    fun leave(competition: Competition) {
        val uid = uid ?: return
        val reference = database.collection("competitions").document(competition.id)
        reference.collection("members").document(uid).delete()
        reference.update("memberUids", FieldValue.arrayRemove(uid)).addOnFailureListener(::report)
    }

    /** Ends a competition now (its owner only). */
    fun end(competition: Competition) {
        database.collection("competitions").document(competition.id).update(stamped(mapOf("endsAt" to Moment.now()))).addOnFailureListener(::report)
    }

    fun members(competition: Competition): Flow<List<CompetitionMember>> = callbackFlow {
        val registration = database.collection("competitions").document(competition.id).collection("members").addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            trySend(snapshot.documents.map { CompetitionMember.from(it.id, it.data.orEmpty()) })
        }
        awaitClose { registration.remove() }
    }

    fun parts(competition: Competition): Flow<List<KhatmahPart>> = callbackFlow {
        val registration = database.collection("competitions").document(competition.id).collection("parts").addSnapshotListener { snapshot, _ ->
            snapshot ?: return@addSnapshotListener
            trySend(snapshot.documents.mapNotNull { KhatmahPart.from(it.id, it.data.orEmpty()) }.sortedBy { it.id })
        }
        awaitClose { registration.remove() }
    }

    /** Claims a free part. */
    fun claim(part: KhatmahPart, competition: Competition, name: String) {
        val uid = uid ?: return
        partReference(part, competition).update(mapOf("claimedBy" to uid, "claimedName" to name, "done" to false)).addOnFailureListener(::report)
    }

    /** Gives a part back, unfinished. */
    fun release(part: KhatmahPart, competition: Competition) {
        partReference(part, competition).update(mapOf("claimedBy" to null, "claimedName" to "", "done" to false)).addOnFailureListener(::report)
    }

    fun setDone(done: Boolean, part: KhatmahPart, competition: Competition) {
        partReference(part, competition).update("done", done).addOnFailureListener(::report)
    }

    private fun partReference(part: KhatmahPart, competition: Competition): DocumentReference =
        database.collection("competitions").document(competition.id).collection("parts").document(part.id.toString())

    /** Reports this student's score in each race among friends that's running, from what they did on this device. */
    fun reportScores(name: String) {
        val uid = uid ?: return
        for (competition in competitions) {
            if (competition.kind != Competition.Kind.FRIENDS || !competition.isRunning()) continue
            val score = CompetitionScore.score(competition.metric, competition.startsAt, competition.endsAt, memorization, revision)
            if (reported[competition.id] == score) continue
            reported[competition.id] = score
            database.collection("competitions").document(competition.id).collection("members").document(uid)
                .set(stamped(mapOf("name" to name, "score" to score, "updatedAt" to Moment.now()))).addOnFailureListener(::report)
        }
    }

    private fun report(error: Exception) {
        problem = AccountStore.problem(error)
    }

    // MARK: - Deleting

    /**
     * Deletes what the account holds of friends and competitions: its friendships and invitations, its places in
     * others' competitions, and the competitions it started.
     */
    suspend fun deleteAccountData(uid: String) {
        val references = ArrayList<DocumentReference>()
        references += database.collection("friendships").whereArrayContains("members", uid).get().await().documents.map { it.reference }
        references += database.collection("friendInvites").whereEqualTo("ownerUid", uid).get().await().documents.map { it.reference }
        val competitions = database.collection("competitions").whereArrayContains("memberUids", uid).get().await()
        for (competition in competitions.documents) {
            if (competition.getString("ownerUid") == uid) {
                references += competition.reference.collection("members").get().await().documents.map { it.reference }
                references += competition.reference.collection("parts").get().await().documents.map { it.reference }
                references += competition.reference
            } else {
                references += competition.reference.collection("members").document(uid)
                competition.reference.update("memberUids", FieldValue.arrayRemove(uid)).await()
            }
        }
        TasmeeStore.delete(references, database)
    }
}
