package com.friday.assistant
/** Only the production BitChord identity is the user's selected music player. */
object BitChordPolicy {
 const val PACKAGE = "com.music.bitchord"
 fun accepts(packageName:String):Boolean = packageName == PACKAGE
}
