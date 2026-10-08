package com.friday.assistant

import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.provider.Settings

/** System holds this light service while Friday is the default assistant. */
class FridayAssistantService : VoiceInteractionService() {
    override fun onReady(){super.onReady();AssistantInvocation.record(this,"Assistant service ready")}
}

object AssistantInvocation {
    fun record(context:android.content.Context,stage:String){
        val p=context.getSharedPreferences("assistant_invocation",0)
        p.edit().putString("last","${java.text.SimpleDateFormat("HH:mm:ss",java.util.Locale.US).format(java.util.Date())}: $stage").apply()
        android.util.Log.i("FridayAssistant",stage)
    }
    fun start(context:android.content.Context,source:String):Boolean{
        record(context,"$source received")
        if(!Settings.canDrawOverlays(context)){record(context,"$source: display-over-apps permission missing");return false}
        return try{
            androidx.core.content.ContextCompat.startForegroundService(context,Intent(context,AssistantOverlayService::class.java))
            record(context,"$source: overlay start requested")
            true
        }catch(e:Exception){record(context,"$source: ${e.javaClass.simpleName}: ${e.message}");false}
    }
}
class FridayAssistantSessionService : VoiceInteractionSessionService() {
    override fun onNewSession(args:Bundle?):VoiceInteractionSession {
        AssistantInvocation.record(this,"System created assistant session")
        return FridayAssistantSession(this)
    }
}
class FridayAssistantSession(context:android.content.Context):VoiceInteractionSession(context){
    override fun onPrepareShow(args:Bundle?,flags:Int){super.onPrepareShow(args,flags);setUiEnabled(false)}
    override fun onShow(args:Bundle?,showFlags:Int){
        super.onShow(args,showFlags)
        // Avoid a trampoline activity whose launch can be cancelled by finishing
        // the voice session. Start the foreground overlay directly while active.
        if(AssistantInvocation.start(context,"System assistant gesture flags=$showFlags")){
            finish()
        }else{
            try{startAssistantActivity(Intent(context,AssistantTrampolineActivity::class.java))}
            catch(e:Exception){AssistantInvocation.record(context,"Assistant fallback: ${e.javaClass.simpleName}: ${e.message}");finish()}
        }
    }
}
