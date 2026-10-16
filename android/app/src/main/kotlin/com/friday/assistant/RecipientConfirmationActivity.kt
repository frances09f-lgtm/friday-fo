package com.friday.assistant

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.ContactsContract
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.util.UUID

/** Foreground, non-exported confirmation shared by the app and assistant overlay.
 * No caller-provided number/token can manufacture consent. Requests live only in memory.
 * WhatsApp's supported route opens a draft; it NEVER presses Send.
 */
class RecipientConfirmationActivity : Activity() {
    companion object {
        private data class Pending(val id: String, val consent: RecipientConsent, val result: MethodChannel.Result)
        private var pending: Pending? = null
        private var activeActivity: WeakReference<RecipientConfirmationActivity>? = null
        private val handler = Handler(Looper.getMainLooper())
        private var timeout: Runnable? = null
        private fun locked(context: Context) = context.getSystemService(KeyguardManager::class.java).isKeyguardLocked
        private fun permitted(context: Context, permission: String) = ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

        fun request(context: Context, activity: Activity?, request: RecipientRequest, result: MethodChannel.Result) {
            // A later command invalidates any old consent before doing anything else.
            pending?.let { complete(it.id, "cancelled") }
            if (locked(context)) { result.success("locked"); return }
            if (FridayAccessibilityService.current?.isRunning == true) { result.success("agent_running"); return }
            if (request.query.isBlank() || (request.operation == RecipientOperation.WHATSAPP_DRAFT && request.body.isBlank())) {
                result.success("error"); return
            }
            val numeric = request.query.trim().matches(Regex("[+0-9][0-9 ()-]{4,}"))
            if (!numeric && (!permitted(context, Manifest.permission.READ_CONTACTS) ||
                (request.operation == RecipientOperation.CALL && !permitted(context, Manifest.permission.CALL_PHONE)))) {
                if (activity != null) ActivityCompat.requestPermissions(activity,
                    if (request.operation == RecipientOperation.CALL) arrayOf(Manifest.permission.READ_CONTACTS, Manifest.permission.CALL_PHONE)
                    else arrayOf(Manifest.permission.READ_CONTACTS), 4242)
                result.success("asked"); return
            }
            if (numeric) { result.success(dispatch(context, request, request.query.trim())); return }
            val resolution = try { resolve(context, request.query) } catch (_: Exception) { result.success("error"); return }
            if (resolution.candidates.isEmpty()) { result.success("no_match"); return }
            if (resolution.exactUnique) {
                // Preserve unique exact-match behavior; no approximate candidate reaches this path.
                result.success(dispatch(context, request, resolution.candidates.single().number)); return
            }
            val id = UUID.randomUUID().toString()
            pending = Pending(id, RecipientConsent(request, resolution, SystemClock.elapsedRealtime() + 120000), result)
            candidates = resolution.candidates
            AssistantOverlayService.volumeWindow(true)
            try {
                context.startActivity(Intent(context, RecipientConfirmationActivity::class.java)
                    .putExtra("request", id).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                val expiry = Runnable { complete(id, "confirmation_expired") }
                timeout = expiry; handler.postDelayed(expiry, 120000)
            } catch (_: Exception) { complete(id, "confirmation_unavailable") }
        }
        // Used only for rendering this single in-memory request, never accepted from an Intent.
        private var candidates: List<ContactEndpoint> = emptyList()
        private fun resolve(context: Context, query: String): RecipientResolution {
            if (!permitted(context, Manifest.permission.READ_CONTACTS)) throw SecurityException()
            val rows = mutableListOf<ContactEndpoint>()
            context.contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, arrayOf(ContactsContract.CommonDataKinds.Phone.CONTACT_ID, ContactsContract.CommonDataKinds.Phone.LOOKUP_KEY,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) rows.add(ContactEndpoint(cursor.getLong(0).toString(), cursor.getString(1) ?: "",
                    cursor.getString(2) ?: "", cursor.getString(3) ?: ""))
            } ?: throw IllegalStateException("Contacts unavailable")
            return ContactNameMatcher.resolve(query, rows)
        }
        private fun dispatch(context: Context, request: RecipientRequest, number: String): String {
            if (locked(context)) return "locked"
            if (FridayAccessibilityService.current?.isRunning == true) return "agent_running"
            return try {
                if (request.operation == RecipientOperation.CALL) {
                    val direct = permitted(context, Manifest.permission.CALL_PHONE)
                    context.startActivity(Intent(if (direct) Intent.ACTION_CALL else Intent.ACTION_DIAL,
                        Uri.fromParts("tel", number, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    if (direct) "calling" else "dialer"
                } else {
                    val digits = ContactNameMatcher.whatsAppDigits(number)
                    val uri = Uri.parse("whatsapp://send?phone=$digits&text=" + Uri.encode(request.body))
                    context.startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage("com.whatsapp")
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    "opened"
                }
            } catch (_: android.content.ActivityNotFoundException) {
                if (request.operation == RecipientOperation.WHATSAPP_DRAFT) "no_whatsapp" else "error"
            } catch (_: Exception) { "error" }
        }
        private fun complete(id: String, outcome: String) {
            val current = pending ?: return
            if (current.id != id) return
            pending = null; current.consent.cancel(); candidates = emptyList()
            timeout?.let { handler.removeCallbacks(it) }; timeout = null
            val activity = activeActivity?.get(); activeActivity = null
            if (activity?.requestId == id) activity.finish()
            AssistantOverlayService.volumeWindow(false)
            current.result.success(outcome)
        }
    }
    private var dialog: AlertDialog? = null
    private val requestId: String get() = intent.getStringExtra("request") ?: ""
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val current = pending
        if (current == null || current.id != requestId || locked(this)) { finish(); return }
        activeActivity = WeakReference(this)
        title = "Friday recipient confirmation"
        val rows = candidates.toList()
        if (rows.size == 1) {
            if (current.consent.choose(rows.single(), SystemClock.elapsedRealtime())) showConfirmation(rows.single())
            else { complete(requestId, "confirmation_expired"); finish() }
        } else {
            dialog = AlertDialog.Builder(this).setTitle("Choose the intended contact")
                .setMessage(null)
                .setItems(rows.map { "${it.name}\n${it.number}" }.toTypedArray()) { _, index ->
                    if (pending?.id == requestId && current.consent.choose(rows[index], SystemClock.elapsedRealtime())) showConfirmation(rows[index])
                    else { complete(requestId, "confirmation_expired"); finish() }
                }.setNegativeButton("Cancel") { _, _ -> complete(requestId, "cancelled"); finish() }
                .setOnCancelListener { complete(requestId, "cancelled"); finish() }.create()
            dialog?.setCanceledOnTouchOutside(false); dialog?.show()
        }
    }
    private fun showConfirmation(endpoint: ContactEndpoint) {
        val current = pending ?: return
        if (current.id != requestId) { finish(); return }
        val call = current.consent.request.operation == RecipientOperation.CALL
        val message = "You asked for: ${current.consent.request.query}\n\n${endpoint.name}\n${endpoint.number}" +
            if (call) "\n\nCall this contact?" else "\nWhatsApp destination: +${ContactNameMatcher.whatsAppDigits(endpoint.number)}\n\nMessage (unchanged):\n${current.consent.request.body}\n\nOpen this WhatsApp draft? Nothing is sent until you tap Send in WhatsApp."
        dialog = AlertDialog.Builder(this).setTitle(if (call) "Confirm contact to call" else "Confirm WhatsApp recipient")
            .setMessage(message)
            .setPositiveButton(if (call) "Call ${endpoint.name}" else "Open WhatsApp draft") { _, _ ->
                if (pending?.id != requestId || dialog?.window?.decorView?.hasWindowFocus() != true || locked(this)) {
                    complete(requestId, "confirmation_expired"); finish(); return@setPositiveButton
                }
                val latest = try { resolve(this, current.consent.request.query) } catch (_: Exception) { null }
                val approved = latest?.let { current.consent.confirm(it, SystemClock.elapsedRealtime()) }
                if (approved == null) { complete(requestId, "recipient_changed"); finish(); return@setPositiveButton }
                // Consent is consumed synchronously before dispatch. Double taps cannot dial twice.
                val outcome = dispatch(this, current.consent.request, approved.number)
                complete(requestId, outcome); finish()
            }.setNegativeButton("Cancel") { _, _ -> complete(requestId, "cancelled"); finish() }
            .setOnCancelListener { complete(requestId, "cancelled"); finish() }.create()
        dialog?.setCanceledOnTouchOutside(false); dialog?.show()
    }
    override fun onStop() {
        // Leaving the foreground (including locking) invalidates consent. Returning cannot resume it.
        complete(requestId, "cancelled")
        super.onStop()
    }
    override fun onDestroy() {
        dialog?.dismiss(); dialog = null
        complete(requestId, "cancelled")
        super.onDestroy()
    }
}
