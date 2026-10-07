package com.azzamalrashed.aqra.ui.util

import android.icu.text.DateFormat
import android.icu.text.RelativeDateTimeFormatter
import android.icu.util.IslamicCalendar
import android.icu.util.ULocale
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Date
import java.util.Locale

/** A number in Arabic-Indic digits, as the Mushaf writes them in every language: ١٢٣. */
fun arabicDigits(number: Int): String = number.toString().map { if (it in '0'..'9') '٠' + (it - '0') else it }.joinToString("")

/** A number as the app's language writes it (Arabic-Indic digits in Arabic). */
fun formatNumber(number: Int, locale: Locale = Locale.getDefault()): String = NumberFormat.getIntegerInstance(locale).format(number)

/** A share as a percentage, with at most [maxFraction] decimals: 12.5%. */
fun formatPercent(share: Double, maxFraction: Int = 1, locale: Locale = Locale.getDefault()): String =
    NumberFormat.getPercentInstance(locale).apply {
        minimumFractionDigits = 0
        maximumFractionDigits = maxFraction
    }.format(share)

/** Today in the Umm al-Qura calendar: «الأربعاء ١٥ ربيع الآخر». */
fun hijriToday(locale: Locale = Locale.getDefault()): String {
    val calendar = IslamicCalendar(ULocale.forLocale(locale)).apply {
        calculationType = IslamicCalendar.CalculationType.ISLAMIC_UMALQURA
        timeInMillis = System.currentTimeMillis()
    }
    val format = DateFormat.getPatternInstance(calendar, DateFormat.WEEKDAY + DateFormat.DAY + DateFormat.MONTH, ULocale.forLocale(locale))
    return format.format(calendar)
}

/** A session's time: «الأربعاء ٨ أكتوبر، ٨:٠٠ م». */
fun formatWhen(instant: Instant, locale: Locale = Locale.getDefault()): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "EEEEdMMMMjmm")
    return DateTimeFormatter.ofPattern(pattern, locale).withZone(ZoneId.systemDefault()).format(instant)
}

/** A day's date, short: «٧ أكتوبر ٢٠٢٦». */
fun formatDay(instant: Instant, locale: Locale = Locale.getDefault()): String =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale).withZone(ZoneId.systemDefault()).format(instant)

/** A time of day, as the device writes it. */
fun formatTime(hour: Int, minute: Int, locale: Locale = Locale.getDefault()): String {
    val calendar = java.util.Calendar.getInstance().apply {
        set(java.util.Calendar.HOUR_OF_DAY, hour)
        set(java.util.Calendar.MINUTE, minute)
    }
    return java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT, locale).format(calendar.time)
}

/** How long ago, in words: «منذ ٥ دقائق», "5 minutes ago"; within a minute, «الآن», "now". */
fun formatRelative(instant: Instant): String = nowIfWithinAMinute(instant) ?: android.text.format.DateUtils.getRelativeTimeSpanString(
    instant.toEpochMilli(), System.currentTimeMillis(), android.text.format.DateUtils.MINUTE_IN_MILLIS,
).toString()

/** «الآن» rather than «منذ ٠ دقيقة», as the iOS app says it. */
private fun nowIfWithinAMinute(instant: Instant): String? =
    if (kotlin.math.abs(System.currentTimeMillis() - instant.toEpochMilli()) >= 60_000) null
    else RelativeDateTimeFormatter.getInstance(ULocale.forLocale(Locale.getDefault()))
        .format(RelativeDateTimeFormatter.Direction.PLAIN, RelativeDateTimeFormatter.AbsoluteUnit.NOW)

/** A weekday's narrow name for a date, and its full name. */
fun weekdayNarrow(date: Date, locale: Locale = Locale.getDefault()): String =
    java.text.SimpleDateFormat("EEEEE", locale).format(date)

fun weekdayWide(date: Date, locale: Locale = Locale.getDefault()): String =
    java.text.SimpleDateFormat("EEEE", locale).format(date)


/** A far date by its Hijri month, in the Umm al-Qura calendar: «رجب ١٤٤٩ هـ». */
fun hijriMonth(instant: Instant, locale: Locale = Locale.getDefault()): String {
    val calendar = IslamicCalendar(ULocale.forLocale(locale)).apply {
        calculationType = IslamicCalendar.CalculationType.ISLAMIC_UMALQURA
        timeInMillis = instant.toEpochMilli()
    }
    return DateFormat.getPatternInstance(calendar, DateFormat.YEAR_MONTH, ULocale.forLocale(locale)).format(calendar)
}

/** A weekday's name as the iOS app numbers weekdays (1 is Sunday): narrow («ح», "S") or wide. */
fun weekdayName(weekday: Int, narrow: Boolean, locale: Locale = Locale.getDefault()): String {
    val symbols = android.icu.text.DateFormatSymbols(ULocale.forLocale(locale))
    val names = symbols.getWeekdays(android.icu.text.DateFormatSymbols.STANDALONE,
        if (narrow) android.icu.text.DateFormatSymbols.NARROW else android.icu.text.DateFormatSymbols.WIDE)
    return names.getOrNull(weekday).orEmpty()
}

/** The weekday a week starts on in this locale (1 is Sunday). */
fun firstWeekday(locale: Locale = Locale.getDefault()): Int = android.icu.util.Calendar.getInstance(ULocale.forLocale(locale)).firstDayOfWeek

/** A day and month, long: «٨ أكتوبر ٢٠٢٦». */
fun formatLongDay(instant: Instant, locale: Locale = Locale.getDefault()): String =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(locale).withZone(ZoneId.systemDefault()).format(instant)

/** A moment with its time: «٨ أكتوبر، ٨:٠٠ م». */
fun formatDayTime(instant: Instant, locale: Locale = Locale.getDefault()): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "dMMMjmm")
    return DateTimeFormatter.ofPattern(pattern, locale).withZone(ZoneId.systemDefault()).format(instant)
}

/** How far away, ahead or behind, in words that sit in a sentence: «خلال ساعتين», "in 2 hours". */
fun formatRelativeAhead(instant: Instant): String {
    nowIfWithinAMinute(instant)?.let { return it }
    val seconds = (instant.toEpochMilli() - System.currentTimeMillis()) / 1000.0
    val span = kotlin.math.abs(seconds)
    val (quantity, unit) = when {
        span < 3_600 -> span / 60 to RelativeDateTimeFormatter.RelativeUnit.MINUTES
        span < 86_400 -> span / 3_600 to RelativeDateTimeFormatter.RelativeUnit.HOURS
        else -> span / 86_400 to RelativeDateTimeFormatter.RelativeUnit.DAYS
    }
    val direction = if (seconds >= 0) RelativeDateTimeFormatter.Direction.NEXT else RelativeDateTimeFormatter.Direction.LAST
    return RelativeDateTimeFormatter.getInstance(ULocale.forLocale(Locale.getDefault()))
        .format(Math.round(quantity).toDouble(), direction, unit)
}
