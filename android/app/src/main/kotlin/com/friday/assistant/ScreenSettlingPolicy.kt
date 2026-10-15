package com.friday.assistant

/** Pure policy; stores no screen text and grants no action authority. */
object ScreenSettlingPolicy {
 fun settled(now:Long, started:Long, lastEvent:Long):Boolean =
  now-started>=220 && now-lastEvent>=180
 fun scrollDirection(deltaY:Int, oldY:Int?, newY:Int, oldIndex:Int?, newIndex:Int):String {
  val delta=when {
   deltaY!=0 -> deltaY
   oldY!=null && newY>=0 && oldY>=0 -> newY-oldY
   oldIndex!=null && newIndex>=0 && oldIndex>=0 -> newIndex-oldIndex
   else -> 0
  }
  return if(delta>0)"down" else if(delta<0)"up" else "unknown"
 }
}
