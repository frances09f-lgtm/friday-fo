package com.friday.assistant

/** Explicit, call-only aliases. Persistence is injected so the safety rules are JVM-testable. */
data class SavedContactMatch(val alias: String, val endpoint: ContactEndpoint)
interface ContactMatchStorage {
    fun read(): List<SavedContactMatch>
    fun write(matches: List<SavedContactMatch>): Boolean
}
class SavedContactMatches(private val storage: ContactMatchStorage) {
    fun all(): List<SavedContactMatch> = storage.read()
    fun has(query: String) = all().any { it.alias == ContactNameMatcher.normalize(query) }
    fun forget(alias: String): Boolean = storage.write(all().filterNot { it.alias == ContactNameMatcher.normalize(alias) })
    fun resolve(query: String, rows: List<ContactEndpoint>, operation: RecipientOperation): ContactEndpoint? {
        if (operation != RecipientOperation.CALL) return null // Never expands to a messaging permission.
        val key = ContactNameMatcher.normalize(query)
        val records = all().filter { it.alias == key }
        if (records.size != 1) return null
        val saved = records.single().endpoint
        if (!valid(key, saved, rows)) return null
        return rows.firstOrNull { it == saved }
    }
    private fun valid(alias: String, endpoint: ContactEndpoint, rows: List<ContactEndpoint>): Boolean {
        if (alias.isBlank() || endpoint.contactId.isBlank() || endpoint.lookupKey.isBlank()) return false
        val sameIdentity = rows.filter { it.contactId == endpoint.contactId && it.lookupKey == endpoint.lookupKey }
        // Added/changed numbers, renamed or deleted contacts all require fresh consent.
        val numbers = sameIdentity.map { ContactNameMatcher.numberKey(it.number) }.distinct()
        if (numbers != listOf(ContactNameMatcher.numberKey(endpoint.number)) || endpoint !in sameIdentity) return false
        // An alias newly belonging to a different contact must not override that contact.
        if (rows.any { ContactNameMatcher.normalize(it.name) == alias &&
            (it.contactId != endpoint.contactId || it.lookupKey != endpoint.lookupKey) }) return false
        // Shared phone endpoints across identities are also ambiguous.
        return rows.none { ContactNameMatcher.numberKey(it.number) == ContactNameMatcher.numberKey(endpoint.number) &&
            (it.contactId != endpoint.contactId || it.lookupKey != endpoint.lookupKey) }
    }
    fun remember(query: String, endpoint: ContactEndpoint, rows: List<ContactEndpoint>,
                 operation: RecipientOperation, explicitlyChecked: Boolean, confirmed: Boolean): Boolean {
        if (!explicitlyChecked || !confirmed || operation != RecipientOperation.CALL) return false
        val key=ContactNameMatcher.normalize(query)
        if (!valid(key,endpoint,rows)) return false
        val existing=all().filter { it.alias == key }
        // Do not replace conflicting saved people implicitly. Forget the old match first.
        if (existing.any { it.endpoint != endpoint }) return false
        return storage.write(all().filterNot { it.alias == key } + SavedContactMatch(key,endpoint))
    }
}
