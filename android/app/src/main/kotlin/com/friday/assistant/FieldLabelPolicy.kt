package com.friday.assistant

/** Empty accessibility descriptions must not hide an observed visible label. */
object FieldLabelPolicy {
 fun primary(description:String?, text:String?):String =
  description?.trim()?.takeIf{it.isNotEmpty()} ?: text?.trim().orEmpty()
}
