package com.azzamalrashed.aqra.account

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.revision.RevisionStore
import com.google.firebase.firestore.DocumentReference
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.google.firebase.firestore.Source
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import java.io.File
import java.util.UUID

/**
 * How long to wait for something that needs the server's answer. Firestore answers a write only once it reaches the
 * server, so offline it would wait forever.
 */
const val SERVER_TIMEOUT = 12_000L

/** How many times the account's copy is fetched before giving up on a merge: the first try right as the app comes back may fail. */
private const val MERGE_ATTEMPTS = 3

/**
 * Backs the student's progress up to their account, and keeps it whole across devices.
 *
 * The device's copy stays the one the app works from. Whenever an account is attached and whenever the app comes back
 * to the foreground after another device wrote to the account, the account's copy is fetched and merged into the
 * device's (see [CloudBackup]: unions, never a blind overwrite), and a couple of seconds after any change, only what
 * changed is written back, row by row. Nothing is ever written before the account's copy has been merged in this
 * session: a device that can't reach the account keeps its changes until it can. The layout is the iOS app's, so a
 * student can move between the two.
 */
class CloudSync(
    private val memorization: MemorizationStore,
    private val revision: RevisionStore,
    private val journey: Journey,
    private val scope: CoroutineScope,
    private val store: CloudStore,
    /**
     * Tells this install's writes from another device's, so coming back to the foreground fetches the account's copy
     * only when another device wrote it since.
     */
    val installId: String,
) {
    /** When the account last confirmed it holds the device's progress. */
    var lastBackup: Moment? by mutableStateOf(null)
        private set
    /** When the account's copy was last merged into the device's, so the screens can rebuild from it. */
    var lastMerge: Moment? by mutableStateOf(null)
        private set

    private var uid: String? = null
    private var pendingUpload: Job? = null
    /**
     * The rows the account is known to hold, from the last merge and this install's writes since, so only what
     * changed is written. Null until the account's copy has been merged in this session: nothing is written before.
     */
    private var uploadedBlocks: Map<Int, BackupBlock>? = null
    private var uploadedRevision: RevisionStore.Snapshot? = null
    private var uploadedJourney: Journey.Snapshot? = null
    /** What a newer app wrote into the account that this one doesn't read, carried back on every write. */
    private var revisionExtras = kotlinx.serialization.json.JsonObject(emptyMap())
    private var rowExtras: Map<Int, List<Double>> = emptyMap()
    private var journeyOriginal = kotlinx.serialization.json.JsonObject(emptyMap())
    /**
     * Whether this app can read the account's revision record and journey. One written by a newer app that this one
     * can't make sense of is left as it is rather than overwritten.
     */
    private var revisionReadable = true
    private var journeyReadable = true
    /** Changes aren't backed up while a merge is replacing the device's copy. */
    private var isRestoring = false
    private var isMerging = false
    /** Set while the account is being deleted: nothing is written back to it. */
    private var uploadsStopped = false

    init {
        memorization.onChange = { scheduleUpload() }
        revision.onChange = { scheduleUpload() }
        journey.onChange = { scheduleUpload() }
    }

    // MARK: - The account in use

    /**
     * Starts backing up to an account: its copy is merged into the device's first, then what the device adds is
     * written back.
     */
    suspend fun attach(uid: String) {
        if (uid == this.uid) return
        this.uid = uid
        uploadsStopped = false
        forgetAccount()
        mergeWithAccount(uid, attempts = MERGE_ATTEMPTS)
        scheduleUpload(after = 0)
    }

    /**
     * Back in the foreground: if another device wrote to the account meanwhile, its copy is merged in. One read tells;
     * the copy itself is fetched only when it's needed.
     */
    suspend fun syncIfChanged() {
        val uid = uid ?: return
        if (isMerging || uploadsStopped) return
        if (uploadedBlocks != null) {
            var writer: Result<String?>? = null
            for (attempt in 1..MERGE_ATTEMPTS) {
                writer = runCatching { store.lastWriter(uid) }
                if (writer.isSuccess || attempt == MERGE_ATTEMPTS) break
                delay(2_000)
            }
            val last = writer?.getOrNull()
            if (writer?.isFailure != false || last == installId || uid != this.uid) return
        }
        mergeWithAccount(uid, attempts = MERGE_ATTEMPTS)
        scheduleUpload(after = 0)
    }

    /** Stops backing up, before signing out or deleting the account. */
    fun detach() {
        pendingUpload?.cancel()
        pendingUpload = null
        uid = null
        forgetAccount()
    }

    /** Stops writing to the account, before its data is deleted: a backup half-way through would bring it back. */
    fun stopUploads() {
        uploadsStopped = true
        pendingUpload?.cancel()
        pendingUpload = null
    }

    /** Writes again, after a deletion that didn't go through. */
    fun resumeUploads() {
        uploadsStopped = false
        scheduleUpload(after = 0)
    }

    /** Clears the device's progress, after signing out: the account keeps its copy. */
    fun clearDevice() {
        isRestoring = true
        memorization.replaceAll(emptyMap())
        revision.apply(RevisionStore.Snapshot.EMPTY)
        journey.apply(Journey.Snapshot.EMPTY)
        isRestoring = false
    }

    private fun forgetAccount() {
        uploadedBlocks = null
        uploadedRevision = null
        uploadedJourney = null
        revisionExtras = kotlinx.serialization.json.JsonObject(emptyMap())
        rowExtras = emptyMap()
        journeyOriginal = kotlinx.serialization.json.JsonObject(emptyMap())
        revisionReadable = true
        journeyReadable = true
        lastBackup = null
    }

    // MARK: - Merging the account's copy

    private suspend fun mergeWithAccount(uid: String, attempts: Int = 1) {
        isMerging = true
        try {
            var remote: CloudProgress? = null
            for (attempt in 1..maxOf(attempts, 1)) {
                try {
                    remote = store.fetchProgress(uid)
                    break
                } catch (error: Exception) {
                    // A fetch right as the app comes back can fail while the connection is re-established.
                    if (attempt == attempts) throw error
                    android.util.Log.i("Aqra", "fetching the account's copy failed (attempt $attempt): $error")
                    delay(2_000)
                }
            }
            if (remote == null || uid != this.uid) return

            val remoteMemory = CloudBackup.memory(remote.blocks.values)
            rowExtras = CloudBackup.extraValues(remote.blocks.values)
            var remoteRevision = remote.revisionJson?.let(CloudBackup::decodeRevision)
            revisionReadable = remote.revisionJson == null || remoteRevision != null
            remote.revisionJson?.let { revisionExtras = CloudBackup.unknownFields(it) }
            // The days are kept beside the record too, only ever added to; whatever the record says, they count.
            if (remoteRevision != null || remote.revisedDays.isNotEmpty() || remote.completedDays.isNotEmpty()) {
                val record = remoteRevision ?: RevisionStore.Snapshot.EMPTY
                remoteRevision = record.copy(
                    revisedDays = (record.revisedDays + remote.revisedDays.map(::Moment)).toSortedSet().toList(),
                    completedDays = (record.completedDays.orEmpty() + remote.completedDays.map(::Moment)).toSortedSet().toList().ifEmpty { null },
                )
            }
            val remoteJourney = readJourney(remote.journeyJson)

            isRestoring = true
            memorization.replaceAll(CloudBackup.merge(memorization.memory, remoteMemory))
            if (remoteRevision != null) revision.apply(CloudBackup.merge(revision.snapshot, remoteRevision))
            if (remoteJourney != null) journey.apply(Journey.Snapshot.merge(journey.snapshot, remoteJourney))
            isRestoring = false
            uploadedBlocks = remote.blocks
            uploadedRevision = remoteRevision
            uploadedJourney = remoteJourney
            lastMerge = Moment.now()
            android.util.Log.i("Aqra", "merged the account's copy: ${remote.blocks.size} blocks")
        } catch (error: Exception) {
            // Offline or refused: nothing on the device is lost, and nothing is written until it goes through.
            isRestoring = false
            android.util.Log.i("Aqra", "merging the account's copy failed: $error")
        } finally {
            isMerging = false
        }
    }

    /** The account's journey, read to merge it and to carry what this app doesn't know; null when there's none. */
    private fun readJourney(json: String?): Journey.Snapshot? {
        journeyOriginal = kotlinx.serialization.json.JsonObject(emptyMap())
        if (json == null) {
            journeyReadable = true
            return null
        }
        journeyOriginal = Journey.original(json)
        val decoded = Journey.decode(json)
        journeyReadable = decoded != null
        return decoded
    }

    // MARK: - Backing up

    private fun scheduleUpload(after: Long = 2_000) {
        if (uid == null || isRestoring || uploadsStopped) return
        pendingUpload?.cancel()
        pendingUpload = scope.launch {
            delay(after)
            runCatching { upload() }
        }
    }

    /**
     * Writes whatever changed since the account was last read, and waits for the account to confirm it. Throws when it
     * can't be reached.
     */
    suspend fun upload() {
        val uid = uid ?: return
        if (uploadsStopped) return
        // The account's copy is merged first (the attach may have happened offline), or nothing is written.
        if (uploadedBlocks == null) {
            mergeWithAccount(uid)
            if (uid != this.uid) return
            check(uploadedBlocks != null) { "The account's copy couldn't be merged yet." }
        }
        val known = uploadedBlocks.orEmpty()
        val rows = HashMap<Int, BackupBlock>()
        for ((index, block) in CloudBackup.blocks(memorization.memory, rowExtras)) {
            val changed = block.filter { (key, row) -> known[index]?.get(key) != row }
            if (changed.isNotEmpty()) rows[index] = changed
        }
        val snapshot = revision.snapshot
        val revisionChanged = revisionReadable && snapshot != uploadedRevision && (uploadedRevision != null || snapshot != RevisionStore.Snapshot.EMPTY)
        val journeySnapshot = journey.snapshot
        val journeyChanged = journeyReadable && journeySnapshot != uploadedJourney &&
            (uploadedJourney != null || journeySnapshot != Journey.Snapshot.EMPTY)
        if (rows.isEmpty() && !revisionChanged && !journeyChanged) {
            lastBackup = lastBackup ?: Moment.now()
            return
        }

        val write = CloudWrite(
            rows = rows,
            revisionJson = if (revisionChanged) CloudBackup.encode(snapshot, revisionExtras) else null,
            revisedDays = if (revisionChanged) snapshot.revisedDays.map { it.sinceReference } else emptyList(),
            completedDays = if (revisionChanged) snapshot.completedDays.orEmpty().map { it.sinceReference } else emptyList(),
            journeyJson = if (journeyChanged) Journey.encode(journeySnapshot, journeyOriginal) else null,
            writer = installId,
        )
        store.write(uid, write)
        if (uid != this.uid || uploadsStopped) return
        val blocks = HashMap(uploadedBlocks.orEmpty())
        for ((index, changed) in rows) blocks[index] = blocks[index].orEmpty() + changed
        uploadedBlocks = blocks
        if (revisionChanged) uploadedRevision = snapshot
        if (journeyChanged) uploadedJourney = journeySnapshot
        lastBackup = Moment.now()
    }

    /** Uploads, giving up after a while: signing out and deleting need the account to answer, not a queue. */
    suspend fun uploadNow(timeoutMillis: Long = 12_000) {
        pendingUpload?.cancel()
        withTimeout(timeoutMillis) { upload() }
    }

    // MARK: - Deleting

    /** Deletes everything the account holds of the student's progress. */
    suspend fun deleteAccountData(uid: String) = store.deleteProgress(uid)
}

