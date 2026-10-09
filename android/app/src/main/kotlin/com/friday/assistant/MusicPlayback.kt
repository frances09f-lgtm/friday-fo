package com.friday.assistant

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.KeyEvent
import io.flutter.plugin.common.MethodChannel

/** Android routes media keys to its current/last media-button session.
 * No app guessing, notification access, UI launch, or play/pause toggle.
 * A dormant app must still have a resumable session/queue to honor Play.
 */
object MusicPlayback {
    fun control(context: Context, command: String, result: MethodChannel.Result) {
        val code = when(command) { "next" -> KeyEvent.KEYCODE_MEDIA_NEXT; "previous" -> KeyEvent.KEYCODE_MEDIA_PREVIOUS; "stop" -> KeyEvent.KEYCODE_MEDIA_STOP; else -> {result.success("error");return} }
        try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val before=audio.isMusicActive
            if(command=="stop"&&!before){result.success("inactive");return}
            val at = SystemClock.uptimeMillis()
            audio.dispatchMediaKeyEvent(KeyEvent(at,at,KeyEvent.ACTION_DOWN,code,0))
            audio.dispatchMediaKeyEvent(KeyEvent(at,at,KeyEvent.ACTION_UP,code,0))
            Handler(Looper.getMainLooper()).postDelayed({try{result.success(if(command=="stop"&&before&&!audio.isMusicActive)"stopped"else "requested")}catch(_:Exception){result.success("requested")}},1000)
        } catch (_: Exception) { result.success("error") }
    }
    fun resume(context: Context, result: MethodChannel.Result) {
        try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (audio.isMusicActive) { result.success("already_active"); return }
            val at = SystemClock.uptimeMillis()
            audio.dispatchMediaKeyEvent(KeyEvent(at, at, KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_MEDIA_PLAY, 0))
            audio.dispatchMediaKeyEvent(KeyEvent(at, at, KeyEvent.ACTION_UP, KeyEvent.KEYCODE_MEDIA_PLAY, 0))
            Handler(Looper.getMainLooper()).postDelayed({
                // Routing acceptance is not playback proof. Report measured audio state.
                try { result.success(if (audio.isMusicActive) "playing" else "requested") }
                catch (_: Exception) { result.success("requested") }
            }, 1500)
        } catch (_: Exception) { result.success("error") }
    }
}
