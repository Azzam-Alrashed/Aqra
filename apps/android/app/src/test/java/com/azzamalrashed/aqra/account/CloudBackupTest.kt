package com.azzamalrashed.aqra.account

import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.memorization.AyahMemory
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.revision.DayPlan
import com.azzamalrashed.aqra.revision.FollowUp
import com.azzamalrashed.aqra.revision.PlanItem
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionRecord.Source
import com.azzamalrashed.aqra.revision.RevisionStore
import com.azzamalrashed.aqra.revision.RevisionStore.Snapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The account backup's format and merge rules, without the network: the same checks as the iOS app's. */
class CloudBackupTest {
    private fun memory(since: Int, reviewed: Int? = null, stability: Double = 14.0, verified: Boolean = false) =
        AyahMemory(stability = stability, lastReviewed = reviewed?.let(::day), lapses = 2, verified = verified, since = day(since))

    @Test
    fun ayatSurviveTheTripThroughBlocks() {
        val ayahs = mapOf(0 to memory(0), 255 to memory(1, reviewed = 3, verified = true),
            256 to memory(2, stability = 33.5), 6235 to memory(4, reviewed = 9))
        val blocks = CloudBackup.blocks(ayahs)
        assertEquals(CloudBackup.BLOCK_COUNT, blocks.size)
        assertTrue(blocks[0]!!.size == 2 && blocks[1]!!.size == 1 && blocks[24]!!.size == 1 && blocks[5]!!.isEmpty())
        assertEquals(ayahs, CloudBackup.ayahs(blocks.values))
        // Rows that can't be read are skipped rather than failing the restore.
        assertTrue(CloudBackup.ayahs(listOf(mapOf("7" to listOf(1.0, 2.0)), mapOf("x" to listOf(1.0, 14.0, -1.0, 0.0, 0.0)),
            mapOf("9000" to listOf(1.0, 14.0, -1.0, 0.0, 0.0)))).isEmpty())
    }

    @Test
    fun mergingKeepsEverythingMemorizedAndTheLatestRevision() {
        val local = mapOf(1 to memory(0, reviewed = 5, stability = 20.0), 2 to memory(0), 3 to memory(0, reviewed = 2, verified = true))
        val remote = mapOf(1 to memory(0, reviewed = 8, stability = 40.0), 3 to memory(0, reviewed = 6), 4 to memory(1))
        val merged = CloudBackup.merge(local, remote)
        assertEquals(setOf(1, 2, 3, 4), merged.keys)
        assertEquals(40.0, merged[1]!!.stability, 0.0)                           // revised later on the account
        assertTrue(merged[3]!!.lastReviewed == day(6) && merged[3]!!.verified)      // the teacher's mark is kept
        assertEquals(merged, CloudBackup.merge(remote, local))
    }

    @Test
    fun mergingTheRevisionRecordKeepsTheStreakAndHistoryOfBoth() {
        val a = RevisionRecord(day(1), 3, Source.APP, emptyList())
        val b = RevisionRecord(day(2), 4, Source.OUTSIDE, emptyList())
        val c = RevisionRecord(day(3), 5, Source.APP, listOf(9))
        var local = Snapshot(dailyPages = 4, rotationCursor = 10, history = listOf(a, b), revisedDays = listOf(day(1), day(2)), updatedAt = day(2))
        val remote = Snapshot(dailyPages = 6, rotationCursor = 20, history = listOf(b, c), revisedDays = listOf(day(2), day(3)), updatedAt = day(3))
        var merged = CloudBackup.merge(local, remote)
        assertTrue(merged.dailyPages == 6 && merged.rotationCursor == 20)   // the account changed and revised more recently
        assertEquals(listOf(day(1), day(2), day(3)), merged.revisedDays)
        assertEquals(listOf(a, b, c), merged.history)
        // A daily amount chosen later on the device wins; the rotation still follows the latest revising.
        local = local.copy(updatedAt = day(4))
        merged = CloudBackup.merge(local, remote)
        assertTrue(merged.dailyPages == 4 && merged.rotationCursor == 20 && merged.updatedAt == day(4))

        // A device just cleared (signed out, then in again) is newer but has nothing to offer: the account's
        // amount, place and history come back.
        val cleared = Snapshot.EMPTY.copy(updatedAt = day(9))
        merged = CloudBackup.merge(cleared, remote)
        assertTrue(merged.dailyPages == 6 && merged.rotationCursor == 20 && merged.history == listOf(b, c))

        // A new install that hasn't changed anything yet takes the account's copy, even when neither is dated.
        val undated = remote.copy(updatedAt = Moment.DISTANT_PAST)
        merged = CloudBackup.merge(Snapshot.EMPTY, undated)
        assertTrue(merged.dailyPages == 6 && merged.rotationCursor == 20)
    }

