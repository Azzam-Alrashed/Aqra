package com.azzamalrashed.aqra.account

import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.TestDates.utc
import com.azzamalrashed.aqra.curriculum.AssessmentStore
import com.azzamalrashed.aqra.memorization.AyahMemory
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.plan.PlanStore
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.rewards.RewardStore
import com.azzamalrashed.aqra.tasmee.TasmeeApply
import com.azzamalrashed.aqra.tasmee.TasmeeRecord
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** The backup's orchestration across devices, with a fake store in place of Firestore: the same checks as the iOS app's. */
@OptIn(ExperimentalCoroutinesApi::class)
class CloudSyncTest {
    private fun memory(since: Int, reviewed: Int? = null, stability: Double = 14.0, verified: Boolean = false) =
        AyahMemory(stability = stability, lastReviewed = reviewed?.let(::day), lapses = 2, verified = verified, since = day(since))

    /** One device: its stores and its backup, all in memory. */
    private class Device(store: FakeCloudStore, id: String, scope: CoroutineScope, val memorization: MemorizationStore = MemorizationStore(file = null)) {
        val revision = RevisionStore(file = null, zone = utc)
        val journey = Journey(PlanStore(file = null, zone = utc), RewardStore(file = null, zone = utc), AssessmentStore(file = null))
        val sync = CloudSync(memorization, revision, journey, scope, store, id)
    }

    @Test
    fun secondDeviceLaunchDoesNotOverwriteANewerAccountCopy() = runTest {
        val account = FakeCloudStore()
        // The tablet has revised page 1's ayah on day 8 and backed it up.
        val tablet = Device(account, "tablet", this)
        tablet.memorization.replaceAll(mapOf(1 to memory(0, reviewed = 8, stability = 40.0), 2 to memory(0)))
        tablet.sync.attach("u")
        tablet.sync.upload()
        advanceUntilIdle()
        assertEquals(1, account.writes.size)

        // The phone holds an older copy (page 1's ayah revised on day 5) and launches later: the account's copy is
        // merged in, and only what the phone adds (ayah 3) is written.
        val phone = Device(account, "phone", this)
        phone.memorization.replaceAll(mapOf(1 to memory(0, reviewed = 5, stability = 20.0), 3 to memory(1)))
        phone.sync.attach("u")
        phone.sync.upload()
        advanceUntilIdle()
        assertEquals(40.0, phone.memorization.memory(1)!!.stability, 0.0)
        assertEquals(setOf(1, 2, 3), phone.memorization.ayahs.keys)
        val accountMemory = CloudBackup.memory(account.blocks("u").values)
        assertTrue(accountMemory.ayahs[1]!!.stability == 40.0 && accountMemory.ayahs.keys == setOf(1, 2, 3))
        assertEquals(mapOf(0 to mapOf("3" to CloudBackup.encode(memory(1)))), account.writes.last().rows)
        assertEquals("phone", account.lastWriter)

        // The tablet comes back to the foreground: another device wrote, so it merges, and has nothing to add.
        tablet.sync.syncIfChanged()
        tablet.sync.upload()
        advanceUntilIdle()
        assertEquals(setOf(1, 2, 3), tablet.memorization.ayahs.keys)
        assertEquals(2, account.writes.size)
        // Nothing changed since the phone wrote: the next foreground reads one document and stops.
        val reads = account.fetches
        phone.sync.syncIfChanged()
        advanceUntilIdle()
        assertEquals(reads, account.fetches)
    }

    @Test
    fun restoredBackupWithStaleFilesMergesInsteadOfOverwriting() = runTest {
        // A phone restored from a device backup brings back old files (ayah 1 at its declared strength) and the same
        // sign-in; meanwhile the account has months of revision. The merge, done in every session, keeps the revision;
        // nothing is written that the account doesn't already hold.
        val account = FakeCloudStore()
        account.seed("u", mapOf(1 to memory(0, reviewed = 60, stability = 80.0), 2 to memory(0, reviewed = 61, stability = 90.0)))
        val phone = Device(account, "phone", this)
        phone.memorization.replaceAll(mapOf(1 to memory(0)))
        phone.sync.attach("u")
        phone.sync.upload()
        advanceUntilIdle()
        assertTrue(phone.memorization.memory(1)!!.stability == 80.0 && phone.memorization.count == 2)
        assertTrue(account.writes.isEmpty())
        assertEquals(80.0, CloudBackup.memory(account.blocks("u").values).ayahs[1]!!.stability, 0.0)
    }

