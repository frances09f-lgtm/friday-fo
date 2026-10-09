package com.friday.assistant

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.plugin.common.MethodChannel

/** Android requires notification-listener access to enumerate active sessions.
 * Never read notification payloads, messages or other apps' media metadata. */
class FridayMediaAccess : NotificationListenerService() {
 override fun onNotificationPosted(sbn:StatusBarNotification?) { /* Intentionally ignored. */ }
 override fun onNotificationRemoved(sbn:StatusBarNotification?) { /* Intentionally ignored. */ }
}
object SpotifySessionControl {
 private const val SPOTIFY="com.spotify.music"
 private fun component(c:Context)=ComponentName(c,FridayMediaAccess::class.java)
 fun enabled(c:Context):Boolean {
  val raw=Settings.Secure.getString(c.contentResolver,"enabled_notification_listeners")?:""
  return raw.split(':').any{ComponentName.unflattenFromString(it)==component(c)}
 }
 fun state(c:Context):Map<String,Any> {
  val granted=enabled(c)
  val sessions=if(granted)try{controllers(c)}catch(_:Exception){emptyList()}else emptyList()
  return mapOf("enabled" to granted,"spotifySessions" to sessions.size,"purpose" to "Spotify transport only; notification content is ignored")
 }
 fun settings(c:Context){c.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))}
 private fun controllers(c:Context):List<MediaController> = (c.getSystemService(Context.MEDIA_SESSION_SERVICE)as MediaSessionManager).getActiveSessions(component(c)).filter{it.packageName==SPOTIFY}
 private fun track(m:MediaMetadata?):String? {
  if(m==null)return null
  val id=m.getString(MediaMetadata.METADATA_KEY_MEDIA_ID)
  if(!id.isNullOrBlank())return id
  val title=m.getString(MediaMetadata.METADATA_KEY_TITLE)
  if(title.isNullOrBlank())return null
  return title+"|"+(m.getString(MediaMetadata.METADATA_KEY_ARTIST)?:"")+"|"+(m.getString(MediaMetadata.METADATA_KEY_ALBUM)?:"")
 }
 fun execute(c:Context,command:String,result:MethodChannel.Result){
  if(!enabled(c)){result.success("access_required");return}
  try {
   val all=controllers(c)
   val playing=all.filter{it.playbackState?.state==PlaybackState.STATE_PLAYING}
   val choices=if(playing.size==1)playing else all
   if(choices.isEmpty()){result.success("no_spotify_session");return}
   if(choices.size!=1){result.success("ambiguous_spotify_session");return}
   val controller=choices.single();val before=controller.playbackState
   val beforeTrack=track(controller.metadata)
   val action=when(command){"play"->PlaybackState.ACTION_PLAY;"pause"->PlaybackState.ACTION_PAUSE;"stop"->(if(((before?.actions?:0L) and PlaybackState.ACTION_STOP)!=0L)PlaybackState.ACTION_STOP else PlaybackState.ACTION_PAUSE);"next"->PlaybackState.ACTION_SKIP_TO_NEXT;"previous"->PlaybackState.ACTION_SKIP_TO_PREVIOUS;else->{result.success("error");return}}
   if(before==null||(before.actions and action)==0L){result.success("unsupported_spotify_action");return}
   if(command=="play"&&before.state==PlaybackState.STATE_PLAYING){result.success("spotify_already_playing");return}
   if(command in setOf("pause","stop")&&before.state!=PlaybackState.STATE_PLAYING){result.success("spotify_already_inactive");return}
   when(command){"play"->controller.transportControls.play();"pause"->controller.transportControls.pause();"stop"->if(action==PlaybackState.ACTION_STOP)controller.transportControls.stop()else controller.transportControls.pause();"next"->controller.transportControls.skipToNext();"previous"->controller.transportControls.skipToPrevious()}
   val h=Handler(Looper.getMainLooper());var attempts=0
   val check=object:Runnable {
    override fun run(){
     try{
      val after=controller.playbackState
      val changed=when(command){
       "play"->after?.state==PlaybackState.STATE_PLAYING&&before.state!=PlaybackState.STATE_PLAYING
       "pause"->after?.state==PlaybackState.STATE_PAUSED&&before.state==PlaybackState.STATE_PLAYING
       "stop"->after?.state in setOf(PlaybackState.STATE_STOPPED,PlaybackState.STATE_PAUSED,PlaybackState.STATE_NONE)&&before.state==PlaybackState.STATE_PLAYING
       else->SpotifyObservation.trackChanged(beforeTrack,track(controller.metadata))
      }
      if(changed){result.success("spotify_verified_$command");return}
      if(++attempts>=8){result.success(if(command in setOf("next","previous")&&beforeTrack==null)"spotify_metadata_unavailable"else "spotify_unverified_$command");return}
      h.postDelayed(this,500)
     }catch(_:Exception){result.success("spotify_session_lost")}
    }
   };h.postDelayed(check,250)
  }catch(_:SecurityException){result.success("access_required")}catch(_:Exception){result.success("error")}
 }
}
