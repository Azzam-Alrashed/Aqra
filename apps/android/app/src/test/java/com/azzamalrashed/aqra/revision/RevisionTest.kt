package com.azzamalrashed.aqra.revision

import com.azzamalrashed.aqra.TestDates.calendarDay
import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.TestDates.start
import com.azzamalrashed.aqra.TestDates.utc
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.memorization.AyahMemory
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.revision.RevisionRecord.Source
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import com.azzamalrashed.aqra.core.CalendarDay
import com.azzamalrashed.aqra.account.CloudBackup
import com.azzamalrashed.aqra.tasmee.TasmeeApply
import com.azzamalrashed.aqra.tasmee.TasmeeRecord
import java.time.LocalDateTime
import java.time.ZoneId

/** The revision engine: the same checks as the iOS app's RevisionTests. */
class RevisionTest {
    private val policy = ReviewPolicy.STANDARD

    // MARK: - Ayah strength

    @Test
    fun strengthFadesWithTimeAndGrowsWithRevision() {
        val declared = AyahMemory(since = start)
        // Declared: faint, and fainter after a month without revision.
        assertTrue(declared.strength(start) < 0.2)
        assertTrue(declared.strength(day(30)) < declared.strength(start))

        // A clean revision after two weeks lengthens the half-life by the full growth; a stumble shortens it.
        val clean = declared.revised(stumbled = false, at = day(14), policy = policy)
        assertEquals(policy.declaredStability * policy.growth, clean.stability, 1e-9)
        assertTrue(clean.strength(day(14)) > declared.strength(day(14)))
        val stumbled = clean.revised(stumbled = true, at = day(20), policy = policy)
        assertEquals(clean.stability * policy.lapseFactor, stumbled.stability, 1e-9)
        assertEquals(1, stumbled.lapses)

        // The first revision of a declared ayah counts in full, even on the day it was declared.
        assertEquals(clean.stability, declared.revised(stumbled = false, at = start, policy = policy).stability, 1e-9)

        // Revising again right away strengthens it only a little (the spacing effect).
        val rushed = clean.revised(stumbled = false, at = day(14), policy = policy)
        assertTrue(rushed.stability < clean.stability * 1.2)

        // Three well-spaced clean revisions make it fully established.
        var memory = declared
        for (revision in listOf(14, 50, 140)) memory = memory.revised(stumbled = false, at = day(revision), policy = policy)
        assertTrue(memory.strength(day(140)) > 0.99)
    }

    @Test
    fun aSheikhsTasmeeCountsMoreThanSelfRevision() {
        assertTrue(policy.weight(Source.APP) == 1.0 && policy.weight(Source.OUTSIDE) == 1.0)
        assertTrue(policy.weight(Source.SHEIKH) == policy.sheikhWeight && policy.sheikhWeight > 1)

        val declared = AyahMemory(since = start)
        val heard = declared.revised(stumbled = false, at = day(14), policy = policy, weight = policy.sheikhWeight)
        assertEquals(policy.declaredStability * (1 + (policy.growth - 1) * policy.sheikhWeight), heard.stability, 1e-9)
        assertTrue(heard.stability > declared.revised(stumbled = false, at = day(14), policy = policy).stability)

        // A stumble is a stumble, whoever heard it.
        val stumbled = heard.revised(stumbled = true, at = day(20), policy = policy, weight = policy.sheikhWeight)
        assertEquals(heard.stability * policy.lapseFactor, stumbled.stability, 1e-9)
        assertEquals(1, stumbled.lapses)

        // A tasmee' applied after a later self-revision never moves the last revision backwards.
        val later = declared.revised(stumbled = false, at = day(20), policy = policy)
        val backdated = later.revised(stumbled = false, at = day(14), policy = policy, weight = policy.sheikhWeight)
        assertEquals(day(20), backdated.lastReviewed)
        assertTrue(backdated.stability > later.stability)
    }

    // MARK: - Today's plan

