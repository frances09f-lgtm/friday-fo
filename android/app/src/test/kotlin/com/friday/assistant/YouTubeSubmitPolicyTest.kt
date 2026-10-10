package com.friday.assistant
import org.junit.Assert.*
import org.junit.Test
class YouTubeSubmitPolicyTest {
 @Test fun onlyFocusedExactYouTubeSearchCanUseKeyboard() {
  assertTrue(YouTubeSubmitPolicy.permits("com.google.android.youtube","search","GTA 6",1,true))
  assertTrue(YouTubeSubmitPolicy.permits("com.google.android.youtube","play","GTA 6",1,true))
  assertFalse(YouTubeSubmitPolicy.permits("com.whatsapp","search","GTA 6",1,true))
  assertFalse(YouTubeSubmitPolicy.permits("com.google.android.youtube","question","GTA 6",1,true))
  assertFalse(YouTubeSubmitPolicy.permits("com.google.android.youtube","search","GTA 6",2,true))
  assertFalse(YouTubeSubmitPolicy.permits("com.google.android.youtube","search","GTA 6",1,false))
  assertFalse(YouTubeSubmitPolicy.permits("com.google.android.youtube","search","",1,true))
 }
 @Test fun onlyExactSearchKeyIsAccepted() {
  assertTrue(YouTubeSubmitPolicy.searchKey("","Search",true,true,false,false))
  assertTrue(YouTubeSubmitPolicy.searchKey("Search","",true,true,false,false))
  for(label in listOf("Send","Enter","Go","Search GTA 6","Clear search","Voice search"))assertFalse(YouTubeSubmitPolicy.searchKey("",label,true,true,false,false))
  assertFalse(YouTubeSubmitPolicy.searchKey("Search","Send",true,true,false,false))
  assertFalse(YouTubeSubmitPolicy.searchKey("","Search",false,true,false,false))
  assertFalse(YouTubeSubmitPolicy.searchKey("","Search",true,false,false,false))
  assertFalse(YouTubeSubmitPolicy.searchKey("","Search",true,true,true,false))
  assertFalse(YouTubeSubmitPolicy.searchKey("","Search",true,true,false,true))
 }
}
