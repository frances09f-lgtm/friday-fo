package com.friday.assistant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
class WhisperHintsTest {
    @Test fun languageComesFromTheCallersTag() {
        assertEquals("en", WhisperHints.from("en-IN", null).language)
        assertEquals("hi", WhisperHints.from("hi_IN", null).language)
        assertNull(WhisperHints.from(null, null).language)
        assertNull(WhisperHints.from("", null).language)
    }
    @Test fun promptCarriesCommandWordsAndCallerHints() {
        val p = WhisperHints.from("en-IN", listOf("above", "XAUUSD", " ", "Friday")).prompt
        assertTrue(p.contains("gold goes above 4,000"))
        assertTrue(p.contains("XAUUSD"))
        assertTrue(p.length <= 700)
    }
}
