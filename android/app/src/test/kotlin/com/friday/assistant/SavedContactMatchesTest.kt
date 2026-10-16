package com.friday.assistant

import org.junit.Assert.*
import org.junit.Test

class SavedContactMatchesTest {
    private val aditya = ContactEndpoint("42", "stable-42", "Aditya Sutar", "+919000000001")
    private val rows = listOf(aditya)
    private val alias = "Aditya Suthar"
    private class Store : ContactMatchStorage {
        var records = emptyList<SavedContactMatch>()
        var writes = 0
        var available = true
        override fun read() = records.toList()
        override fun write(matches: List<SavedContactMatch>): Boolean {
            if (!available) return false
            writes++; records = matches.toList(); return true
        }
    }
    private fun saved(store: Store = Store()): Pair<Store,SavedContactMatches> {
        val sut = SavedContactMatches(store)
        assertTrue(sut.remember(alias,aditya,rows,RecipientOperation.CALL,true,true))
        return store to sut
    }
    @Test fun uncheckedConfirmationDoesNotRemember() {
        val st=Store(); val sut=SavedContactMatches(st)
        assertFalse(sut.remember(alias,aditya,rows,RecipientOperation.CALL,false,true))
        assertNull(sut.resolve(alias,rows,RecipientOperation.CALL)); assertEquals(0,st.writes)
    }
    @Test fun cancelledCheckedDialogDoesNotRemember() {
        val st=Store(); val sut=SavedContactMatches(st)
        assertFalse(sut.remember(alias,aditya,rows,RecipientOperation.CALL,true,false))
        assertEquals(0,st.writes)
    }
    @Test fun explicitOptInCanBeReusedRepeatedly() {
        val (_,sut)=saved()
        repeat(3) { assertEquals(aditya,sut.resolve(alias,rows,RecipientOperation.CALL)) }
    }
    @Test fun recreatingManagerReadsPersistedMatch() {
        val (store,_)=saved()
        assertEquals(aditya,SavedContactMatches(store).resolve(alias,rows,RecipientOperation.CALL))
    }
    @Test fun normalizedAliasCanBeUsedButNearbyAliasIsNotLearned() {
        val (_,sut)=saved()
        assertEquals(aditya,sut.resolve("  ADITYA   SUTHAR! ",rows,RecipientOperation.CALL))
        assertNull(sut.resolve("Aditya Suther",rows,RecipientOperation.CALL))
        assertEquals(1,sut.all().size)
    }
    @Test fun whatsappCannotSaveOrUseCallAlias() {
        val (_,sut)=saved()
        assertNull(sut.resolve(alias,rows,RecipientOperation.WHATSAPP_DRAFT))
        assertFalse(sut.remember("other",aditya,rows,RecipientOperation.WHATSAPP_DRAFT,true,true))
        assertEquals(1,sut.all().size)
    }
    @Test fun deletedContactCannotBeReplacedByAnotherPerson() {
        val (_,sut)=saved()
        assertNull(sut.resolve(alias,emptyList(),RecipientOperation.CALL))
        assertNull(sut.resolve(alias,listOf(aditya.copy(contactId="99",lookupKey="stable-99")),RecipientOperation.CALL))
    }
    @Test fun renumberedContactRequiresFreshChoice() {
        val (_,sut)=saved()
        assertNull(sut.resolve(alias,listOf(aditya.copy(number="+919000000002")),RecipientOperation.CALL))
    }
    @Test fun additionalNumberRequiresFreshChoice() {
        val (_,sut)=saved()
        assertNull(sut.resolve(alias,rows+aditya.copy(number="+919000000002"),RecipientOperation.CALL))
    }
    @Test fun changedLookupKeyOrNameRequiresFreshChoice() {
        val (_,sut)=saved()
        assertNull(sut.resolve(alias,listOf(aditya.copy(lookupKey="new")),RecipientOperation.CALL))
        assertNull(sut.resolve(alias,listOf(aditya.copy(name="Different person")),RecipientOperation.CALL))
    }
    @Test fun aliasNowBelongingToDifferentExactNameIsConflict() {
        val (_,sut)=saved()
        assertNull(sut.resolve(alias,rows+aditya.copy(contactId="88",lookupKey="key88",name=alias,number="+919000000002"),RecipientOperation.CALL))
    }
    @Test fun sharedNumberAndDuplicateAliasRecordsAreAmbiguous() {
        val (st,sut)=saved()
        assertNull(sut.resolve(alias,rows+aditya.copy(contactId="88",lookupKey="88"),RecipientOperation.CALL))
        st.records=st.records+st.records
        assertNull(sut.resolve(alias,rows,RecipientOperation.CALL))
    }
    @Test fun conflictingSavedPersonCannotBeSilentlyOverwritten() {
        val (_,sut)=saved()
        val other=aditya.copy(contactId="90",lookupKey="90",number="+919000000002")
        assertFalse(sut.remember(alias,other,listOf(other),RecipientOperation.CALL,true,true))
        assertEquals(aditya,sut.all().single().endpoint)
    }
    @Test fun multiNumberContactCannotBeSavedForDirectReuse() {
        val sut=SavedContactMatches(Store())
        assertFalse(sut.remember(alias,aditya,rows+aditya.copy(number="+919000000002"),RecipientOperation.CALL,true,true))
    }
    @Test fun forgetPersistsAndAllowsNewExplicitChoice() {
        val (st,sut)=saved()
        assertTrue(sut.forget(" ADITYA SUTHAR "))
        assertNull(SavedContactMatches(st).resolve(alias,rows,RecipientOperation.CALL))
        assertTrue(sut.remember(alias,aditya,rows,RecipientOperation.CALL,true,true))
    }
    @Test fun failedStorageWriteDoesNotClaimSavedMatch() {
        val st=Store(); st.available=false
        val sut=SavedContactMatches(st)
        assertFalse(sut.remember(alias,aditya,rows,RecipientOperation.CALL,true,true))
        assertNull(sut.resolve(alias,rows,RecipientOperation.CALL))
    }
}
