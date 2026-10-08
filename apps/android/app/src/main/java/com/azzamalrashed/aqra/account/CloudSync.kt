package com.azzamalrashed.aqra.account

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.Preferences
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

/**
 * How long to wait for something that needs the server's answer. Firestore answers a write only once it reaches the
 * server, so offline it would wait forever.
 */
const val SERVER_TIMEOUT = 12_000L

/**
 * Backs the student's progress up to their account, and restores it on a new device or after a reinstall.
 *
 * The device's copy stays the one the app works from. A couple of seconds after it changes, the blocks that changed
 * are written to the account (Firestore queues them while offline). The first time an account is used on this
 * install, its copy is fetched and merged with the device's (see [CloudBackup]). This is a backup across devices, not
 * live editing on two at once. The layout is the iOS app's, so a student can move between the two.
 */
class CloudSync(
    private val memorization: MemorizationStore,
    private val revision: RevisionStore,
    private val journey: Journey,
    private val prefs: Preferences,
    private val scope: CoroutineScope,
) {
    /** When the account last confirmed it holds the device's progress. */
    var lastBackup: Moment? by mutableStateOf(null)
        private set

    private var uid: String? = null
    private var pendingUpload: Job? = null
    /**
     * What the account is known to hold, so only what changed is written. Null until known: then every block is
     * written, so a block emptied on the device (ayat unmarked) is emptied in the account too.
     */
    private var uploadedBlocks: Map<Int, BackupBlock>? = null
    private var uploadedRevision: RevisionStore.Snapshot? = null
    private var uploadedJourney: Journey.Snapshot? = null
    /** What a newer app wrote into the account that this one doesn't read, carried back on every write. */
    private var revisionExtras = kotlinx.serialization.json.JsonObject(emptyMap())
    private var rowExtras: Map<Int, List<Double>> = emptyMap()
    private var journeyOriginal = kotlinx.serialization.json.JsonObject(emptyMap())
    /**
     * Whether this app can read the account's journey. A newer app may write one this app can't make sense of; then
     * it's left as it is rather than overwritten.
     */
    private var journeyReadable = true
    /** Changes aren't backed up while a restore is replacing the device's copy. */
    private var isRestoring = false

    init {
        memorization.onChange = { scheduleUpload() }
        revision.onChange = { scheduleUpload() }
        journey.onChange = { scheduleUpload() }
    }

    private val database get() = FirebaseFirestore.getInstance()

    private fun user(uid: String): DocumentReference = database.collection("users").document(uid)

    // MARK: - The account in use

    /** Starts backing up to an account, merging its copy first if this install hasn't yet. */
    suspend fun attach(uid: String) {
        if (uid == this.uid) return
        this.uid = uid
        uploadedBlocks = null
        uploadedRevision = null
        uploadedJourney = null
        revisionExtras = kotlinx.serialization.json.JsonObject(emptyMap())
        rowExtras = emptyMap()
        journeyOriginal = kotlinx.serialization.json.JsonObject(emptyMap())
        journeyReadable = true
        lastBackup = null
        // The account's copy is read on every launch for what a newer app may have added; it's merged in only once.
        if (prefs.restoredAccount != uid) restoreAndMerge(uid) else readExtras(uid)
        scheduleUpload(after = 0)
    }

    /** Stops backing up, before signing out or deleting the account. */
    fun detach() {
        pendingUpload?.cancel()
        pendingUpload = null
        uid = null
        lastBackup = null
        prefs.restoredAccount = null
        prefs.journeyRestoredAccount = null
    }

    /** Clears the device's progress, after signing out: the account keeps its copy. */
    fun clearDevice() {
        isRestoring = true
        memorization.replaceAll(emptyMap())
        revision.apply(RevisionStore.Snapshot.EMPTY)
        journey.apply(Journey.Snapshot.EMPTY)
        isRestoring = false
    }

    // MARK: - Restoring

    private suspend fun restoreAndMerge(uid: String) {
        try {
            // From the server only: offline, the cache answers with whatever this install happens to hold, and
            // merging with that would count as restored.
            val blocks = user(uid).collection("memory").get(Source.SERVER).await()
            val state = user(uid).collection("revision").document("state").get(Source.SERVER).await()
            val journeyState = user(uid).collection("journey").document("state").get(Source.SERVER).await()
            if (uid != this.uid) return

            val remoteBlocks = HashMap<Int, BackupBlock>()
            for (document in blocks.documents) {
                val index = document.id.removePrefix("block-").toIntOrNull() ?: continue
                remoteBlocks[index] = block(document.get("ayahs"))
            }
            val json = state.getString("json")
            val remoteRevision = json?.let(CloudBackup::decodeRevision)
            json?.let { revisionExtras = CloudBackup.unknownFields(it) }
            rowExtras = CloudBackup.extraValues(remoteBlocks.values)
            val remoteJourney = readJourney(journeyState.getString("json"))

            isRestoring = true
            memorization.replaceAll(CloudBackup.merge(memorization.ayahs, CloudBackup.ayahs(remoteBlocks.values)))
            if (remoteRevision != null) revision.apply(CloudBackup.merge(revision.snapshot, remoteRevision))
            if (remoteJourney != null) journey.apply(Journey.Snapshot.merge(journey.snapshot, remoteJourney))
            isRestoring = false
            uploadedBlocks = remoteBlocks
            uploadedRevision = remoteRevision
            uploadedJourney = remoteJourney
            prefs.restoredAccount = uid
            prefs.journeyRestoredAccount = uid
        } catch (_: Exception) {
            // Offline or refused: the next launch tries again, and nothing on the device is lost meanwhile.
            isRestoring = false
        }
    }

    /** Reads, without merging, what a newer app wrote into the account that this one doesn't know. */
    private suspend fun readExtras(uid: String) {
        try {
            val blocks = user(uid).collection("memory").get().await()
            val state = user(uid).collection("revision").document("state").get().await()
            val journeyState = user(uid).collection("journey").document("state").get().await()
            if (uid != this.uid) return
            rowExtras = CloudBackup.extraValues(blocks.documents.map { block(it.get("ayahs")) })
            state.getString("json")?.let { revisionExtras = CloudBackup.unknownFields(it) }
            val remoteJourney = readJourney(journeyState.getString("json"))
            // An account restored by a version of the app from before the journey was kept: its journey is merged once.
            if (prefs.journeyRestoredAccount != uid) {
                if (remoteJourney != null) {
                    isRestoring = true
                    journey.apply(Journey.Snapshot.merge(journey.snapshot, remoteJourney))
                    isRestoring = false
                }
                uploadedJourney = remoteJourney
                prefs.journeyRestoredAccount = uid
            }
        } catch (_: Exception) {
            // Offline: nothing is lost, the next launch reads them again.
        }
    }

    /** The account's journey, read to merge it and to carry what this app doesn't know; null when there's none. */
    private fun readJourney(json: String?): Journey.Snapshot? {
        if (json == null) return null
        journeyOriginal = Journey.original(json)
        val decoded = Journey.decode(json)
        journeyReadable = decoded != null
        return decoded
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

    // MARK: - Backing up

    private fun scheduleUpload(after: Long = 2_000) {
        if (uid == null || isRestoring) return
        pendingUpload?.cancel()
        pendingUpload = scope.launch {
            delay(after)
            runCatching { upload() }
        }
    }

    /** Writes whatever changed since the account last heard from this device, and waits for the account to confirm it. */
    suspend fun upload() {
        val uid = uid ?: return
        // Nothing is written until this install has merged the account's copy (an earlier try may have failed
        // offline): the device's copy, empty after a reinstall while the sign-in survives, would replace it.
        if (prefs.restoredAccount != uid) {
            restoreAndMerge(uid)
            if (uid != this.uid) return
            check(prefs.restoredAccount == uid) { "The account's copy couldn't be merged yet." }
        }
        val blocks = CloudBackup.blocks(memorization.ayahs, rowExtras)
        val uploaded = uploadedBlocks
        val changed = if (uploaded == null) blocks else blocks.filter { (index, block) -> uploaded[index].orEmpty() != block }
        val snapshot = revision.snapshot
        val revisionChanged = snapshot != uploadedRevision && (uploadedRevision != null || snapshot != RevisionStore.Snapshot.EMPTY)
        val journeySnapshot = journey.snapshot
        val journeyChanged = journeyReadable && journeySnapshot != uploadedJourney &&
            (uploadedJourney != null || journeySnapshot != Journey.Snapshot.EMPTY)
        if (changed.isEmpty() && !revisionChanged && !journeyChanged) {
            lastBackup = lastBackup ?: Moment.now()
            return
        }

        val batch = database.batch()
        val user = user(uid)
        batch.set(user, mapOf("updatedAt" to FieldValue.serverTimestamp()), SetOptions.merge())
        for ((index, block) in changed) {
            batch.set(user.collection("memory").document(CloudBackup.blockId(index)), mapOf("ayahs" to block, "updatedAt" to FieldValue.serverTimestamp()))
        }
        if (revisionChanged) {
            batch.set(user.collection("revision").document("state"), mapOf("json" to CloudBackup.encode(snapshot, revisionExtras), "updatedAt" to FieldValue.serverTimestamp()))
        }
        if (journeyChanged) {
            batch.set(user.collection("journey").document("state"), mapOf("json" to Journey.encode(journeySnapshot, journeyOriginal), "updatedAt" to FieldValue.serverTimestamp()))
        }
        batch.commit().await()
        if (uid != this.uid) return
        uploadedBlocks = (uploadedBlocks.orEmpty()) + changed
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
    suspend fun deleteAccountData(uid: String) {
        val user = user(uid)
        val batch = database.batch()
        for (index in 0 until CloudBackup.BLOCK_COUNT) batch.delete(user.collection("memory").document(CloudBackup.blockId(index)))
        batch.delete(user.collection("revision").document("state"))
        batch.delete(user.collection("journey").document("state"))
        batch.delete(user)
        batch.commit().await()
    }
}
