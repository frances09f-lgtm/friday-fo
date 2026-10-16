package com.friday.assistant

import java.text.Normalizer
import java.util.Locale

/** Local-only identity and immutable phone endpoint. Never dedupe different people by name. */
data class ContactEndpoint(val contactId: String, val lookupKey: String, val name: String, val number: String)
enum class RecipientOperation { CALL, WHATSAPP_DRAFT }
data class RecipientRequest(val operation: RecipientOperation, val query: String, val body: String = "")
data class RecipientResolution(val candidates: List<ContactEndpoint>, val exactUnique: Boolean)

object ContactNameMatcher {
    fun normalize(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFKD)
        .replace(Regex("\\p{M}+"), "").lowercase(Locale.ROOT)
        .replace(Regex("[^\\p{L}\\p{N}]+"), " ").trim().replace(Regex("\\s+"), " ")
    fun numberKey(value: String): String = value.filter { it.isDigit() || it == '+' }
    // Preserve the existing local-number convention, but display this actual destination
    // before confirming any suggested/ambiguous WhatsApp recipient.
    fun whatsAppDigits(number: String): String {
        val digits = number.filter { it.isDigit() }
        return if (digits.length == 10) "91$digits" else digits
    }

    fun resolve(query: String, rows: List<ContactEndpoint>): RecipientResolution {
        val wanted = normalize(query)
        if (wanted.isBlank()) return RecipientResolution(emptyList(), false)
        val endpoints = rows.filter { it.contactId.isNotBlank() && it.lookupKey.isNotBlank() &&
            it.name.isNotBlank() && it.number.matches(Regex("[+0-9][0-9 ()-]{4,}")) }
            .distinctBy { Triple(it.contactId, it.lookupKey, numberKey(it.number)) }
        val exact = endpoints.filter { normalize(it.name) == wanted }
        if (exact.isNotEmpty()) return RecipientResolution(exact.sortedWith(order), exact.size == 1)
        val ranked = endpoints.mapNotNull { endpoint -> score(wanted, normalize(endpoint.name))?.let { it to endpoint } }
            .sortedWith(compareBy<Pair<Int, ContactEndpoint>> { it.first }.thenBy { normalize(it.second.name) }
                .thenBy { it.second.contactId }.thenBy { numberKey(it.second.number) })
        // Do not silently truncate ambiguities into a single result.
        return RecipientResolution(ranked.map { it.second }, false)
    }
    private val order = compareBy<ContactEndpoint> { normalize(it.name) }.thenBy { it.contactId }.thenBy { numberKey(it.number) }
    private fun score(query: String, name: String): Int? {
        val q = query.split(' '); val n = name.split(' ')
        // A partial but correctly spelled name is still a suggestion, never an automatic call.
        if (q.all { it.length >= 3 } && q.size < n.size && q.all { token -> n.count { it == token } == 1 }) return 10
        if (q.size != n.size) return null
        var changes = 0
        for (i in q.indices) {
            if (q[i] == n[i]) continue
            if (q[i].length < 4 || n[i].length < 4 || q[i].first() != n[i].first()) return null
            val distance = distance(q[i], n[i])
            if (distance > 1) return null
            changes += distance
        }
        return if (changes == 1) changes else null
    }
    private fun distance(a: String, b: String): Int {
        var previous = IntArray(b.length + 1) { it }
        for (i in a.indices) {
            val next = IntArray(b.length + 1); next[0] = i + 1
            for (j in b.indices) next[j + 1] = minOf(next[j] + 1, previous[j + 1] + 1,
                previous[j] + if (a[i] == b[j]) 0 else 1)
            previous = next
        }
        return previous[b.length]
    }
}

/** A one-use consent bound to the original action/body and exact selected endpoint.
 * The entire candidate set is re-read before dispatch. No number/name changes are followed.
 */
class RecipientConsent(val request: RecipientRequest, private val snapshot: RecipientResolution, private val expiresAt: Long) {
    private var live = true
    private var selected: ContactEndpoint? = null
    fun choose(endpoint: ContactEndpoint, now: Long): Boolean {
        if (!live || now >= expiresAt || endpoint !in snapshot.candidates) return false
        selected = endpoint
        return true
    }
    fun cancel() { live = false; selected = null }
    fun confirm(current: RecipientResolution, now: Long): ContactEndpoint? {
        if (!live) return null
        live = false // consume even failed confirmation; double taps can never repeat an action
        val choice = selected ?: return null
        if (now >= expiresAt || current != snapshot || choice !in current.candidates) return null
        return choice
    }
}
