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

/**
 * Draws Friday's assistant panel over whatever app is on screen. Runs its own
 * Flutter engine with the assistantOverlayMain entrypoint; the panel talks
 * back over the friday/assistant channel (dismiss, openFriday).
 */
class AssistantOverlayService : Service() {

    companion object {
        private const val CHANNEL = "friday/assistant"
        private const val NOTIF_CHANNEL = "friday_assistant"
        private const val NOTIF_ID = 71
        var active=false
        const val MODE_BUBBLE="bubble"
        private const val ACTION_STOP="com.friday.assistant.STOP_BUBBLE"

    }

    private var engine: FlutterEngine? = null
    private var view: FlutterView? = null
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
        AssistantInvocation.record(this,"Overlay service created")
        startForeground(NOTIF_ID, buildNotification())

        windowManager=getSystemService(WINDOW_SERVICE) as WindowManager
    }
    private fun clearPanel(){
        view?.let{try{windowManager?.removeView(it)}catch(_:Exception){};it.detachFromFlutterEngine()}
        engine?.destroy();engine=null;view=null
    }
    private fun clearBubble(){hold?.let{handler.removeCallbacks(it)};hold=null;bubble?.let{try{windowManager?.removeView(it)}catch(_:Exception){}};bubble=null}
    private fun showBubble(){
        clearPanel();clearBubble()
        if(!Settings.canDrawOverlays(this)){stopSelf();return}
        val density=resources.displayMetrics.density
        val size=(56*density).toInt()
        val v=TextView(this).apply{text="F";textSize=24f;gravity=Gravity.CENTER;setTextColor(-1);contentDescription="Friday bubble. Tap for panel, hold for voice, swipe sideways to open Friday.";background=GradientDrawable().apply{shape=GradientDrawable.OVAL;colors=intArrayOf(0xffa17cff.toInt(),0xff6750a4.toInt());setStroke((2*density).toInt(),0xffc5b3ff.toInt())}}
        val params=WindowManager.LayoutParams(size,size,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,PixelFormat.TRANSLUCENT).apply{gravity=Gravity.TOP or Gravity.START;x=resources.displayMetrics.widthPixels-size;y=resources.displayMetrics.heightPixels/3}
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
            when(call.method){
                "panelExpanded"->{
                    val expanded=call.argument<Boolean>("expanded")==true
                    view?.let{v-> val lp=v.layoutParams as? WindowManager.LayoutParams
                        if(lp!=null){lp.height=((if(expanded)360 else 132)*resources.displayMetrics.density).toInt();windowManager?.updateViewLayout(v,lp)}
                    };result.success(null)
                }
                "launchMode"->result.success(mapOf("voice" to voice))
                "dismiss"->{result.success(null);handler.post{if(persistent)showBubble()else stopSelf()}}
                "hideBubble"->{result.success(null);stopSelf()}
                "openFriday"->{openFriday();result.success(null);handler.post{if(persistent)showBubble()else stopSelf()}}
                else->result.notImplemented()
            }
        }
        DeviceBridge.register(e.dartExecutor.binaryMessenger,this,null)
        engine=e
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),"assistantOverlayMain"))
        val texture=FlutterTextureView(this).apply{isOpaque=false};val v=FlutterView(this,texture);v.setBackgroundColor(android.graphics.Color.TRANSPARENT);v.attachToFlutterEngine(e);e.lifecycleChannel.appIsResumed();view=v
        val params=WindowManager.LayoutParams(-1,(132*resources.displayMetrics.density).toInt(),WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,PixelFormat.TRANSLUCENT).apply{gravity=Gravity.BOTTOM;softInputMode=WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE}
        try{windowManager?.addView(v,params);AssistantInvocation.record(this,"Overlay visible")}catch(e:Exception){AssistantInvocation.record(this,"Overlay failed: ${e.javaClass.simpleName}: ${e.message}");stopSelf()}
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
            nm.createNotificationChannel(
                NotificationChannel(
                    NOTIF_CHANNEL,
                    "Friday assistant",
                    NotificationManager.IMPORTANCE_MIN,
                )
            )
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, NOTIF_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Friday assistant available")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(open)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel,"Hide",PendingIntent.getService(this,1,Intent(this,AssistantOverlayService::class.java).setAction(ACTION_STOP),PendingIntent.FLAG_IMMUTABLE))
            .setOngoing(true)
            .build()
    }

    override fun onDestroy(){active=false;clearBubble();clearPanel();super.onDestroy()}
}
