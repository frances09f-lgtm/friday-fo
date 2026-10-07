package com.friday.assistant

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.provider.Settings
import android.provider.ContactsContract
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Friday's bridge to the phone: installed-app lookup, app launching, SMS
 * reading, torch, volume, brightness, calls and texts. Shared by the main
 * activity and the assistant overlay service. When there is no Activity
 * (overlay), permission requests are skipped and the action reports "asked"
 * so the full app can collect the grant later.
 */
object DeviceBridge {
    private const val CHANNEL = "friday/device"
    private const val PERMISSION_REQUEST = 4242

    fun register(messenger: BinaryMessenger, context: Context, activity: Activity?) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> result.success(installedApps(context))
                "openApp" -> result.success(openApp(context, call.argument<String>("package")))
                "readSms" -> result.success(
                    readSms(
                        context,
                        call.argument<String>("query") ?: "",
                        (call.argument<Int>("limit") ?: 10).coerceAtMost(50),
                    )
                )
                "hasSmsPermission" -> result.success(hasPermission(context, Manifest.permission.READ_SMS))
                "setTorch" -> result.success(setTorch(context, call.argument<Boolean>("on") == true))
                "volumeUp" -> result.success(adjustVolume(context, AudioManager.ADJUST_RAISE))
                "volumeDown" -> result.success(adjustVolume(context, AudioManager.ADJUST_LOWER))
                "openPanel" -> result.success(openPanel(context, call.argument<String>("which") ?: "wifi"))
                "requestSmsPermission" -> {
                    requestPermissions(activity, arrayOf(Manifest.permission.READ_SMS))
                    result.success(true)
                }
                "callContact" -> result.success(callContact(context, activity, call.argument<String>("who") ?: ""))
                "sendWhatsApp" -> result.success(sendWhatsApp(context, activity,
                    call.argument<String>("who") ?: "", call.argument<String>("text") ?: ""))
                "sendText" -> result.success(sendText(context, activity,
                    call.argument<String>("who") ?: "", call.argument<String>("text") ?: ""))
                "setVolume" -> result.success(setVolumePercent(context, call.argument<Int>("percent") ?: -1))
                "setBrightness" -> result.success(setBrightnessPercent(context, activity, call.argument<Int>("percent") ?: -1))
                else -> result.notImplemented()
            }
        }
    }

    private fun hasPermission(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermissions(activity: Activity?, permissions: Array<String>) {
        if (activity != null) {
            ActivityCompat.requestPermissions(activity, permissions, PERMISSION_REQUEST)
        }
    }

    private fun installedApps(context: Context): List<Map<String, Any>> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = mutableSetOf<String>()
        val out = mutableListOf<Map<String, Any>>()
        for (info in pm.queryIntentActivities(intent, 0)) {
            val pkg = info.activityInfo.packageName
            if (pkg !in seen) {
                seen.add(pkg)
                out.add(mapOf("label" to info.loadLabel(pm).toString(), "package" to pkg))
            }
        }
        return out
    }

    private fun openApp(context: Context, pkg: String?): Boolean {
        if (pkg.isNullOrEmpty()) return false
        return try {
            val intent = context.packageManager.getLaunchIntentForPackage(pkg) ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun setTorch(context: Context, on: Boolean): Boolean = try {
        val cm = context.getSystemService(CameraManager::class.java)
        cm.setTorchMode(cm.cameraIdList[0], on)
        true
    } catch (e: Exception) {
        false
    }

    private fun adjustVolume(context: Context, direction: Int): Boolean = try {
        val am = context.getSystemService(AudioManager::class.java)
        am.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, AudioManager.FLAG_SHOW_UI)
        true
    } catch (e: Exception) {
        false
    }

    private fun openPanel(context: Context, which: String): Boolean = try {
        val intent = when (which) {
            "bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            else -> if (android.os.Build.VERSION.SDK_INT >= 29) {
                Intent(Settings.Panel.ACTION_WIFI)
            } else {
                Intent(Settings.ACTION_WIFI_SETTINGS)
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (e: Exception) {
        false
    }

    private fun looksLikeNumber(who: String): Boolean =
        who.trim().matches(Regex("[+0-9][0-9 ()-]{4,}"))

    private fun findContactNumber(context: Context, who: String): String? =
        findContacts(context, who).firstOrNull()?.get("number")

    /**
     * Ranked, deduped contact matches. Dedupes by CONTACT_ID so the same
     * person synced from several accounts appears once (primary number
     * preferred); ranking is exact > starts-with > contains on the trimmed,
     * case-insensitive display name, so "Aai" never silently picks "Aai
     * Rane" when an exact "Aai" exists.
     */
    private fun findContacts(context: Context, who: String): List<Map<String, String>> {
        val cleaned = who.trim()
        if (cleaned.isEmpty()) return emptyList()
        if (looksLikeNumber(cleaned)) return listOf(mapOf("name" to cleaned, "number" to cleaned))
        if (!hasPermission(context, Manifest.permission.READ_CONTACTS)) return emptyList()
        val wanted = cleaned.lowercase()
        val byContact = linkedMapOf<Long, Triple<String, String, Boolean>>()
        context.contentResolver.query(
            ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
            arrayOf(
                ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                ContactsContract.CommonDataKinds.Phone.NUMBER,
                ContactsContract.CommonDataKinds.Phone.IS_SUPER_PRIMARY,
            ),
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " LIKE ?",
            arrayOf("%$cleaned%"),
            null
        )?.use { c ->
            while (c.moveToNext()) {
                val id = c.getLong(0)
                val name = c.getString(1) ?: ""
                val number = c.getString(2) ?: ""
                val primary = c.getInt(3) == 1
                val cur = byContact[id]
                if (cur == null || (primary && !cur.third)) {
                    byContact[id] = Triple(name, number, primary)
                }
            }
        }
        fun rank(name: String): Int {
            val n = name.trim().lowercase()
            return when {
                n == wanted -> 0
                n.startsWith(wanted) -> 1
                else -> 2
            }
        }
        return byContact.values
            .filter { it.first.isNotBlank() && it.second.isNotBlank() }
            .sortedWith(compareBy({ rank(it.first) }, { it.first.length }))
            .take(5)
            .map { mapOf("name" to it.first, "number" to it.second) }
    }

    /** One unambiguous match, or a "pick:" list when several contacts tie. */
    private fun resolveContact(context: Context, who: String): String {
        val matches = findContacts(context, who)
        if (matches.isEmpty()) return ""
        val wanted = who.trim().lowercase()
        val exact = matches.filter { it["name"]!!.trim().lowercase() == wanted }
        if (exact.size == 1) return exact.single()["number"]!!
        if (matches.size == 1) return matches.single()["number"]!!
        return "pick:" + matches.joinToString("|") { it["name"]!! }
    }

    private fun sendWhatsApp(context: Context, activity: Activity?, who: String, text: String): String {
        if (who.isBlank() || text.isBlank()) return "error"
        if (needsPhonePermissions(context, who)) {
            requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.READ_CONTACTS,
                    Manifest.permission.CALL_PHONE,
                    Manifest.permission.SEND_SMS
                )
            )
            return "asked"
        }
        val resolved = resolveContact(context, who)
        if (resolved.isEmpty()) return "no_match"
        if (resolved.startsWith("pick:")) return resolved
        var digits = resolved.filter { it.isDigit() }
        // Local 10-digit numbers get the user's home country code (+91).
        if (digits.length == 10) digits = "91$digits"
        return try {
            val uri = android.net.Uri.parse(
                "whatsapp://send?phone=$digits&text=" + android.net.Uri.encode(text)
            )
            context.startActivity(
                Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            "opened"
        } catch (e: android.content.ActivityNotFoundException) {
            "no_whatsapp"
        } catch (e: Exception) {
            "error"
        }
    }

    private fun needsPhonePermissions(context: Context, who: String): Boolean =
        !looksLikeNumber(who) && !hasPermission(context, Manifest.permission.READ_CONTACTS)

    private fun callContact(context: Context, activity: Activity?, who: String): String {
        if (who.isBlank()) return "error"
        if (needsPhonePermissions(context, who) ||
            (!looksLikeNumber(who) && !hasPermission(context, Manifest.permission.CALL_PHONE))
        ) {
            requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.READ_CONTACTS,
                    Manifest.permission.CALL_PHONE,
                    Manifest.permission.SEND_SMS
                )
            )
            return "asked"
        }
        val number = resolveContact(context, who)
        if (number.isEmpty()) return "no_match"
        if (number.startsWith("pick:")) return number
        val uri = android.net.Uri.parse("tel:$number")
        return try {
            if (hasPermission(context, Manifest.permission.CALL_PHONE)) {
                context.startActivity(Intent(Intent.ACTION_CALL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "calling"
            } else {
                context.startActivity(Intent(Intent.ACTION_DIAL, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                "dialer"
            }
        } catch (e: Exception) {
            "error"
        }
    }

    private fun sendText(context: Context, activity: Activity?, who: String, text: String): String {
        if (who.isBlank() || text.isBlank()) return "error"
        if (needsPhonePermissions(context, who) ||
            !hasPermission(context, Manifest.permission.SEND_SMS)
        ) {
            requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.READ_CONTACTS,
                    Manifest.permission.CALL_PHONE,
                    Manifest.permission.SEND_SMS
                )
            )
            return "asked"
        }
        val number = resolveContact(context, who)
        if (number.isEmpty()) return "no_match"
        if (number.startsWith("pick:")) return number
        return try {
            android.telephony.SmsManager.getDefault().sendTextMessage(number, null, text, null, null)
            "sent"
        } catch (e: Exception) {
            "error"
        }
    }

    private fun setVolumePercent(context: Context, percent: Int): Boolean {
        if (percent < 0 || percent > 100) return false
        return try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            audio.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(max * percent / 100.0f), 0)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun setBrightnessPercent(context: Context, activity: Activity?, percent: Int): String {
        if (percent < 0 || percent > 100) return "error"
        if (!Settings.System.canWrite(context)) {
            if (activity != null) {
                try {
                    context.startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_WRITE_SETTINGS,
                            android.net.Uri.parse("package:" + context.packageName)
                        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    )
                } catch (e: Exception) {
                    return "error"
                }
            }
            return "asked"
        }
        return try {
            Settings.System.putInt(
                context.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS_MODE,
                Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL
            )
            Settings.System.putInt(
                context.contentResolver,
                Settings.System.SCREEN_BRIGHTNESS,
                Math.round(255 * percent / 100.0f)
            )
            "ok"
        } catch (e: Exception) {
            "error"
        }
    }

    private fun readSms(context: Context, query: String, limit: Int): List<Map<String, Any>> {
        if (!hasPermission(context, Manifest.permission.READ_SMS)) return emptyList()
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
            context.contentResolver.query(
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