    @Test
    fun theRevisionRecordSurvivesItsJson() {
        val revision = RevisionStore(file = null)
        val memorization = MemorizationStore(file = null)
        memorization.mark(listOf(7), memorized = true)
        revision.setDailyPages(5)
        revision.refreshPlan(listOf(1, 2, 3))
        revision.record(2, listOf(7), emptySet(), Source.SHEIKH, memorization)
        val decoded = CloudBackup.decodeRevision(CloudBackup.encode(revision.snapshot))
        assertEquals(revision.snapshot, decoded)
        assertEquals(Source.SHEIKH, decoded!!.history.last().source)
    }

    /** The account's revision record as the iOS app writes it (Swift's JSONEncoder), read by this app. */
    @Test
    fun readsTheRevisionRecordTheIosAppWrites() {
        val ios = """{"dailyPages":4,"plan":{"day":821692800,"items":[{"page":11,"kind":"followUp","done":true},{"kind":"rotation","done":false,"page":12}]},"followUps":{"11":{"due":821779200,"step":0},"300":{"due":821692800,"step":2}},"rotationCursor":13,"history":[{"stumbles":[100,101],"source":"sheikh","date":821696461.5,"page":11}],"revisedDays":[821692800],"updatedAt":821692800.123456}"""
        val day = Moment(821_692_800.0)
        val expected = Snapshot(
            dailyPages = 4, rotationCursor = 13,
            followUps = mapOf(11 to FollowUp(Moment(821_779_200.0), 0), 300 to FollowUp(day, 2)),
            plan = DayPlan(day, listOf(PlanItem(11, PlanItem.Kind.FOLLOW_UP, done = true), PlanItem(12, PlanItem.Kind.ROTATION))),
            history = listOf(RevisionRecord(Moment(821_696_461.5), 11, Source.SHEIKH, listOf(100, 101))),
            revisedDays = listOf(day), updatedAt = Moment(821_692_800.123456),
        )
        assertEquals(expected, CloudBackup.decodeRevision(ios))
        // An empty record, with the distant past the iOS app starts from.
        val empty = """{"updatedAt":-63114076800,"followUps":{},"revisedDays":[],"history":[],"rotationCursor":1}"""
        assertEquals(Snapshot.EMPTY, CloudBackup.decodeRevision(empty))
    }

    /** What this app writes holds every key the iOS app requires, with optional ones left out when missing. */
    @Test
    fun writesTheRevisionRecordAsTheIosAppReadsIt() {
        val json = CloudBackup.encode(Snapshot.EMPTY)
        for (key in listOf("rotationCursor", "followUps", "history", "revisedDays", "updatedAt")) assertTrue(key, "\"$key\"" in json)
        assertTrue("\"dailyPages\"" !in json && "\"plan\"" !in json && "null" !in json)
        val withPlan = CloudBackup.encode(Snapshot(followUps = mapOf(11 to FollowUp(Moment(1.0), 0))))
        assertTrue(withPlan, "\"followUps\":{\"11\":{\"due\":1.0,\"step\":0}}" in withPlan)
    }

    @Test
    fun restoringReplacesTheStoresAndReportsTheChange() {
        val memorization = MemorizationStore(file = null)
        val revision = RevisionStore(file = null)
        var changes = 0
        memorization.onChange = { changes += 1 }
        revision.onChange = { changes += 1 }

        memorization.replaceAll(mapOf(7 to memory(0), 8 to memory(0)))
        revision.apply(Snapshot(dailyPages = 3, rotationCursor = 50, revisedDays = listOf(day(0)), updatedAt = day(0)))
        assertTrue(memorization.count == 2 && revision.dailyPages == 3 && revision.rotationCursor == 50)
        assertEquals(2, changes)

        // Clearing the device on signing out.
        memorization.replaceAll(emptyMap())
        revision.apply(Snapshot.EMPTY)
        assertTrue(memorization.count == 0 && revision.dailyPages == null && revision.revisedDays.isEmpty())
    }
}

/** What a newer app writes into the account is carried back untouched. */
class CloudBackupForwardTest {
    @org.junit.Test
    fun fieldsThisAppDoesntKnowAreKept() {
        val newer = """{"rotationCursor":4,"followUps":{},"history":[],"revisedDays":[813013200],"laterField":[813013200],"updatedAt":1.5}"""
        val extras = CloudBackup.unknownFields(newer)
        org.junit.Assert.assertEquals(setOf("laterField"), extras.keys)
        val snapshot = CloudBackup.decodeRevision(newer)!!.copy(rotationCursor = 9)
        val written = CloudBackup.encode(snapshot, extras)
        org.junit.Assert.assertTrue(written, "\"laterField\":[813013200]" in written)
        org.junit.Assert.assertEquals(9, CloudBackup.decodeRevision(written)!!.rotationCursor)

        val rows = listOf(mapOf("3" to listOf(1.0, 14.0, -1.0, 0.0, 0.0, 2.0, 7.0, 4.0, 5.0)))
        val memory = CloudBackup.ayahs(rows)
        val back = CloudBackup.blocks(memory, CloudBackup.extraValues(rows))
        org.junit.Assert.assertEquals(listOf(1.0, 14.0, -1.0, 0.0, 0.0, 2.0, 7.0, 4.0, 5.0), back[0]!!["3"])
    }
}
