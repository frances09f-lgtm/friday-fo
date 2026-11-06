package com.friday.assistant
import org.junit.Assert.*
import org.junit.Test
class BitChordPolicyTest {
 @Test fun acceptsOnlyProductionBitChord(){assertTrue(BitChordPolicy.accepts("com.music.bitchord"))}
 @Test fun neverFallsBackToSpotifyOrDev(){for(p in listOf("com.spotify.music","com.dev.bitchord","com.google.android.apps.youtube.music","","com.music.bitchord.fake"))assertFalse(p,BitChordPolicy.accepts(p))}
}
