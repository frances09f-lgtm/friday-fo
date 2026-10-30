package com.friday.assistant
import org.junit.Assert.assertEquals
import org.junit.Test
class GoldTaskRuleTest {
    private fun rule(dir: String = "below", threshold: Double = 4150.0, bid: Double = 4148.0,
        ask: Double = 4150.0, at: Long = 990000, last: Long = 0, now: Long = 1000000) =
        GoldTaskRule.evaluate(dir, threshold, bid, ask, at, last, now, 300000)
    @Test fun thresholdAndSpread() {
        assertEquals("triggered", rule())
        assertEquals("not_met", rule(bid = 4150.0, ask = 4150.0))
        assertEquals("triggered", rule(dir = "above", bid = 4150.0, ask = 4152.0))
    }
    @Test fun freshnessAndDedupe() {
        assertEquals("stale_quote", rule(at=0))
        assertEquals("stale_quote", rule(at=1000001))
        assertEquals("stale_quote", rule(at=699999))
        assertEquals("same_quote", rule(last=990000))
        assertEquals("same_quote", rule(last=995000))
    }
    @Test fun invalidDataCannotAlert() {
        assertEquals("invalid_quote", rule(bid=Double.NaN))
        assertEquals("invalid_quote", rule(ask=Double.POSITIVE_INFINITY))
        assertEquals("invalid_quote", rule(bid=4152.0,ask=4150.0))
        assertEquals("invalid_quote", rule(threshold=0.0))
        assertEquals("invalid_condition", rule(dir="buy"))
    }
    @Test fun crossAlertTakesItsSideFromTheFirstFreshQuote() {
        // Below the target: wait for gold to rise above it.
        assertEquals("above", GoldTaskRule.resolveCross(4000.0, 3962.5, 990000, 1000000, 300000))
        // Above the target: wait for it to fall below.
        assertEquals("below", GoldTaskRule.resolveCross(4000.0, 4031.0, 990000, 1000000, 300000))
        // No fresh valid quote yet, or exactly on the target: keep waiting.
        assertEquals(null, GoldTaskRule.resolveCross(4000.0, 3962.5, 0, 1000000, 300000))
        assertEquals(null, GoldTaskRule.resolveCross(4000.0, 3962.5, 600000, 1000000, 300000))
        assertEquals(null, GoldTaskRule.resolveCross(4000.0, Double.NaN, 990000, 1000000, 300000))
        assertEquals(null, GoldTaskRule.resolveCross(4000.0, 4000.0, 990000, 1000000, 300000))
    }
}
