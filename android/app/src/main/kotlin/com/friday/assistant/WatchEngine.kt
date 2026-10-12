package com.friday.assistant

/** Source adapters supply evidence, never instructions or executable code. */
data class WatchSample(val source: String, val value: Double, val observedAt: Long,
                       val fingerprint: String)
data class WatchDecision(val outcome: String, val changed: Boolean = false,
                         val matched: Boolean = false, val fingerprint: String? = null)

/** Small deterministic core. Model hooks may consume changed samples, but may
 * not override source freshness, conditions, or notification deduplication. */
object WatchEngine {
    fun compare(sample: WatchSample?, previousFingerprint: String, now: Long,
                maxAgeMs: Long, direction: String, threshold: Double, previousObservedAt: Long = 0): WatchDecision {
        if (sample == null) return WatchDecision("source_unavailable")
        if (!sample.value.isFinite() || sample.value <= 0 || sample.source.isBlank() ||
            sample.fingerprint.isBlank()) return WatchDecision("invalid_sample")
        if (sample.observedAt <= 0 || sample.observedAt > now ||
            now - sample.observedAt > maxAgeMs) return WatchDecision("stale_sample")
        if (!threshold.isFinite() || threshold <= 0 || direction !in setOf("above", "below"))
            return WatchDecision("invalid_condition")
        if (sample.observedAt < previousObservedAt) return WatchDecision("out_of_order")
        if (sample.fingerprint == previousFingerprint) return WatchDecision("unchanged")
        val matched = if (direction == "below") sample.value < threshold else sample.value > threshold
        return WatchDecision(if (matched) "triggered" else "not_met", true, matched, sample.fingerprint)
    }
    fun workerInterval(requestedMinutes: Int): Long = requestedMinutes.coerceIn(15, 1440).toLong()
}

interface WatchSource { fun fetch(): WatchSample? }
interface ChangedSampleHandler { fun onChanged(sample: WatchSample) }

/** Optional summaries only see fresh changed evidence. Numeric gold watches
 * pass no handler, keeping both local and cloud models asleep. */
class WatchPipeline(private val source: WatchSource,
                    private val changedHandler: ChangedSampleHandler? = null) {
    fun run(previous: String, now: Long, maxAgeMs: Long,
            direction: String, threshold: Double, previousObservedAt: Long = 0): WatchDecision {
        val sample = source.fetch()
        val decision = WatchEngine.compare(sample, previous, now, maxAgeMs, direction, threshold, previousObservedAt)
        if (decision.changed && sample != null) changedHandler?.onChanged(sample)
        return decision
    }
}
