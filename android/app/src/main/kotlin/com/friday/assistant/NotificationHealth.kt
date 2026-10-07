package com.friday.assistant
import android.app.*
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

object NotificationHealth {
    private val channels = mapOf("friday_reminders" to "Friday reminders", "friday_gold_alerts" to "Gold task alerts", "friday_gold_running" to "Background gold checks")
    fun channelAllowed(c: Context, id: String): Boolean {
        val nm=c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return GoldTasks.notificationsAllowed(c) && (nm.getNotificationChannel(id)?.importance ?: NotificationManager.IMPORTANCE_DEFAULT) != NotificationManager.IMPORTANCE_NONE
    }
    fun state(c: Context): Map<String,Any> {
        val nm=c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val pm=c.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf("enabled" to GoldTasks.notificationsAllowed(c),
          "batteryUnrestricted" to pm.isIgnoringBatteryOptimizations(c.packageName),
          "exactAlarms" to (Build.VERSION.SDK_INT < 31 || (c.getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()),
          "channels" to channels.map { (id,name) -> mapOf("name" to name,"id" to id,"enabled" to channelAllowed(c,id)) })
    }
    fun settings(c: Context) { c.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,c.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    fun test(c: Context): String {
        val nm=c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("friday_reminders","Friday reminders",NotificationManager.IMPORTANCE_HIGH))
        if (!channelAllowed(c,"friday_reminders")) return "Notifications or the Friday reminders channel are disabled. Enable them in Notification settings."
        return try {
            val open=PendingIntent.getActivity(c,91,Intent(c,MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE)
            nm.notify(91,Notification.Builder(c,"friday_reminders").setSmallIcon(R.drawable.ic_friday_notification)
              .setContentTitle("Friday notification test").setContentText("If you can see this, immediate notifications work. Scheduled reminders are tested separately.").setContentIntent(open).setAutoCancel(true).build())
            "Test notification submitted to Android. Check your notification shade; this is not a delivery guarantee."
        } catch (_: Exception) { "Android rejected the test notification." }
    }
}
