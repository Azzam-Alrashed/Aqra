package com.azzamalrashed.aqra.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.time.Instant
import java.time.ZoneId

/**
 * A moment in time, kept the way the iOS app keeps its dates: seconds since 1 January 2001 (UTC). The progress
 * files and the account's revision record store dates in that form, so both apps read each other's backups exactly.
 */
@Serializable(with = Moment.Serializer::class)
@JvmInline
value class Moment(val sinceReference: Double) : Comparable<Moment> {
    companion object {
        /** 1 January 2001, in seconds since 1970. */
        private const val REFERENCE_EPOCH = 978_307_200.0

        /** The iOS app's `Date.distantPast` (1 January 0001). */
        val DISTANT_PAST = Moment(-63_114_076_800.0)

        fun now(): Moment = of(Instant.now())

        fun of(instant: Instant) = Moment(instant.epochSecond - REFERENCE_EPOCH + instant.nano / 1e9)

        fun ofEpochSeconds(seconds: Double) = Moment(seconds - REFERENCE_EPOCH)

        fun ofEpochMillis(millis: Long) = ofEpochSeconds(millis / 1000.0)
    }

    val epochSeconds: Double get() = sinceReference + REFERENCE_EPOCH
    val epochMillis: Long get() = Math.round(epochSeconds * 1000)

    fun toInstant(): Instant {
        val seconds = Math.floor(epochSeconds)
        return Instant.ofEpochSecond(seconds.toLong(), Math.round((epochSeconds - seconds) * 1e9))
    }

    operator fun plus(seconds: Double) = Moment(sinceReference + seconds)
    operator fun minus(other: Moment): Double = sinceReference - other.sinceReference

    override fun compareTo(other: Moment) = sinceReference.compareTo(other.sinceReference)

    /** The start of this moment's day in a time zone. */
    fun startOfDay(zone: ZoneId): Moment = of(toInstant().atZone(zone).toLocalDate().atStartOfDay(zone).toInstant())

    /** The same time of day, a number of days later (or earlier) in a time zone. */
    fun plusDays(days: Long, zone: ZoneId): Moment = of(toInstant().atZone(zone).plusDays(days).toInstant())

    object Serializer : KSerializer<Moment> {
        override val descriptor = PrimitiveSerialDescriptor("Moment", PrimitiveKind.DOUBLE)
        override fun serialize(encoder: Encoder, value: Moment) = encoder.encodeDouble(value.sinceReference)
        override fun deserialize(decoder: Decoder) = Moment(decoder.decodeDouble())
    }
}

/** The JSON of the progress files and the account's backup: optional values are left out when missing, as on iOS. */
val ProgressJson = Json {
    encodeDefaults = true
    explicitNulls = false
    ignoreUnknownKeys = true
}

/** The weekday as the iOS app numbers it (and keeps it in backups): 1 is Sunday, 7 Saturday. */
fun Moment.weekday(zone: ZoneId): Int = toInstant().atZone(zone).dayOfWeek.value % 7 + 1

/** A new random id, written as the iOS app writes its UUIDs. */
fun newId(): String = java.util.UUID.randomUUID().toString().uppercase()
