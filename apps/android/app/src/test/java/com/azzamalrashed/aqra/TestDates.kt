package com.azzamalrashed.aqra

import com.azzamalrashed.aqra.core.CalendarDay
import com.azzamalrashed.aqra.core.Moment
import java.time.ZoneId

/** Fixed dates and a fixed time zone, so every rule can be checked exactly. */
object TestDates {
    val utc: ZoneId = ZoneId.of("UTC")
    val start: Moment = Moment.ofEpochSeconds(1_800_000_000.0)
    fun day(n: Int): Moment = start + n * 86_400.0
    /** A test day as the revision store keeps it. */
    fun calendarDay(n: Int): CalendarDay = CalendarDay.of(day(n), utc)
}
