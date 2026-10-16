package com.friday.assistant
import org.junit.Assert.*
import org.junit.Test
class ConversationExitPolicyTest {
 @Test fun exactConversationCanExit() {for(flow in listOf("contact","search")) assertTrue(ConversationExitPolicy.permits("com.whatsapp",flow,true,true,false))}
 @Test fun wrongAppCannotExit() {assertFalse(ConversationExitPolicy.permits("com.android.settings","contact",true,true,false))}
 @Test fun wrongWorkflowCannotExit() {assertFalse(ConversationExitPolicy.permits("com.whatsapp","question",true,true,false))}
 @Test fun partialEvidenceCannotExit() {for(pair in listOf(false to true,true to false,false to false)) assertFalse(ConversationExitPolicy.permits("com.whatsapp","contact",pair.first,pair.second,false))}
 @Test fun promptCannotExit() {assertFalse(ConversationExitPolicy.permits("com.whatsapp","contact",true,true,true))}
}
