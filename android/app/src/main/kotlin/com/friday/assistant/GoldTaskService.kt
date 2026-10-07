package com.friday.assistant

import android.app.*
import android.content.Intent
import android.os.IBinder
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class GoldTaskService : Service() {
    private val executor = Executors.newSingleThreadScheduledExecutor()
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel("friday_gold_running", "Background gold checks", NotificationManager.IMPORTANCE_LOW).apply { setSound(null, null) })
        val stop = PendingIntent.getService(this, 81, Intent(this, GoldTaskService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 82, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        startForeground(81, Notification.Builder(this, "friday_gold_running")
            .setSmallIcon(android.R.drawable.ic_menu_info_details).setContentTitle("Friday background checks")
            .setContentText("Checking saved Oro quotes. No trades are placed.")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, "Stop checks", stop).build()).build())
        GoldTasks.runtime(this, "Foreground checker running")
        executor.scheduleWithFixedDelay({
            try { GoldTasks.check(this); GoldTasks.runtime(this, "Foreground checker running"); if (!GoldTasks.hasActive(this)) stopSelf() } catch (_: Exception) { GoldTasks.runtime(this, "Background check failed; retrying") }
        }, 0, 30, TimeUnit.SECONDS)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") { GoldTasks.cancelAll(this); stopSelf(); return START_NOT_STICKY }
        return START_STICKY
    }
    override fun onDestroy() { executor.shutdownNow(); GoldTasks.runtime(this, "Foreground checker stopped"); super.onDestroy() }
    companion object {
        fun alert(c: android.content.Context, id: String, title: String, body: String) {
            val nm = c.getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(NotificationChannel("friday_gold_alerts", "Gold task alerts", NotificationManager.IMPORTANCE_DEFAULT))
            val open = PendingIntent.getActivity(c, 82, Intent(c, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
            nm.notify(id, 82, Notification.Builder(c, "friday_gold_alerts").setSmallIcon(android.R.drawable.ic_menu_info_details)
                .setContentTitle(title).setContentText(body).setStyle(Notification.BigTextStyle().bigText(body))
                .setContentIntent(open).setAutoCancel(true).build())
        }
    }
}
