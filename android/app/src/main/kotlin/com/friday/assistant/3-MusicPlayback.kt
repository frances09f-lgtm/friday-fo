package com.friday.assistant
import android.content.Context
import io.flutter.plugin.common.MethodChannel
/** BitChord is the user-selected default. Never send media keys to another app when access/session is absent. */
object MusicPlayback {
 fun control(context:Context,command:String,result:MethodChannel.Result){BitChordSessionControl.execute(context,command,result)}
 fun resume(context:Context,result:MethodChannel.Result){BitChordSessionControl.execute(context,"play",result)}
}
