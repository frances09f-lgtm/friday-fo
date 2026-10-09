package com.friday.assistant

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Button
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Honest foreground UI for a user-issued volume command from the overlay.
 * Does not alter settings, fake foreground audio, or bypass OEM restrictions. */
class VolumeControlActivity:Activity() {
 companion object {
  private data class Request(val id:String,val percent:Int?,val up:Boolean?,val result:MethodChannel.Result)
  private var pending:Request?=null
  private val handler=Handler(Looper.getMainLooper())
  fun request(context:Context,percent:Int?,up:Boolean?,result:MethodChannel.Result){
   if((context.getSystemService(Context.KEYGUARD_SERVICE) as android.app.KeyguardManager).isKeyguardLocked){result.success("Unlock the phone before changing volume from Friday. No write made.");return}
   if(pending!=null){result.success("A volume change is already pending. No new write made.");return}
   if(percent!=null&&percent !in 0..100){result.success("Volume percent must be 0 to 100.");return}
   val id=UUID.randomUUID().toString();pending=Request(id,percent,up,result)
   AssistantOverlayService.volumeWindow(true)
   try{context.startActivity(Intent(context,VolumeControlActivity::class.java).putExtra("request",id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))}
   catch(_:Exception){complete(id,"Could not show foreground volume control. No success claimed.")}
   handler.postDelayed({complete(id,"Foreground volume control timed out. Check current volume before retrying. No success claimed.")},10000)
  }
  private fun complete(id:String,message:String){
   val p=pending?:return;if(p.id!=id)return
   pending=null;AssistantOverlayService.volumeWindow(false);p.result.success(message)
  }
 }
 private var started=false
 private val requestId:String get()=intent.getStringExtra("request")?:""
 override fun onCreate(state:Bundle?){
  super.onCreate(state)
  val p=pending
  if(p==null||p.id!=requestId){finish();return}
  title="Friday volume control"
  window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
  val box=LinearLayout(this).apply{orientation=LinearLayout.VERTICAL;setPadding(32,28,32,24)}
  box.addView(TextView(this).apply{text="Changing phone media volume ${p.percent?.let{"to $it%"}?:if(p.up==true)"up"else "down"}.\n\nFriday shows this window because some phones reject volume changes from an overlay. The result is read back twice and will remain in the bar.";textSize=17f})
  box.addView(Button(this).apply{text="Cancel";setOnClickListener{complete(requestId,"Volume control cancelled. A started write may already have happened; check current volume.");finish()}})
  setContentView(box)
 }
 override fun onWindowFocusChanged(focus:Boolean){
  super.onWindowFocusChanged(focus)
  if(!focus||started)return
  val p=pending?:return;if(p.id!=requestId)return
  started=true
  // Execute only once the real Activity is visible and has window focus.
  DeviceBridge.measuredVolume(this,p.percent,p.up,object:MethodChannel.Result{
   override fun success(value:Any?){complete(requestId,(value as? String?:"Volume readback missing. No success claimed.")+" Foreground volume window used.");finish()}
   override fun error(code:String,message:String?,details:Any?){complete(requestId,"Foreground volume error. No success claimed.");finish()}
   override fun notImplemented(){complete(requestId,"Foreground volume unavailable. No success claimed.");finish()}
  })
 }
 @Deprecated("Deprecated in Java")
 override fun onBackPressed(){complete(requestId,"Volume control closed. Check current volume before retrying.");super.onBackPressed()}
 override fun onDestroy(){
  if(isFinishing)complete(requestId,"Volume window closed before verification. No success claimed.")
  super.onDestroy()
 }
}
