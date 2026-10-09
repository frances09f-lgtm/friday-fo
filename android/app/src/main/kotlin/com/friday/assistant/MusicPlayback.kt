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
    fun resume(context: Context, result: MethodChannel.Result) {
        try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (audio.isMusicActive) { result.success("playing"); return }
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
