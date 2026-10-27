package com.friday.assistant
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
class BubbleRestorePolicyTest {
    @Test fun restoresWhenUserLeftItOnAndServiceIsDead() {
        assertTrue(BubbleRestorePolicy.shouldRestore(persistedEnabled = true, serviceActive = false, canDrawOverlays = true))
    }
    @Test fun neverRestartsAnAlreadyRunningService() {
        assertFalse(BubbleRestorePolicy.shouldRestore(persistedEnabled = true, serviceActive = true, canDrawOverlays = true))
    }
    @Test fun staysOffWhenUserTurnedItOff() {
        assertFalse(BubbleRestorePolicy.shouldRestore(persistedEnabled = false, serviceActive = false, canDrawOverlays = true))
    }
    @Test fun staysOffWithoutOverlayPermission() {
        assertFalse(BubbleRestorePolicy.shouldRestore(persistedEnabled = true, serviceActive = false, canDrawOverlays = false))
    }
}
