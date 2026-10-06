package com.friday.assistant

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.provider.Settings
import android.provider.ContactsContract
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
                    "setTorch" -> result.success(setTorch(call.argument<Boolean>("on") == true))
                    "volumeUp" -> result.success(adjustVolume(AudioManager.ADJUST_RAISE))
                    "volumeDown" -> result.success(adjustVolume(AudioManager.ADJUST_LOWER))
                    "openPanel" -> result.success(openPanel(call.argument<String>("which") ?: "wifi"))
                    "requestSmsPermission" -> {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.READ_SMS),
                            SMS_PERMISSION_REQUEST,
                        )
                        result.success(true)
                    }
                    "callContact" -> result.success(callContact(call.argument<String>("who") ?: ""))
                    "sendText" -> result.success(sendText(
                        call.argument<String>("who") ?: "",
                        call.argument<String>("text") ?: ""
                    ))
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

    private fun setTorch(on: Boolean): Boolean = try {
        val cm = getSystemService(CameraManager::class.java)
        cm.setTorchMode(cm.cameraIdList[0], on)
        true
    } catch (e: Exception) {
        false
    }

    private fun adjustVolume(direction: Int): Boolean = try {
        val am = getSystemService(AudioManager::class.java)
        am.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
        true
    } catch (e: Exception) {
        false
    }

    private fun openPanel(which: String): Boolean = try {
        val intent = when (which) {
            "bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            else -> if (android.os.Build.VERSION.SDK_INT >= 29) {
                Intent(Settings.Panel.ACTION_WIFI)
            } else {
                Intent(Settings.ACTION_WIFI_SETTINGS)
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun hasContactsPermission(): Boolean =
        ContextCompat.checkSelfPermission(this, Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPhonePermissions() {
        ActivityCompat.requestPermissions(
            this,
            arrayOf(
                Manifest.permission.READ_CONTACTS,
                Manifest.permission.CALL_PHONE,
                Manifest.permission.SEND_SMS
            ),
            42
        )
    }

    private fun looksLikeNumber(who: String): Boolean =
        who.trim().matches(Regex("[+0-9][0-9 ()-]{4,}"))

    private fun findContactNumber(who: String): String? {
        val cleaned = who.trim()
        if (cleaned.isEmpty()) return null
        if (looksLikeNumber(cleaned)) return cleaned
        if (!hasContactsPermission()) return null
        return contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(ContactsContract.CommonDataKinds.Phone.NUMBER),
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " LIKE ?",
            arrayOf("%" + cleaned + "%"),
            null
        )?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
    }

    private fun callContact(who: String): String {
        if (who.isBlank()) return "error"
        if (!looksLikeNumber(who) && !hasContactsPermission()) {
            requestPhonePermissions()
            return "asked"
        }
        val number = findContactNumber(who) ?: return "no_match"
        val uri = android.net.Uri.parse("tel:" + number)
        return try {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.CALL_PHONE) ==
                PackageManager.PERMISSION_GRANTED
            ) {
                startActivity(Intent(Intent.ACTION_CALL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "calling"
            } else {
                startActivity(Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "dialer"
            }
        } catch (e: Exception) {
            "error"
        }
    }

    private fun sendText(who: String, text: String): String {
        if (who.isBlank() || text.isBlank()) return "error"
        if (!looksLikeNumber(who) && !hasContactsPermission()) {
            requestPhonePermissions()
            return "asked"
        }
        val number = findContactNumber(who) ?: return "no_match"
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPhonePermissions()
            return "asked"
        }
        return try {
            android.telephony.SmsManager.getDefault().sendTextMessage(number, null, text, null, null)
            "sent"
        } catch (e: Exception) {
            "error"
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
