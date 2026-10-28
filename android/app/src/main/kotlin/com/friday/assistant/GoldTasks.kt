package com.friday.assistant

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

object GoldTasks {
    private const val PREFS = "friday_gold_tasks"
    private const val WORK = "friday_gold_checks"
    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun tasks(c: Context): JSONArray = try { JSONArray(prefs(c).getString("tasks", "[]")) } catch (_: Exception) { JSONArray() }
    private fun save(c: Context, ts: JSONArray) { kotlin.check(prefs(c).edit().putString("tasks", ts.toString()).commit()) }
    /** Done tasks (completed, cancelled, expired) leave the list; see GoldTaskRetention. */
    private fun withoutDone(ts: JSONArray): JSONArray {
        val keep = GoldTaskRetention.keepIndices((0 until ts.length()).map { ts.optJSONObject(it)?.optString("status") ?: "done" })
        val out = JSONArray()
        for (i in keep) out.put(ts.getJSONObject(i))
        return out
    }
    /** Save, dropping done tasks so they disappear from the Tasks page. */
    private fun saveOpen(c: Context, ts: JSONArray) = save(c, withoutDone(ts))
    fun saver(c: Context) = prefs(c).getBoolean("saver", false)
    fun notificationsAllowed(c: Context): Boolean = NotificationManagerCompat.from(c).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    @Synchronized fun state(c: Context): Map<String, Any> {
        val stored = tasks(c)
        val ts = withoutDone(stored)
        // Tasks finished by an older build (or between checks) are cleared on read.
        if (ts.length() != stored.length()) try { save(c, ts) } catch (_: Exception) { }
        return mapOf("mode" to if (saver(c)) "battery_saver" else "foreground",
            "runtime" to prefs(c).getString("runtime", "Not running")!!,
            "engine" to "watch_compare_notify_v1",
            "source" to "Oro saved quote", "modelPolicy" to "Not needed for numeric thresholds",
            "tasks" to (0 until ts.length()).map { i ->
                val j = ts.getJSONObject(i)
                j.keys().asSequence().associateWith { j.get(it) }
            })
    }
    fun runtime(c: Context, state: String) { prefs(c).edit().putString("runtime", state).commit() }
    @Synchronized fun create(c: Context, direction: String, threshold: Double, interval: Int): String {
        if (direction !in listOf("above", "below") || !threshold.isFinite() || threshold <= 0 || interval !in 5..1440)
            return "Use a gold above/below alert with an interval from 5 minutes to 24 hours."
        if (!NotificationHealth.channelAllowed(c, "friday_gold_alerts")) return "Gold alert notifications are disabled. Open Notifications in Friday and enable them before starting a task."
        val ts = tasks(c)
        if ((0 until ts.length()).count { ts.getJSONObject(it).optString("status") == "active" } >= 20)
            return "There are already 20 active tasks. Cancel one first."
        val now = System.currentTimeMillis()
        val id = java.util.UUID.randomUUID().toString()
        ts.put(JSONObject().put("id", id).put("direction", direction).put("threshold", threshold)
            .put("intervalMinutes", interval).put("status", "active").put("createdAt", now)
            .put("source", "oro_saved_quote").put("lastFingerprint", "").put("changedChecks", 0)
            .put("nextCheckAt", now).put("lastCheckAt", 0).put("lastQuoteAt", 0).put("lastOutcome", "Waiting for first check"))
        save(c, ts)
        try { ensure(c) } catch (_: Exception) {
            ts.getJSONObject(ts.length()-1).put("status", "blocked").put("lastOutcome", "Could not start background execution")
            save(c, ts)
            return "The task was saved but could not start. Reopen Friday, cancel this blocked task, and create it again."
        }
        return if (saver(c)) "Saved a one-shot gold $direction $threshold alert. Battery saver checks are best-effort, at least 15 minutes apart. It reads Oro's saved quote, not a fresh internet price."
          else "Saved a one-shot gold $direction $threshold alert, checking about every $interval minutes. A quiet notification shows Friday is checking. It reads Oro's saved quote; old or missing quotes will not trigger an alert."
    }
    @Synchronized fun cancelAll(c: Context): String {
        val ts = tasks(c)
        for (i in 0 until ts.length()) if (ts.getJSONObject(i).optString("status") in listOf("active", "blocked"))
            ts.getJSONObject(i).put("status", "cancelled").put("lastOutcome", "Cancelled by you")
        saveOpen(c, ts)
        WorkManager.getInstance(c).cancelUniqueWork(WORK)
        c.stopService(Intent(c, GoldTaskService::class.java))
        runtime(c, "Stopped")
        return "Cancelled all gold background tasks."
    }
    /**
     * Remove one task the user deleted from the Tasks page. It is marked
     * cancelled and dropped from storage (so it never comes back after a
     * restart), its alert notification is cleared, and when no active task is
     * left the worker and the foreground checker are stopped.
     */
    @Synchronized fun cancel(c: Context, id: String?, direction: String?, threshold: Double?): String {
        val ts = tasks(c)
        val rows = (0 until ts.length()).map { ts.optJSONObject(it) ?: JSONObject() }
        val i = GoldTaskRetention.matchIndex(rows.map { it.optString("id", "") }, rows.map { it.optString("direction", "") },
            rows.map { it.optDouble("threshold", Double.NaN) }, id, direction, threshold)
        if (i < 0) return "That task was already removed."
        val task = rows[i]
        task.put("status", "cancelled").put("lastOutcome", "Removed by you")
        saveOpen(c, ts)
        val taskId = task.optString("id", "")
        if (taskId.isNotEmpty()) try {
            (c.getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager).cancel(taskId, 82)
        } catch (_: Exception) { }
        val left = tasks(c)
        if (!GoldTaskRetention.anyActive((0 until left.length()).map { left.optJSONObject(it)?.optString("status") })) {
            WorkManager.getInstance(c).cancelUniqueWork(WORK)
            c.stopService(Intent(c, GoldTaskService::class.java))
            runtime(c, "Stopped")
        }
        val name = "gold ${task.optString("direction")} ${formatThreshold(task.optDouble("threshold"))}".trim()
        return "Removed the $name task."
    }
    private fun formatThreshold(v: Double): String = if (!v.isFinite()) "" else if (v == Math.floor(v)) v.toLong().toString() else v.toString()
    @Synchronized fun setMode(c: Context, batterySaver: Boolean): String {
        prefs(c).edit().putBoolean("saver", batterySaver).commit()
        WorkManager.getInstance(c).cancelUniqueWork(WORK)
        c.stopService(Intent(c, GoldTaskService::class.java))
        return try {
            ensure(c)
            if (batterySaver) "Battery saver enabled. Checks are best-effort, at least 15 minutes apart."
            else "Foreground checks enabled. A quiet persistent notification stays visible while tasks are active; Android may still delay checks."
        } catch (_: Exception) { "Mode saved, but background execution could not start. Reopen Friday and retry." }
    }
    @Synchronized fun hasActive(c: Context): Boolean {
        val ts = tasks(c)
        return (0 until ts.length()).any { ts.getJSONObject(it).optString("status") == "active" }
    }
    @Synchronized fun delayUntilNextCheck(c: Context): Long {
        val ts = tasks(c)
        val now = System.currentTimeMillis()
        val next = (0 until ts.length()).map { ts.getJSONObject(it) }
            .filter { it.optString("status") == "active" }
            .map { it.optLong("nextCheckAt", now) }
        return TaskTiming.delay(now, next)
    }
    fun ensure(c: Context, fromBoot: Boolean = false) {
        if (!hasActive(c)) return
        if (saver(c) || fromBoot) {
            // Do not start a forbidden foreground service at boot. A worker restores checks.
            val saved = tasks(c)
            val interval = (0 until saved.length()).map { saved.getJSONObject(it) }
                .filter { it.optString("status") == "active" }
                .minOfOrNull { WatchEngine.workerInterval(it.optInt("intervalMinutes", 15)) } ?: 15L
            val request = PeriodicWorkRequestBuilder<GoldTaskWorker>(interval, TimeUnit.MINUTES)
                .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 1, TimeUnit.MINUTES).build()
            WorkManager.getInstance(c).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.UPDATE, request)
            runtime(c, if (fromBoot && !saver(c)) "After reboot: slower worker until Friday is reopened" else "Battery saver worker scheduled")
        } else {
            WorkManager.getInstance(c).cancelUniqueWork(WORK)
            ContextCompat.startForegroundService(c, Intent(c, GoldTaskService::class.java))
        }
    }
    @Synchronized fun check(c: Context) {
        val ts = tasks(c)
        val now = System.currentTimeMillis()
        if (!(0 until ts.length()).any { ts.getJSONObject(it).optString("status") == "active" && now >= ts.getJSONObject(it).optLong("nextCheckAt") }) return
        val snapshot = try {
            c.contentResolver.query(Uri.parse("content://com.ambi.gold_paper_trading.bridge/status"), null, null, null, null)?.use {
                if (it.moveToFirst()) JSONObject(it.getString(0)) else null
            }
        } catch (_: Exception) { null }
        for (i in 0 until ts.length()) {
            val task = ts.getJSONObject(i)
            if (task.optString("status") != "active" || now < task.optLong("nextCheckAt")) continue
            val interval = task.optInt("intervalMinutes", 15).coerceIn(5, 1440)
            task.put("lastCheckAt", now).put("nextCheckAt", now + (if (saver(c)) WatchEngine.workerInterval(interval) else interval.toLong()) * 60000L)
            if (!NotificationHealth.channelAllowed(c, "friday_gold_alerts")) { task.put("lastOutcome", "Gold alert notifications disabled; no alert sent"); continue }
            if (snapshot == null) { task.put("lastOutcome", "No Oro snapshot. Open Oro and let it update."); continue }
            val quoteAt = snapshot.optLong("quoteAt", 0)
            val bid = snapshot.optDouble("bid", Double.NaN)
            val ask = snapshot.optDouble("ask", Double.NaN)
            val sample = if (bid.isFinite() && ask.isFinite() && bid > 0 && ask >= bid)
                WatchSample("oro_saved_quote", (bid + ask) / 2, quoteAt, "$bid:$ask") else null
            val pipeline = WatchPipeline(object : WatchSource { override fun fetch() = sample })
            val decision = pipeline.run(task.optString("lastFingerprint"), now,
                300000L, task.optString("direction"), task.optDouble("threshold"), task.optLong("lastQuoteAt"))
            val outcome = decision.outcome
            if (decision.changed) task.put("changedChecks", task.optInt("changedChecks") + 1)
            task.put("lastOutcome", when(outcome) {
                "stale_sample" -> "Oro quote is old or has no valid timestamp; waiting for Oro to update"
                "unchanged" -> "Quote value unchanged; skipped further processing"
                "out_of_order" -> "Older source quote ignored; waiting for a newer update"
                "not_met" -> "Checked Oro's saved quote; condition not met"
                "triggered" -> "Condition met in Oro's saved quote"
                else -> "Invalid Oro quote; no alert sent"
            })
            if (outcome == "unchanged") task.put("lastQuoteAt", quoteAt)
            if (outcome == "not_met") task.put("lastQuoteAt", quoteAt).put("lastFingerprint", decision.fingerprint)
            if (outcome == "triggered") {
                // Stable notification ID makes crash retries replace, not duplicate, the alert.
                // Complete only after dispatch succeeds; never silently lose a failed alert.
                task.put("status", "active").put("lastOutcome", "Condition met; notification pending")
                save(c, ts)
                try {
                    val mid = (snapshot.getDouble("bid") + snapshot.getDouble("ask")) / 2
                    GoldTaskService.alert(c, task.optString("id"), "Gold ${task.optString("direction")} ${task.optDouble("threshold")}",
                        "Oro saved quote: %.2f, %d seconds old. No trade was placed.".format(mid, (now-quoteAt)/1000))
                    task.put("status", "completed").put("lastQuoteAt", quoteAt).put("lastFingerprint", decision.fingerprint)
                } catch (_: Exception) { task.put("lastOutcome", "Condition met, but notification failed; retry on next check") }
            }
        }
        saveOpen(c, ts)
        if (!(0 until ts.length()).any { ts.getJSONObject(it).optString("status") == "active" }) {
            WorkManager.getInstance(c).cancelUniqueWork(WORK)
        }
    }
}
class GoldTaskWorker(c: Context, p: WorkerParameters) : Worker(c, p) {
    override fun doWork(): Result = try { GoldTasks.check(applicationContext); Result.success() } catch (_: Exception) { Result.retry() }
}
class GoldTaskBootReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in listOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED))
            try { GoldTasks.ensure(context, fromBoot = true) } catch (_: Exception) { }
    }
}
