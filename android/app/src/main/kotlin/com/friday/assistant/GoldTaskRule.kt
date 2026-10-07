package com.friday.assistant

/** Pure evaluation. A snapshot is not a live market feed. */
object GoldTaskRule {
    fun evaluate(direction: String, threshold: Double, bid: Double, ask: Double,
                 quoteAt: Long, previousQuoteAt: Long, now: Long, maxAgeMs: Long): String {
        if (!threshold.isFinite() || threshold <= 0 || !bid.isFinite() || !ask.isFinite() ||
            bid <= 0 || ask <= 0 || ask < bid) return "invalid_quote"
        if (quoteAt <= 0 || quoteAt > now || now - quoteAt > maxAgeMs) return "stale_quote"
        if (quoteAt <= previousQuoteAt) return "same_quote"
        val mid = (bid + ask) / 2
        return when (direction) {
            "below" -> if (mid < threshold) "triggered" else "not_met"
            "above" -> if (mid > threshold) "triggered" else "not_met"
            else -> "invalid_condition"
        }
    }
}
