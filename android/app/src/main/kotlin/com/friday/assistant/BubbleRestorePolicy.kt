package com.friday.assistant

/** Whether the floating bubble should be (re)started. Pure logic, kept free
    of Android classes so the native unit tests lock the restore behavior:
    only when the user left it on, it is not already running, and Friday is
    still allowed to draw over other apps. */
object BubbleRestorePolicy {
    fun shouldRestore(persistedEnabled: Boolean, serviceActive: Boolean, canDrawOverlays: Boolean): Boolean =
        persistedEnabled && !serviceActive && canDrawOverlays
}
