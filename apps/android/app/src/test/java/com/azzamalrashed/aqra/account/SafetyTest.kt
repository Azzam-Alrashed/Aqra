package com.azzamalrashed.aqra.account

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Blocking someone hides them on this device, and lasts; a report carries what the team needs, in bounds. As on iOS. */
class SafetyTest {
    @Test
    fun blockingLastsAndUnblockingUndoesIt() {
        var saved: String? = null
        val safety = SafetyStore({ saved }, { saved = it })
        val teacher = PersonRef("t1", "الشيخ أحمد", PersonReport.Context.TEACHER)
        safety.block(teacher)
        safety.block(teacher)
        assertEquals(1, safety.blocked.size)
        assertTrue(SafetyStore({ saved }, { saved = it }).isBlocked("t1"))
        safety.unblock("t1")
        assertFalse(SafetyStore({ saved }, { saved = it }).isBlocked("t1"))
    }

    @Test
    fun readsTheListTheIosAppWrites() {
        val safety = SafetyStore({ """[{"uid":"f1","name":"سارة"}]""" }, {})
        assertTrue(safety.isBlocked("f1"))
        assertEquals("سارة", safety.blocked.single().name)
    }

    @Test
    fun aReportHoldsWhatTheRulesTake() {
        val person = PersonRef("s1", "ن".repeat(150), PersonReport.Context.CALL, "session-1")
        val fields = PersonReport(person, PersonReport.Reason.ABUSE, "  " + "x".repeat(1_200) + "  ").fields("me")
        assertEquals("me", fields["reporter"])
        assertEquals("s1", fields["subject"])
        assertEquals("call", fields["context"])
        assertEquals("session-1", fields["contextId"])
        assertEquals("abuse", fields["reason"])
        assertEquals(100, (fields["subjectName"] as String).length)
        assertEquals(PersonReport.NOTE_LIMIT, (fields["note"] as String).length)
        assertEquals(setOf("reporter", "subject", "subjectName", "context", "contextId", "reason", "note"), fields.keys)
    }

    @Test
    fun anEmptyNoteIsLeftOut() {
        val fields = PersonReport(PersonRef("f1", "", PersonReport.Context.FRIEND), PersonReport.Reason.SPAM, "   ").fields("me")
        assertNull(fields["note"])
        assertNull(fields["contextId"])
    }
}