// MARK: - The account's documents

/**
 * The account's progress as the store holds it: the blocks of rows, the revision record with its days, and the
 * journey, each as it was written (see [CloudBackup] for the layout).
 */
data class CloudProgress(
    val blocks: Map<Int, BackupBlock> = emptyMap(),
    val revisionJson: String? = null,
    /** Seconds since 2001, as the JSON keeps dates. */
    val revisedDays: List<Double> = emptyList(),
    val completedDays: List<Double> = emptyList(),
    val journeyJson: String? = null,
)

/** What a device writes: the rows that changed, merged into their blocks, and the records that changed. */
data class CloudWrite(
    val rows: Map<Int, BackupBlock> = emptyMap(),
    val revisionJson: String? = null,
    /** Added to the days the account already holds, never replacing them. */
    val revisedDays: List<Double> = emptyList(),
    val completedDays: List<Double> = emptyList(),
    val journeyJson: String? = null,
    val writer: String,
)

/**
 * What a device needs of the account: the documents under `users/{uid}`, read and written as plain values, so the
 * backup can be tested with a fake store in place of Firestore.
 */
interface CloudStore {
    /** The install that last wrote the account's progress, or null when nothing says. */
    suspend fun lastWriter(uid: String): String?
    /** The account's progress, from the server: offline, the cache would answer with whatever this install holds. */
    suspend fun fetchProgress(uid: String): CloudProgress
    suspend fun write(uid: String, write: CloudWrite)
    suspend fun deleteProgress(uid: String)
}

