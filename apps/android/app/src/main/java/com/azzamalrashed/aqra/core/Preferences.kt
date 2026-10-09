package com.azzamalrashed.aqra.core

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.core.content.edit

/**
 * The app's settings and small flags, kept on the device under the same names the iOS app uses. Each is a Compose
 * state, so screens follow its changes, and each change is written right away.
 */
class Preferences(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("aqra", Context.MODE_PRIVATE)

    val hasSeenOnboarding = bool("hasSeenOnboarding", false)
    /** Whether the student has said what they've memorized (or that they're just starting). */
    val hasDeclared = bool("memorization.hasDeclared", false)
    /**
     * Where a student who chose to mark what they've memorized in the Mushaf is in setup: "marking", then
     * "dailyAmount" (when they've marked anything), then "plan", as the other path goes; "" when it's done.
     */
    val setupAfterMarking = string("setup.afterMarking", "")
    val lastPage = int("mushaf.lastPage", 1)
    val tajweed = bool("mushaf.tajweed", true)
    /** Whether the student revises aloud, Aqra following by ear; kept for the next revision. */
    val recitationListens = bool("recitation.listens", false)
    val topics = bool("mushaf.topics", true)
    val reminderOn = bool("reminder.on", false)
    /** Minutes after midnight. */
    val reminderMinutes = int("reminder.minutes", 5 * 60 + 30)
    /** «لاحقًا» on the invitation to sign in hides it until this time (seconds since 1970). */
    val saveProgressSnoozedUntil = double("home.saveProgressSnoozedUntil", 0.0)
    /** The newest tasmee' whose card was closed, so it isn't shown again. */
    val seenTasmee = string("home.seenTasmee", "")
    /** The gentle chime for rewards. */
    val soundsOn = bool("sounds.on", true)

    /** The account whose copy this install has already merged, so it's merged once rather than on every launch. */
    var restoredAccount: String?
        get() = prefs.getString("cloud.restoredAccount", null)
        set(value) = prefs.edit { if (value == null) remove("cloud.restoredAccount") else putString("cloud.restoredAccount", value) }

    /** The same, for the journey (the plan, rewards and stages), kept since a later version of the app. */
    var journeyRestoredAccount: String?
        get() = prefs.getString("cloud.journeyRestoredAccount", null)
        set(value) = prefs.edit { if (value == null) remove("cloud.journeyRestoredAccount") else putString("cloud.journeyRestoredAccount", value) }

    /** Pages the rotation's suggestions were dismissed for, and until when (seconds since 1970). */
    var rotationDismissed: Map<Int, Double>
        get() = prefs.getString("rotation.dismissed", null)?.split(',')?.mapNotNull { entry ->
            val (page, until) = entry.split(':').takeIf { it.size == 2 } ?: return@mapNotNull null
            (page.toIntOrNull() ?: return@mapNotNull null) to (until.toDoubleOrNull() ?: return@mapNotNull null)
        }?.toMap().orEmpty()
        set(value) = prefs.edit { putString("rotation.dismissed", value.entries.joinToString(",") { "${it.key}:${it.value}" }) }

    /** The reminders set for the sessions booked, as JSON (see SessionReminders). */
    var sessionReminders: String?
        get() = prefs.getString("reminders.sessions", null)
        set(value) = prefs.edit { if (value == null) remove("reminders.sessions") else putString("reminders.sessions", value) }

    /** The tasmee' records already applied on this install, so none is applied twice while its mark is on its way. */
    var appliedTasmee: List<String>
        get() = prefs.getString("tasmee.applied", null)?.split('\n')?.filter { it.isNotEmpty() }.orEmpty()
        set(value) = prefs.edit { putString("tasmee.applied", value.joinToString("\n")) }

    private fun bool(key: String, default: Boolean) = Pref(mutableStateOf(prefs.getBoolean(key, default))) { prefs.edit { putBoolean(key, it) } }
    private fun int(key: String, default: Int) = Pref(mutableStateOf(prefs.getInt(key, default))) { prefs.edit { putInt(key, it) } }
    private fun string(key: String, default: String) =
        Pref(mutableStateOf(prefs.getString(key, default) ?: default)) { prefs.edit { putString(key, it) } }
    private fun double(key: String, default: Double) =
        Pref(mutableStateOf(java.lang.Double.longBitsToDouble(prefs.getLong(key, java.lang.Double.doubleToRawLongBits(default))))) {
            prefs.edit { putLong(key, java.lang.Double.doubleToRawLongBits(it)) }
        }
}

/** One setting: read and written like a Compose state, saved on every change. */
class Pref<T>(private val state: MutableState<T>, private val write: (T) -> Unit) : MutableState<T> {
    override var value: T
        get() = state.value
        set(newValue) {
            if (newValue == state.value) return
            state.value = newValue
            write(newValue)
        }

    override fun component1(): T = value
    override fun component2(): (T) -> Unit = { value = it }
}
