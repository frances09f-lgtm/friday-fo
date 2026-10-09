package com.friday.assistant
import org.junit.Assert.*
import org.junit.Test
class SpotifyObservationTest {
 @Test fun changedTrack(){assertTrue(SpotifyObservation.trackChanged("spotify:track:a","spotify:track:b"))}
 @Test fun sameTrackOrRestartIsNotSkipProof(){assertFalse(SpotifyObservation.trackChanged("a","a"))}
 @Test fun missingMetadataNeverCounts(){
  assertFalse(SpotifyObservation.trackChanged(null,"b"));assertFalse(SpotifyObservation.trackChanged("a",null));assertFalse(SpotifyObservation.trackChanged(null,null));assertFalse(SpotifyObservation.trackChanged("","b"));assertFalse(SpotifyObservation.trackChanged("a"," "))
 }
}
