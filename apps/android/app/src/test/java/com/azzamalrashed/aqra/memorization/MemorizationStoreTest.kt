package com.azzamalrashed.aqra.memorization

import com.azzamalrashed.aqra.TestQuran
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.ReviewPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class MemorizationStoreTest {
    @Test
    fun marksTogglesAndCounts() {
        val memorization = MemorizationStore(file = null)
        memorization.toggle(7)
        assertTrue(memorization.isMemorized(7) && memorization.count == 1)
        memorization.mark(0..6, memorized = true)
        assertEquals(8, memorization.count)
        assertEquals(8, memorization.memorizedCount(0..9))
        memorization.toggle(7)
        assertFalse(memorization.isMemorized(7))
        // Numbers outside the Quran's 6,236 ayat are ignored.
        memorization.mark(listOf(-1, MushafStore.AYAH_COUNT), memorized = true)
        assertEquals(7, memorization.count)
        // Newly marked ayat start faint (a modest half-life, not yet revised) and unverified.
        val memory = memorization.memory(0)!!
        assertEquals(ReviewPolicy.STANDARD.declaredStability, memory.stability, 0.0)
        assertNull(memory.lastReviewed)
        assertFalse(memory.verified)
        assertTrue((memorization.strength(0) ?: 1.0) < 0.2)
    }

    /** A file written by an earlier version (version 2, before unmarking was remembered) still loads whole. */
    @Test
    fun anOlderMemorizationFileStillLoads() {
        val file = File(Files.createTempDirectory("aqra-memorization").toFile(), "memorization.json")
        file.writeText("""{"version":2,"ayahs":[{"ayah":5,"memory":{"stability":21.5,"lastReviewed":821692800.0,"lapses":1,"verified":true,"since":800000000.0}},""" +
            """{"ayah":6,"memory":{"since":800000000.0}}]}""")
        val memorization = MemorizationStore(file)
        assertTrue(!memorization.loadFailed && memorization.count == 2 && memorization.removed.isEmpty())
        val memory = memorization.memory(5)!!
        assertTrue(memory.stability == 21.5 && memory.verified && memory.lapses == 1 && memory.lastReviewed == Moment(821_692_800.0))
        assertEquals(ReviewPolicy.STANDARD.declaredStability, memorization.memory(6)!!.stability, 0.0)
    }

    @Test
    fun unmarkingLeavesATombstoneUntilTheAyahIsMarkedAgain() {
        val file = File(Files.createTempDirectory("aqra-memorization").toFile(), "memorization.json")
        val memorization = MemorizationStore(file)
        memorization.mark(listOf(1, 2, 3), memorized = true)
        memorization.mark(listOf(2), memorized = false)
        assertTrue(memorization.removed.keys == setOf(2) && memorization.memory.removed.size == 1)
        memorization.saveNow()
        // The tombstone is kept with the file, so a merge after a relaunch still knows.
        val reloaded = MemorizationStore(file)
        assertTrue(reloaded.removed.keys == setOf(2) && reloaded.count == 2)
        // Marking it again, or learning it as a new portion, takes the tombstone away.
        reloaded.mark(listOf(2), memorized = true)
        assertTrue(reloaded.removed.isEmpty())
        reloaded.mark(listOf(3), memorized = false)
        reloaded.learn(listOf(3), stability = 2.0)
        assertTrue(reloaded.removed.isEmpty() && reloaded.count == 3)
        // An undo brings the record back, dated from the undo, and takes the tombstone away.
        val unmarked = reloaded.mark(listOf(1), memorized = false)
        reloaded.restore(unmarked)
        assertTrue(reloaded.isMemorized(1) && reloaded.removed.isEmpty() && reloaded.memory(1)!!.since >= unmarked[1]!!.since)
        // A merge with the account keeps what the account unmarked too.
        reloaded.replaceAll(com.azzamalrashed.aqra.account.CloudBackup.Memory(mapOf(1 to AyahMemory(since = Moment.now())), mapOf(9 to Moment.now())))
        assertTrue(reloaded.count == 1 && reloaded.removed.keys == setOf(9))
    }

    @Test
    fun verifyingMarksOnlyMemorizedAyat() {
        val memorization = MemorizationStore(file = null)
        var changes = 0
        memorization.onChange = { changes += 1 }
        memorization.mark(10..12, memorized = true)
        memorization.verify(listOf(11, 12, 13))
        assertTrue(memorization.memory(11)!!.verified && memorization.memory(12)!!.verified)
        assertTrue(!memorization.memory(10)!!.verified && !memorization.isMemorized(13))
        assertEquals(2, changes)
        // Verifying what's already verified changes nothing.
        memorization.verify(listOf(11))
        assertEquals(2, changes)
        // A stumble before the teacher takes the mark away.
        memorization.verify(listOf(11, 12), except = setOf(12))
        assertTrue(memorization.memory(11)!!.verified && !memorization.memory(12)!!.verified)
        assertEquals(3, changes)
    }

    @Test
    fun theQuransSharesCountEveryJuzEquallyInEveryMeasure() {
        val store = TestQuran.store
        val memorization = MemorizationStore(file = null)
        // Juz' ʿAmma, all mastered and verified: a ninth of the Quran's ayat, but a thirtieth of the Mushaf. Mastered
        // and verified are measured as memorized is, so they can't read more than it.
        val amma = store.juzAyahs.getValue(30)
        memorization.replaceAll(amma.associateWith { AyahMemory(stability = 90.0, since = Moment.now()) })
        memorization.verify(amma)
        val memorized = memorization.quranShare(store)
        assertEquals(1.0 / 30, memorized, 0.000_1)
        assertEquals(memorized, memorization.quranShare(store) { memorization.masteredCount(it) }, 0.0)
        assertEquals(memorized, memorization.quranShare(store) { memorization.verifiedCount(it) }, 0.0)
    }

    @Test
    fun savesAndReloads() {
        val file = File.createTempFile("memorization", ".json").apply { delete(); deleteOnExit() }
        val memorization = MemorizationStore(file)
        memorization.mark(100..120, memorized = true)
        memorization.saveNow()
        val reloaded = MemorizationStore(file)
        assertEquals(21, reloaded.count)
        assertTrue(reloaded.isMemorized(110) && !reloaded.isMemorized(121))
    }

    /** Files from before revision existed (version 1, written by the iOS app) hold only strength, verified and since. */
    @Test
    fun oldMemorizationFilesStillLoad() {
        val file = File.createTempFile("memorization-v1", ".json").apply { deleteOnExit() }
        file.writeText("""{"version":1,"ayahs":[{"ayah":5,"memory":{"strength":0,"verified":false,"since":800000000}}]}""")
        val memorization = MemorizationStore(file)
        assertTrue(memorization.isMemorized(5))
        assertEquals(ReviewPolicy.STANDARD.declaredStability, memorization.memory(5)!!.stability, 0.0)
    }

    @Test
    fun markingSessionMarksRangesAndPages() {
        val memorization = MemorizationStore(file = null)
        val session = MarkingSession(memorization)
        // A held press starts a range at an unmarked ayah, marking it; the next tap marks everything up to it.
        session.beginRange(14)
        assertTrue(memorization.isMemorized(14) && session.rangeStart == 14)
        session.tap(10)
        assertTrue(memorization.memorizedCount(10..14) == 5 && session.rangeStart == null)
        // Starting on a marked ayah unmarks the range instead.
        session.beginRange(12)
        session.tap(13)
        assertEquals(3, memorization.memorizedCount(10..14))
        // Without a range, a tap toggles one ayah.
        session.tap(12)
        assertTrue(memorization.isMemorized(12))
        // A whole page: marks all of it unless it's all marked already, then unmarks it.
        session.toggle(10..14)
        assertEquals(5, memorization.memorizedCount(10..14))
        session.toggle(10..14)
        assertEquals(0, memorization.memorizedCount(10..14))
    }

    /** «حدّد نطاقًا»: the next tap starts a range, the one after ends it; cancelling goes back to single taps. */
    @Test
    fun aRangeCanBeChosenWithAButton() {
        val memorization = MemorizationStore(file = null)
        val session = MarkingSession(memorization)
        session.chooseRange()
        assertTrue(session.choosingRangeStart && session.rangeStart == null)
        session.tap(40)
        assertTrue(!session.choosingRangeStart && session.rangeStart == 40 && memorization.isMemorized(40))
        session.tap(44)
        assertTrue(session.rangeStart == null && memorization.memorizedCount(40..44) == 5)
        session.chooseRange()
        session.cancelRange()
        session.tap(50)
        assertTrue(memorization.isMemorized(50) && session.rangeStart == null && memorization.count == 6)
    }

    /** The records with their dates of memorization set aside: an undo dates them from itself. */
    private fun ignoringSince(ayahs: Map<Int, AyahMemory>) = ayahs.mapValues { (_, memory) -> memory.copy(since = Moment.DISTANT_PAST) }

    @Test
    fun undoingAnUnmarkingRestoresTheRecordsExactly() {
        val memorization = MemorizationStore(file = null)
        val session = MarkingSession(memorization)
        memorization.mark(20..29, memorized = true)
        memorization.recordRevision(20..29, stumbled = setOf(22), at = Moment.now(), policy = ReviewPolicy.STANDARD)
        memorization.verify(listOf(23, 24))
        val before = memorization.ayahs

        // Marking offers nothing to undo.
        session.tap(30)
        assertTrue(session.unmarked.isEmpty())
        session.tap(30)

        // A tap: the ayah comes back with its revisions, stumble and teacher's mark.
        session.tap(22)
        assertTrue(session.unmarked.size == 1 && !memorization.isMemorized(22))
        session.undo()
        assertTrue(ignoringSince(memorization.ayahs) == ignoringSince(before) && session.unmarked.isEmpty())
        // Dated from the undo, so that across devices the unmarking is seen to come before it; the tombstone goes.
        assertTrue(memorization.memory(22)!!.since >= before[22]!!.since && 22 !in memorization.removed)

        // A range that unmarks counts its first ayah, unmarked when the range began.
        session.beginRange(21)
        assertEquals(1, session.unmarked.size)
        session.tap(24)
        assertTrue(session.unmarked.size == 4 && memorization.memorizedCount(20..29) == 6)
        session.undo()
        assertEquals(ignoringSince(before), ignoringSince(memorization.ayahs))

        // A whole page.
        session.toggle(20..29)
        assertTrue(session.unmarked.size == 10 && memorization.count == 0)
        session.undo()
        assertEquals(ignoringSince(before), ignoringSince(memorization.ayahs))

        // The undo expires, but an earlier unmarking's timer doesn't take a later one's.
        session.tap(25)
        val first = session.unmarkedVersion
        session.tap(26)
        session.expireUndo(first)
        assertEquals(listOf(26), session.unmarked.keys.sorted())
        session.expireUndo(session.unmarkedVersion)
        assertTrue(session.unmarked.isEmpty())
    }
}
