package com.friday.assistant

import org.junit.Assert.*
import org.junit.Test

class FirebaseUpdatePolicyTest {
    @Test fun onlyNewerRelease() {
        assertFalse(FirebaseUpdatePolicy.shouldOffer(55, null, 0, -1, 0))
        assertFalse(FirebaseUpdatePolicy.shouldOffer(55, 55, 0, -1, 0))
        assertFalse(FirebaseUpdatePolicy.shouldOffer(55, 54, 0, -1, 0))
        assertTrue(FirebaseUpdatePolicy.shouldOffer(55, 56, 0, -1, 0))
    }
    @Test fun laterSuppressesSameReleaseForADay() {
        assertFalse(FirebaseUpdatePolicy.shouldOffer(55, 56, 1001, 56, 1000))
        assertTrue(FirebaseUpdatePolicy.shouldOffer(55, 56, 1000 + FirebaseUpdatePolicy.LATER_INTERVAL_MS, 56, 1000))
        assertTrue(FirebaseUpdatePolicy.shouldOffer(55, 57, 1001, 56, 1000))
        assertTrue(FirebaseUpdatePolicy.shouldOffer(55, 56, 999, 56, 1000))
    }
}
