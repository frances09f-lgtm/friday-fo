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
    fun saver(c: Context) = prefs(c).getBoolean("saver", false)
    fun notificationsAllowed(c: Context): Boolean = NotificationManagerCompat.from(c).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)
    @Synchronized fun state(c: Context): Map<String, Any> {
        val ts = tasks(c)
        return mapOf("mode" to if (saver(c)) "battery_saver" else "foreground",
            "runtime" to prefs(c).getString("runtime", "Not running")!!,
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
        save(c, ts)
        WorkManager.getInstance(c).cancelUniqueWork(WORK)
        c.stopService(Intent(c, GoldTaskService::class.java))
        runtime(c, "Stopped")
        return "Cancelled all gold background tasks."
    }
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
            val request = PeriodicWorkRequestBuilder<GoldTaskWorker>(15, TimeUnit.MINUTES).build()
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
            task.put("lastCheckAt", now).put("nextCheckAt", now + interval * 60000L)
            if (!NotificationHealth.channelAllowed(c, "friday_gold_alerts")) { task.put("lastOutcome", "Gold alert notifications disabled; no alert sent"); continue }
            if (snapshot == null) { task.put("lastOutcome", "No Oro snapshot. Open Oro and let it update."); continue }
            val quoteAt = snapshot.optLong("quoteAt", 0)
            val outcome = GoldTaskRule.evaluate(task.optString("direction"), task.optDouble("threshold"),
                snapshot.optDouble("bid", Double.NaN), snapshot.optDouble("ask", Double.NaN),
                quoteAt, task.optLong("lastQuoteAt"), now, 300000L)
            task.put("lastOutcome", when(outcome) {
                "stale_quote" -> "Oro quote is old or has no valid timestamp; waiting for Oro to update"
                "same_quote" -> "Oro has no newer quote; waiting"
                "not_met" -> "Checked Oro's saved quote; condition not met"
                "triggered" -> "Condition met in Oro's saved quote"
                else -> "Invalid Oro quote; no alert sent"
            })
            if (outcome in listOf("not_met", "triggered")) task.put("lastQuoteAt", quoteAt)
            if (outcome == "triggered") {
                // Persist completion before notification so a process restart cannot duplicate it.
                task.put("status", "completed")
                save(c, ts)
                try {
                    val mid = (snapshot.getDouble("bid") + snapshot.getDouble("ask")) / 2
                    GoldTaskService.alert(c, task.optString("id"), "Gold ${task.optString("direction")} ${task.optDouble("threshold")}",
                        "Oro saved quote: %.2f, %d seconds old. No trade was placed.".format(mid, (now-quoteAt)/1000))
                } catch (_: Exception) { task.put("status", "blocked").put("lastOutcome", "Condition met, but notification could not be shown") }
            }
        }
        save(c, ts)
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
