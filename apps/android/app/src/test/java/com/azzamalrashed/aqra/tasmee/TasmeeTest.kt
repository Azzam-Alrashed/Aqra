package com.azzamalrashed.aqra.tasmee

import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.TestDates.utc
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.revision.ReviewPolicy
import com.azzamalrashed.aqra.revision.RevisionRecord
import com.azzamalrashed.aqra.revision.RevisionStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The tasmee' values and how a tasmee' is applied to the student's progress: the same checks as the iOS app's. */
class TasmeeTest {
    @Test
    fun biddingClosesThreeHoursBeforeOrLateForASessionSoon() {
        val now = day(0)
        // How many minutes from now bidding closes, for a session starting in [minutes].
        fun closes(minutes: Int): Long? = TasmeeSession.biddingClosesAt(now + minutes * 60.0, now)?.let { Math.round((it - now) / 60) }
        // Far enough: three hours before.
        assertEquals(21 * 60L, closes(24 * 60))
        assertEquals(30L, closes(210))
        // Sooner, three hours before would leave under half an hour to bid: 30 minutes before instead.
        assertEquals(170L, closes(200))
        assertEquals(30L, closes(60))
        // Under an hour away: no auction.
        assertNull(closes(59))
    }

    @Test
    fun valuesSurviveTheirDocuments() {
        val teacher = Teacher("t", "الشيخ أحمد", "الدمام", "إجازة", vetted = true)
        assertEquals(teacher, Teacher.from("t", teacher.document))
        assertNull(Teacher.from("t", mapOf("city" to "x")))

        val session = TasmeeSession("s", "t", "الشيخ أحمد", day(1), place = "المسجد", seats = 5, booked = 2, createdAt = day(0))
        assertEquals(session, TasmeeSession.from("s", session.document))
        assertEquals("inPerson", session.document["kind"])
        // Firestore hands numbers back as Long or Double.
        val document = session.document.toMutableMap()
        document["seats"] = 5L
        document["booked"] = 2.0
        assertEquals(session, TasmeeSession.from("s", document))
        document["status"] = "done"
        assertNull(TasmeeSession.from("s", document))
        assertTrue(session.seatsLeft == 3 && !session.isFull && session.isUpcoming(day(0)) && !session.isUpcoming(day(2)))
        val cancelled = session.copy(status = TasmeeSession.Status.CANCELLED)
        assertTrue(!cancelled.isUpcoming(day(0)) && !cancelled.isCurrent(day(0)))

        val seat = Seat("alice", "Alice", day(0), 40, "٣٠، ٢٩")
        assertEquals(seat, Seat.from("alice", seat.document))
        val bare = Seat("bob", "Bob", day(0), 0)
        assertTrue("juzSummary" !in bare.document && Seat.from("bob", bare.document) == bare)

        val booking = Booking(session)
        assertTrue(booking.id == "s" && booking.teacherName == "الشيخ أحمد" && booking.startsAt == day(1))
        assertEquals(booking, Booking.from("s", booking.document))

        val record = TasmeeRecord("r", teacherId = "t", teacherName = "الشيخ أحمد", sessionId = "s", at = day(1), pages = listOf(2, 3), stumbles = listOf(8, 20))
        assertTrue("appliedAt" in record.document && record.document["appliedAt"] == null)
        assertEquals(record, TasmeeRecord.from("r", record.document))
        assertEquals(day(2), TasmeeRecord.from("r", record.copy(appliedAt = day(2)).document)?.appliedAt)
        assertNull(TasmeeRecord.from("r", record.document - "pages"))
    }

    @Test
    fun aVideoSessionsCallIsOpenFromAQuarterOfAnHourBeforeUntilThreeHoursAfter() {
        val starts = day(1)
        val session = TasmeeSession("s", "t", "الشيخ أحمد", starts, TasmeeSession.Kind.VIDEO, place = "", seats = 5)
        assertFalse(CallModel.isOpen(session, starts + (-16 * 60.0)))
        assertTrue(CallModel.isOpen(session, starts + (-15 * 60.0)))
        assertTrue(CallModel.isOpen(session, starts + 3 * 3_600.0))
        assertFalse(CallModel.isOpen(session, starts + (3 * 3_600.0 + 1)))
        // Only a video session has a call, and not once it's cancelled.
        assertFalse(CallModel.isOpen(session.copy(kind = TasmeeSession.Kind.IN_PERSON), starts))
        assertFalse(CallModel.isOpen(session.copy(status = TasmeeSession.Status.CANCELLED), starts))
    }