    @Test
    fun planTakesFollowUpsFirstThenTheRotation() {
        val revision = RevisionStore(file = null, zone = utc)
        val memorization = MemorizationStore(file = null)
        revision.setDailyPages(3)
        val pages = listOf(10, 11, 12, 13, 14, 20)
        revision.refreshPlan(pages, now = day(0))
        assertEquals(listOf(10, 11, 12), revision.plan?.items?.map { it.page })
        assertTrue(revision.plan!!.items.all { it.kind == PlanItem.Kind.ROTATION })

        // A stumble on page 11 brings it back tomorrow, ahead of the rotation, which continues after page 12.
        revision.record(10, listOf(100), emptySet(), Source.APP, memorization, now = day(0))
        revision.record(11, listOf(110), setOf(110), Source.APP, memorization, now = day(0))
        revision.record(12, listOf(120), emptySet(), Source.OUTSIDE, memorization, now = day(0))
        assertTrue(revision.plan!!.isComplete)
        revision.refreshPlan(pages, now = day(1))
        assertEquals(listOf(11, 13, 14), revision.plan?.items?.map { it.page })
        assertEquals(PlanItem.Kind.FOLLOW_UP, revision.plan?.items?.first()?.kind)

        // Clean follow-ups space out (3 days, then 7) and then leave follow-up.
        revision.record(11, listOf(110), emptySet(), Source.APP, memorization, now = day(1))
        assertEquals(calendarDay(4), revision.followUps[11]?.due)
        revision.record(11, listOf(110), emptySet(), Source.APP, memorization, now = day(4))
        assertEquals(calendarDay(11), revision.followUps[11]?.due)
        revision.record(11, listOf(110), emptySet(), Source.APP, memorization, now = day(11))
        assertNull(revision.followUps[11])
    }

    @Test
    fun missedDaysDontPileUpAndTheRotationWraps() {
        val revision = RevisionStore(file = null, zone = utc)
        val memorization = MemorizationStore(file = null)
        revision.setDailyPages(2)
        val pages = listOf(1, 2, 3, 4, 5)
        revision.refreshPlan(pages, now = day(0))
        revision.record(1, listOf(0), emptySet(), Source.APP, memorization, now = day(0))
        revision.record(2, listOf(7), emptySet(), Source.APP, memorization, now = day(0))

        // Three days missed: the plan is still two pages, continuing where the student stopped.
        revision.refreshPlan(pages, now = day(4))
        assertEquals(listOf(3, 4), revision.plan?.items?.map { it.page })

        // A page skipped today stays first tomorrow, even if a later one was revised.
        revision.record(4, listOf(20), emptySet(), Source.APP, memorization, now = day(4))
        revision.refreshPlan(pages, now = day(5))
        assertEquals(listOf(3, 4), revision.plan?.items?.map { it.page })
        revision.record(3, listOf(15), emptySet(), Source.APP, memorization, now = day(5))
        revision.record(4, listOf(20), emptySet(), Source.APP, memorization, now = day(5))

        // The rotation wraps from the last memorized page back to the first.
        revision.refreshPlan(pages, now = day(6))
        assertEquals(listOf(5, 1), revision.plan?.items?.map { it.page })
    }

    @Test
    fun planStaysFixedWithinTheDay() {
        val revision = RevisionStore(file = null, zone = utc)
        revision.setDailyPages(2)
        revision.refreshPlan(listOf(50, 51, 52), now = day(0))
        // Memorizing more during the day doesn't reshuffle today's plan; unmarking a page drops it.
        revision.refreshPlan(listOf(40, 50, 51, 52), now = day(0) + 3_600.0)
        assertEquals(listOf(50, 51), revision.plan?.items?.map { it.page })
        revision.refreshPlan(listOf(40, 51, 52), now = day(0) + 7_200.0)
        assertEquals(listOf(51), revision.plan?.items?.map { it.page })
        // Nothing memorized: an empty plan, made again as soon as something is.
        val empty = RevisionStore(file = null, zone = utc)
        empty.refreshPlan(emptyList(), now = day(0))
        assertTrue(empty.plan!!.items.isEmpty())
        empty.refreshPlan(listOf(7), now = day(0))
        assertEquals(listOf(7), empty.plan?.items?.map { it.page })
    }

    @Test
    fun revisionUpdatesTheAyatOfThePage() {
        val revision = RevisionStore(file = null, zone = utc)
        val memorization = MemorizationStore(file = null)
        memorization.mark(0..6, memorized = true)
        val before = memorization.memory(3)!!.stability
        revision.record(1, (0..6).toList(), setOf(3), Source.APP, memorization, now = Moment.now() + 14 * 86_400.0)
        assertTrue(memorization.memory(3)!!.stability < before)
        assertTrue(memorization.memory(2)!!.stability > before)
        assertEquals(listOf(3), revision.history.last().stumbles)
    }

