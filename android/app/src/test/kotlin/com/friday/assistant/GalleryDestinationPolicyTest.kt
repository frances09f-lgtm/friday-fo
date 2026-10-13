package com.friday.assistant
import org.junit.Assert.*
import org.junit.Test
class GalleryDestinationPolicyTest {
 @Test fun selectsOnlyUserChosenGallery(){
  assertEquals(listOf("com.oneplus.gallery"),GalleryDestinationPolicy.uniqueHandlers(listOf("com.oneplus.gallery","com.friday.assistant","com.google.android.apps.photos","com.oneplus.gallery")))
 }
 @Test fun noDefaultOrOtherOemSubstitution(){
  assertTrue(GalleryDestinationPolicy.uniqueHandlers(listOf("com.coloros.gallery3d","com.sec.android.app.gallery")).isEmpty())
 }
}
