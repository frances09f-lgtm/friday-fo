package com.friday.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.view.WindowManager
import android.view.Gravity
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.content.Intent
import android.provider.Settings

class FridayAccessibilityService:AccessibilityService(){
 companion object {
  var current:FridayAccessibilityService?=null
  fun register(m:BinaryMessenger,c:Context){MethodChannel(m,"friday/agent").setMethodCallHandler{call,result->
   val s=current
   try {when(call.method){
    "settings"->{c.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));result.success(mapOf("success" to true))}
    "state"->result.success(mapOf("success" to (s!=null)))
    "start"->result.success(s?.start(call.argument<String>("package")?:"",call.argument<String>("query")?:"",call.argument<Boolean>("settings")==true)?:mapOf("success" to false,"error" to "Enable Friday Accessibility in Settings"))
    "stop"->{s?.stop();result.success(mapOf("success" to true))}
    "observe"->result.success(s?.observe()?:mapOf("success" to false,"error" to "Accessibility disconnected"))
    "act"->{if(s==null)result.success(mapOf("success" to false,"error" to "Accessibility disconnected")) else s.act(call.argument<Map<String,Any>>("action")?:emptyMap(),call.argument<String>("token")?:"",result)}
    "log"->{val line=call.argument<String>("line")?:"";if(Regex("Step [0-9]+ [a-z_]+: (verified|not verified)").matches(line)){val p=c.getSharedPreferences("agent_debug",0);val old=p.getString("log","")?:"";p.edit().putString("log",(old+"\n"+line).lines().takeLast(60).joinToString("\n")).apply()};result.success(mapOf("success" to true))}
    "logs"->result.success(mapOf("log" to c.getSharedPreferences("agent_debug",0).getString("log","")))
    else->result.notImplemented()
   }}catch(e:Exception){result.success(mapOf("success" to false,"error" to "Native operation failed"))}
  }}
 }
 private val timer=android.os.Handler(android.os.Looper.getMainLooper())
 private val expire=Runnable { stop() }
 val isRunning:Boolean get()=active
 private var active=false
 private var allowed=""
 private var query=""
 private var settings=false
 private var overlay:LinearLayout?=null
 private val nodes=mutableListOf<AccessibilityNodeInfo>()
 private var token=""
 override fun onServiceConnected(){current=this}
 override fun onAccessibilityEvent(event:AccessibilityEvent?){}
 override fun onInterrupt(){stop()}
 override fun onDestroy(){stop();current=null;super.onDestroy()}
 fun start(pkg:String,q:String,setting:Boolean):Map<String,Any>{
  if(active)return fail("Agent already running")
  if(pkg !in listOf("com.google.android.youtube","com.android.chrome","com.instagram.android","com.android.settings"))return fail("App outside core V1")
  allowed=pkg;query=q;settings=setting;active=true
  try{
   val box=LinearLayout(this).apply{orientation=LinearLayout.HORIZONTAL;setBackgroundColor(0xff202020.toInt())}
   box.addView(TextView(this).apply{text="Friday Agent";setTextColor(-1);setPadding(12,12,12,12)})
   box.addView(Button(this).apply{text="STOP";setOnClickListener{stop()}})
   (getSystemService(WINDOW_SERVICE) as WindowManager).addView(box,WindowManager.LayoutParams(-2,-2,WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,android.graphics.PixelFormat.TRANSLUCENT).apply{gravity=Gravity.TOP or Gravity.END;y=60})
   overlay=box
  }catch(e:Exception){active=false;return fail("Cannot show Stop control")}
  timer.postDelayed(expire,60000)
  return ok()
 }
 fun stop(){timer.removeCallbacks(expire);active=false;overlay?.let{try{(getSystemService(WINDOW_SERVICE) as WindowManager).removeView(it)}catch(_:Exception){}};overlay=null;nodes.clear();token=""}
 private fun fail(msg:String)=mapOf("success" to false,"error" to msg)
 private fun ok()=mapOf("success" to true)
 fun observe():Map<String,Any>{
  if(!active)return fail("Agent stopped")
  val root=windows.firstOrNull{it.type==android.view.accessibility.AccessibilityWindowInfo.TYPE_APPLICATION && it.isActive}?.root ?: rootInActiveWindow ?: return fail("No readable active window")
  timer.removeCallbacks(expire);timer.postDelayed(expire,60000)
  nodes.clear();val elements=mutableListOf<Map<String,Any>>();var visits=0
  fun walk(n:AccessibilityNodeInfo,depth:Int){
   if(visits++>=400||depth>18||elements.size>=70)return
   if(n.isVisibleToUser&&(n.text!=null||n.contentDescription!=null||n.isEditable||n.isScrollable)){
    val b=Rect();n.getBoundsInScreen(b)
    if(!n.isPassword){nodes.add(n);elements.add(mapOf("text" to (n.text?.toString()?.take(120)?:""),"contentDescription" to (n.contentDescription?.toString()?.take(120)?:""),"resourceId" to (n.viewIdResourceName?:""),"class" to (n.className?.toString()?:""),"clickable" to n.isClickable,"editable" to n.isEditable,"scrollable" to n.isScrollable,"bounds" to listOf(b.left,b.top,b.right,b.bottom)))}
   }
   for(i in 0 until n.childCount){n.getChild(i)?.let{walk(it,depth+1)}}
  }
  val pkg=root.packageName?.toString()?:""
  if(pkg==allowed)walk(root,0)
  token=(pkg+elements.toString()).hashCode().toString()
  return mapOf("success" to true,"package" to pkg,"screen" to (root.className?.toString()?:""),"elements" to elements,"token" to token,"truncated" to (visits>=400||elements.size>=70))
 }
 fun act(a:Map<String,Any>,oldToken:String,result:MethodChannel.Result){
  if(!active){result.success(fail("Agent stopped"));return}
  val now=observe();if(now["token"]!=oldToken){result.success(fail("Screen changed. Observe again"));return}
  val action=a["action"]?.toString()?:"";val target=a["target"] as? Map<*,*>?:emptyMap<Any,Any>()
  if(action=="open_app"){
   if(target["package"]!=allowed){result.success(fail("App outside user goal"));return}
   result.success(mapOf("success" to DeviceBridge.openApp(this,allowed)));return
  }
  if(now["package"]!=allowed){result.success(fail("Wrong foreground app"));return}
  if(action in listOf("wait","read_screen")){result.success(ok());return}
  if(action in listOf("back","home")){result.success(mapOf("success" to performGlobalAction(if(action=="back")GLOBAL_ACTION_BACK else GLOBAL_ACTION_HOME)));return}
  val field=listOf("text","contentDescription","resourceId").filter{(target[it]?.toString()?:"").isNotBlank()}
  fun matches(n:AccessibilityNodeInfo)=field.isNotEmpty()&&field.all{val wanted=target[it].toString();val value=when(it){"text"->n.text?.toString();"contentDescription"->n.contentDescription?.toString();else->n.viewIdResourceName};value.equals(wanted,ignoreCase=true)}
  var matches=nodes.filter{matches(it)}
  if(action=="scroll"&&field.isEmpty())matches=nodes.filter{it.isScrollable}
  if(matches.size!=1){result.success(fail("Target missing or ambiguous"));return}
  var node=matches.single()
  if(node.isPassword||!node.isEnabled){result.success(fail("Protected or disabled target"));return}
  val labels=(node.text?.toString()?:"")+" "+(node.contentDescription?.toString()?:"")+" "+(node.viewIdResourceName?:"")
  if(action=="type"){
   val text=a["text"]?.toString()?:""
   if(settings||text!=query||!node.isEditable||!Regex("search|url_bar|address|omnibox",RegexOption.IGNORE_CASE).containsMatchIn(labels)){result.success(fail("Typing allowed only in a search field with exact user query"));return}
   result.success(mapOf("success" to node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply{putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,text)})));return
  }
  if(action=="tap"){
   val safe=if(settings)node.text?.toString().equals("Bluetooth",true)&&!node.isCheckable else Regex("search|url_bar|address|omnibox",RegexOption.IGNORE_CASE).containsMatchIn(labels)
   if(!safe||Regex("send|post|buy|delete|call|allow|permission",RegexOption.IGNORE_CASE).containsMatchIn(labels)){result.success(fail("Action needs review or is outside core V1"));return}
   if(node.isEditable && node.text?.toString()==query){
    if(android.os.Build.VERSION.SDK_INT<30){result.success(fail("Submitting search requires Android 11+ IME action"));return}
    result.success(mapOf("success" to node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)));return
   }
   var climb=0;while(!node.isClickable&&climb++<3){node=node.parent?:break}
   val ancestorLabels=(node.text?.toString()?:"")+" "+(node.contentDescription?.toString()?:"")+" "+(node.viewIdResourceName?:"")
   if(Regex("send|post|buy|delete|call|allow|permission",RegexOption.IGNORE_CASE).containsMatchIn(ancestorLabels)){result.success(fail("Unsafe clickable ancestor"));return}
   if(node.isCheckable||node.className?.toString()?.contains("Switch")==true){result.success(fail("Settings changes disabled"));return}
   result.success(mapOf("success" to node.performAction(AccessibilityNodeInfo.ACTION_CLICK)));return
  }
  if(action=="scroll"&&!settings){result.success(mapOf("success" to node.performAction(if(a["text"]=="up")AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD else AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)));return}
  if(action=="swipe"&&!settings&&node.isScrollable){
   val b=Rect();node.getBoundsInScreen(b);val path=Path();val up=a["text"]=="up";path.moveTo(b.centerX().toFloat(),(if(up)b.top+b.height()/4 else b.bottom-b.height()/4).toFloat());path.lineTo(b.centerX().toFloat(),(if(up)b.bottom-b.height()/4 else b.top+b.height()/4).toFloat())
   val accepted=dispatchGesture(GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path,0,300)).build(),object:GestureResultCallback(){override fun onCompleted(g:GestureDescription?){result.success(ok())};override fun onCancelled(g:GestureDescription?){result.success(fail("Gesture cancelled"))}},null)
   if(!accepted)result.success(fail("Gesture dispatch refused"));return
  }
  result.success(fail("Unsupported core action"))
 }
}
