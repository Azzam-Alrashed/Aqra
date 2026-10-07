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
import com.azzamalrashed.aqra.MainActivity
import com.azzamalrashed.aqra.R
import com.azzamalrashed.aqra.core.Preferences
import java.util.Calendar

/** The daily reminder of today's wird: one notification a day at the chosen time. */
object DailyReminder {
    private const val CHANNEL = "daily-wird"
    internal const val ACTION = "com.azzamalrashed.aqra.DAILY_WIRD"
    private const val NOTIFICATION = 1

    /** Whether the app may post notifications (asked for at run time from Android 13). */
    fun isAllowed(context: Context): Boolean =
        (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** Sets the next reminder, at [minutes] after midnight, today if that's still ahead, else tomorrow. */
    fun schedule(context: Context, minutes: Int) {
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, minutes / 60)
            set(Calendar.MINUTE, minutes % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        val alarms = context.getSystemService(AlarmManager::class.java)
        // Within a quarter of an hour of the time chosen, which needs no exact-alarm permission.
        alarms.setWindow(AlarmManager.RTC_WAKEUP, next.timeInMillis, 15 * 60 * 1000L, pendingIntent(context))
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent(context))
    }

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, DailyReminderReceiver::class.java).setAction(ACTION),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    internal fun handle(context: Context, intent: Intent) {
        val prefs = Preferences(context)
        if (!prefs.reminderOn.value) return
        if (intent.action == ACTION) post(context)
        schedule(context, prefs.reminderMinutes.value)
    }

    private fun post(context: Context) {
        if (!isAllowed(context)) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, context.getString(R.string.todays_revision), NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(ContextCompat.getColor(context, R.color.brand))
            .setContentTitle(context.getString(R.string.todays_revision))
            .setContentText(context.getString(R.string.your_pages_for_today_are_waiting_for_you))
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

/** Posts the day's reminder and sets the next one; sets it again after the device restarts. */
class DailyReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DailyReminder.ACTION && intent.action != Intent.ACTION_BOOT_COMPLETED) return
        DailyReminder.handle(context, intent)
    }
}
