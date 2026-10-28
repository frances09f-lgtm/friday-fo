package com.friday.assistant

/**
 * Which saved gold tasks stay on the Tasks page. A task that is done (its
 * one-shot alert fired and it completed, or it was cancelled or expired) is
 * dropped from storage, so the Tasks page only shows work still pending:
 * active checks and blocked tasks that still need the user.
 * Pure Kotlin so it is unit-tested without Android.
 */
object GoldTaskRetention {
    val DONE_STATUSES = setOf("completed", "cancelled", "canceled", "expired", "done", "fired", "failed")

    fun isDone(status: String?): Boolean = status?.trim()?.lowercase() in DONE_STATUSES

    /** Indices (in order) of the tasks to keep, given each task's status. */
    fun keepIndices(statuses: List<String?>): List<Int> = statuses.indices.filter { !isDone(statuses[it]) }

    /**
     * Which stored task the user asked to remove. Tasks are matched by id; a
     * task saved by an old build without an id is matched by its direction and
     * threshold instead. Returns -1 when nothing matches (already gone).
     */
    fun matchIndex(ids: List<String?>, directions: List<String?>, thresholds: List<Double>,
                   id: String?, direction: String?, threshold: Double?): Int {
        val wanted = id?.trim().orEmpty()
        if (wanted.isNotEmpty()) return ids.indexOfFirst { it?.trim() == wanted }
        if (direction.isNullOrBlank() || threshold == null || !threshold.isFinite()) return -1
        return ids.indices.firstOrNull {
            ids[it].isNullOrBlank() && directions[it] == direction && thresholds[it] == threshold
        } ?: -1
    }

    /** Whether any background checking is still needed after a removal. */
    fun anyActive(statuses: List<String?>): Boolean = statuses.any { it?.trim()?.lowercase() == "active" }
}
