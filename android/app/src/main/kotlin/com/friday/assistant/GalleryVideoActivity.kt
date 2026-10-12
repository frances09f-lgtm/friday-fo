package com.friday.assistant

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.VideoView
import android.widget.MediaController
import io.flutter.plugin.common.MethodChannel

/** Local-only player: report playing only after the decoder prepared and starts.
 * No network URL, exported receiver, or external app's autoplay assumption.
 */
class GalleryVideoActivity: Activity() {
 companion object {
  private var pending:MethodChannel.Result?=null
  private val handler=Handler(Looper.getMainLooper())
  private var timeout:Runnable?=null
  fun request(context:Context,uri:Uri,result:MethodChannel.Result){
   if(uri.scheme!="content" || uri.authority!="media"){result.success(mapOf("success" to false,"errorMessage" to "Invalid local media URI"));return}
   if(pending!=null){result.success(mapOf("success" to false,"errorMessage" to "A video start is already pending"));return}
   pending=result
   timeout=Runnable{complete(false,"Video did not start within 15 seconds. Check the player before retrying.")}.also{handler.postDelayed(it,15000)}
   try {context.startActivity(Intent(context,GalleryVideoActivity::class.java).setData(uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))}
   catch(_:Exception){complete(false,"Could not open the local video player.")}
  }
  private fun complete(playing:Boolean,message:String){
   timeout?.let{handler.removeCallbacks(it)};timeout=null
   val result=pending;pending=null
   result?.success(mapOf("success" to playing,"status" to if(playing)"PLAYING" else "FAILED","errorMessage" to message))
  }
 }
 private var video:VideoView?=null
 override fun onCreate(state:Bundle?){
  super.onCreate(state)
  val uri=intent.data
  if(uri==null || uri.scheme!="content" || uri.authority!="media"){complete(false,"Invalid local video URI.");finish();return}
  video=VideoView(this).apply{
   setMediaController(MediaController(this@GalleryVideoActivity))
   setOnPreparedListener{player->
    start()
    handler.postDelayed({complete(isPlaying,if(isPlaying)"Local player started." else "Video prepared but playback did not start.")},200)
   }
   setOnErrorListener{_,_,_->complete(false,"Video decoder could not play this file.");true}
   setVideoURI(uri)
  }
  setContentView(video)
 }
 override fun onPause(){video?.pause();super.onPause()}
 override fun onDestroy(){video?.stopPlayback();complete(false,"Video player closed before verified start.");super.onDestroy()}
}
