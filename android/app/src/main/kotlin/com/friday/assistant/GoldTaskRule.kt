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

    /**
     * A "cross" alert was made with no quote to compare with ("tell me when
     * gold hits 4000" before Sona had a price). The first fresh quote fixes
     * the side: below the target waits for gold to rise above it, above
     * waits for it to fall below. Null while there is no fresh valid quote
     * (or the quote sits exactly on the target).
     */
    fun resolveCross(threshold: Double, mid: Double, quoteAt: Long, now: Long, maxAgeMs: Long): String? {
        if (!threshold.isFinite() || threshold <= 0 || !mid.isFinite() || mid <= 0) return null
        if (quoteAt <= 0 || quoteAt > now || now - quoteAt > maxAgeMs) return null
        return when {
            mid < threshold -> "above"
            mid > threshold -> "below"
            else -> null
        }
    }
}
