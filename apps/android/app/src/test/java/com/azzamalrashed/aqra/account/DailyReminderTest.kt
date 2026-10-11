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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.azzamalrashed.aqra.core.CalendarDay
import java.time.ZoneId
import java.time.ZonedDateTime

/** Today's reminder is left out once today's work is done, as the iOS app's JourneyTests check it. */
class DailyReminderTest {
    /**
     * Each launch (and resume) sets the reminder again for the time chosen, in the time zone the device is in now, or
     * takes it back when it's off: an alarm set in one time zone means another clock time in the next.
     */
    @Test
    fun dailyReminderReschedulesOnLaunch() {
        val alarms = FakeAlarms()
        val riyadh = ZoneId.of("Asia/Riyadh")
        val london = ZoneId.of("Europe/London")
        val now = day(0) // 15 January 2027, 08:00 UTC: 11:00 in Riyadh, 08:00 in London
        val halfPastFive = 5 * 60 + 30
        // Launched in Riyadh with the reminder on: 05:30 has passed, so tomorrow's.
        val first = DailyReminder.refresh(on = true, minutes = halfPastFive, alarms = alarms, now = now, zone = riyadh)
        assertEquals(ZonedDateTime.of(2027, 1, 16, 5, 30, 0, 0, riyadh).toInstant().toEpochMilli(), first?.epochMillis)
        assertEquals(listOf(first?.epochMillis), alarms.set)
        // Launched again after flying to London: the same clock time, three hours later in the world.
        val second = DailyReminder.refresh(on = true, minutes = halfPastFive, alarms = alarms, now = now, zone = london)
        assertEquals(first!!.epochMillis + 3 * 3_600_000, second?.epochMillis)
        assertEquals(2, alarms.set.size)
        // A time still ahead today is today's.
        val evening = DailyReminder.refresh(on = true, minutes = 20 * 60, alarms = alarms, now = now, zone = london)
        assertEquals(ZonedDateTime.of(2027, 1, 15, 20, 0, 0, 0, london).toInstant().toEpochMilli(), evening?.epochMillis)
        // Turned off, a launch takes the alarm back.
        assertNull(DailyReminder.refresh(on = false, minutes = halfPastFive, alarms = alarms, now = now, zone = london))
        assertEquals(1, alarms.cancelled)
        assertEquals(3, alarms.set.size)
    }

    private class FakeAlarms : DailyReminder.Alarms {
        val set = mutableListOf<Long>()
        var cancelled = 0

        override fun set(atMillis: Long) {
            set += atMillis
        }

        override fun cancel() {
            cancelled += 1
        }
    }

    @Test
    fun todaysWorkIsDoneWithTheWirdAndTheDuePortion() {
        val now = day(0)
        val done = DayPlan(CalendarDay.of(now, utc), listOf(PlanItem(1, PlanItem.Kind.ROTATION, done = true), PlanItem(2, PlanItem.Kind.ROTATION, done = true)))
        val halfway = DayPlan(CalendarDay.of(now, utc), listOf(PlanItem(1, PlanItem.Kind.ROTATION, done = true), PlanItem(2, PlanItem.Kind.ROTATION)))
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
