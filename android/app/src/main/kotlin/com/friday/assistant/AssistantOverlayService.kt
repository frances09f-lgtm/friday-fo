package com.friday.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.MethodChannel

/**
 * Draws Friday's assistant panel over whatever app is on screen. Runs its own
 * Flutter engine with the assistantOverlayMain entrypoint; the panel talks
 * back over the friday/assistant channel (dismiss, openFriday).
 */
class AssistantOverlayService : Service() {

    companion object {
        private const val CHANNEL = "friday/assistant"
        private const val NOTIF_CHANNEL = "friday_assistant"
        private const val NOTIF_ID = 71
    }

    private var engine: FlutterEngine? = null
    private var view: FlutterView? = null
    private var windowManager: WindowManager? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildNotification())

        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val e = FlutterEngine(this)
        e.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint(
                loader.findAppBundlePath(),
                "assistantOverlayMain",
            )
        )
        MethodChannel(e.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dismiss" -> {
                        result.success(null)
                        stopSelf()
                    }
                    "openFriday" -> {
                        startActivity(
                            Intent(this, MainActivity::class.java)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                        stopSelf()
                    }
                    else -> result.notImplemented()
                }
            }
        engine = e
        DeviceBridge.register(e.dartExecutor.binaryMessenger, this, null)

        val v = FlutterView(this)
        v.attachToFlutterEngine(e)
        e.lifecycleChannel.appIsResumed()
        view = v

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.BOTTOM
        params.softInputMode =
            android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm
        wm.addView(v, params)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    NOTIF_CHANNEL,
                    "Friday assistant",
                    NotificationManager.IMPORTANCE_MIN,
                )
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, NOTIF_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Friday is listening")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        view?.let { v ->
            try {
                windowManager?.removeView(v)
            } catch (_: Exception) {
            }
            v.detachFromFlutterEngine()
        }
        engine?.destroy()
        engine = null
        view = null
        super.onDestroy()
    }
}
