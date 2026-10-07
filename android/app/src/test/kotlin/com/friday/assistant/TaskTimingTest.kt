package com.friday.assistant
import org.junit.Assert.assertEquals
import org.junit.Test
class TaskTimingTest {
 @Test fun waitsForEarliestTaskNotThirtySecondPolling(){
  assertEquals(300000L, TaskTiming.delay(1000000,listOf(1300000,4600000)))
  assertEquals(3600000L, TaskTiming.delay(1000000,listOf(4600000)))
 }
 @Test fun stopsWhenEmptyAndHandlesOverdueWithoutSpinning(){
  assertEquals(-1L,TaskTiming.delay(1000000,emptyList()))
  assertEquals(1000L,TaskTiming.delay(1000000,listOf(999999)))
 }
}
