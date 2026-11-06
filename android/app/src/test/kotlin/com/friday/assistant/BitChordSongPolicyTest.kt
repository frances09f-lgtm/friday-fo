package com.friday.assistant
import org.junit.Assert.*
import org.junit.Test
class BitChordSongPolicyTest {
 private val a=BitChordSongPolicy.Song("a","Tum Ho","Mohit Chauhan")
 private val b=BitChordSongPolicy.Song("b","Tum Ho","Other Singer")
 @Test fun uniqueTitleOnly(){assertEquals(a,BitChordSongPolicy.select("tum ho",listOf(a),true))}
 @Test fun ambiguousNoFirstHit(){assertNull(BitChordSongPolicy.select("Tum Ho",listOf(a,b),true))}
 @Test fun namedArtist(){assertEquals(a,BitChordSongPolicy.select("Tum Ho by Mohit Chauhan",listOf(a,b),true))}
 @Test fun incompleteNeverProvesUnique(){assertNull(BitChordSongPolicy.select("Tum Ho",listOf(a),false))}
 @Test fun suffixAndWrongArtistNeverMatch(){assertNull(BitChordSongPolicy.select("Tum Ho",listOf(a.copy(title="Tum Ho remix")),true));assertNull(BitChordSongPolicy.select("Tum Ho by Somebody",listOf(a),true))}
 @Test fun duplicateIDNotAmbiguity(){assertEquals(a,BitChordSongPolicy.select("Tum Ho",listOf(a,a),true))}
}
