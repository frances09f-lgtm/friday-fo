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
import android.widget.CheckBox
import android.widget.Toast
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
            val rows = try { contactRows(context) } catch (_: Exception) { result.success("error"); return }
            val matches = SavedContactMatches(ContactMatchPreferences(context))
            val remembered = matches.resolve(request.query, rows, request.operation)
            if (remembered != null) {
                // Dispatch still rechecks lock, running agent and CALL_PHONE.
                result.success(dispatch(context, request, remembered.number)); return
            }
            val staleCallAlias = request.operation == RecipientOperation.CALL && matches.has(request.query)
            val resolution = ContactNameMatcher.resolve(request.query, rows)
            if (resolution.candidates.isEmpty()) { result.success("no_match"); return }
            if (resolution.exactUnique && !staleCallAlias) {
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
        private fun resolve(context: Context, query: String): RecipientResolution = ContactNameMatcher.resolve(query, contactRows(context))
        private fun contactRows(context: Context): List<ContactEndpoint> {
            if (!permitted(context, Manifest.permission.READ_CONTACTS)) throw SecurityException()
            val rows = mutableListOf<ContactEndpoint>()
            context.contentResolver.query(ContactsContract.CommonDataKinds.Phone.CONTENT_URI, arrayOf(ContactsContract.CommonDataKinds.Phone.CONTACT_ID, ContactsContract.CommonDataKinds.Phone.LOOKUP_KEY,
                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME, ContactsContract.CommonDataKinds.Phone.NUMBER), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) rows.add(ContactEndpoint(cursor.getLong(0).toString(), cursor.getString(1) ?: "",
                    cursor.getString(2) ?: "", cursor.getString(3) ?: ""))
            } ?: throw IllegalStateException("Contacts unavailable")
            return rows
        }
        fun manageSavedMatches(activity: Activity) {
            fun usable() = !activity.isFinishing && !activity.isDestroyed &&
                !locked(activity) && FridayAccessibilityService.current?.isRunning != true
            if (!usable()) return
            val matches = SavedContactMatches(ContactMatchPreferences(activity))
            lateinit var show: () -> Unit
            fun message(text: String) { Toast.makeText(activity,text,Toast.LENGTH_LONG).show() }
            fun chooseContact(alias: String, original: SavedContactMatch?) {
                if (!usable()) return
                if (!permitted(activity, Manifest.permission.READ_CONTACTS)) {
                    ActivityCompat.requestPermissions(activity,arrayOf(Manifest.permission.READ_CONTACTS),4242)
                    message("Allow Contacts access, then add or edit the nickname again. Nothing saved.")
                    return
                }
                val rows = try { contactRows(activity).distinct().sortedWith(compareBy({ it.name.lowercase() },{ it.number })) }
                    catch (_: Exception) { message("Contacts unavailable. Nothing saved."); return }
                if (rows.isEmpty()) { message("No phone contacts available. Nothing saved."); return }
                // A search filters real contact rows; it never proposes a person or number.
                val search = android.widget.EditText(activity).apply { hint="Search contacts"; isSingleLine=true }
                val list = android.widget.ListView(activity)
                var filtered = rows
                val adapter = android.widget.ArrayAdapter(activity,android.R.layout.simple_list_item_1,
                    filtered.map { "${it.name}\n${it.number}" }.toMutableList())
                list.adapter=adapter
                val layout=android.widget.LinearLayout(activity).apply {
                    orientation=android.widget.LinearLayout.VERTICAL
                    addView(search); addView(list,android.widget.LinearLayout.LayoutParams(-1,(300*activity.resources.displayMetrics.density).toInt()))
                }
                search.addTextChangedListener(object: android.text.TextWatcher {
                    override fun beforeTextChanged(s:CharSequence?,start:Int,count:Int,after:Int) {}
                    override fun onTextChanged(s:CharSequence?,start:Int,before:Int,count:Int) {
                        val term=s?.toString()?.trim().orEmpty()
                        filtered=rows.filter { it.name.contains(term,true) || it.number.contains(term) }
                        adapter.clear();adapter.addAll(filtered.map { "${it.name}\n${it.number}" });adapter.notifyDataSetChanged()
                    }
                    override fun afterTextChanged(s:android.text.Editable?) {}
                })
                val picker=AlertDialog.Builder(activity).setTitle("Choose contact for “$alias”")
                    .setView(layout).setNegativeButton("Cancel",null).create()
                list.setOnItemClickListener { _,_,index,_ ->
                    val selected=filtered.getOrNull(index)?:return@setOnItemClickListener
                    picker.dismiss()
                    if (!usable()) return@setOnItemClickListener
                    AlertDialog.Builder(activity).setTitle("Save call nickname?")
                        .setMessage("$alias → ${selected.name}\n${selected.number}\n\nSaying or typing ‘call $alias’ will call this contact directly. Only on this phone; not used for WhatsApp. A changed or ambiguous contact must be chosen again.")
                        .setPositiveButton("Save nickname") { _,_ ->
                            if (!usable()) return@setPositiveButton
                            val fresh=try { contactRows(activity) } catch (_:Exception) { null }
                            val saved= fresh != null && if (original == null)
                                matches.remember(alias,selected,fresh,RecipientOperation.CALL,true,true)
                            else matches.edit(original,alias,selected,fresh,true)
                            if (!saved) message("Not saved: contact changed, has multiple/shared numbers, or nickname conflicts. Review existing matches first.")
                            show()
                        }.setNegativeButton("Cancel",null).show()
                }
                picker.show()
            }
            fun editAlias(original: SavedContactMatch?) {
                if (!usable()) return
                val input=android.widget.EditText(activity).apply {
                    hint="Nickname, e.g. Appa";isSingleLine=true;setText(original?.alias.orEmpty())
                }
                val dialog=AlertDialog.Builder(activity).setTitle(if(original==null) "Add call nickname" else "Edit call nickname")
                    .setMessage("Enter the name you will say after ‘call’, then choose a real contact. Existing saved matches are not silently replaced.")
                    .setView(input).setPositiveButton("Choose contact",null).setNegativeButton("Cancel",null).create()
                dialog.setOnShowListener {
                    dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                        val alias=input.text.toString().trim()
                        val key=ContactNameMatcher.normalize(alias)
                        if (key.isBlank() || alias.length>80 || key.matches(Regex("[0-9 +()-]+"))) {
                            input.error="Enter a name, not a phone number (up to 80 characters)";return@setOnClickListener
                        }
                        if (matches.all().any { it.alias==key && it != original }) {
                            input.error="This nickname already exists. Edit or forget that match first.";return@setOnClickListener
                        }
                        dialog.dismiss();chooseContact(alias,original)
                    }
                }
                dialog.show()
            }
            show = show@{
                if (!usable()) return@show
                val saved=matches.all()
                val builder=AlertDialog.Builder(activity).setTitle("Contact nicknames & saved matches")
                    .setPositiveButton("Add nickname") { _,_ -> editAlias(null) }.setNegativeButton("Close", null)
                if (saved.isEmpty()) builder.setMessage("No saved matches. Add your own call nickname or tick ‘Always use’ when confirming a suggested contact. Saved only on this phone; calls only.")
                else builder.setItems(saved.map { "${it.alias} → ${it.endpoint.name}\n${it.endpoint.number}" }.toTypedArray()) { _,index ->
                    val selected=saved[index]
                    AlertDialog.Builder(activity).setTitle("${selected.alias} → ${selected.endpoint.name}")
                        .setMessage("${selected.endpoint.number}\nCall nickname saved on this phone.")
                        .setPositiveButton("Edit") { _,_ -> editAlias(selected) }
                        .setNeutralButton("Forget") { _,_ ->
                            if (!usable()) return@setNeutralButton
                            AlertDialog.Builder(activity).setTitle("Forget this name match?")
                                .setMessage("${selected.alias} → ${selected.endpoint.name}\n${selected.endpoint.number}")
                                .setPositiveButton("Forget") { _,_ ->
                                    if (!usable()) return@setPositiveButton
                                    if (!matches.forget(selected.alias)) message("Could not forget match")
                                    show()
                                }.setNegativeButton("Keep",null).show()
                        }.setNegativeButton("Close",null).show()
                }
                builder.show()
            }
            show()
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
        val remember = CheckBox(this).apply {
            text = "Always use this contact for this name when calling\nSaved only on this phone. Forget it in Settings → Saved call name matches."
            isChecked = false
        }
        dialog = AlertDialog.Builder(this).setTitle(if (call) "Confirm contact to call" else "Confirm WhatsApp recipient")
            .setMessage(message)
            .setView(if (call) remember else null)
            .setPositiveButton(if (call) "Call ${endpoint.name}" else "Open WhatsApp draft") { _, _ ->
                if (pending?.id != requestId || dialog?.window?.decorView?.hasWindowFocus() != true || locked(this)) {
                    complete(requestId, "confirmation_expired"); finish(); return@setPositiveButton
                }
                val latestRows = try { contactRows(this) } catch (_: Exception) { null }
                val latest = latestRows?.let { ContactNameMatcher.resolve(current.consent.request.query, it) }
                val approved = latest?.let { current.consent.confirm(it, SystemClock.elapsedRealtime()) }
                if (approved == null) { complete(requestId, "recipient_changed"); finish(); return@setPositiveButton }
                // Consent is consumed synchronously before dispatch. Double taps cannot dial twice.
                if (call && remember.isChecked && latestRows != null) {
                    val saved = SavedContactMatches(ContactMatchPreferences(this)).remember(current.consent.request.query,
                        approved, latestRows, current.consent.request.operation, explicitlyChecked = true, confirmed = true)
                    if (!saved) Toast.makeText(this,"Match not saved: contact is ambiguous, changed, or conflicts with an older match. Manage saved matches in Settings.",Toast.LENGTH_LONG).show()
                }
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
