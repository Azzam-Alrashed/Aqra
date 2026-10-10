package com.azzamalrashed.aqra.account

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.azzamalrashed.aqra.AqraApp
import com.azzamalrashed.aqra.AqraApplication
import com.azzamalrashed.aqra.MainActivity
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.core.CalendarDay
import com.azzamalrashed.aqra.core.Moment
import com.azzamalrashed.aqra.core.Preferences
import com.azzamalrashed.aqra.revision.DayPlan
import java.time.ZoneId

/**
 * The daily reminder of today's wird: one notification a day at the chosen time. On the plan's study days it also
 * mentions the new portion. Once today's work is done it isn't sent, and one already shown is taken away.
 *
 * The alarm means a time of day where the student is, so it's set again whenever the app comes to the front, after
 * the device restarts, and when its clock or time zone changes (the iOS app refreshes its dated reminders the same way).
 */
object DailyReminder {
    private const val CHANNEL = "daily-wird"
    internal const val ACTION = "com.azzamalrashed.aqra.DAILY_WIRD"
    private const val NOTIFICATION = 1

    /** Where the reminder's alarm is kept: Android's AlarmManager, or a stand-in in tests. */
    interface Alarms {
        fun set(atMillis: Long)
        fun cancel()
    }

    private class SystemAlarms(private val context: Context) : Alarms {
        private val manager: AlarmManager get() = context.getSystemService(AlarmManager::class.java)

        // Inexact, so it needs no exact-alarm permission; allowed while the device dozes, so it isn't held back until
        // the device wakes (setWindow was, by hours).
        override fun set(atMillis: Long) = manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pendingIntent(context))

        override fun cancel() = manager.cancel(pendingIntent(context))
    }

    /** Whether the app may post notifications (asked for at run time from Android 13). */
    fun isAllowed(context: Context): Boolean =
        (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** The next time the reminder is due: [minutes] after midnight, today if that's still ahead, else tomorrow. */
    fun nextTime(minutes: Int, now: Moment = Moment.now(), zone: ZoneId = ZoneId.systemDefault()): Moment {
        val today = now.toInstant().atZone(zone).toLocalDate()
        fun at(day: java.time.LocalDate) = Moment.of(day.atTime(minutes / 60, minutes % 60).atZone(zone).toInstant())
        val todays = at(today)
        return if (todays > now) todays else at(today.plusDays(1))
    }

    /**
     * Sets the reminder as the settings say, or takes it back when it's off. Returns the time set, so a test can
     * check it: the time chosen, in the time zone the device is in now.
     */
    fun refresh(on: Boolean, minutes: Int, alarms: Alarms, now: Moment = Moment.now(), zone: ZoneId = ZoneId.systemDefault()): Moment? {
        if (!on) {
            alarms.cancel()
            return null
        }
        return nextTime(minutes, now, zone).also { alarms.set(it.epochMillis) }
    }

    /** Sets the reminder as the settings say: on every launch and resume, and from the receiver below. */
    fun refresh(context: Context, prefs: Preferences = Preferences(context)) {
        refresh(prefs.reminderOn.value, prefs.reminderMinutes.value, SystemAlarms(context))
    }

    /** Sets the next reminder, at [minutes] after midnight, today if that's still ahead, else tomorrow. */
    fun schedule(context: Context, minutes: Int) {
        refresh(on = true, minutes = minutes, alarms = SystemAlarms(context))
    }

    fun cancel(context: Context) {
        SystemAlarms(context).cancel()
    }

    /**
     * Whether today's work is done: today's [wird] complete and, on a study day of an active plan, the new portion
     * recorded (or nothing left to memorize: [portionDue] is false).
     */
    fun isTodayDone(wird: DayPlan?, portionDue: Boolean, now: Moment = Moment.now(), zone: ZoneId = ZoneId.systemDefault()): Boolean =
        wird != null && wird.day == CalendarDay.of(now, zone) && wird.isComplete && !portionDue

    fun isTodayDone(app: AqraApp): Boolean = isTodayDone(app.revision.plan, app.plan.isPortionDue(app.memorization))

    /** Takes away today's reminder once today's work is done, if it was already shown. */
    fun withdrawIfDone(context: Context, app: AqraApp) {
        if (isTodayDone(app)) NotificationManagerCompat.from(context).cancel(NOTIFICATION)
    }

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, DailyReminderReceiver::class.java).setAction(ACTION),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    internal fun handle(context: Context, intent: Intent) {
        val prefs = Preferences(context)
        if (intent.action == ACTION && prefs.reminderOn.value) post(context)
        // After each reminder, a restart, or a change of clock or time zone: the next one, at the time chosen.
        refresh(context, prefs)
    }

    private fun post(context: Context) {
        if (!isAllowed(context)) return
        val app = (context.applicationContext as? AqraApplication)?.app
        // Today's work done already: nothing to remind of today.
        if (app != null && isTodayDone(app)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.todays_revision), NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // The plan is read as the reminder goes out, so it follows the plan's days as they change.
        val plan = app?.plan
        val withPortion = plan?.plan?.paused == false && plan.isStudyDay(Moment.now())
        val text = context.getString(if (withPortion) R.string.your_new_portion_and_your_pages_for_today_are_waiting else R.string.your_pages_for_today_are_waiting_for_you)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(context, R.color.brand))
            .setContentTitle(context.getString(R.string.todays_revision))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(NOTIFICATION, notification)
        } catch (_: SecurityException) {
            // Notifications were turned off between the check and now.
        }
    }
}

/**
 * Posts the day's reminder and sets the next one; sets it again after the device restarts and when its clock or time
 * zone changes.
 */
class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in HANDLED) return
        DailyReminder.handle(context, intent)
    }

    private companion object {
        val HANDLED = setOf(DailyReminder.ACTION, Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_TIME_CHANGED)
    }
}
