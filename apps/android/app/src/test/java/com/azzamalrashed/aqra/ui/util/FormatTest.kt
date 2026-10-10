package com.azzamalrashed.aqra.ui.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.Locale

/** Dates as the app's language writes them. */
class FormatTest {
    /** 15 January 2027, 08:00 UTC. */
    private val instant: Instant = Instant.ofEpochSecond(1_800_000_000)
    private val arabic: Locale = Locale.forLanguageTag("ar-SA")

    /** java.time writes Western digits unless told the locale's; in Arabic the dates carry Arabic-Indic digits, like every other number. */
    @Test
    fun arabicDatesUseArabicDigits() {
        for (text in listOf(formatDay(instant, arabic), formatLongDay(instant, arabic))) {
            assertTrue(text, text.any { it in '٠'..'٩' })
            assertFalse(text, text.any { it in '0'..'9' })
        }
        for (text in listOf(formatDay(instant, Locale.ENGLISH), formatLongDay(instant, Locale.ENGLISH))) {
            assertTrue(text, text.contains("2027"))
            assertFalse(text, text.any { it in '٠'..'٩' })
        }
    }
}
