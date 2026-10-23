package com.friday.assistant

internal object FloatingAssistantSizing {
    const val SCALE = 0.7f
    const val BUBBLE_WIDTH_DP = 72f * SCALE
    const val BUBBLE_HEIGHT_DP = 48f * SCALE
    const val BUBBLE_TEXT_SP = 22f * SCALE
    fun panelWidth(screenWidthPixels: Int) = (screenWidthPixels * SCALE).toInt()
    fun panelHeight(expanded: Boolean, density: Float) =
        ((if (expanded) 360 else 132) * SCALE * density).toInt()
}