    @Test
    fun recordSavesAndReloads() {
        val file = File.createTempFile("revision", ".json").apply { delete(); deleteOnExit() }
        val memorization = MemorizationStore(file = null)
        val revision = RevisionStore(file, zone = utc)
        revision.setDailyPages(4)
        revision.refreshPlan(listOf(3, 4, 5), now = day(0))
        revision.record(3, listOf(15), setOf(15), Source.APP, memorization, now = day(0))
        val reloaded = RevisionStore(file, zone = utc)
        assertEquals(4, reloaded.dailyPages)
        assertTrue(reloaded.plan!!.items.first { it.page == 3 }.done)
        assertNotNull(reloaded.followUps[3])
        assertEquals(1, reloaded.history.size)
        assertEquals(1, reloaded.streak(now = day(0)))
    }

    // MARK: - Streak

    @Test
    fun streakCountsDaysInARow() {
        val revision = RevisionStore(file = null, zone = utc)
        val memorization = MemorizationStore(file = null)
        assertEquals(0, revision.streak(now = day(0)))
        for (n in listOf(0, 1, 2)) revision.record(1, listOf(0), emptySet(), Source.OUTSIDE, memorization, now = day(n))
        assertEquals(3, revision.streak(now = day(2)))
        // Today not revised yet: the streak still stands, counted from yesterday, until the day ends.
        assertEquals(3, revision.streak(now = day(3)))
        // A whole day missed breaks it.
        assertEquals(0, revision.streak(now = day(4)))
        revision.record(1, listOf(0), emptySet(), Source.APP, memorization, now = day(4))
        assertEquals(1, revision.streak(now = day(4)))
        // The last seven days, oldest first, ending today.
        assertEquals(listOf(false, false, true, true, true, false, true), revision.recentDays(7, now = day(4)))
    }

    // MARK: - A page's revision

    @Test
    fun sessionRevealsInOrderAndMarksStumbles() {
        val session = RevisionSession(2, listOf(7, 8, 9))
        assertTrue(session.isVeiled(7) && session.isVeiled(9))
        session.tap(null)                   // anywhere: reveals the first
        assertTrue(!session.isVeiled(7) && session.isVeiled(8))
        session.tap(9)                      // a veiled ayah: reveals the next
        assertFalse(session.isVeiled(8))
        session.tap(7)                      // a revealed ayah: marks a stumble, and a second tap clears it
        assertEquals(setOf(7), session.stumbles)
        session.tap(7)
        assertTrue(session.stumbles.isEmpty())
        session.revealAll()
        assertTrue(session.isComplete && !session.isVeiled(9))
        assertTrue(!session.covers(40) && !session.isVeiled(40))
    }

    /** «تعثّرتُ هنا» reveals the next ayah already marked as a stumble; past the last ayah it does nothing. */
    @Test
    fun stumblingOnTheNextAyahRevealsItMarked() {
        val session = RevisionSession(2, listOf(7, 8, 9))
        session.revealNext()
        session.stumbleOnNext()
        assertTrue(session.revealed == 2 && session.stumbles == setOf(8))
        session.stumbleOnNext()
        assertTrue(session.isComplete && session.stumbles == setOf(8, 9))
        session.stumbleOnNext()
        assertTrue(session.revealed == 3 && session.stumbles == setOf(8, 9))
        // A tap on a revealed ayah still clears its stumble.
        session.tap(9)
        assertEquals(setOf(8), session.stumbles)
    }

    /** «تم» on a partly revealed page records the ayat revealed, or all of them when the student counts the rest. */
    @Test
    fun doneCountsOnlyTheRevealedAyatUnlessTheRestIsCounted() {
        val session = RevisionSession(2, listOf(7, 8, 9, 10))
        session.revealNext()
        session.stumbleOnNext()
        assertEquals(listOf(7, 8), session.revisedAyahs(countingRest = false))
        assertEquals(listOf(7, 8, 9, 10), session.revisedAyahs(countingRest = true))
        session.revealAll()
        assertEquals(listOf(7, 8, 9, 10), session.revisedAyahs(countingRest = false))
    }

    // MARK: - Days, time zones and the clock (the same checks as the iOS app's RevisionTests)