    @Test
    fun undecodableRemoteRevisionIsNotOverwritten() = runTest {
        // A newer app wrote a revision record this version can't read: it's left alone, while the memory still syncs.
        val account = FakeCloudStore()
        account.seed("u", mapOf(1 to memory(0)), revisionJson = "{not json")
        val phone = Device(account, "phone", this)
        phone.revision.setDailyPages(7)
        phone.memorization.replaceAll(mapOf(5 to memory(2)))
        phone.sync.attach("u")
        phone.sync.upload()
        advanceUntilIdle()
        assertEquals("{not json", account.revisionJson("u"))
        assertEquals(setOf(1, 5), CloudBackup.memory(account.blocks("u").values).ayahs.keys)
    }

    @Test
    fun unreadableLocalFileDoesNotWipeTheAccount() = runTest {
        // The memorization file on the device can't be read: it's set aside, the account's copy is restored, and
        // nothing empty is written over it.
        val directory = Files.createTempDirectory("aqra-sync").toFile()
        val file = File(directory, "memorization.json")
        file.writeText("""{"version": 3, "ayahs": [{"ayah": "seven"}]}""")
        val memorization = MemorizationStore(file)
        assertTrue(memorization.loadFailed && memorization.count == 0)
        assertFalse(file.exists())
        assertEquals(1, directory.listFiles { f -> f.name.startsWith("memorization.json.corrupt-") }!!.size)

        val account = FakeCloudStore()
        account.seed("u", mapOf(1 to memory(0, reviewed = 3), 2 to memory(0)))
        val phone = Device(account, "phone", this, memorization)
        phone.sync.attach("u")
        phone.sync.upload()
        advanceUntilIdle()
        assertTrue(memorization.count == 2 && account.writes.isEmpty())
        // And while the account can't be reached, nothing is written either.
        val offline = FakeCloudStore().apply { isOffline = true }
        val empty = Device(offline, "x", this)
        empty.sync.attach("u")
        val failed = runCatching { empty.sync.upload() }.isFailure
        advanceUntilIdle()
        assertTrue(failed && offline.writes.isEmpty())
    }

    @Test
    fun aTasmeeAppliedOnOneDeviceReachesTheOther() = runTest {
        // The phone applies a sheikh's tasmee' of page 1 (ayat 0..6): clean but ayah 3, verified. The tablet, which
        // never saw the record, gets the strengths, the mark and the sheikh's revision from the account.
        val account = FakeCloudStore()
        val phone = Device(account, "phone", this)
        val tablet = Device(account, "tablet", this)
        val ayahs = (0..6).associateWith { memory(0, stability = 14.0) }
        phone.memorization.replaceAll(ayahs)
        tablet.memorization.replaceAll(ayahs)
        phone.sync.attach("u")
        phone.sync.upload()
        tablet.sync.attach("u")
        advanceUntilIdle()

        val record = TasmeeRecord(id = "r1", teacherId = "t", teacherName = "Sheikh", sessionId = "s", at = day(2), pages = listOf(1), stumbles = listOf(3))
        TasmeeApply.apply(record, phone.memorization, phone.revision) { 0..6 }
        phone.sync.upload()
        tablet.sync.syncIfChanged()
        advanceUntilIdle()
        assertTrue(tablet.memorization.memory(0)!!.verified)
        assertFalse(tablet.memorization.memory(3)!!.verified)
        assertEquals(phone.memorization.memory(3)!!.lapses, tablet.memorization.memory(3)!!.lapses)
        assertEquals(phone.memorization.memory(0)!!.stability, tablet.memorization.memory(0)!!.stability, 0.0)
        assertTrue(tablet.revision.history.last().source == RevisionRecord.Source.SHEIKH && tablet.revision.revisedDays.size == 1)
    }

