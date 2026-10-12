// Adapted from user-authorized Abhijeet724/Operator commit9a03ef22 GalleryPlayer.kt.
package com.friday.assistant

import android.content.ContentUris
import android.content.Context
import android.os.Build
import android.provider.MediaStore

class GalleryPlayer(private val context: Context) {

    /**
     * Plays the Nth video from the gallery (1-based, most-recent-first).
     *
     * Queries MediaStore for videos sorted by DATE_ADDED DESC and launches
     * an ACTION_VIEW intent for the video at [index]. Returns a result map
     * for the MethodChannel.
     */
    fun selectVideoAt(index: Int?): Map<String, Any?> {
        if(index==null || index !in 1..50) return errorMap("INVALID_REQUEST", "Video number must be 1 to 50.")
        val safeIndex = index

        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            @Suppress("DEPRECATION") MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

        val projection = arrayOf(
            MediaStore.Video.Media._ID,
            MediaStore.Video.Media.DISPLAY_NAME
        )
        val sortOrder = "${MediaStore.Video.Media.DATE_ADDED} DESC, ${MediaStore.Video.Media._ID} DESC"

        try {
            val cursor = context.contentResolver.query(
                collection,
                projection,
                null,
                null,
                sortOrder
            ) ?: return errorMap("ACCESS_FAILED", "Could not query gallery videos.")

            cursor.use {
                val idColumn = it.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                

                var position = 0
                var targetId: Long? = null
                
                while (it.moveToNext()) {
                    position++
                    if (position == safeIndex) {
                        targetId = it.getLong(idColumn)
                        
                        break
                    }
                }

                if (targetId == null) {
                    return mapOf(
                        "success" to false,
                        "status" to "VIDEO_NOT_FOUND",
                        "errorMessage" to "Only found $position video(s); no video #$safeIndex."
                    )
                }

                val contentUri = ContentUris.withAppendedId(collection, targetId)
                return mapOf("success" to true,"status" to "SELECTED","uri" to contentUri.toString())
            }
        } catch (e: SecurityException) {
            return errorMap(
                "PERMISSION_DENIED",
                "Gallery permission is required to play videos. Please grant media access in settings."
            )
        } catch (e: Exception) {
            return errorMap("ACCESS_FAILED", e.localizedMessage ?: "Could not open gallery videos.")
        }
    }

    private fun errorMap(status: String, msg: String): Map<String, Any?> = mapOf(
        "success" to false,
        "status" to status,
        "errorMessage" to msg
    )
}
