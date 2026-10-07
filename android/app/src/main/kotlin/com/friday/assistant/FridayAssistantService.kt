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
class FridayAssistantService : VoiceInteractionService()

class FridayAssistantSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args: Bundle?): VoiceInteractionSession =
        FridayAssistantSession(this)
}

class FridayAssistantSession(context: android.content.Context) :
    VoiceInteractionSession(context) {

    override fun onShow(args: Bundle?, showFlags: Int) {
        super.onShow(args, showFlags)
        try {
            context.startActivity(
                Intent(context, AssistantTrampolineActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Exception) {
        }
        finish()
    }
}
