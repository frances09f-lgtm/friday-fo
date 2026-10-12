package com.friday.assistant
import org.junit.Assert.*
import org.junit.Test
class WatchEngineTest {
    private fun check(value: Double=4200.0, at: Long=1000, previous: String="", direction: String="below") =
        WatchEngine.compare(WatchSample("oro", value, at, value.toString()), previous, 1100, 300000, direction, 4150.0)
    @Test fun unchangedValuesSkipEvenWithFreshTimestamp() { assertEquals("unchanged",check(previous="4200.0").outcome) }
    @Test fun crossingThresholdTriggers() { assertTrue(check(4100.0).matched); assertFalse(check().matched) }
    @Test fun staleAndFutureNeverTrigger() { assertFalse(check(4100.0, -1).matched);assertFalse(check(4100.0,1200).matched) }
    @Test fun invalidValueAndConditionNeverTrigger() {assertFalse(check(Double.NaN).changed);assertFalse(check(4100.0,direction="buy").matched)}
    @Test fun workerIntervalRespectsAndroidFloor() {assertEquals(15L,WatchEngine.workerInterval(5));assertEquals(60L,WatchEngine.workerInterval(60))}
    @Test fun optionalHandlerOnlyRunsOnFreshChange() {
        var calls=0
        val sample=WatchSample("oro",4200.0,1000,"4200")
        val pipeline=WatchPipeline(object:WatchSource {override fun fetch()=sample},
            object:ChangedSampleHandler {override fun onChanged(sample:WatchSample) {calls++}})
        pipeline.run("",1100,300000,"below",4150.0)
        pipeline.run("4200",1100,300000,"below",4150.0)
        pipeline.run("",400000,300000,"below",4150.0)
        assertEquals(1,calls)
    }
    @Test fun olderSourceUpdateCannotTrigger() { assertEquals("out_of_order",
        WatchEngine.compare(WatchSample("oro",4100.0,1000,"4100"),"4200",1100,300000,"below",4150.0,1050).outcome) }
    @Test fun absentSourceCannotTrigger() {assertEquals("source_unavailable",WatchEngine.compare(null,"",1100,300000,"below",4150.0).outcome)}
}
