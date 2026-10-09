package com.friday.assistant
/** Only a changed, nonempty observed track identity proves skip completion.
 * Position changes alone can mean a seek or natural playback, not a new track. */
object SpotifyObservation {
 fun trackChanged(before:String?,after:String?):Boolean = !before.isNullOrBlank()&&!after.isNullOrBlank()&&before!=after
}
