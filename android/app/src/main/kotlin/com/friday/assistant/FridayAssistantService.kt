package com.friday.assistant

import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService

/// Presence of this service (plus the manifest declaration) is what makes
/// Friday appear in Settings > Default apps > Digital assistant app. When
/// Friday holds the assistant role, the long-press-power gesture binds this
/// service and shows a session; the session immediately hands off to the
/// trampoline, which opens the floating panel - the same path as the
/// ASSIST intent, so behavior is identical however the gesture arrives.
class FridayAssistantService : VoiceInteractionService() {
    /// Android 12+ power-button gesture lands here. The default
    /// implementation does show the session on most builds, but being
    /// explicit removes OEM differences (OxygenOS 14 included).
    override fun onLaunchVoiceAssist(voiceAssistType: Int) {
        showSession(Bundle(), SHOW_WITH_ASSIST_GESTURE)
    }
}

class FridayAssistantSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession =
        FridayAssistantSession(this)
}

class FridayAssistantSession(context: android.content.Context) :
    VoiceInteractionSession(context) {

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        val intent = Intent(context, AssistantTrampolineActivity::class.java)
        var launched = false
        // startAssistantActivity is the sanctioned way for a session to
        // open its own UI and is exempt from background-activity-start
        // blocking; a plain context.startActivity from the session context
        // can be silently swallowed on OxygenOS - which looked exactly like
        // "long-press power does nothing".
        try {
            startAssistantActivity(intent)
            launched = true
        } catch (_: Exception) {
        }
        if (!launched) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                launched = true
            } catch (_: Exception) {
            }
        }
        if (!launched) {
            // Last resort: the overlay service itself. Service starts from
            // the active assistant are allowed, and the panel is the point.
            try {
                context.startService(Intent(context, AssistantOverlayService::class.java))
            } catch (_: Exception) {
            }
        }
        finish()
    }
}
