package com.friday.assistant
import android.app.*
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

object NotificationHealth {
    private val channels = mapOf("friday_reminders" to "Friday reminders", "friday_gold_alerts" to "Gold task alerts", "friday_gold_running" to "Background gold checks")

    /** Create every Friday channel at startup. Before this, the gold alert channel only
     *  existed after the first alert, so it was missing from Android's notification
     *  settings and could not be switched on or off there. An existing channel keeps
     *  the importance the user already has. */
    fun ensureChannels(c: Context) {
        try {
            val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(NotificationChannel("friday_reminders", "Friday reminders", NotificationManager.IMPORTANCE_HIGH))
            nm.createNotificationChannel(NotificationChannel("friday_gold_alerts", "Gold task alerts", NotificationManager.IMPORTANCE_HIGH))
            nm.createNotificationChannel(NotificationChannel("friday_gold_running", "Background gold checks", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null) })
        } catch (_: Exception) { }
    }
    fun channelAllowed(c: Context, id: String): Boolean {
        val nm=c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return GoldTasks.notificationsAllowed(c) && (nm.getNotificationChannel(id)?.importance ?: NotificationManager.IMPORTANCE_DEFAULT) != NotificationManager.IMPORTANCE_NONE
    }
    fun state(c: Context): Map<String,Any> {
        ensureChannels(c)
        val nm=c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val pm=c.getSystemService(Context.POWER_SERVICE) as PowerManager
        return mapOf("enabled" to GoldTasks.notificationsAllowed(c),
          "batteryUnrestricted" to pm.isIgnoringBatteryOptimizations(c.packageName),
          "exactAlarms" to (Build.VERSION.SDK_INT < 31 || (c.getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()),
          "manufacturer" to Build.MANUFACTURER,
          "sdk" to Build.VERSION.SDK_INT,
          "channels" to channels.map { (id,name) -> mapOf("name" to name,"id" to id,"enabled" to channelAllowed(c,id)) })
    }
    private fun launch(c: Context, options: List<Intent>): Boolean {
        for (i in options) {
            try { c.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); return true } catch (_: Exception) { }
        }
        return false
    }
    private fun appDetails(c: Context) = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + c.packageName))
    fun settings(c: Context) { c.startActivity(Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE,c.packageName).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
    /** Android 12+: the "Alarms & reminders" switch for Friday. Older phones have no such switch. */
    fun exactAlarmSettings(c: Context): Boolean {
        val options = mutableListOf<Intent>()
        if (Build.VERSION.SDK_INT >= 31) options.add(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + c.packageName)))
        options.add(appDetails(c))
        return launch(c, options)
    }
    /** One-tap box "Allow Friday to run in the background"; falls back to the battery list, then app info. */
    @android.annotation.SuppressLint("BatteryLife")
    fun batterySettings(c: Context): Boolean = launch(c, listOf(
        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:" + c.packageName)),
        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
        appDetails(c)))
    /** Maker-specific background or auto-launch screen when it exists, otherwise Friday's app info page. */
    fun autostartSettings(c: Context): Boolean {
        val options = mutableListOf<Intent>()
        if (Build.MANUFACTURER.lowercase().contains("oneplus"))
            options.add(Intent().setComponent(ComponentName("com.oneplus.security", "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity")))
        options.add(appDetails(c))
        return launch(c, options)
    }
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
