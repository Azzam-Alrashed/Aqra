package com.azzamalrashed.aqra.plan

import com.azzamalrashed.aqra.TestDates.day
import com.azzamalrashed.aqra.TestDates.utc
import org.junit.Assert.assertEquals
import org.junit.Test

/** The plan's pace, as the iOS app's JourneyTests check it. */
class PlanPaceTest {
    /** Ten days paused don't count as study days: the pace after the pause is the pace before it. */
    @Test
    fun recentPaceIgnoresPausedDays() {
        val everyDay = MemorizationPlan(15, (1..7).toSet(), MemorizationPlan.Order.FROM_END)
        val portions = (0 until 7).map { Portion(date = day(it), planned = listOf(it), memorized = listOf(it), plannedLines = 8.0, actualLines = 8.0) }
        val plan = PlanStore(file = null, zone = utc)
        plan.apply(PlanStore.Snapshot(everyDay, portions, listOf(PlanChange(day(0), everyDay))))
        val before = plan.recentPace(day(7))!!
        assertEquals(8.0, before, 1e-9)
        val paused = everyDay.copy(paused = true)
        plan.apply(PlanStore.Snapshot(everyDay, portions, listOf(PlanChange(day(0), everyDay), PlanChange(day(7), paused), PlanChange(day(17), everyDay))))
        assertEquals(before, plan.recentPace(day(17))!!, 1e-9)
    }
}
