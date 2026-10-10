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
import org.junit.Assert.assertNull
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

    // MARK: - Merging across devices (the same checks as the iOS app's)

    @Test
    fun mergePrefersRevisedRecordOverFreshDeclaration() {
        // A hafiz on a new phone declares the juz' again (dated now, never revised), then signs in: months of
        // revision in the account win, and the memorization is dated from its earliest declaration.
        val history = memory(0, reviewed = 60, stability = 80.0, verified = true)
        val fresh = AyahMemory(since = day(90))
        for (merged in listOf(CloudBackup.merge(fresh, history), CloudBackup.merge(history, fresh))) {
            assertTrue(merged.stability == 80.0 && merged.lastReviewed == day(60) && merged.verified && merged.lapses == 2)
            assertEquals(day(0), merged.since)
        }
        // Neither revised: the earlier declaration is the record, still dated from the earliest.
        val early = AyahMemory(since = day(1))
        val late = AyahMemory(since = day(5), stability = 30.0)
        assertEquals(14.0, CloudBackup.merge(early, late).stability, 0.0)
        assertEquals(day(1), CloudBackup.merge(late, early).since)
        // When it was learned as a new portion is kept from whichever side knows.
        val learned = memory(3, reviewed = 4).copy(learnedAt = day(3))
        assertEquals(day(3), CloudBackup.merge(learned, memory(3, reviewed = 9)).learnedAt)
    }

    @Test
    fun mergeDropsVerifiedAfterALaterStumble() {
        // Verified by a sheikh on one device (day 10), then stumbled on with the other device (day 20).
        val verified = memory(0, reviewed = 10, stability = 40.0, verified = true).copy(lapses = 0)
        var stumbled = memory(0, reviewed = 20, stability = 12.0).copy(lapses = 1, lastLapseAt = day(20))
        val merged = CloudBackup.merge(verified, stumbled)
        assertTrue(!merged.verified && merged.lastLapseAt == day(20) && merged.lapses == 1)
        assertEquals(merged, CloudBackup.merge(stumbled, verified))
        // A stumble before the teacher heard it clean doesn't take the mark away.
        stumbled = stumbled.copy(lastLapseAt = day(5), lastReviewed = day(5))
        assertTrue(CloudBackup.merge(verified, stumbled).verified)
        // A device that never saw the tasmee' revised later, clean: the mark holds.
        assertTrue(CloudBackup.merge(verified, memory(0, reviewed = 30, stability = 50.0)).verified)
    }

    @Test
    fun mergeKeepsFollowUpsOfBothSides() {
        val a = RevisionRecord(day(1), 3, Source.APP, listOf(7))
        val b = RevisionRecord(day(2), 9, Source.APP, listOf(8))
        val local = Snapshot(
            followUps = mapOf(3 to FollowUp(day(2), 0), 5 to FollowUp(day(4), 1)),
            plan = DayPlan(day(2), listOf(PlanItem(3, PlanItem.Kind.FOLLOW_UP, done = true), PlanItem(4, PlanItem.Kind.ROTATION))),
            history = listOf(a), revisedDays = listOf(day(1)), updatedAt = day(1),
        )
        val remote = Snapshot(
            followUps = mapOf(5 to FollowUp(day(6), 2), 9 to FollowUp(day(3), 0)),
            plan = DayPlan(day(2), listOf(PlanItem(3, PlanItem.Kind.FOLLOW_UP), PlanItem(4, PlanItem.Kind.ROTATION, done = true))),
            history = listOf(b), revisedDays = listOf(day(2)), updatedAt = day(2),
        )
        val merged = CloudBackup.merge(local, remote)
        // Page by page: both sides' pages, each at its later date.
        assertEquals(mapOf(3 to FollowUp(day(2), 0), 5 to FollowUp(day(6), 2), 9 to FollowUp(day(3), 0)), merged.followUps)
        // The same day's plan: a page done on either device is done.
        assertEquals(listOf(true, true), merged.plan!!.items.map { it.done })
        assertEquals(merged.followUps, CloudBackup.merge(remote, local).followUps)
    }

    @Test
    fun unmarkedAyatStayUnmarkedAcrossDevices() {
        // Unmarked on the phone (day 5) after the account last touched the ayah (revised day 3): it stays gone.
        val phone = CloudBackup.Memory(mapOf(1 to memory(0)), mapOf(2 to day(5)))
        val account = CloudBackup.Memory(mapOf(1 to memory(0), 2 to memory(0, reviewed = 3)))
        var merged = CloudBackup.merge(phone, account)
        assertTrue(merged.ayahs.keys == setOf(1) && merged.removed == mapOf(2 to day(5)))
        assertEquals(merged, CloudBackup.merge(account, phone))
        // Marked again on the tablet after that (day 7): it's back, and the tombstone goes.
        val tablet = CloudBackup.Memory(mapOf(2 to AyahMemory(since = day(7))))
        merged = CloudBackup.merge(merged, tablet)
        assertTrue(merged.ayahs[2]!!.since == day(7) && merged.removed.isEmpty())
        // Tombstones travel through the blocks, and no app reads one as memorized.
        val blocks = CloudBackup.blocks(phone)
        assertEquals(CloudBackup.tombstone(day(5)), blocks[0]!!["2"])
        assertNull(CloudBackup.decode(CloudBackup.tombstone(day(5))))
        assertEquals(phone, CloudBackup.memory(blocks.values))
    }

    @Test
    fun decodeRejectsNonFiniteRows() {
        val good = listOf(day(0).epochSeconds, 14.0, -1.0, 0.0, 0.0, -1.0, -1.0)
        assertTrue(CloudBackup.decode(good) != null)
        for ((index, bad) in listOf(0 to Double.NaN, 1 to Double.POSITIVE_INFINITY, 2 to Double.NEGATIVE_INFINITY, 3 to Double.NaN,
            3 to 1e300, 0 to 1e300, 5 to Double.NaN, 6 to Double.POSITIVE_INFINITY)) {
            val row = good.toMutableList().also { it[index] = bad }
            assertNull("row[$index] = $bad", CloudBackup.decode(row))
            assertNull(CloudBackup.removedAt(row))
        }
        assertNull(CloudBackup.removedAt(listOf(Double.NaN, 0.0)))
        assertNull(CloudBackup.removedAt(listOf(1e300, 0.0)))
    }

    @Test
    fun strengthLevelHandlesNaN() {
        // A corrupt record's strength can't crash the page: it draws as the faintest shade.
        assertEquals(0, com.azzamalrashed.aqra.mushaf.TopicHighlight(0, Double.NaN).level)
        assertEquals(0, com.azzamalrashed.aqra.mushaf.TopicHighlight(0, Double.POSITIVE_INFINITY).level)
        assertEquals(2, com.azzamalrashed.aqra.mushaf.TopicHighlight(0, 0.5).level)
    }

    /** The account's journey as the iOS app writes it (Swift's JSONEncoder), read by this app. */
    @Test
    fun readsTheJourneyTheIosAppWrites() {
        // Dates as seconds since 2001, a dictionary keyed by an enum as a flat list, one keyed by a number as an
        // object, a set as a list, plus a challenge of a kind this version doesn't know and a part left out.
        val ios = """{"plan":{"plan":{"dailyLines":8,"studyDays":[1,2,3,4,5,7],"order":"fromEnd","paused":false},""" +
            """"portions":[{"id":"6B5D2E0A-2A3B-4C0D-9E8F-000000000001","date":821692800,"planned":[1,2],"memorized":[1],"plannedLines":2,"actualLines":1}],""" +
            """"history":[{"date":821692800,"plan":{"dailyLines":8,"studyDays":[1],"order":"fromStart","paused":false}}],"updatedAt":821692800},""" +
            """"rewards":{"points":12,"events":[{"date":821692800,"points":2,"reason":"page"}],"achievements":["firstRevision",821692800],""" +
            """"challenges":[{"id":"6B5D2E0A-2A3B-4C0D-9E8F-000000000003","kind":"wirdDays","target":5,"start":821692800,"end":822297600},""" +
            """{"id":"6B5D2E0A-2A3B-4C0D-9E8F-000000000004","kind":"later","target":1,"start":821692800,"end":822297600}],"updatedAt":821692800},""" +
            """"assessments":{"results":[{"id":"6B5D2E0A-2A3B-4C0D-9E8F-000000000002","stage":1,"date":821692800,"questions":10,"correct":9}],""" +
            """"sheikhTests":[{"id":"r1","stage":1,"date":821692800,"teacherName":"Sheikh","passed":true}],"passes":{"1":821692800},"updatedAt":821692800}}"""
        val decoded = Journey.decode(ios)!!
        val day = Moment(821_692_800.0)
        assertTrue(decoded.plan.plan?.dailyLines == 8 && decoded.plan.portions.size == 1 && decoded.plan.history.size == 1)
        assertEquals(2.0, decoded.plan.portions[0].plannedLines, 0.0)
        assertTrue(decoded.rewards.points == 12 && decoded.rewards.events.size == 1)
        assertEquals(mapOf("firstRevision" to day), decoded.rewards.achievements)
        assertEquals(1, decoded.rewards.challenges.size)   // the unknown kind is passed over, the rest kept
        assertTrue(decoded.assessments.results[0].correct == 9 && decoded.assessments.sheikhTests[0].passed)
        assertEquals(mapOf(1 to day), decoded.assessments.passes)
        // Missing parts are empty, not fatal.
        assertEquals(3, Journey.decode("""{"rewards":{"points":3}}""")!!.rewards.points)
        assertEquals(com.azzamalrashed.aqra.plan.PlanStore.Snapshot.EMPTY, Journey.decode("""{"rewards":{"points":3}}""")!!.plan)
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
