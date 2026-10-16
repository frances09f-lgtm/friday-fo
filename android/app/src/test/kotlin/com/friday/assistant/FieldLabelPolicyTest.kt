package com.friday.assistant

import org.junit.Assert.assertEquals
import org.junit.Test

class FieldLabelPolicyTest {
 @Test fun emptyDescriptionUsesObservedText(){ assertEquals("Send",FieldLabelPolicy.primary("","Send")) }
 @Test fun blankDescriptionUsesObservedText(){ assertEquals("Search",FieldLabelPolicy.primary("  "," Search ")) }
 @Test fun realDescriptionStillWins(){ assertEquals("Delete",FieldLabelPolicy.primary("Delete","Send")) }
 @Test fun absentLabelsStayAbsent(){ assertEquals("",FieldLabelPolicy.primary(null,null)) }
}
