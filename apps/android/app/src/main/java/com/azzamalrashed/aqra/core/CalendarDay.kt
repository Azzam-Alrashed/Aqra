package com.azzamalrashed.aqra.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.roundToLong

/**
 * A day of the calendar, the same wherever the student is: the number of days since 1 January 1970 (day 0), as the
 * iOS app's `CalendarDay` counts it.
 *
 * It's stored as that day's midnight in UTC, a [Moment], so backups keep the shape of the dates earlier versions
 * wrote. Those were the device's local midnight, which is within twelve hours of it, so they read back as the same day.
 */
@Serializable(with = CalendarDay.Serializer::class)
@JvmInline
value class CalendarDay(val number: Long) : Comparable<CalendarDay> {
    companion object {
        /** The day a moment falls on in a time zone. */
        fun of(moment: Moment, zone: ZoneId) = CalendarDay(moment.toInstant().atZone(zone).toLocalDate().toEpochDay())

        /** A day as stored: the UTC midnight nearest to the moment. */
        fun stored(moment: Moment) = CalendarDay((moment.epochSeconds / 86_400.0).roundToLong())
    }

    /** The day's midnight in UTC, as it's stored. */
    val stored: Moment get() = Moment.ofEpochSeconds(number * 86_400.0)

    /** When the day begins in a time zone (after a change of clocks at midnight, when they've changed). */
    fun start(zone: ZoneId): Moment = Moment.of(LocalDate.ofEpochDay(number).atStartOfDay(zone).toInstant())

    operator fun plus(days: Int) = CalendarDay(number + days)

    override fun compareTo(other: CalendarDay) = number.compareTo(other.number)

    override fun toString(): String = LocalDate.ofEpochDay(number).toString()

    object Serializer : KSerializer<CalendarDay> {
        override val descriptor = PrimitiveSerialDescriptor("CalendarDay", PrimitiveKind.DOUBLE)
        override fun serialize(encoder: Encoder, value: CalendarDay) = encoder.encodeDouble(value.stored.sinceReference)
        override fun deserialize(decoder: Decoder) = stored(Moment(decoder.decodeDouble()))
    }
}
