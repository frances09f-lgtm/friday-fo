package com.friday.assistant

/** No release URL, account, token, or private release data is persisted here. */
internal object FirebaseUpdatePolicy {
    const val CHECK_INTERVAL_MS = 60L * 60L * 1000L
    const val LATER_INTERVAL_MS = 24L * 60L * 60L * 1000L

    fun shouldOffer(installed: Long, available: Long?, now: Long,
                    declinedVersion: Long, declinedAt: Long): Boolean {
        if (available == null || available <= installed) return false
        return declinedVersion != available || now < declinedAt ||
            now - declinedAt >= LATER_INTERVAL_MS
    }
}