/** The account's documents in Firestore. */
class FirestoreCloudStore : CloudStore {
    private val database get() = FirebaseFirestore.getInstance()

    private fun user(uid: String): DocumentReference = database.collection("users").document(uid)

    override suspend fun lastWriter(uid: String): String? = user(uid).get(Source.SERVER).await().getString("lastWriter")

    override suspend fun fetchProgress(uid: String): CloudProgress {
        val blocks = user(uid).collection("memory").get(Source.SERVER).await()
        val state = user(uid).collection("revision").document("state").get(Source.SERVER).await()
        val journey = user(uid).collection("journey").document("state").get(Source.SERVER).await()
        val rows = HashMap<Int, BackupBlock>()
        for (document in blocks.documents) {
            val index = document.id.removePrefix("block-").toIntOrNull() ?: continue
            rows[index] = block(document.get("ayahs"))
        }
        return CloudProgress(
            blocks = rows,
            revisionJson = state.getString("json"),
            revisedDays = numbers(state.get("revisedDays")),
            completedDays = numbers(state.get("completedDays")),
            journeyJson = journey.getString("json"),
        )
    }

    override suspend fun write(uid: String, write: CloudWrite) {
        val batch = database.batch()
        val user = user(uid)
        batch.set(user, mapOf("updatedAt" to FieldValue.serverTimestamp(), "lastWriter" to write.writer), SetOptions.merge())
        for ((index, rows) in write.rows) {
            batch.set(user.collection("memory").document(CloudBackup.blockId(index)),
                mapOf("ayahs" to rows, "updatedAt" to FieldValue.serverTimestamp()), SetOptions.merge())
        }
        write.revisionJson?.let { json ->
            val data = HashMap<String, Any>(mapOf("json" to json, "updatedAt" to FieldValue.serverTimestamp()))
            if (write.revisedDays.isNotEmpty()) data["revisedDays"] = FieldValue.arrayUnion(*write.revisedDays.toTypedArray())
            if (write.completedDays.isNotEmpty()) data["completedDays"] = FieldValue.arrayUnion(*write.completedDays.toTypedArray())
            batch.set(user.collection("revision").document("state"), data, SetOptions.merge())
        }
        write.journeyJson?.let { json ->
            batch.set(user.collection("journey").document("state"),
                mapOf("json" to json, "updatedAt" to FieldValue.serverTimestamp()), SetOptions.merge())
        }
        batch.commit().await()
    }

