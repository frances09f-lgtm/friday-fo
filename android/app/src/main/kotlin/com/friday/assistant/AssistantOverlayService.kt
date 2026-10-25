package com.friday.assistant

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.view.Gravity
import android.view.WindowManager
import android.view.MotionEvent
import android.widget.TextView
import android.graphics.drawable.GradientDrawable
import android.provider.Settings
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.plugin.common.MethodChannel

class AssistantOverlayService : Service() {
    companion object {
        private const val CHANNEL = "friday/assistant"
        private const val NOTIF_CHANNEL = "friday_assistant"
        private const val NOTIF_ID = 71
        var active=false
        var instance:AssistantOverlayService?=null
        fun volumeWindow(show:Boolean){
            val service=instance?:return
            if(!service.panelAttached)return
            service.view?.let { v ->
                val params=v.layoutParams as? WindowManager.LayoutParams?:return@let
                if(show)params.flags=params.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                else params.flags=params.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
                v.visibility=if(show)android.view.View.INVISIBLE else android.view.View.VISIBLE
                try{service.windowManager?.updateViewLayout(v,params)}catch(_:Exception){}
            }
        }
        const val MODE_BUBBLE="bubble"
        private const val ACTION_STOP="com.friday.assistant.STOP_BUBBLE"
    }
    private var engine: FlutterEngine? = null
    private var view: FlutterView? = null
    private var panelAttached=false
    private var windowManager: WindowManager? = null
    private var bubble:TextView?=null
    private var persistent=false
    private var voice=false
    private val handler=Handler(Looper.getMainLooper())
    private var hold:Runnable?=null
    private var downX=0f;private var downY=0f
    private var longTriggered=false
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        instance=this
        AssistantInvocation.record(this,"Overlay service created")
        startForeground(NOTIF_ID, buildNotification())
        windowManager=getSystemService(WINDOW_SERVICE) as WindowManager
    }
    private fun hidePanelImmediately(){
        view?.let { v ->
            v.visibility=android.view.View.GONE
            if(panelAttached){
                try{windowManager?.removeViewImmediate(v)}catch(_:Exception){}
                panelAttached=false
            }
        }
    }
    private fun outsideDismiss(){
        hidePanelImmediately()
        engine?.let { MethodChannel(it.dartExecutor.binaryMessenger,CHANNEL).invokeMethod("outsideTap",null) }
    }
    private fun clearPanel(){
        hidePanelImmediately()
        view?.let{it.detachFromFlutterEngine()}
        engine?.destroy();engine=null;view=null
    }
    private fun clearBubble(){hold?.let{handler.removeCallbacks(it)};hold=null;bubble?.let{try{windowManager?.removeView(it)}catch(_:Exception){}};bubble=null}
    private fun showBubble(){
        clearPanel();clearBubble()
        if(!Settings.canDrawOverlays(this)){stopSelf();return}
        val density=resources.displayMetrics.density
        val size=(FloatingAssistantSizing.BUBBLE_HEIGHT_DP*density).toInt();val barW=(FloatingAssistantSizing.BUBBLE_WIDTH_DP*density).toInt()
        val night=(resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK)==android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg=if(night)0xff00503f.toInt() else 0xffb9f0df.toInt();val fg=if(night)0xffb9f0df.toInt() else 0xff00201a.toInt();val edge=if(night)0xff4fd8b8.toInt() else 0xff00695a.toInt()
        val v=TextView(this).apply{text="F";textSize=FloatingAssistantSizing.BUBBLE_TEXT_SP;setTypeface(null,android.graphics.Typeface.BOLD);gravity=Gravity.CENTER;setTextColor(fg);contentDescription="Friday bubble. Tap for panel, hold for voice, swipe sideways to open Friday.";background=GradientDrawable().apply{shape=GradientDrawable.RECTANGLE;setCornerRadius(24*density*FloatingAssistantSizing.SCALE);setColor(bg);setStroke((1.5f*density*FloatingAssistantSizing.SCALE).toInt().coerceAtLeast(1),edge)}}
        val params=WindowManager.LayoutParams(barW,size,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,PixelFormat.TRANSLUCENT).apply{gravity=Gravity.TOP or Gravity.START;x=resources.displayMetrics.widthPixels-barW;y=resources.displayMetrics.heightPixels/3}
        v.setOnTouchListener{_,event->
            when(event.actionMasked){
                MotionEvent.ACTION_DOWN->{downX=event.rawX;downY=event.rawY;longTriggered=false;hold=Runnable{longTriggered=true;showPanel(true)};handler.postDelayed(hold!!,600)}
                MotionEvent.ACTION_MOVE->{if(kotlin.math.abs(event.rawX-downX)>20*density||kotlin.math.abs(event.rawY-downY)>20*density)hold?.let{handler.removeCallbacks(it)}}
                MotionEvent.ACTION_UP->{hold?.let{handler.removeCallbacks(it)};val dx=event.rawX-downX;val dy=event.rawY-downY
                    if(!longTriggered){if(kotlin.math.abs(dx)>50*density){openFriday();showBubble()}else if(kotlin.math.abs(dy)>30*density){params.y=(params.y+dy.toInt()).coerceIn(0,resources.displayMetrics.heightPixels-size);windowManager?.updateViewLayout(v,params)}else showPanel(false)}}
                MotionEvent.ACTION_CANCEL->{hold?.let{handler.removeCallbacks(it)}}
            };true
        }
        bubble=v
        try{windowManager?.addView(v,params);AssistantInvocation.record(this,"Overlay visible")}catch(e:Exception){AssistantInvocation.record(this,"Overlay failed: ${e.javaClass.simpleName}: ${e.message}");stopSelf()}
    }
    private fun openFriday(){startActivity(Intent(this,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))}
    private fun showPanel(listen:Boolean){
        clearBubble();clearPanel();voice=listen
        if(!Settings.canDrawOverlays(this)){stopSelf();return}
        val loader=FlutterInjector.instance().flutterLoader();loader.startInitialization(applicationContext);loader.ensureInitializationComplete(applicationContext,null)
        val e=FlutterEngine(this)
        MethodChannel(e.dartExecutor.binaryMessenger,CHANNEL).setMethodCallHandler{call,result->
            if(engine !== e){result.error("stale_panel","Panel invocation has ended",null);return@setMethodCallHandler}
            when(call.method){
                "hidePanelWhileBusy"->{hidePanelImmediately();result.success(null)}
                "panelExpanded"->{
                    val expanded=call.argument<Boolean>("expanded")==true
                    view?.let{v-> val lp=v.layoutParams as? WindowManager.LayoutParams
                        if(lp!=null&&panelAttached){lp.height=FloatingAssistantSizing.panelHeight(expanded,resources.displayMetrics.density);windowManager?.updateViewLayout(v,lp)}
                    };result.success(null)
                }
                "launchMode"->result.success(mapOf("voice" to voice))
                "dismiss"->{hidePanelImmediately();result.success(null);handler.post{if(engine === e){if(persistent)showBubble()else stopSelf()}}}
                "hideBubble"->{result.success(null);stopSelf()}
                "openFriday"->{openFriday();hidePanelImmediately();result.success(null);handler.post{if(engine === e){if(persistent)showBubble()else stopSelf()}}}
                else->result.notImplemented()
            }
        }
        DeviceBridge.register(e.dartExecutor.binaryMessenger,this,null)
        ShrutiBridge.register(e.dartExecutor.binaryMessenger)
        engine=e
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),"assistantOverlayMain"))
        val texture=FlutterTextureView(this).apply{isOpaque=false};val v=object:FlutterView(this,texture){
            override fun dispatchTouchEvent(event:MotionEvent):Boolean{
                if(event.actionMasked==MotionEvent.ACTION_OUTSIDE){outsideDismiss();return true}
                return super.dispatchTouchEvent(event)
            }
            override fun dispatchKeyEvent(event:android.view.KeyEvent):Boolean{
                if(event.keyCode==android.view.KeyEvent.KEYCODE_BACK&&event.action==android.view.KeyEvent.ACTION_UP){outsideDismiss();return true}
                return super.dispatchKeyEvent(event)
            }
        };v.setBackgroundColor(android.graphics.Color.TRANSPARENT);v.attachToFlutterEngine(e);e.lifecycleChannel.appIsResumed();view=v
        val params=WindowManager.LayoutParams(FloatingAssistantSizing.panelWidth(resources.displayMetrics.widthPixels),FloatingAssistantSizing.panelHeight(false,resources.displayMetrics.density),WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,PixelFormat.TRANSLUCENT).apply{gravity=Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL;softInputMode=WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE}
        try{windowManager?.addView(v,params);panelAttached=true;AssistantInvocation.record(this,"Overlay visible")}catch(e:Exception){AssistantInvocation.record(this,"Overlay failed: ${e.javaClass.simpleName}: ${e.message}");stopSelf()}
    }
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int{
        if(intent?.action==ACTION_STOP){stopSelf();return START_NOT_STICKY}
        if(!Settings.canDrawOverlays(this)){stopSelf();return START_NOT_STICKY}
        active=true
        if(intent?.getBooleanExtra(MODE_BUBBLE,false)==true){persistent=true;showBubble()}else showPanel(true)
        return START_NOT_STICKY
    }
    private fun buildNotification(): Notification {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(NOTIF_CHANNEL,"Friday assistant",NotificationManager.IMPORTANCE_MIN))
        }
        val open = PendingIntent.getActivity(this,0,Intent(this, MainActivity::class.java),PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) { Notification.Builder(this, NOTIF_CHANNEL) }
            else { @Suppress("DEPRECATION") Notification.Builder(this) }
        return builder.setContentTitle("Friday assistant available")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now).setContentIntent(open)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel,"Hide",PendingIntent.getService(this,1,Intent(this,AssistantOverlayService::class.java).setAction(ACTION_STOP),PendingIntent.FLAG_IMMUTABLE))
            .setOngoing(true).build()
    }
    override fun onDestroy(){instance=null;active=false;clearBubble();clearPanel();super.onDestroy()}
}
