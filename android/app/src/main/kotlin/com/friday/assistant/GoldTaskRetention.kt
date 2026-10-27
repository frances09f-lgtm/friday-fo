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
}
