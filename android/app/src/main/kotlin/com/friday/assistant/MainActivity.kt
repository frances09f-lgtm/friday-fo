package com.friday.assistant

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Friday's bridge to the phone: installed-app lookup, app launching, and SMS
 * reading. Kept deliberately small; all "thinking" happens on the Dart side.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "friday/device"
        private const val SMS_PERMISSION_REQUEST = 4242
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstalledApps" -> result.success(installedApps())
                    "openApp" -> result.success(openApp(call.argument<String>("package")))
                    "readSms" -> result.success(
                        readSms(
                            call.argument<String>("query") ?: "",
                            (call.argument<Int>("limit") ?: 10).coerceAtMost(50),
                        )
                    )
                    "hasSmsPermission" -> result.success(hasSmsPermission())
                    "requestSmsPermission" -> {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.READ_SMS),
                            SMS_PERMISSION_REQUEST,
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installedApps(): List<Map<String, Any>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = mutableSetOf<String>()
        val out = mutableListOf<Map<String, Any>>()
        for (info in pm.queryIntentActivities(intent, 0)) {
            val pkg = info.activityInfo.packageName
            if (pkg !in seen) {
                seen.add(pkg)
                out.add(
                    mapOf(
                        "label" to info.loadLabel(pm).toString(),
                        "package" to pkg,
                    )
                )
            }
        }
        return out
    }

    private fun openApp(pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        return try {
            val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun hasSmsPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED

    private fun readSms(query: String, limit: Int): List<Map<String, Any>> {
        if (!hasSmsPermission()) return emptyList()
        val out = mutableListOf<Map<String, Any>>()
        try {
            val projection = arrayOf(
                Telephony.Sms.Inbox.ADDRESS,
                Telephony.Sms.Inbox.BODY,
                Telephony.Sms.Inbox.DATE,
            )
            val selection: String?
            val args: Array<String>?
            if (query.isBlank()) {
                selection = null
                args = null
            } else {
                selection = "${Telephony.Sms.Inbox.BODY} LIKE ? OR ${Telephony.Sms.Inbox.ADDRESS} LIKE ?"
                args = arrayOf("%$query%", "%$query%")
            }
            contentResolver.query(
                Telephony.Sms.Inbox.CONTENT_URI,
                projection,
                selection,
                args,
                "${Telephony.Sms.Inbox.DATE} DESC",
            )?.use { cursor ->
                while (cursor.moveToNext() && out.size < limit) {
                    out.add(
                        mapOf(
                            "sender" to (cursor.getString(0) ?: ""),
                            "body" to (cursor.getString(1) ?: ""),
                            "date" to (cursor.getLong(2)),
                        )
                    )
                }
            }
        } catch (e: Exception) {
            // No permission, vendor skin blocking the inbox: report what we have.
        }
        return out
    }
}
