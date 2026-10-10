package com.azzamalrashed.aqra.revision

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
        assertEquals(day(4).startOfDay(utc), revision.followUps[11]?.due)
        revision.record(11, listOf(110), emptySet(), Source.APP, memorization, now = day(4))
        assertEquals(day(11).startOfDay(utc), revision.followUps[11]?.due)
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

    @Test
    fun suggestedDailyAmountCoversAboutAMonth() {
        assertEquals(2, ReviewPolicy.suggestedDailyPages(20))
        assertEquals(10, ReviewPolicy.suggestedDailyPages(300))
        assertEquals(20, ReviewPolicy.suggestedDailyPages(604))
    }
}
