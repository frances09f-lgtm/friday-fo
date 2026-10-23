package com.friday.assistant

internal object FloatingAssistantSizing {
    /** Bubble keeps the v75 size. */
    const val SCALE = 0.7f
    /** Assistant bar: back to the v74 size (v75 and v76 were 0.7, v77 was 0.85). */
    const val PANEL_SCALE = 1.0f
    const val BUBBLE_WIDTH_DP = 72f * SCALE
    const val BUBBLE_HEIGHT_DP = 48f * SCALE
    const val BUBBLE_TEXT_SP = 22f * SCALE
    fun panelWidth(screenWidthPixels: Int) = (screenWidthPixels * PANEL_SCALE).toInt()
    fun panelHeight(expanded: Boolean, density: Float) =
        ((if (expanded) 360 else 132) * PANEL_SCALE * density).toInt()
}
