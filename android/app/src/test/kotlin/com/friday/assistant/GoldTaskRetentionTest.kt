package com.friday.assistant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
class GoldTaskRetentionTest {
    @Test fun doneTasksLeaveTheList() {
        val statuses = listOf("active", "completed", "blocked", "cancelled", "expired", "active", "Completed ")
        assertEquals(listOf(0, 2, 5), GoldTaskRetention.keepIndices(statuses))
    }
    @Test fun activeAndBlockedStay() {
        assertFalse(GoldTaskRetention.isDone("active"))
        assertFalse(GoldTaskRetention.isDone("blocked"))
        assertTrue(GoldTaskRetention.isDone("completed"))
        assertTrue(GoldTaskRetention.isDone("cancelled"))
        assertTrue(GoldTaskRetention.isDone("expired"))
    }
    @Test fun emptyAndMissing() {
        assertEquals(emptyList<Int>(), GoldTaskRetention.keepIndices(emptyList()))
        // A task with no status is not known to be done; keep it visible.
        assertEquals(listOf(0), GoldTaskRetention.keepIndices(listOf(null)))
    }
    @Test fun removeMatchesById() {
        val ids = listOf("a", "b", "c")
        val dirs = listOf("above", "below", "above")
        val th = listOf(4140.0, 4150.0, 4140.0)
        assertEquals(1, GoldTaskRetention.matchIndex(ids, dirs, th, "b", "above", 4140.0))
        assertEquals(-1, GoldTaskRetention.matchIndex(ids, dirs, th, "gone", "above", 4140.0))
    }
    @Test fun removeMatchesOldTasksWithoutId() {
        val ids = listOf("a", "", null)
        val dirs = listOf("above", "below", "above")
        val th = listOf(4140.0, 4150.0, 4140.0)
        // Never removes a task that has an id when the request had none.
        assertEquals(2, GoldTaskRetention.matchIndex(ids, dirs, th, null, "above", 4140.0))
        assertEquals(1, GoldTaskRetention.matchIndex(ids, dirs, th, "", "below", 4150.0))
        assertEquals(-1, GoldTaskRetention.matchIndex(ids, dirs, th, null, "below", 9.0))
        assertEquals(-1, GoldTaskRetention.matchIndex(ids, dirs, th, null, null, null))
    }
    @Test fun checkerStopsWhenNoActiveTaskLeft() {
        assertTrue(GoldTaskRetention.anyActive(listOf("blocked", "Active")))
        assertFalse(GoldTaskRetention.anyActive(listOf("blocked")))
        assertFalse(GoldTaskRetention.anyActive(emptyList()))
    }
}
