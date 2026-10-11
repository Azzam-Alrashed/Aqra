package com.azzamalrashed.aqra.revision

import com.azzamalrashed.aqra.tasmee.MistakeType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/**
 * Until listening is tried with real voices, the stumbles it hears are suggestions: recorded only once the student
 * keeps them in the page's summary (docs/SRS.md REV-18). As on iOS.
 */
class HeardStumbleTest {
    @Test
    fun heardStumblesAreSuggestionsUntilKept() {
        val session = RevisionSession(1, listOf(0, 1, 2, 3))
        session.revealAll()
        session.markStumble(1, setOf(MistakeType.HESITATION))
        session.tap(3)
        assertEquals(setOf(1, 3), session.stumbles)
        assertEquals(setOf(3), session.recordedStumbles)
        session.keepHeard(1, true)
        assertEquals(setOf(1, 3), session.recordedStumbles)
        session.keepHeard(1, false)
        assertEquals(setOf(3), session.recordedStumbles)
    }

    @Test
    fun theStudentsOwnMarkStaysTheirs() {
        val session = RevisionSession(1, listOf(0, 1, 2))
        session.revealAll()
        session.tap(2)
        session.markStumble(2, setOf(MistakeType.MEMORIZATION))
        assertEquals(setOf(2), session.recordedStumbles)
        session.markStumble(0, setOf(MistakeType.PROMPTING))
        session.markStumble(0)
        assertEquals(setOf(0, 2), session.recordedStumbles)
        session.tap(0)
        assertEquals(setOf(2), session.recordedStumbles)
        assertFalse(0 in session.heard)
    }

    @Test
    fun theMarksComeBackAsTheyWereSaved() {
        val session = RevisionSession(1, listOf(0, 1, 2))
        session.restoreMarks(stumbles = setOf(0, 1, 9), suggested = setOf(1), heard = setOf(1))
        assertEquals(setOf(0, 1), session.stumbles)
        assertEquals(setOf(0), session.recordedStumbles)
    }
}
