package com.azzamalrashed.aqra.revision

import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.TestDates.utc
import com.azzamalrashed.aqra.TestQuran
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.revision.RevisionRecord.Source
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.ceil

/** The near lane (سبقي) and the rotation's share, as the iOS app's JourneyTests check them. */
class NearLaneTest {
    /**
     * The pages memorized in Aqra lately (not today's) come back every day beside the daily amount, the newest up to the
     * policy's number; the rotation leaves them out and still gets its share.
     */
    @Test
    fun theNearLaneComesBackDailyBesideTheAmount() {
        val store = TestQuran.store
        val memorization = MemorizationStore(file = null)
        memorization.mark(0..200, memorized = true)
        // Pages 30 to 33 memorized in Aqra over the last four days, page 34 today.
        for ((offset, page) in listOf(30, 31, 32, 33, 34).withIndex()) {
            memorization.mark(store.page(page).ayahs, memorized = false)
            memorization.learn(store.page(page).ayahs, at = day(offset - 4), stability = 2.0)
        }
        val revision = RevisionStore(file = null, policy = ReviewPolicy.STANDARD.copy(nearLanePages = 3), zone = utc)
        revision.setDailyPages(4)
        val near = revision.nearLanePages(store, memorization, day(0))
        assertEquals(listOf(31, 32, 33), near)
        val pages = RevisionStore.memorizedPages(store, memorization)
        revision.refreshPlan(pages, day(0), near)
        val plan = revision.plan!!
        assertEquals(listOf(31, 32, 33), plan.items.filter { it.kind == PlanItem.Kind.NEAR }.map { it.page })
        assertEquals(listOf(1, 2, 3, 4), plan.items.filter { it.kind == PlanItem.Kind.ROTATION }.map { it.page })
        assertEquals(ceil((pages.size - 3) / 4.0).toInt(), revision.cycleDays(pages.size, 3, day(0)))
    }

    /** However many pages are due for follow-up, the rotation keeps at least half the daily amount. */
    @Test
    fun followUpsLeaveTheRotationAtLeastHalf() {
        val memorization = MemorizationStore(file = null)
        val revision = RevisionStore(file = null, zone = utc)
        revision.setDailyPages(4)
        for (page in 10..15) revision.record(page, emptyList(), setOf(page), Source.APP, memorization, day(-1))
        revision.refreshPlan((1..20).toList(), day(0))
        assertEquals(listOf(PlanItem.Kind.FOLLOW_UP, PlanItem.Kind.FOLLOW_UP, PlanItem.Kind.ROTATION, PlanItem.Kind.ROTATION), revision.plan?.items?.map { it.kind })
        assertEquals(listOf(10, 11, 1, 2), revision.plan?.items?.map { it.page })
        assertEquals(10, revision.cycleDays(20, now = day(0)))
    }
}
