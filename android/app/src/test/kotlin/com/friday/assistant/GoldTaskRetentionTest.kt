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
}
