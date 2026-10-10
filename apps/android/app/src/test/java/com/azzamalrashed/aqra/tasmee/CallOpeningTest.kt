package com.azzamalrashed.aqra.tasmee

import com.azzamalrashed.aqra.core.Moment
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.ZoneId
import java.time.ZonedDateTime

/** A call that isn't open yet says the day it opens, not only «a quarter of an hour before». As on iOS. */
class CallOpeningTest {
    private val zone = ZoneId.of("Asia/Riyadh")

    private fun day(day: Int, hour: Int, minute: Int = 0) = Moment.of(ZonedDateTime.of(2026, 10, day, hour, minute, 0, 0, zone).toInstant())

    @Test
    fun saysTheDayItOpens() {
        val now = day(13, 22)
        fun opening(date: Moment) = CallOpening.day(date, now, zone)
        assertEquals(CallOpening.TODAY, opening(day(13, 23, 45)))
        assertEquals(CallOpening.TOMORROW, opening(day(14, 0, 15)))
        assertEquals(CallOpening.THIS_WEEK, opening(day(19, 20)))
        assertEquals(CallOpening.LATER, opening(day(20, 20)))
        // Already open or past: today, never a day before it.
        assertEquals(CallOpening.TODAY, opening(day(13, 8)))
    }
}
