package com.friday.assistant
import android.content.Context
import io.flutter.plugin.common.MethodChannel
/** Spotify only. Never send media keys to another app when access/session is absent. */
object MusicPlayback {
 fun control(context:Context,command:String,result:MethodChannel.Result){SpotifySessionControl.execute(context,command,result)}
 fun resume(context:Context,result:MethodChannel.Result){SpotifySessionControl.execute(context,"play",result)}
}