    @Test
    fun applyingATasmeeRecordsASheikhRevisionAndVerifies() {
        val policy = ReviewPolicy.STANDARD
        val memorization = MemorizationStore(file = null)
        val revision = RevisionStore(file = null, zone = utc)
        memorization.mark(7..11, memorized = true)
        revision.setDailyPages(2)
        revision.refreshPlan(listOf(2), now = day(5))

        // Page 2 holds ayat 7…20; the student memorized 7…11 and stumbled on 8 (and on 300, which isn't on the page).
        val record = TasmeeRecord("r", teacherId = "t", teacherName = "x", sessionId = "s", at = day(5), pages = listOf(2, 9), stumbles = listOf(8, 300))
        TasmeeApply.apply(record, memorization, revision) { if (it == 2) 7..20 else 500..520 }

        // One revision, the sheikh's, of page 2 with the stumble that was on it; page 9 had nothing memorized.
        assertEquals(1, revision.history.size)
        assertEquals(RevisionRecord.Source.SHEIKH, revision.history.last().source)
        assertEquals(listOf(8), revision.history.last().stumbles)
        assertEquals(2, revision.history.last().page)
        // The stumbled ayah weakened and isn't verified; the clean ones grew by the sheikh's weight and are.
        assertTrue(memorization.memory(8)!!.lapses == 1 && !memorization.memory(8)!!.verified)
        for (ayah in listOf(7, 9, 10, 11)) {
            assertTrue(memorization.memory(ayah)!!.verified)
            assertEquals(policy.declaredStability * (1 + (policy.growth - 1) * policy.sheikhWeight), memorization.memory(ayah)!!.stability, 1e-9)
        }
        // Ayat the student never marked stay unmarked.
        assertEquals(0, memorization.memorizedCount(12..20))
        // The page follows up tomorrow, the day counts, and today's plan item is checked off.
        assertEquals(day(6).startOfDay(utc), revision.followUps[2]?.due)
        assertTrue(day(5).startOfDay(utc) in revision.revisedDays)
        assertTrue(revision.plan!!.items.first { it.page == 2 }.done)
    }

    @Test
    fun recordsCarryTheirKindMistakesAndTest() {
        val record = TasmeeRecord("r", teacherId = "t", teacherName = "x", sessionId = "s", at = day(1), pages = listOf(2, 3), stumbles = listOf(8, 20),
            mistakes = listOf(Mistake(20, MistakeType.HESITATION)), test = TasmeeRecord.StageTest(10, 1))
        val decoded = TasmeeRecord.from("r", record.document)
        assertEquals(record, decoded)
        assertTrue(decoded!!.kind == TasmeeRecord.Kind.SHEIKH && record.document["kind"] == "sheikh")
        assertTrue(record.mistakeType(20) == MistakeType.HESITATION && record.mistakeType(8) == MistakeType.MEMORIZATION)
        // Two mistakes over two pages, one allowed per page: passed. A third would fail it.
        assertEquals(true, record.passesTest)
        assertEquals(false, record.copy(stumbles = record.stumbles + 25).passesTest)
        // Records written before kinds existed are a sheikh's.
        val old = record.document - setOf("kind", "mistakes", "test")
        assertEquals(TasmeeRecord.Kind.SHEIKH, TasmeeRecord.from("r", old)?.kind)
        assertNull(TasmeeRecord.from("r", old)?.test)
        assertNull(TasmeeRecord.from("r", old)?.passesTest)
        // Sessions by video, and bookings of them.
        val call = TasmeeSession("c", "t", "x", day(1), TasmeeSession.Kind.VIDEO, "", 3)
        assertEquals(TasmeeSession.Kind.VIDEO, TasmeeSession.from("c", call.document)?.kind)
        assertEquals(TasmeeSession.Kind.VIDEO, Booking.from("c", Booking(call).document)?.kind)
        assertEquals(TasmeeSession.Kind.IN_PERSON, Booking.from("c", Booking(call).document - "kind")?.kind)
    }

