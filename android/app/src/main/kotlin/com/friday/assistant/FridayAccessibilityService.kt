package com.friday.assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import java.io.ByteArrayOutputStream
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.SystemClock
import android.os.Looper
import android.provider.Settings
import android.view.inputmethod.EditorInfo
import android.text.InputType
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** All screen data stays in memory. Planner proposes; this executor rechecks scope,
 * foreground, freshness, uniqueness, lock state and sensitive controls independently. */
class FridayAccessibilityService : AccessibilityService() {
 companion object {
  var current: FridayAccessibilityService? = null
  val supported = setOf("com.google.android.youtube", "com.android.chrome", "com.instagram.android", "com.android.settings", "com.whatsapp", "com.openai.chatgpt")
  fun register(m: BinaryMessenger, c: Context) {
   MethodChannel(m,"friday/agent").setMethodCallHandler { call,result ->
    val s=current
    try { when(call.method) {
     "buildInfo" -> {val i=c.packageManager.getPackageInfo(c.packageName,0);result.success(mapOf("version" to i.versionName,"build" to i.longVersionCode))}
     "settings" -> {c.startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));result.success(mapOf("success" to true))}
     "state" -> result.success(mapOf("success" to (s!=null),"running" to (s?.active==true)))
     "start" -> result.success(s?.start(call.argument<String>("package")?:"",call.argument<String>("query")?:"",call.argument<Boolean>("settings")==true,call.argument<String>("workflow")?:"search",call.argument<List<Map<String,Any>>>("commands")?:emptyList())?:mapOf("success" to false,"error" to "Enable Friday Accessibility in Settings"))
     "stop" -> {s?.stop();result.success(mapOf("success" to true))}
     "screenshot" -> if(s==null)result.success(mapOf("success" to false,"error" to "Accessibility disconnected")) else s.capture(result)
     "await_screen" -> if(s==null)result.success(mapOf("success" to false,"error" to "Accessibility disconnected"))else s.awaitScreen(result,(call.argument<Int>("timeoutMs")?:1200).coerceIn(220,1500))
     "observe" -> result.success(s?.observe()?:mapOf("success" to false,"error" to "Accessibility disconnected"))
     "act" -> if(s==null)result.success(mapOf("success" to false,"error" to "Accessibility disconnected"))else s.act(call.argument<Map<String,Any>>("action")?:emptyMap(),call.argument<String>("token")?:"",result)
     "progress" -> {s?.indicator?.text=call.argument<String>("phase")?.take(65)?:"Friday screen control";result.success(mapOf("success" to true))}
     "log" -> {val line=call.argument<String>("line")?:"";if(Regex("Step [0-9]+ [a-z_]+: (verified|not verified)|Check [0-9]+: (protected_screen|action_refused|screen_loading|expected_result|wrong_or_missing_result); [0-9]+ ms").matches(line)){val p=c.getSharedPreferences("agent_debug",0);p.edit().putString("log",((p.getString("log","")?:"")+"\n"+line).lines().takeLast(60).joinToString("\n")).apply()};result.success(mapOf("success" to true))}
     "logs" -> result.success(mapOf("log" to c.getSharedPreferences("agent_debug",0).getString("log","")))
     else -> result.notImplemented()
    }}catch(e:Exception){result.success(mapOf("success" to false,"error" to "Native ${call.method} failed (${e.javaClass.simpleName}); no completion claimed"))}
   }
  }
 }
 private val timer=Handler(Looper.getMainLooper())
 private val expire=Runnable{stop("Native safety timer expired after 60 seconds without a screen observation")}
 private var active=false
 val isRunning get()=active
 private var allowed=""
 private var query=""
 private var settings=false
 private var searchIntentAttempted=false
 private var youtubeEditorAttempted=false
 private var youtubeImeAttempted=false
 private var youtubeKeyboardAttempted=false
 private var workflow="search"
 private var commands=emptyList<Map<String,Any>>()
 private var overlay:LinearLayout?=null
 private var indicator:TextView?=null
 private var stopReason="No active accessibility task"
 private var token=""
 private val nodes=mutableListOf<AccessibilityNodeInfo>()
 private var observedPackage=""
 private fun locked()=(getSystemService(KEYGUARD_SERVICE)as KeyguardManager).isKeyguardLocked
 private fun fail(s:String,blocked:Boolean=false)=mapOf("success" to false,"error" to s,"blocked" to blocked)
 private fun ok()=mapOf("success" to true)
 @Suppress("DEPRECATION") private fun releaseNodes(){nodes.forEach{try{it.recycle()}catch(_:Exception){}};nodes.clear();token=""}
 override fun onServiceConnected(){current=this;serviceInfo=serviceInfo.apply{if(android.os.Build.VERSION.SDK_INT>=33)flags=flags or AccessibilityServiceInfo.FLAG_INPUT_METHOD_EDITOR;flags=flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS;eventTypes=AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or AccessibilityEvent.TYPE_WINDOWS_CHANGED or AccessibilityEvent.TYPE_VIEW_SCROLLED or AccessibilityEvent.TYPE_VIEW_FOCUSED or AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED}}
 private var eventRevision=0L
 private var lastEventAt=0L
 private var scrollEvent=emptyMap<String,Any>()
 private var scrollPositions=mutableMapOf<String,Pair<Int,Int>>()
 override fun onAccessibilityEvent(e:AccessibilityEvent?){
  if(!active||e==null||e.packageName?.toString()!=allowed)return
  eventRevision++;lastEventAt=SystemClock.uptimeMillis()
  if(e.eventType==AccessibilityEvent.TYPE_VIEW_SCROLLED){
   val n=e.source?:return
   try{
    if(!n.isScrollable||!n.isVisibleToUser)return
    val b=Rect();n.getBoundsInScreen(b)
    val key="${n.viewIdResourceName}:${b.toShortString()}"
    val previous=scrollPositions[key]
    val delta=if(android.os.Build.VERSION.SDK_INT>=28)e.scrollDeltaY else 0
    val direction=ScreenSettlingPolicy.scrollDirection(delta,previous?.first,e.scrollY,previous?.second,e.fromIndex)
    scrollPositions[key]=Pair(e.scrollY,e.fromIndex)
    scrollEvent=mapOf("revision" to eventRevision,"package" to allowed,
     "bounds" to listOf(b.left,b.top,b.right,b.bottom),"direction" to direction,"moved" to (direction!="unknown"))
   }finally{n.recycle()}
  }
 }
 private fun awaitScreen(result:MethodChannel.Result, timeout:Int){
  val started=SystemClock.uptimeMillis()
  fun check(){
   if(!active){result.success(fail(stopReason));return}
   val now=SystemClock.uptimeMillis()
   val stable=ScreenSettlingPolicy.settled(now,started,lastEventAt)
   if(stable||now-started>=timeout){result.success(observe()+mapOf("settlingTimedOut" to !stable));return}
   timer.postDelayed({check()},60)
  }
  check()
 }
 override fun onInterrupt(){stop("Android interrupted the accessibility service")}
 override fun onDestroy(){stop("Accessibility service was destroyed");current=null;super.onDestroy()}
 fun start(pkg:String,q:String,setting:Boolean,flow:String="search",steps:List<Map<String,Any>> = emptyList()):Map<String,Any>{
  if(active)return fail("Agent already running")
  if(locked())return fail("Unlock your phone before screen control",true)
  scrollPositions.clear();scrollEvent=emptyMap();eventRevision=0;lastEventAt=SystemClock.uptimeMillis()
  workflow=flow;commands=steps;searchIntentAttempted=false;youtubeEditorAttempted=false;youtubeImeAttempted=false;youtubeKeyboardAttempted=false
  var target=pkg
  if(target.isEmpty()&&flow in setOf("read","commands")){
   val root=applicationRoot(flow=="read")?:return fail("No readable underlying application. Open the app to read first.")
   target=root.packageName?.toString()?:"";@Suppress("DEPRECATION") root.recycle()
  }
  if(target.isBlank()||target=="com.android.systemui"||target.contains("permissioncontroller"))return fail("Security or permission screen requires you",true)
  if(flow !in setOf("read","commands")&&target !in supported)return fail("App outside supported workflow")
  if(flow !in setOf("read","commands"))try{packageManager.getApplicationInfo(target,0)}catch(_:Exception){return fail("Requested app is not installed",true)}
  if(q.length>250||steps.size>8)return fail("Task exceeds safe limits")
  allowed=target;query=q;settings=setting;stopReason="";active=true
  try{
   val box=LinearLayout(this).apply{orientation=LinearLayout.HORIZONTAL;setBackgroundColor(0xff202020.toInt())}
   indicator=TextView(this).apply{text="Friday screen control";setTextColor(-1);setPadding(12,12,12,12)};box.addView(indicator)
   box.addView(Button(this).apply{text="STOP";setOnClickListener{stop("Stop control activated. Touch source could not be determined; no completion claimed")}})
   (getSystemService(WINDOW_SERVICE)as WindowManager).addView(box,WindowManager.LayoutParams(-2,-2,WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,android.graphics.PixelFormat.TRANSLUCENT).apply{gravity=Gravity.BOTTOM or Gravity.START;y=80});overlay=box
  }catch(_:Exception){active=false;return fail("Cannot show Stop control")}
  timer.postDelayed(expire,60000);return mapOf("success" to true,"package" to allowed)
 }
 fun stop(reason:String="Stopped by Friday task controller"){
  if(active)stopReason=reason;timer.removeCallbacks(expire);active=false
  overlay?.let{try{(getSystemService(WINDOW_SERVICE)as WindowManager).removeView(it)}catch(_:Exception){}};overlay=null;indicator=null;releaseNodes();commands=emptyList();query=""
 }
 @Suppress("DEPRECATION") private fun applicationRoot(readUnderlying:Boolean=false):AccessibilityNodeInfo? {
  val ws=windows
  // Never use an accessibility overlay/IME root as application content.
  // Security application windows remain eligible and will be refused below.
  val apps=ws.filter{it.type==AccessibilityWindowInfo.TYPE_APPLICATION}.sortedByDescending{it.layer}
  val roots=apps.mapNotNull{it.root}
  ws.forEach{it.recycle()}
  val root=roots.firstOrNull{!readUnderlying || it.packageName?.toString()!=packageName}
  roots.filter{it!==root}.forEach{it.recycle()}
  return root
 }
 @Suppress("DEPRECATION") fun observe():Map<String,Any>{
  if(!active)return fail(stopReason.ifEmpty{"No active accessibility task"})
  if(locked()){stop("Phone locked; unlock and restart manually");return fail(stopReason,true)}
  val root=applicationRoot(workflow=="read")
  if(root==null)return mapOf("success" to false,"error" to "No readable active window","transient" to true,"windowDiagnostic" to "Connected; no app root")
  timer.removeCallbacks(expire);timer.postDelayed(expire,60000);releaseNodes()
  observedPackage=root.packageName?.toString()?:""
  val elements=mutableListOf<Map<String,Any>>();var visits=0
  fun walk(n:AccessibilityNodeInfo,depth:Int,path:String,parentContext:String){
   try{
    if(visits++>=600||depth>22||elements.size>=100)return
    if(n.isVisibleToUser&&!n.isPassword&&(n.text!=null||n.contentDescription!=null||n.isEditable||n.isClickable||n.isScrollable)){
     val b=Rect();n.getBoundsInScreen(b);nodes.add(AccessibilityNodeInfo.obtain(n))
     elements.add(mapOf("id" to path,"parentContext" to parentContext,"text" to (n.text?.toString()?.take(250)?:""),"contentDescription" to (n.contentDescription?.toString()?.take(180)?:""),"resourceId" to (n.viewIdResourceName?:""),"hintText" to (if(android.os.Build.VERSION.SDK_INT>=26)n.hintText?.toString()?.take(180)?:"" else ""),"class" to (n.className?.toString()?:""),"clickable" to n.isClickable,"editable" to n.isEditable,"scrollable" to n.isScrollable,"focused" to n.isFocused,"bounds" to listOf(b.left,b.top,b.right,b.bottom)))
    }
    val context=if(n.isPassword)"" else (n.contentDescription?.toString()?:n.viewIdResourceName?:n.className?.toString()?:"").take(180)
    for(i in 0 until n.childCount)n.getChild(i)?.let{walk(it,depth+1,"$path/$i",context)}
   }finally{n.recycle()}
  }
  val rootClass=root.className?.toString()?:""
  if(observedPackage==allowed)walk(root,0,"root","")else root.recycle()
  token=(observedPackage+elements.toString()).hashCode().toString()
  if(observedPackage.contains("permissioncontroller")||observedPackage=="com.android.systemui")return fail("Permission or security application requires you: $observedPackage (workflow $workflow). No action on it was run",true)
  val audioActive=(getSystemService(AUDIO_SERVICE)as android.media.AudioManager).isMusicActive
  return mapOf("eventRevision" to eventRevision,"scrollEvent" to scrollEvent,"audioActive" to audioActive,"success" to true,"package" to observedPackage,"screen" to rootClass,"elements" to elements,"token" to token,"truncated" to (visits>=600||elements.size>=100))
 }
 private fun label(n:AccessibilityNodeInfo)="${n.text?:""} ${n.contentDescription?:""} ${n.viewIdResourceName?:""} ${if(android.os.Build.VERSION.SDK_INT>=26)n.hintText?:"" else ""}"
 private fun protected(label:String)=Regex("\\b(send|post|buy|purchase|delete|pay|call|allow|permission|sign.?in|log.?in|subscribe|confirm)\\b",RegexOption.IGNORE_CASE).containsMatchIn(label)
 private fun search(label:String)=Regex("search|검색|url_bar|address|omnibox",RegexOption.IGNORE_CASE).containsMatchIn(label)
 private fun resultAnswer(result:MethodChannel.Result,success:Boolean)=result.success(if(success)ok()else fail("Android refused the action; inspect screen before retrying"))
 @Suppress("DEPRECATION") fun act(a:Map<String,Any>,oldToken:String,result:MethodChannel.Result){
  if(!active){result.success(fail(stopReason.ifEmpty{"No active accessibility task"}));return}
  val now=observe();if(now["success"]==false){result.success(now);return};if(now["token"]!=oldToken){result.success(fail("Screen changed. Observe again"));return}
  val action=a["action"]?.toString()?:"";val target=a["target"]as?Map<*,*>?:emptyMap<Any,Any>();val text=a["text"]?.toString()?:""
  if(action=="open_app"){
   if(target["package"]!=allowed){result.success(fail("App outside user goal",true));return}
   resultAnswer(result,DeviceBridge.openApp(this,allowed));return
  }
  if(now["package"]!=allowed){result.success(fail("Wrong foreground app",true));return}
  if(action in setOf("wait","read_screen")){result.success(ok());return}
  if(action=="back"){
   val chatExit=ConversationExitPolicy.permits(allowed,workflow,
    nodes.any{Regex("conversation_contact|conversation_title",RegexOption.IGNORE_CASE).containsMatchIn(it.viewIdResourceName?:"")},
    nodes.any{it.isEditable&&Regex("(?:^|[/_:])entry$|message",RegexOption.IGNORE_CASE).containsMatchIn("${it.viewIdResourceName?:""} ${it.contentDescription?:""}".trim())},
    nodes.any{Regex("\\b(login|log.?in|sign.?in|permission|allow)\\b",RegexOption.IGNORE_CASE).containsMatchIn(label(it))})
   if(!chatExit&&(workflow!="commands"||commands.none{it["action"]=="back"})){result.success(fail("Back not authorized by this workflow",true));return}
   resultAnswer(result,performGlobalAction(GLOBAL_ACTION_BACK));return
  }
  // Home deliberately not dispatched: changes target context without a goal.
  if(action=="search_intent"){
   if(searchIntentAttempted||allowed !in setOf("com.google.android.youtube","com.android.chrome")||workflow !in setOf("search","play")||target["package"]!=allowed||text!=query||query.isBlank()||query.length>200){result.success(fail("Search intent outside exact YouTube task",true));return}
   searchIntentAttempted=true
   resultAnswer(result,DeviceBridge.searchApp(this,if(allowed=="com.google.android.youtube")"youtube" else "chrome",query));return
  }
  val fields=listOf("text","contentDescription","resourceId","hintText").filter{(target[it]?.toString()?:"").isNotBlank()}
  var matches=nodes.filter{n->fields.isNotEmpty()&&fields.all{f->val actual=when(f){"text"->n.text?.toString();"contentDescription"->n.contentDescription?.toString();"hintText"->if(android.os.Build.VERSION.SDK_INT>=26)n.hintText?.toString() else null;else->n.viewIdResourceName};actual.equals(target[f]?.toString(),true)}}
  if(action in setOf("scroll","swipe")&&fields.isEmpty())matches=nodes.filter{it.isScrollable}
  val wantedBounds=target["bounds"] as? List<*>
  if(wantedBounds!=null && wantedBounds.size==4){matches=matches.filter{n->val b=Rect();n.getBoundsInScreen(b);wantedBounds==listOf(b.left,b.top,b.right,b.bottom)}}
  if(matches.size!=1){result.success(fail("Target missing or ambiguous for $action in $observedPackage ($workflow); ${matches.size} exact matches. Choose a visible exact label",true));return}
  val node=matches.single();val labels=label(node)
  if(action=="tap"&&workflow!="commands"&&Regex("clear|dismiss|close|reset",RegexOption.IGNORE_CASE).containsMatchIn(labels)){result.success(fail("Clear or dismiss is not a search-opening action",true));return}
  if(node.isPassword||!node.isEnabled){result.success(fail("Protected or disabled target",true));return}
  if(protected(labels)&&!(workflow=="question"&&action=="submit"&&allowed=="com.openai.chatgpt"&&Regex("^(send|send prompt|send message|submit)$",RegexOption.IGNORE_CASE).matches(FieldLabelPolicy.primary(node.contentDescription?.toString(),node.text?.toString())))){result.success(fail("Action needs review or is outside task scope",true));return}
  if(action=="type"){
   val exact=if(workflow=="commands")commands.any{it["action"]=="type"&&it["text"]==text}else text==query
   val fieldSafe=when(workflow){"commands"-> !protected(labels);"question"->allowed=="com.openai.chatgpt";else->search(labels)}
   if(settings||!exact||!node.isEditable||!fieldSafe||(allowed=="com.whatsapp"&&!search(labels))){result.success(fail("Typing allowed only in the requested safe field; WhatsApp message composer is blocked",true));return}
   youtubeEditorAttempted=false;youtubeImeAttempted=false;youtubeKeyboardAttempted=false
   resultAnswer(result,node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT,Bundle().apply{putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,text)}));return
  }
  if(action=="submit"||(action=="tap"&&node.isEditable&&node.isFocused&&node.text?.toString()==query)){
   if(workflow=="question"&&allowed=="com.openai.chatgpt"&&text==query&&nodes.count{it.isEditable&&it.text?.toString()==query}==1&&Regex("^(send|send prompt|send message|submit)$",RegexOption.IGNORE_CASE).matches(FieldLabelPolicy.primary(node.contentDescription?.toString(),node.text?.toString()))) {resultAnswer(result,node.performAction(AccessibilityNodeInfo.ACTION_CLICK));return}
   if(!node.isEditable&&search(labels)&&Regex("^(search|submit search)$",RegexOption.IGNORE_CASE).matches(FieldLabelPolicy.primary(node.contentDescription?.toString(),node.text?.toString()))&&nodes.count{it.isEditable&&it.text?.toString()==query}==1){resultAnswer(result,node.performAction(AccessibilityNodeInfo.ACTION_CLICK));return}
   if(!node.isEditable||!search(labels)||node.text?.toString()!=query){result.success(fail("Submit limited to the exact requested search",true));return}
   val youtube=allowed=="com.google.android.youtube" && workflow in setOf("search","play")
   if(youtube){
    if(!YouTubeSubmitPolicy.permits(observedPackage,workflow,query,nodes.count{it.isEditable&&it.text?.toString()==query},node.isFocused)){result.success(fail("YouTube submit requires the unique focused exact-query field",true));return}
    // Android 13+ has a direct editor Search action. It does not depend
    // on an IME exposing its Search key as a clickable accessibility node.
    if(android.os.Build.VERSION.SDK_INT>=33 && !youtubeEditorAttempted){
     if(editorSearch(result))return
    }
    // Only after a prior attempt was observed not to produce results.
    if(youtubeImeAttempted){keyboardSearch(result);return}
    youtubeImeAttempted=true
   }
   if(android.os.Build.VERSION.SDK_INT<30){result.success(fail("Field IME action unavailable; re-observe before keyboard Search fallback",!youtube));return}
   resultAnswer(result,node.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id));return
  }
  if(action=="tap"){
   val safe=when(workflow){
    "commands" -> commands.any{it["action"]=="tap"&&(it["target"]as?Map<*,*>)?.get("text")?.toString().equals(node.text?.toString(),true)}
    "contact" -> search(labels)||node.text?.toString().equals(query,true)
    "question" -> node.isEditable
    "play" -> search(labels)||labels.contains(query,true)
    else -> if(settings)node.text?.toString().equals("Bluetooth",true)&&!node.isCheckable else search(labels)
   }
   if(!safe){result.success(fail("Action needs review or is outside task scope",true));return}
   if(workflow=="contact"&&!search(labels)&&!node.text?.toString().equals(query,true)){result.success(fail("Contact identity not exact",true));return}
   var click=node;val parents=mutableListOf<AccessibilityNodeInfo>();var climb=0
   while(!click.isClickable&&climb++<4){val p=click.parent?:break;parents.add(p);click=p}
   try{
    if(protected(label(click))||click.isCheckable||click.className?.toString()?.contains("Switch")==true){result.success(fail("Unsafe clickable ancestor; user review required",true));return}
    if(click.performAction(AccessibilityNodeInfo.ACTION_CLICK)){result.success(ok());return}
    // Coordinate fallback uses only this exact, unique, enabled semantic node's
    // freshly observed bounds, never model-supplied coordinates.
    val bounds=Rect();click.getBoundsInScreen(bounds)
    if(overlapsOverlay(bounds)){result.success(fail("Tap fallback overlaps Friday Stop control. No gesture dispatched",true));return}
    if(bounds.isEmpty||!click.isVisibleToUser){result.success(fail("No safe bounds for fallback"));return}
    val path=Path().apply{moveTo(bounds.centerX().toFloat(),bounds.centerY().toFloat())};gesture(path,70,result)
   }finally{parents.forEach{it.recycle()}}
   return
  }
  if(action=="scroll"&&!settings){resultAnswer(result,node.performAction(if(text=="up")AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD else AccessibilityNodeInfo.ACTION_SCROLL_FORWARD));return}
  if(action=="swipe"&&!settings&&node.isScrollable){val b=Rect();node.getBoundsInScreen(b);if(overlapsOverlay(b)){result.success(fail("Swipe intersects Friday Stop control. Use semantic scroll",true));return};val path=Path();val up=text=="up";path.moveTo(b.centerX().toFloat(),(if(up)b.top+b.height()/4 else b.bottom-b.height()/4).toFloat());path.lineTo(b.centerX().toFloat(),(if(up)b.bottom-b.height()/4 else b.top+b.height()/4).toFloat());gesture(path,300,result);return}
  result.success(fail("Unsupported screen action"))
 }
 @android.annotation.TargetApi(33)
 private fun editorSearch(result:MethodChannel.Result):Boolean {
  // The caller already re-observed and checked foreground, exact focused
  // query, uniqueness, lock, enabled state and safe YouTube task scope.
  val im=inputMethod?:return false
  val info=im.currentInputEditorInfo?:return false
  val connection=im.currentInputConnection?:return false
  val surrounding=connection.getSurroundingText(251,251,0)?:return false
  val password=(info.inputType and InputType.TYPE_MASK_VARIATION) in setOf(InputType.TYPE_TEXT_VARIATION_PASSWORD,InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,InputType.TYPE_NUMBER_VARIATION_PASSWORD)
  if(!YouTubeSubmitPolicy.editorSearch(info.packageName?:"",info.imeOptions and EditorInfo.IME_MASK_ACTION,im.currentInputStarted,surrounding.text.toString(),surrounding.offset,password,query))return false
  youtubeEditorAttempted=true
  connection.performEditorAction(EditorInfo.IME_ACTION_SEARCH)
  // Dispatch is not completion. Dart must re-observe actual search results.
  result.success(mapOf("success" to true,"submitMethod" to "editor_search"))
  return true
 }
 @Suppress("DEPRECATION") private fun keyboardSearch(result:MethodChannel.Result){
  if(youtubeKeyboardAttempted){result.success(fail("Keyboard Search already attempted; finish manually",true));return}
  if(!active||locked()||observedPackage!="com.google.android.youtube"){result.success(fail("Keyboard fallback requires the unlocked YouTube task",true));return}
  val ws=windows
  val roots=ws.filter{it.type==AccessibilityWindowInfo.TYPE_INPUT_METHOD}.mapNotNull{it.root}
  ws.forEach{it.recycle()}
  val keys=mutableListOf<AccessibilityNodeInfo>();var visited=0
  fun walk(n:AccessibilityNodeInfo,depth:Int){
   try{
    if(visited++>=400||depth>20)return
    if(YouTubeSubmitPolicy.searchKey(n.text?.toString()?:"",n.contentDescription?.toString()?:"",n.isEnabled,n.isVisibleToUser,n.isPassword,n.isEditable))keys.add(AccessibilityNodeInfo.obtain(n))
    for(i in 0 until n.childCount)n.getChild(i)?.let{walk(it,depth+1)}
   }finally{n.recycle()}
  }
  roots.forEach{walk(it,0)}
  try{
   if(visited>=400||keys.size!=1){result.success(fail("Keyboard Search key missing or ambiguous; finish manually",true));return}
   // Invoke only the key itself. No clickable ancestor, gesture or key injection.
   val key=keys.single()
   if(!key.isClickable){result.success(fail("Keyboard Search key has no accessible click action",true));return}
   youtubeKeyboardAttempted=true
   resultAnswer(result,key.performAction(AccessibilityNodeInfo.ACTION_CLICK))
  }finally{keys.forEach{it.recycle()}}
 }
 private fun overlapsOverlay(bounds:Rect):Boolean {
  val v=overlay?:return false
  val xy=IntArray(2);v.getLocationOnScreen(xy)
  val overlayBounds=Rect(xy[0],xy[1],xy[0]+v.width,xy[1]+v.height)
  // Expand slightly so the stroke cannot hit an edge after rounding.
  overlayBounds.inset(-12,-12)
  return Rect.intersects(bounds,overlayBounds)
 }
 private fun capture(result:MethodChannel.Result){
  if(!active||locked()){result.success(fail("Screenshot requires an active unlocked task",true));return}
  if(android.os.Build.VERSION.SDK_INT<30){result.success(fail("Accessibility screenshots require Android 11+",true));return}
  takeScreenshot(android.view.Display.DEFAULT_DISPLAY,mainExecutor,object:TakeScreenshotCallback{
   override fun onSuccess(r:ScreenshotResult){
    val buffer=r.hardwareBuffer
    try{
     if(!active||locked()){result.success(fail("Task stopped before screenshot returned"));return}
     val bitmap=Bitmap.wrapHardwareBuffer(buffer,r.colorSpace)?:run{result.success(fail("Screenshot bitmap unavailable"));return}
     try{val copy=bitmap.copy(Bitmap.Config.ARGB_8888,false)?:run{result.success(fail("Screenshot copy unavailable"));return};try{val output=ByteArrayOutputStream();copy.compress(Bitmap.CompressFormat.PNG,100,output);result.success(mapOf("success" to true,"bytes" to output.toByteArray()))}finally{copy.recycle()}}finally{bitmap.recycle()}
    }finally{buffer.close()}
   }
   override fun onFailure(errorCode:Int){result.success(fail("Android refused screenshot ($errorCode). Protected screens are not bypassed",true))}
  })
 }
 private fun gesture(path:Path,duration:Long,result:MethodChannel.Result){
  val accepted=dispatchGesture(GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path,0,duration)).build(),object:GestureResultCallback(){override fun onCompleted(g:GestureDescription?){result.success(if(active)ok()else fail("Stopped while gesture was in progress"))};override fun onCancelled(g:GestureDescription?){result.success(fail("Gesture cancelled"))}},null)
  if(!accepted)result.success(fail("Gesture dispatch refused"))
 }
}
