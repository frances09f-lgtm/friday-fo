package com.friday.assistant

import org.junit.Assert.*
import org.junit.Test

class ContactNameMatcherTest {
    private val gaurav = ContactEndpoint("42", "stable-42", "Gaurav Dhavale", "+919000000001")
    private fun resolve(query: String = "gourav dhavale", contacts: List<ContactEndpoint> = listOf(gaurav)) = ContactNameMatcher.resolve(query, contacts)
    private fun consent(op: RecipientOperation = RecipientOperation.CALL, body: String = "") =
        RecipientConsent(RecipientRequest(op, "gourav dhavale", body), resolve(), 100)

    @Test fun whatsappDestinationIsDeterministicAndShownWithoutRewritingBody() {
        assertEquals("919000000001", ContactNameMatcher.whatsAppDigits("90000 00001"))
        assertEquals("449000000001", ContactNameMatcher.whatsAppDigits("+44 90000 00001"))
    }
    @Test fun gouravSuggestsGauravButNeverBecomesExact() {
        val r = resolve(); assertEquals(listOf(gaurav), r.candidates); assertFalse(r.exactUnique)
    }
    @Test fun exactUniquePreservesExistingRoute() { assertTrue(resolve("gaurav dhavale").exactUnique) }
    @Test fun normalizesCaseSpacingAndPunctuation() { assertTrue(resolve("  GAURAV  DHAVALE ").exactUnique) }
    @Test fun unicodeAccentNormalizationIsDeterministic() { assertTrue(resolve("Gauráv Dhavale").exactUnique) }
    @Test fun unicodeNamesCanMatchExactly() {
        val row = gaurav.copy(name = "गौरव धवळे")
        assertTrue(resolve("गौरव धवळे", listOf(row)).exactUnique)
    }
    @Test fun unrelatedNamesProduceNoMatch() { assertTrue(resolve("Rahul Patil").candidates.isEmpty()) }
    @Test fun shortFuzzyNamesAreRejected() { assertTrue(resolve("gor dhavale").candidates.isEmpty()) }
    @Test fun differentInitialNotGuessed() { assertTrue(resolve("saurav dhavale").candidates.isEmpty()) }
    @Test fun emptyQueryNotGuessed() { assertTrue(resolve("  ").candidates.isEmpty()) }
    @Test fun tokenReorderingNotGuessed() { assertTrue(resolve("dhavale gourav").candidates.isEmpty()) }
    @Test fun tiesNeverPickFirst() {
        val other = gaurav.copy(contactId = "43", lookupKey = "stable-43", name = "Gourav Dhavle")
        val r = resolve(contacts = listOf(gaurav, other))
        assertEquals(2, r.candidates.size); assertFalse(r.exactUnique)
    }
    @Test fun duplicateNamesRetainDifferentStableIdentities() {
        val other = gaurav.copy(contactId = "43", lookupKey = "stable-43", number = "+919000000002")
        val r = resolve("gaurav dhavale", listOf(gaurav, other))
        assertEquals(2, r.candidates.size); assertFalse(r.exactUnique)
    }
    @Test fun sharedNumberAcrossPeopleStillNeedsSelection() {
        val other = gaurav.copy(contactId = "43", lookupKey = "stable-43")
        assertEquals(2, resolve("gaurav dhavale", listOf(gaurav, other)).candidates.size)
    }
    @Test fun multipleNumbersRequireSelectionEvenForExactName() {
        val r = resolve("gaurav dhavale", listOf(gaurav, gaurav.copy(number = "+919000000002")))
        assertFalse(r.exactUnique); assertEquals(2, r.candidates.size)
    }
    @Test fun repeatedProviderRowsDedupSameContactEndpoint() {
        assertTrue(resolve("gaurav dhavale", listOf(gaurav, gaurav.copy(number = "+91 90000 00001"))).exactUnique)
    }
    @Test fun exactMatchWinsOverLongerNameButPartialNameDoesNotAutodial() {
        val other = gaurav.copy(contactId = "43", lookupKey = "other", name = "Gaurav Dhavale Work")
        assertEquals(listOf(gaurav), resolve("gaurav dhavale", listOf(other, gaurav)).candidates)
        assertFalse(resolve("gaurav").exactUnique)
    }
    @Test fun noTruncationTurnsAmbiguityIntoUniqueMatch() {
        val contacts = (1..8).map { gaurav.copy(contactId = "$it", lookupKey = "key-$it") }
        assertEquals(8, resolve(contacts = contacts).candidates.size)
    }
    @Test fun malformedNumbersOrMissingStableIdentityExcluded() {
        assertTrue(resolve(contacts = listOf(gaurav.copy(number = "123;send"), gaurav.copy(lookupKey = ""))).candidates.isEmpty())
    }
    @Test fun noSelectionMeansNoCall() { assertNull(consent().confirm(resolve(), 1)) }
    @Test fun selectionAloneDoesNotConsumeOrAuthorizeCall() {
        val c = consent(); assertTrue(c.choose(gaurav, 1)); c.cancel(); assertNull(c.confirm(resolve(), 2))
    }
    @Test fun explicitConfirmationReturnsExactEndpointOnce() {
        val c = consent(); c.choose(gaurav, 1)
        assertEquals(gaurav, c.confirm(resolve(), 2)); assertNull(c.confirm(resolve(), 3))
    }
    @Test fun arbitraryEndpointCannotBeSelected() {
        val c = consent(); assertFalse(c.choose(gaurav.copy(number = "+919000000002"), 1)); assertNull(c.confirm(resolve(), 2))
    }
    @Test fun expiryPreventsSelectionAndConfirmation() {
        val c = consent(); assertFalse(c.choose(gaurav, 100)); assertNull(c.confirm(resolve(), 101))
        val d = consent(); d.choose(gaurav, 1); assertNull(d.confirm(resolve(), 100))
    }
    @Test fun changedNumberInvalidatesConsentRatherThanFollowingNewNumber() {
        val c = consent(); c.choose(gaurav, 1)
        assertNull(c.confirm(resolve(contacts = listOf(gaurav.copy(number = "+919000000002"))), 2))
    }
    @Test fun changedNameLookupOrDeletedContactInvalidatesConsent() {
        for (changed in listOf(gaurav.copy(name = "Gourav Dhavale"), gaurav.copy(lookupKey = "replacement"), gaurav.copy(contactId = "999"))) {
            val c = consent(); c.choose(gaurav, 1); assertNull(c.confirm(resolve(contacts = listOf(changed)), 2))
        }
        val c = consent(); c.choose(gaurav, 1); assertNull(c.confirm(resolve(contacts = emptyList()), 2))
    }
    @Test fun newAmbiguousCandidateRequiresFreshReview() {
        val c = consent(); c.choose(gaurav, 1)
        assertNull(c.confirm(resolve(contacts = listOf(gaurav, gaurav.copy(contactId = "43", lookupKey = "another"))), 2))
    }
    @Test fun candidateOrderDoesNotChangeBoundSelection() {
        val other = gaurav.copy(number = "+919000000002")
        val r = resolve(contacts = listOf(gaurav, other))
        val c = RecipientConsent(RecipientRequest(RecipientOperation.CALL, "gourav dhavale"), r, 100)
        c.choose(other, 1); assertEquals(other, c.confirm(resolve(contacts = listOf(other, gaurav)), 2))
    }
    @Test fun cancelledOrExpiredWhatsAppCannotProduceDraftEndpoint() {
        val c = consent(RecipientOperation.WHATSAPP_DRAFT, "helo"); c.choose(gaurav, 1); c.cancel()
        assertNull(c.confirm(resolve(), 2))
        val d = consent(RecipientOperation.WHATSAPP_DRAFT, "helo"); d.choose(gaurav, 1); assertNull(d.confirm(resolve(), 100))
    }
    @Test fun whatsappConsentBindsOriginalOperationAndVerbatimBody() {
        val body = "  helo Gaurv\nDon't autocorrect this!  "
        val c = consent(RecipientOperation.WHATSAPP_DRAFT, body); c.choose(gaurav, 1)
        assertEquals(gaurav, c.confirm(resolve(), 2))
        assertEquals(RecipientOperation.WHATSAPP_DRAFT, c.request.operation); assertEquals(body, c.request.body)
    }
    @Test fun whatsappNoSelectionNoDraftAndDoubleConfirmCannotRepeat() {
        val c = consent(RecipientOperation.WHATSAPP_DRAFT, "hello")
        assertNull(c.confirm(resolve(), 2))
        val d = consent(RecipientOperation.WHATSAPP_DRAFT, "hello"); d.choose(gaurav, 1)
        assertNotNull(d.confirm(resolve(), 2)); assertNull(d.confirm(resolve(), 3))
    }
}
