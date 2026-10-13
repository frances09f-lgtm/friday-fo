package com.friday.assistant

/** User selected OnePlus Gallery, never a generic default video player. */
object GalleryDestinationPolicy {
 const val ONEPLUS="com.oneplus.gallery"
 fun allowed(packageName:String)=packageName==ONEPLUS
 fun uniqueHandlers(packages:List<String>)=packages.filter(::allowed).distinct()
}
