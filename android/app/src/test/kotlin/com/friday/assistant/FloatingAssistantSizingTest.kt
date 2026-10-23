package com.friday.assistant
import org.junit.Assert.assertEquals
import org.junit.Test
class FloatingAssistantSizingTest {
    @Test fun bubbleDimensions() {
        assertEquals(50.4f, FloatingAssistantSizing.BUBBLE_WIDTH_DP, 0.01f)
        assertEquals(33.6f, FloatingAssistantSizing.BUBBLE_HEIGHT_DP, 0.01f)
        assertEquals(15.4f, FloatingAssistantSizing.BUBBLE_TEXT_SP, 0.01f)
    }
    @Test fun windowDimensions() {
        assertEquals(288, FloatingAssistantSizing.panelWidth(412))
        assertEquals(92, FloatingAssistantSizing.panelHeight(false, 1f))
        assertEquals(252, FloatingAssistantSizing.panelHeight(true, 1f))
    }
}
