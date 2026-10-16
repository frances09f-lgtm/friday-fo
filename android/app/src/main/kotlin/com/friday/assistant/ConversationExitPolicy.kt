package com.friday.assistant

/** Allows navigation back out of an observed WhatsApp conversation only.
 * No recipient text is stored; the service still checks package/token/lock.
 */
object ConversationExitPolicy {
 fun permits(pkg:String, workflow:String, header:Boolean, composer:Boolean,
             protectedPrompt:Boolean):Boolean =
  pkg=="com.whatsapp" && workflow in setOf("contact","search") &&
  header && composer && !protectedPrompt
}