    override suspend fun deleteProgress(uid: String) {
        val user = user(uid)
        val batch = database.batch()
        for (index in 0 until CloudBackup.BLOCK_COUNT) batch.delete(user.collection("memory").document(CloudBackup.blockId(index)))
        batch.delete(user.collection("revision").document("state"))
        batch.delete(user.collection("journey").document("state"))
        batch.delete(user)
        batch.commit().await()
    }

    /** A block as Firestore returns it: numbers arrive as Long or Double. */
    private fun block(value: Any?): BackupBlock {
        val rows = value as? Map<*, *> ?: return emptyMap()
        return rows.entries.mapNotNull { (key, row) ->
            val list = row as? List<*> ?: return@mapNotNull null
            val numbers = list.mapNotNull { (it as? Number)?.toDouble() }
            if (key is String && numbers.size == list.size) key to numbers else null
        }.toMap()
    }

    private fun numbers(value: Any?): List<Double> =
        (value as? List<*>)?.mapNotNull { (it as? Number)?.toDouble()?.takeIf(Double::isFinite) }.orEmpty()
}

/**
 * A name for this install, made once and kept where device backups don't reach (a backup restored on another phone
 * makes a new one), so the account can tell which device wrote last.
 */
object InstallId {
    fun of(context: Context): String {
        val file = File(context.noBackupFilesDir, "install-id")
        runCatching { file.readText().trim() }.getOrNull()?.takeIf { it.isNotEmpty() }?.let { return it }
        val id = UUID.randomUUID().toString()
        runCatching { file.writeText(id) }
        return id
    }
}