    @Test
    fun aPeersTasmeeCountsAsAPeerRevisionAndNeverVerifies() {
        val policy = ReviewPolicy.STANDARD
        val memorization = MemorizationStore(file = null)
        val revision = RevisionStore(file = null, zone = utc)
        memorization.mark(7..11, memorized = true)
        val record = TasmeeRecord("p", TasmeeRecord.Kind.PEER, "friend", "", "ABC234", day(5), listOf(2), listOf(8))
        TasmeeApply.apply(record, memorization, revision) { 7..20 }
        assertTrue(revision.history.last().source == RevisionRecord.Source.PEER && revision.history.last().stumbles == listOf(8))
        assertEquals(1, memorization.memory(8)!!.lapses)
        for (ayah in listOf(7, 9, 10, 11)) {
            assertFalse(memorization.memory(ayah)!!.verified)
            assertEquals(policy.declaredStability * (1 + (policy.growth - 1) * policy.peerWeight), memorization.memory(ayah)!!.stability, 1e-9)
        }
        assertTrue(policy.weight(RevisionRecord.Source.APP) < policy.weight(RevisionRecord.Source.PEER) &&
            policy.weight(RevisionRecord.Source.PEER) < policy.weight(RevisionRecord.Source.SHEIKH))
    }

    @Test
    fun peerCodesAreShortClearAndRoundTrip() {
        repeat(50) {
            val code = PeerRequest.randomCode()
            assertTrue(PeerRequest.isWellFormed(code))
            assertTrue("O" !in code && "0" !in code && "I" !in code && "1" !in code)
        }
        assertEquals("ABC234", PeerRequest.normalize(" abc-234 "))
        assertTrue(!PeerRequest.isWellFormed("ABC23") && !PeerRequest.isWellFormed("ABC2340") && !PeerRequest.isWellFormed("ABC0O4"))
        val request = PeerRequest("ABC234", "alice", "Alice", 582, day(0), day(0) + PeerRequest.LIFETIME)
        assertEquals(request, PeerRequest.from("ABC234", request.document))
        assertEquals("ABC234", PeerRequest.code(request.link))
        assertNull(PeerRequest.code("aqra://friend/ABC234"))
        assertTrue(request.isValid(day(0)) && !request.isValid(day(1)))
        val unnamed = PeerRequest("ABC234", "alice", null, createdAt = day(0), expiresAt = day(0))
        assertTrue("studentName" !in unnamed.document && "startPage" !in unnamed.document)
    }

    @Test
    fun anApplicationSurvivesItsDocumentAndKnowsWhenItsComplete() {
        var application = TeacherApplication("alice", "أحمد", city = "الدمام", ijazahFrom = "الشيخ فلان", contact = "0500000000", createdAt = day(0), updatedAt = day(0))
        assertFalse(application.isComplete)
        application = application.copy(files = listOf("ijazahs/alice/a.jpg"))
        assertTrue(application.isComplete && application.canEdit)
        assertEquals(application, TeacherApplication.from("alice", application.document))
        assertFalse(application.copy(status = TeacherApplication.Status.INTERVIEW).canEdit)
        assertEquals("ijazahs/alice/a.pdf", TeacherApplication.filePath("alice", "a.pdf"))
    }

    @Test
    fun studentFilesReadTheirDocuments() {
        val file = StudentFile.from("alice", mapOf("name" to "Alice", "lastHeardAt" to day(2), "notes" to "سورة الملك"))
        assertNotNull(file)
        assertTrue(file!!.name == "Alice" && file.lastHeardAt == day(2) && file.notes == "سورة الملك")
        assertNull(StudentFile.from("bob", mapOf("notes" to "x")))
    }
}
