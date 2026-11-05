package com.friday.assistant

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.*
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Pins Sona's bound headless runner only while this confirmed order is pending. */
object SonaBackgroundOrder {
    private val handler = Handler(Looper.getMainLooper())
    private var active: ServiceConnection? = null
    private var activeId: String? = null
    private fun trustedSona(context: Context): Boolean = try {
        val pm = context.packageManager
        val info = if (Build.VERSION.SDK_INT >= 28) pm.getPackageInfo("com.ambi.gold_paper_trading", android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES)
            else @Suppress("DEPRECATION") pm.getPackageInfo("com.ambi.gold_paper_trading", android.content.pm.PackageManager.GET_SIGNATURES)
        val sigs = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else @Suppress("DEPRECATION") info.signatures
        sigs?.any { sig -> java.security.MessageDigest.getInstance("SHA-256").digest(sig.toByteArray()).joinToString("") { "%02x".format(it) } == "54cfa6b82110b0d377f1f93fd767e08bb93a97362996637cecdb9208858f24e0" } == true
    } catch (_: Exception) { false }
    fun submit(context: Context, raw: String, reply: MethodChannel.Result) {
        if (!trustedSona(context)) { reply.success("unsupported"); return }
        if (active != null) { reply.success("error"); return }
        val app = context.applicationContext
        val uri = android.net.Uri.parse("content://com.ambi.gold_paper_trading.bridge")
        val id = try { JSONObject(raw).getString("id") } catch (_: Exception) { reply.success("error"); return }
        var answered = false
        var queued = false
        fun answer(status: String) { if (!answered) { answered = true; reply.success(status) } }
        lateinit var connection: ServiceConnection
        fun finish() {
            if (active === connection) {
                active = null; activeId = null
                if (queued) try { app.contentResolver.call(uri, "fridayTradeCancel", id, null) } catch (_: Exception) {}
                try { app.unbindService(connection) } catch (_: Exception) {}
            }
        }
        connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                if (active !== this) return
                try {
                    val accepted = app.contentResolver.call(uri, "fridayTradeSubmit", raw, null)
                    if (accepted?.getBoolean("accepted", false) != true) { answer("error"); finish(); return }
                    queued = true
                    Messenger(binder).send(Message.obtain(null, 1))
                    answer("ok")
                } catch (_: Exception) {
                    // Accepted queue may be claimed already: never resend or claim certainty.
                    if (queued) answer("ok") else answer("error")
                    finish()
                }
            }
            override fun onServiceDisconnected(name: ComponentName) { if (!queued) answer("error"); finish() }
            override fun onNullBinding(name: ComponentName) { answer("error"); finish() }
            override fun onBindingDied(name: ComponentName) { if (!queued) answer("error"); finish() }
        }
        try {
            val ping = app.contentResolver.call(uri, "fridayTradePing", null, null)
            if (ping?.getBoolean("background", false) != true) { answer("unsupported"); return }
            active = connection; activeId = id
            if (!app.bindService(Intent().setComponent(ComponentName("com.ambi.gold_paper_trading", "com.ambi.gold_paper_trading.FridayOrderService")), connection, Context.BIND_AUTO_CREATE)) {
                answer("error"); finish(); return
            }
            handler.postDelayed({ if (active === connection) { answer(if (queued) "ok" else "error"); finish() } }, 85_000)
            handler.postDelayed({ if (active === connection && !queued) { answer("error"); finish() } }, 8_000)
        } catch (_: Exception) { answer("error"); if (active === connection) finish() }
    }
    fun result(context: Context, id: String, raw: String?) {
        if (id != activeId || raw == null) return
        val status = try { JSONObject(raw).optString("status") } catch (_: Exception) { return }
        if (status in listOf("done", "rejected", "unknown")) {
            val c = active ?: return
            active = null; activeId = null
            try { context.applicationContext.unbindService(c) } catch (_: Exception) {}
        }
    }
}
