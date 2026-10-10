package com.friday.assistant

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * Full-app entry point. All phone bridges live in DeviceBridge so the
 * assistant overlay service registers the exact same channel.
 */
class MainActivity : FlutterActivity() {
    private val updates by lazy { FirebaseUpdateController(this) }

    override fun onPostResume() {
        super.onPostResume()
        updates.onResume()
    }

    override fun onDestroy() {
        updates.close()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DeviceBridge.register(flutterEngine.dartExecutor.binaryMessenger, this, this)
    }
}
