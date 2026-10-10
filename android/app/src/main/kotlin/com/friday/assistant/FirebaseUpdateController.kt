package com.friday.assistant

import android.app.Activity
import android.app.AlertDialog
import android.os.Build
import android.os.SystemClock
import android.widget.Toast
import com.google.firebase.FirebaseApp
import com.google.firebase.appdistribution.FirebaseAppDistribution

/** Foreground-only private tester updates. No server credential or automatic install. */
internal class FirebaseUpdateController(private val activity: Activity) {
    private val prefs = activity.getSharedPreferences("friday_tester_updates", 0)
    private var busy = false
    private var lastCheck: Long? = null
    private var dialog: AlertDialog? = null
    private var destroyed = false

    private fun available() = !destroyed && !activity.isFinishing && !activity.isDestroyed

    fun onResume() {
        if (!available() || busy || dialog?.isShowing == true) return
        // With no console config this feature stays inactive; core offline Friday still works.
        val app = FirebaseApp.getApps(activity).firstOrNull()
            ?: FirebaseApp.initializeApp(activity) ?: return
        if (app.options.applicationId != "1:509368336413:android:bdf178861eee975f0a46f4" ||
            app.options.projectId != "app-testing-2cdba") return
        val sdk = FirebaseAppDistribution.getInstance()
        if (!sdk.isTesterSignedIn) {
            val askedAt = prefs.getLong("alerts_asked_at", 0)
            val wallNow = System.currentTimeMillis()
            if (wallNow >= askedAt && wallNow - askedAt < FirebaseUpdatePolicy.LATER_INTERVAL_MS) return
            dialog = AlertDialog.Builder(activity)
                .setTitle("Enable update alerts?")
                .setMessage("Sign in with your Firebase tester Google account to get in-app updates.")
                .setPositiveButton("Enable") { _, _ ->
                    prefs.edit().putLong("alerts_asked_at", System.currentTimeMillis()).apply()
                    busy = true
                    sdk.signInTester().addOnCompleteListener(activity) { task ->
                        busy = false
                        if (!available()) return@addOnCompleteListener
                        if (task.isSuccessful) check(sdk)
                        else {
                            prefs.edit().putLong("alerts_asked_at", 0).apply()
                            Toast.makeText(activity, "Update alerts weren't enabled. Try again when you reopen Friday.", Toast.LENGTH_LONG).show()
                        }
                    }
                }
                .setNegativeButton("Later") { _, _ -> }
                .create()
            // Never repeat a consent/sign-in popup on every resume in the same session.
            prefs.edit().putLong("alerts_asked_at", System.currentTimeMillis()).apply()
            dialog?.show()
            return
        }
        check(sdk)
    }

    private fun check(sdk: FirebaseAppDistribution) {
        val now = SystemClock.elapsedRealtime()
        if (lastCheck?.let { now - it < FirebaseUpdatePolicy.CHECK_INTERVAL_MS } == true) return
        lastCheck = now
        busy = true
        sdk.checkForNewRelease().addOnCompleteListener(activity) { task ->
            busy = false
            if (!available() || !task.isSuccessful) return@addOnCompleteListener
            val release = task.result ?: return@addOnCompleteListener
            val version = release.buildVersion.toLongOrNull() ?: return@addOnCompleteListener
            val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
            val installed = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            if (!FirebaseUpdatePolicy.shouldOffer(installed, version, System.currentTimeMillis(),
                    prefs.getLong("later_version", -1), prefs.getLong("later_at", 0))) return@addOnCompleteListener
            dialog = AlertDialog.Builder(activity)
                .setTitle("New version available")
                .setMessage("Update Friday to version ${release.displayVersion}.")
                .setPositiveButton("Update") { _, _ ->
                    busy = true
                    // Uses precisely the SDK release cached by checkForNewRelease, no second prompt.
                    sdk.updateApp().addOnCompleteListener(activity) { update ->
                        busy = false
                        if (available() && !update.isSuccessful) {
                            Toast.makeText(activity, "Update didn't finish. You can try again later.", Toast.LENGTH_LONG).show()
                        }
                    }
                }
                .setNegativeButton("Later") { _, _ -> defer(version) }
                .setOnCancelListener { defer(version) }
                .create()
            dialog?.show()
        }
    }

    private fun defer(version: Long) {
        prefs.edit().putLong("later_version", version)
            .putLong("later_at", System.currentTimeMillis()).apply()
    }

    fun close() {
        destroyed = true
        dialog?.dismiss()
        dialog = null
    }
}
