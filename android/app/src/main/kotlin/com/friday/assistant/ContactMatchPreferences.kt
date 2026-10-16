package com.friday.assistant

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import android.util.AtomicFile
import java.io.File

/** App-private on-device storage; excluded from backup by the app manifest. No network use. */
class ContactMatchPreferences(context: Context): ContactMatchStorage {
    private val file=AtomicFile(File(context.noBackupFilesDir,"confirmed_call_matches.json"))
    override fun read(): List<SavedContactMatch> = try {
        val data=JSONArray(if (file.baseFile.exists()) file.openRead().bufferedReader().use { it.readText() } else "[]")
        (0 until data.length()).map { i ->
            val r=data.getJSONObject(i)
            SavedContactMatch(r.getString("alias"), ContactEndpoint(r.getString("contactId"),r.getString("lookupKey"),r.getString("name"),r.getString("number")))
        }
    } catch (_: Exception) { emptyList() }
    override fun write(matches: List<SavedContactMatch>): Boolean {
        val data=JSONArray()
        matches.forEach { m -> data.put(JSONObject().put("alias",m.alias).put("contactId",m.endpoint.contactId)
            .put("lookupKey",m.endpoint.lookupKey).put("name",m.endpoint.name).put("number",m.endpoint.number)) }
        var output: java.io.FileOutputStream? = null
        return try {
            output=file.startWrite(); output.write(data.toString().toByteArray(Charsets.UTF_8)); file.finishWrite(output); true
        } catch (_: Exception) { output?.let { file.failWrite(it) }; false }
    }
}
