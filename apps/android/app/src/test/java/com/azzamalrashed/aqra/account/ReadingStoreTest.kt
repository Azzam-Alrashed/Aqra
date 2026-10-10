package com.azzamalrashed.aqra.account

import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.curriculum.AssessmentStore
import com.azzamalrashed.aqra.plan.PlanStore
import com.azzamalrashed.aqra.rewards.RewardStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** The reader's ribbon, as the iOS app's JourneyTests check it. */
class ReadingStoreTest {
    /**
     * Placed and moved on the device, kept in its file, carried in the journey's backup, and merged so the later
     * choice wins, a removal included.
     */
    @Test
    fun theBookmarkSurvivesTheBackupAndMerges() {
        val file = File.createTempFile("reading", ".json").also { it.delete(); it.deleteOnExit() }
        val reading = ReadingStore(file)
        var changes = 0
        reading.onChange = { changes += 1 }
        reading.place(4, at = day(1))
        reading.place(4, at = day(2))           // the same page: nothing changes
        reading.place(605, at = day(2))         // past the Mushaf: ignored
        assertTrue(reading.bookmark == ReadingStore.Bookmark(4, day(1)) && changes == 1)
        assertEquals(4, ReadingStore(file).bookmark?.page)

        val journey = Journey(PlanStore(file = null), RewardStore(file = null), AssessmentStore(file = null), reading)
        val json = Journey.encode(journey.snapshot)
        assertEquals(4, Journey.decode(json)?.reading?.bookmark?.page)
        // A backup from before the ribbon existed reads with none.
        val old = Journey.decode(
            """{"plan":{"portions":[],"history":[],"updatedAt":0},"rewards":{"points":0,"events":[],"achievements":[],"challenges":[],"updatedAt":0},"assessments":{"results":[],"sheikhTests":[],"passes":{},"updatedAt":0}}""",
        )
        assertTrue(old != null && old.reading == null)

        // The later choice wins: a ribbon moved on another device, then a removal here.
        val here = ReadingStore.Snapshot(ReadingStore.Bookmark(4, day(1)), updatedAt = day(1))
        val there = ReadingStore.Snapshot(ReadingStore.Bookmark(50, day(3)), updatedAt = day(3))
        assertEquals(50, ReadingStore.Snapshot.merge(here, there).bookmark?.page)
        val removed = ReadingStore.Snapshot(null, updatedAt = day(5))
        assertNull(ReadingStore.Snapshot.merge(there, removed).bookmark)
        assertNull(Journey.Snapshot.merge(Journey.Snapshot(reading = there), Journey.Snapshot(reading = removed)).reading?.bookmark)
        reading.apply(there)
        assertEquals(50, reading.bookmark?.page)
    }
}
