package com.friday.assistant
object TaskTiming {
    fun delay(now: Long, dueTimes: List<Long>): Long =
        dueTimes.minOrNull()?.let { (it - now).coerceAtLeast(1000L) } ?: -1L
}
