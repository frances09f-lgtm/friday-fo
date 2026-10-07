package com.friday.assistant

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.provider.Settings

/**
 * Handles the system assistant invocation (long-press power on Android 12+,
 * "digital assistant app" role). It never shows UI itself: it starts the
 * overlay service that draws Friday's panel over the current app. When the
 * overlay permission is missing we open the permission page plus the full
 * app once - otherwise nothing at all would appear, which is worse than
 * breaking the overlay-only rule during setup.
 */
class AssistantTrampolineActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Settings.canDrawOverlays(this)) {
            startService(Intent(this, AssistantOverlayService::class.java))
        } else {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
        finish()
    }
}
