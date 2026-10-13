package com.friday.assistant

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri

/** Validate installed handler before a package-bound VIEW. No substitute player. */
object OnePlusGalleryDispatch {
 fun open(context:Context,uri:Uri):Map<String,Any> {
  if(uri.scheme!="content"||uri.authority!="media") return failed("Invalid local video URI. No player opened.")
  val pkg=GalleryDestinationPolicy.ONEPLUS
  try {context.packageManager.getApplicationInfo(pkg,0)}
  catch(_:Exception){return failed("OnePlus Gallery (com.oneplus.gallery) was not found. Send its App info package name; no other player was opened.")}
  val intent=Intent(Intent.ACTION_VIEW).apply{
   setDataAndType(uri,"video/*");setPackage(pkg)
   addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
  }
  val handlers=context.packageManager.queryIntentActivities(intent,PackageManager.MATCH_DEFAULT_ONLY)
  val destinations=GalleryDestinationPolicy.uniqueHandlers(handlers.map{it.activityInfo.packageName})
  if(destinations.size!=1)return failed("Installed OnePlus Gallery does not expose a unique video-view handler. Open this video there manually or send its App info; no other player was opened.")
  return try {
   context.startActivity(intent)
   mapOf("success" to true,"status" to "GALLERY_DISPATCHED","package" to pkg)
  }catch(_:Exception){failed("OnePlus Gallery refused this video-view request. No alternate player was opened.")}
 }
 private fun failed(message:String):Map<String,Any> = mapOf("success" to false,"status" to "DESTINATION_REQUIRED","errorMessage" to message)
}
