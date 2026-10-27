package com.friday.assistant

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Brings the floating bubble back after a reboot and after Friday updates
    itself, but only when the user left it enabled. */
class AssistantBubbleBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED))
            try { AssistantOverlayService.ensureBubble(context) } catch (_: Exception) { }
    }
}
