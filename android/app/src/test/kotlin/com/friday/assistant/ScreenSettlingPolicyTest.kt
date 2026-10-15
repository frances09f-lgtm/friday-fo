package com.friday.assistant
import org.junit.Assert.*
import org.junit.Test
class ScreenSettlingPolicyTest {
 @Test fun quietWindowMustFollowMinimumObservationTime(){
  assertFalse(ScreenSettlingPolicy.settled(100,0,0))
  assertFalse(ScreenSettlingPolicy.settled(400,0,300))
  assertTrue(ScreenSettlingPolicy.settled(500,0,300))
 }
 @Test fun loadingEventsKeepWindowUnsettled(){
  for(now in 300L..1500L step 100)assertFalse(ScreenSettlingPolicy.settled(now,0,now-50))
 }
 @Test fun scrollNeedsActualDirectionNotAnUnrelatedEvent(){
  assertEquals("unknown",ScreenSettlingPolicy.scrollDirection(0,null,-1,null,-1))
  assertEquals("unknown",ScreenSettlingPolicy.scrollDirection(0,100,100,1,1))
  assertEquals("down",ScreenSettlingPolicy.scrollDirection(40,null,-1,null,-1))
  assertEquals("up",ScreenSettlingPolicy.scrollDirection(-40,null,-1,null,-1))
  assertEquals("down",ScreenSettlingPolicy.scrollDirection(0,20,40,null,-1))
  assertEquals("up",ScreenSettlingPolicy.scrollDirection(0,null,-1,4,2))
 }
}
