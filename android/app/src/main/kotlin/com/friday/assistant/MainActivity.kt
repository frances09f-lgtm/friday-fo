package com.friday.assistant

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Full-app entry point. All phone bridges live in DeviceBridge so the
 * assistant overlay service registers the exact same channel. The Alerts tab
 * also uses "friday/alerts" for the three Android settings pages it opens.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DeviceBridge.register(flutterEngine.dartExecutor.binaryMessenger, this, this)
        ShrutiBridge.register(flutterEngine.dartExecutor.binaryMessenger)
        NotificationHealth.ensureChannels(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "friday/alerts").setMethodCallHandler { call, result ->
            when (call.method) {
                "exactAlarmSettings" -> result.success(NotificationHealth.exactAlarmSettings(this))
                "batterySettings" -> result.success(NotificationHealth.batterySettings(this))
                "autostartSettings" -> result.success(NotificationHealth.autostartSettings(this))
                else -> result.notImplemented()
            }
        }
    }
}
