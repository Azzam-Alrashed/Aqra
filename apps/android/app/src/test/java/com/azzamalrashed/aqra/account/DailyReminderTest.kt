package com.azzamalrashed.aqra.account

import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.TestDates.utc
import com.azzamalrashed.aqra.TestQuran
import com.azzamalrashed.aqra.core.weekday
import com.azzamalrashed.aqra.memorization.MemorizationStore
import com.azzamalrashed.aqra.plan.MemorizationPlan
import com.azzamalrashed.aqra.plan.PlanStore
import com.azzamalrashed.aqra.plan.TodayPortion
import com.azzamalrashed.aqra.revision.DayPlan
import com.azzamalrashed.aqra.revision.PlanItem
import com.azzamalrashed.aqra.revision.RevisionStore
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Today's reminder is left out once today's work is done, as the iOS app's JourneyTests check it. */
class DailyReminderTest {
    @Test
    fun todaysWorkIsDoneWithTheWirdAndTheDuePortion() {
        val now = day(0)
        val done = DayPlan(now, listOf(PlanItem(1, PlanItem.Kind.ROTATION, done = true), PlanItem(2, PlanItem.Kind.ROTATION, done = true)))
        val halfway = DayPlan(now, listOf(PlanItem(1, PlanItem.Kind.ROTATION, done = true), PlanItem(2, PlanItem.Kind.ROTATION)))
        assertTrue(DailyReminder.isTodayDone(done, portionDue = false, now = now, zone = utc))
        // Not with the wird half done, a portion still due, yesterday's wird, or no wird at all.
        assertFalse(DailyReminder.isTodayDone(halfway, portionDue = false, now = now, zone = utc))
        assertFalse(DailyReminder.isTodayDone(done, portionDue = true, now = now, zone = utc))
        assertFalse(DailyReminder.isTodayDone(done, portionDue = false, now = day(1), zone = utc))
        assertFalse(DailyReminder.isTodayDone(null, portionDue = false, now = now, zone = utc))
    }

    @Test
    fun aPortionIsDueOnAStudyDayUntilItsRecorded() {
        val store = TestQuran.store
        val memorization = MemorizationStore(file = null)
        val plan = PlanStore(file = null, zone = utc)
        val revision = RevisionStore(file = null, zone = utc)
        assertFalse(plan.isPortionDue(memorization, day(0)))
        val weekday = day(0).weekday(utc)
        plan.setPlan(MemorizationPlan(15, setOf(weekday, weekday % 7 + 1), MemorizationPlan.Order.FROM_END), now = day(0))
        assertTrue(plan.isPortionDue(memorization, day(0)))
        // Not on a rest day.
        assertFalse(plan.isPortionDue(memorization, day(2)))
        val portion = (plan.today(memorization, store, day(0)) as TodayPortion.Due).ayahs
        plan.record(portion, portion, store, memorization, revision, day(0))
        assertFalse(plan.isPortionDue(memorization, day(0)))
        assertTrue(plan.isPortionDue(memorization, day(1)))
    }
}