    @Test
    fun deletingTheAccountStopsUploadsFirst() = runTest {
        val account = FakeCloudStore()
        val phone = Device(account, "phone", this)
        phone.memorization.replaceAll(mapOf(1 to memory(0)))
        phone.sync.attach("u")
        phone.sync.upload()
        advanceUntilIdle()
        // A change just before the deletion: its upload, due in two seconds, never happens.
        phone.memorization.mark(listOf(2), memorized = true)
        phone.sync.stopUploads()
        phone.sync.deleteAccountData("u")
        phone.sync.upload()
        advanceUntilIdle()
        assertTrue(account.blocks("u").isEmpty())
        assertEquals(FakeCloudStore.Event.DELETE, account.events.last())
        // Had the deletion failed, the backups would go on.
        phone.sync.resumeUploads()
        advanceUntilIdle()
        assertEquals(FakeCloudStore.Event.WRITE, account.events.last())
    }
}

/**
 * The account's documents, kept in memory and merged as Firestore merges them: a block's rows written over the ones it
 * holds, the day arrays only added to.
 */
private class FakeCloudStore : CloudStore {
    enum class Event { FETCH, WRITE, DELETE }

    private class Revision(var json: String?, var revisedDays: List<Double>, var completedDays: List<Double>)

    private val blocks = HashMap<String, Map<Int, BackupBlock>>()
    private val revisions = HashMap<String, Revision>()
    private val journeys = HashMap<String, String>()
    private val writers = HashMap<String, String>()
    val writes = ArrayList<CloudWrite>()
    val events = ArrayList<Event>()
    var fetches = 0
    var isOffline = false

    val lastWriter: String? get() = writers["u"]

    fun seed(uid: String, ayahs: Map<Int, AyahMemory>, revisionJson: String? = null) {
        blocks[uid] = CloudBackup.blocks(ayahs).filterValues { it.isNotEmpty() }
        if (revisionJson != null) revisions[uid] = Revision(revisionJson, emptyList(), emptyList())
    }

    fun blocks(uid: String): Map<Int, BackupBlock> = blocks[uid].orEmpty()
    fun revisionJson(uid: String): String? = revisions[uid]?.json

    override suspend fun lastWriter(uid: String): String? {
        if (isOffline) throw java.io.IOException("offline")
        return writers[uid]
    }

    override suspend fun fetchProgress(uid: String): CloudProgress {
        if (isOffline) throw java.io.IOException("offline")
        fetches += 1
        events += Event.FETCH
        val revision = revisions[uid]
        return CloudProgress(blocks[uid].orEmpty(), revision?.json, revision?.revisedDays.orEmpty(), revision?.completedDays.orEmpty(), journeys[uid])
    }

    override suspend fun write(uid: String, write: CloudWrite) {
        if (isOffline) throw java.io.IOException("offline")
        writes += write
        events += Event.WRITE
        writers[uid] = write.writer
        val merged = HashMap(blocks[uid].orEmpty())
        for ((index, rows) in write.rows) merged[index] = merged[index].orEmpty() + rows
        blocks[uid] = merged
        write.revisionJson?.let { json ->
            val revision = revisions.getOrPut(uid) { Revision(null, emptyList(), emptyList()) }
            revision.json = json
            revision.revisedDays = revision.revisedDays + write.revisedDays.filter { it !in revision.revisedDays }
            revision.completedDays = revision.completedDays + write.completedDays.filter { it !in revision.completedDays }
        }
        write.journeyJson?.let { journeys[uid] = it }
    }

    override suspend fun deleteProgress(uid: String) {
        if (isOffline) throw java.io.IOException("offline")
        events += Event.DELETE
        blocks.remove(uid)
        revisions.remove(uid)
        journeys.remove(uid)
    }
}
