package com.azzamalrashed.aqra.memorization

import com.azzamalrashed.aqra.quran.MushafStore
import com.azzamalrashed.aqra.revision.ReviewPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

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
}
