package com.azzamalrashed.aqra.account

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.azzamalrashed.aqra.MainActivity
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.core.Preferences
import com.azzamalrashed.aqra.tasmee.Booking
import com.azzamalrashed.aqra.tasmee.TasmeeSession
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * A reminder an hour before each tasmee' session booked, kept in step with the bookings. Nothing is asked: the
 * reminders are only set when notifications are already allowed (by the daily reminder). They're kept on the device,
 * so they're set again after it restarts.
 */
object SessionReminders {
    private const val CHANNEL = "sessions"
    internal const val ACTION = "com.azzamalrashed.aqra.SESSION_REMINDER"
    private const val EXTRA_ID = "session"
    private const val LEAD = 3_600_000L
    /** Android delivers an inexact alarm within a window of at least ten minutes; this one is centred on the hour. */
    private const val WINDOW = 10 * 60_000L

    @Serializable
    internal data class Reminder(val id: String, val atMillis: Long, val teacherName: String, val video: Boolean, val place: String)

    private val json = Json { ignoreUnknownKeys = true }

    /**
     * Sets a reminder for each booking still more than an hour away, and takes back the rest. [bookings] are as the
     * sessions are now: a teacher may have moved or cancelled one since it was booked.
     */
    fun schedule(context: Context, bookings: List<Pair<Booking, TasmeeSession.Status?>>) {
        val prefs = Preferences(context)
        stored(prefs).forEach { cancel(context, it.id) }
        val now = System.currentTimeMillis()
        val reminders = if (DailyReminder.isAllowed(context)) {
            bookings.filter { (_, status) -> status != TasmeeSession.Status.CANCELLED }.map { (booking, _) ->
                Reminder(booking.id, booking.startsAt.epochMillis - LEAD, booking.teacherName, booking.kind == TasmeeSession.Kind.VIDEO, booking.place)
            }.filter { it.atMillis > now }
        } else {
            emptyList()
        }
        reminders.forEach { set(context, it) }
        prefs.sessionReminders = json.encodeToString(ListSerializer(Reminder.serializer()), reminders)
    }

    private fun stored(prefs: Preferences): List<Reminder> =
        prefs.sessionReminders?.let { runCatching { json.decodeFromString(ListSerializer(Reminder.serializer()), it) }.getOrNull() }.orEmpty()

    private fun set(context: Context, reminder: Reminder) {
        context.getSystemService(AlarmManager::class.java)
            .setWindow(AlarmManager.RTC_WAKEUP, reminder.atMillis - WINDOW / 2, WINDOW, pendingIntent(context, reminder.id))
    }

    private fun cancel(context: Context, id: String) {
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent(context, id))
    }

    /** Each session's alarm is its own, told apart by its address. */
    private fun pendingIntent(context: Context, id: String): PendingIntent = PendingIntent.getBroadcast(
        context, 0,
        Intent(context, SessionReminderReceiver::class.java).setAction(ACTION).setData(Uri.parse("aqra-reminder://session/$id")).putExtra(EXTRA_ID, id),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    internal fun handle(context: Context, intent: Intent) {
        val prefs = Preferences(context)
        val reminders = stored(prefs)
        when (intent.action) {
            ACTION -> reminders.firstOrNull { it.id == intent.getStringExtra(EXTRA_ID) }?.let { post(context, it) }
            // Alarms don't survive a restart: the ones still ahead are set again.
            Intent.ACTION_BOOT_COMPLETED -> reminders.filter { it.atMillis > System.currentTimeMillis() }.forEach { set(context, it) }
        }
    }

    private fun post(context: Context, reminder: Reminder) {
        if (!DailyReminder.isAllowed(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.tasmee), NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val text = if (reminder.video) context.getString(R.string.with_s_by_video, reminder.teacherName)
            else context.getString(R.string.with_s_at_s, reminder.teacherName, reminder.place)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(context, R.color.brand))
            .setContentTitle(context.getString(R.string.your_tasmee_in_an_hour))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(reminder.id, 0, notification)
        } catch (_: SecurityException) {
            // Notifications were turned off between the check and now.
        }
    }
}

/** Posts a session's reminder when its alarm goes off; sets the reminders again after the device restarts. */
class SessionReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != SessionReminders.ACTION && intent.action != Intent.ACTION_BOOT_COMPLETED) return
        SessionReminders.handle(context, intent)
    }
}