    /** A moment given as the time on the clock in a time zone. */
    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, zone: String): Moment =
        Moment.of(LocalDateTime.of(year, month, day, hour, minute).atZone(ZoneId.of(zone)).toInstant())

    private fun temporaryFile(): File = File.createTempFile("revision", ".json").also { it.delete(); it.deleteOnExit() }

    private fun record(revision: RevisionStore, page: Int, now: Moment, stumbles: Set<Int> = emptySet()) =
        revision.record(page, emptyList(), stumbles, Source.APP, MemorizationStore(file = null), now)

    @Test
    fun daysWrittenAsLocalMidnightReadBackAsTheSameDay() {
        val days = listOf(Triple("Asia/Riyadh", 3, 12), Triple("America/New_York", 3, 12), Triple("Africa/Cairo", 4, 24), Triple("Europe/London", 3, 29))
        for ((zone, month, date) in days) {
            val id = ZoneId.of(zone)
            val noon = at(2026, month, date, 12, zone = zone)
            assertEquals(zone, CalendarDay.of(noon, id), CalendarDay.stored(noon.startOfDay(id)))
            assertEquals(String.format("2026-%02d-%02d", month, date), CalendarDay.of(noon, id).toString())
        }
        // A whole file from before: its days, its plan's day and its follow-up's day.
        val riyadh = ZoneId.of("Asia/Riyadh")
        val midnight = at(2026, 3, 12, 12, zone = "Asia/Riyadh").startOfDay(riyadh).sinceReference
        val file = temporaryFile()
        file.writeText(
            """{"version":1,"rotationCursor":3,"followUps":[{"page":9,"due":${midnight + 86_400},"step":0}],""" +
                """"plan":{"day":$midnight,"items":[{"page":1,"kind":"rotation","done":true}]},"history":[],""" +
                """"revisedDays":[${midnight - 86_400},$midnight],"completedDays":[$midnight]}""",
        )
        val revision = RevisionStore(file, zone = riyadh)
        val today = CalendarDay.of(at(2026, 3, 12, 20, zone = "Asia/Riyadh"), riyadh)
        assertTrue(revision.plan?.day == today && revision.followUps[9]?.due == today + 1)
        assertEquals(setOf(today + -1, today), revision.revisedDays)
        assertEquals(setOf(today), revision.completedDays)
        assertEquals(2, revision.streak(at(2026, 3, 12, 20, zone = "Asia/Riyadh")))
    }

    @Test
    fun streakSurvivesATimeZoneChange() {
        val file = temporaryFile()
        val riyadh = RevisionStore(file, zone = ZoneId.of("Asia/Riyadh"))
        for (date in 10..12) record(riyadh, 1, at(2026, 3, date, 21, zone = "Asia/Riyadh"))
        assertEquals(3, riyadh.streak(at(2026, 3, 12, 22, zone = "Asia/Riyadh")))
        val london = RevisionStore(file, zone = ZoneId.of("Europe/London"))
        assertEquals(3, london.streak(at(2026, 3, 12, 19, 30, zone = "Europe/London")))
        assertEquals(listOf(true, true, true), london.recentDays(3, at(2026, 3, 12, 19, 30, zone = "Europe/London")))
        assertEquals(3, london.streak(at(2026, 3, 13, 8, zone = "Europe/London")))
    }

    @Test
    fun planSurvivesRelaunchInAnotherZoneOnTheSameDay() {
        val file = temporaryFile()
        val pages = listOf(1, 2, 3, 4, 5)
        val riyadh = RevisionStore(file, zone = ZoneId.of("Asia/Riyadh"))
        riyadh.setDailyPages(3)
        riyadh.refreshPlan(pages, at(2026, 3, 12, 9, zone = "Asia/Riyadh"))
        record(riyadh, 1, at(2026, 3, 12, 10, zone = "Asia/Riyadh"))
        val london = RevisionStore(file, zone = ZoneId.of("Europe/London"))
        london.refreshPlan(pages, at(2026, 3, 12, 15, zone = "Europe/London"))
        assertEquals(listOf(1, 2, 3), london.plan?.items?.map { it.page })
        assertEquals(1, london.plan?.doneCount)
    }

    /** In Cairo the clocks go forward at midnight on Friday 24 April 2026, so that day starts at 01:00. */
    @Test
    fun streakCrossesAMidnightDSTGap() {
        val cairo = ZoneId.of("Africa/Cairo")
        assertEquals(1, at(2026, 4, 24, 12, zone = "Africa/Cairo").startOfDay(cairo).toInstant().atZone(cairo).hour)
        val revision = RevisionStore(file = null, zone = cairo)
        for (date in 20..27) record(revision, 1, at(2026, 4, date, 20, zone = "Africa/Cairo"))
        assertEquals(8, revision.streak(at(2026, 4, 27, 21, zone = "Africa/Cairo")))
        assertTrue(revision.recentDays(8, at(2026, 4, 27, 21, zone = "Africa/Cairo")).all { it })
    }

    @Test
    fun followUpSetOnADSTDayIsDueTheNextDay() {
        val cairo = ZoneId.of("Africa/Cairo")
        val revision = RevisionStore(file = null, zone = cairo)
        record(revision, 5, at(2026, 4, 23, 23, 30, zone = "Africa/Cairo"), stumbles = setOf(40))
        assertEquals(CalendarDay.of(at(2026, 4, 24, 12, zone = "Africa/Cairo"), cairo), revision.followUps[5]?.due)
        revision.refreshPlan(listOf(5, 6), at(2026, 4, 24, 1, 5, zone = "Africa/Cairo"))
        assertEquals(PlanItem(5, PlanItem.Kind.FOLLOW_UP), revision.plan?.items?.first())
    }

    @Test
    fun recordingAfterMidnightMovesTheWirdOn() {
        val revision = RevisionStore(file = null, zone = utc)
        val pages = listOf(10, 11, 12, 13)
        revision.setDailyPages(3)
        revision.refreshPlan(pages, day(0))
        record(revision, 10, day(0))
        val afterMidnight = day(1).startOfDay(utc) + 10 * 60.0
        record(revision, 11, afterMidnight)
        assertEquals(listOf(true, true, false), revision.plan?.items?.map { it.done })
        assertEquals(12, revision.plan?.items?.first { !it.done }?.page)
        record(revision, 12, afterMidnight)
        assertEquals(setOf(calendarDay(0)), revision.completedDays)
        assertEquals(setOf(calendarDay(0), calendarDay(1)), revision.revisedDays)
        assertEquals(13, revision.rotationCursor)
        revision.refreshPlan(pages, afterMidnight)
        assertTrue(revision.plan?.day == calendarDay(1) && revision.plan?.items?.first()?.page == 13)
    }

    @Test
    fun cleanRevisionBeforeDueDoesNotAdvanceAFollowUp() {
        val revision = RevisionStore(file = null, zone = utc)
        record(revision, 7, day(0), stumbles = setOf(70))
        record(revision, 7, day(0) + 2 * 3_600.0)
        assertEquals(FollowUp(calendarDay(1), 0), revision.followUps[7])
        record(revision, 7, day(1))
        assertEquals(FollowUp(calendarDay(4), 1), revision.followUps[7])
        record(revision, 7, day(9))
        assertEquals(FollowUp(calendarDay(16), 2), revision.followUps[7])
    }

    @Test
    fun futureDatedRevisionIsClampedToNow() {
        val memorization = MemorizationStore(file = null)
        val revision = RevisionStore(file = null, zone = utc)
        memorization.mark(7..8, memorized = true)
        val record = TasmeeRecord("r", teacherId = "t", teacherName = "x", sessionId = "s", at = day(6), pages = listOf(2), stumbles = emptyList())
        TasmeeApply.apply(record, memorization, revision, now = day(5)) { 7..8 }
        assertTrue(memorization.memory(7)?.lastReviewed == day(5) && revision.history.last().date == day(5))

        val ahead = AyahMemory(since = day(0), lastReviewed = day(40), lastLapseAt = day(40))
        val merged = CloudBackup.merge(CloudBackup.Memory(mapOf(9 to ahead)), CloudBackup.Memory(removed = mapOf(10 to day(40))), now = day(5))
        assertTrue(merged.ayahs[9]?.lastReviewed == day(5) && merged.ayahs[9]?.lastLapseAt == day(5) && merged.removed[10] == day(5))
    }

    @Test
    fun firstRevisionOfALearnedAyahIsSpaced() {
        val policy = ReviewPolicy.STANDARD
        val learned = AyahMemory(stability = 2.0, since = start, learnedAt = start)
        assertTrue(learned.revised(false, start + 3_600.0, policy).stability < 2 * 1.2)
        assertEquals(2 * policy.growth, learned.revised(false, day(2), policy).stability, 1e-12)
        assertEquals(policy.declaredStability * policy.growth, AyahMemory(since = start).revised(false, start, policy).stability, 1e-12)
    }

    @Test
    fun suggestedDailyAmountCoversAboutAMonth() {
        assertEquals(2, ReviewPolicy.suggestedDailyPages(20))
        assertEquals(10, ReviewPolicy.suggestedDailyPages(300))
        assertEquals(20, ReviewPolicy.suggestedDailyPages(604))
    }
}
