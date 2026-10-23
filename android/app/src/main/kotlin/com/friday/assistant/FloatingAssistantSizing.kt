package com.friday.assistant

internal object FloatingAssistantSizing {
    /** Bubble keeps the v75 size. */
    const val SCALE = 0.7f
    /** Assistant bar: halfway between v74 (1.0) and v75/v76 (0.7). */
    const val PANEL_SCALE = 0.85f
    const val BUBBLE_WIDTH_DP = 72f * SCALE
    const val BUBBLE_HEIGHT_DP = 48f * SCALE
    const val BUBBLE_TEXT_SP = 22f * SCALE
    fun panelWidth(screenWidthPixels: Int) = (screenWidthPixels * PANEL_SCALE).toInt()
    fun panelHeight(expanded: Boolean, density: Float) =
        ((if (expanded) 360 else 132) * PANEL_SCALE * density).toInt()
}
