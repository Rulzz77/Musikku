package com.music.bitchord.data.listentogether

import android.content.Intent
import com.music.bitchord.BuildConfig
import java.net.InetAddress
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder

data class ParsedJamInvite(
    val code: String,
    val serverUrl: String? = null,
)

/** Relays a BitChord web or scheme invite from [com.music.bitchord.MainActivity] to Compose. */
object JamInviteLink {

    const val ORIGIN = "https://bitchord.kushagrasingh.in"

    private const val EXTRA_CONSUMED = "bitchord.jamInviteConsumed"
    private const val HOST = "bitchord.kushagrasingh.in"
    private const val CUSTOM_SCHEME = "bitchord"
    private const val CUSTOM_HOST = "party"

    private val _pending = MutableStateFlow<ParsedJamInvite?>(null)
    val pending: StateFlow<ParsedJamInvite?> = _pending.asStateFlow()

    /** Reads a web invite from a cold launch or a new intent on the existing task. */
    fun consume(intent: Intent?): Boolean {
        if (
            intent == null ||
            intent.action != Intent.ACTION_VIEW ||
            intent.getBooleanExtra(EXTRA_CONSUMED, false)
        ) return false

        val invite = parseInvite(intent.dataString) ?: return false
        intent.putExtra(EXTRA_CONSUMED, true)
        _pending.value = invite
        return true
    }

    fun handled() {
        _pending.value = null
    }

    /** Returns the normalized party code only for the public invite URL shape. */
    fun parse(value: String?): String? = parseInvite(value)?.code

    /**
     * Parses an incoming invite:
     * 1. bitchord://party/<CODE>?server=<SERVER>
     * 2. https://bitchord.kushagrasingh.in/invite/<CODE>?server=<SERVER>
     */
    fun parseInvite(value: String?): ParsedJamInvite? {
        val uri = runCatching { URI(value ?: return null) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase() ?: return null
        val host = uri.host?.lowercase() ?: return null
        // Reject user-info even on custom-scheme links; it has no legitimate
        // meaning here and can make a copied invite visually misleading.
        if (uri.rawUserInfo != null) return null
        val query = uri.rawQuery
        val rawServer = extractQueryParam(query, "server")
        val server = rawServer?.let { sanitizeServerUrl(it) }
        if (rawServer != null && server == null) return null

        // 1. Custom scheme: bitchord://party/<CODE> or bitchord://party?code=<CODE>
        if (scheme == CUSTOM_SCHEME && host == CUSTOM_HOST) {
            val pathPart = uri.path.orEmpty().trim('/').takeIf { it.isNotBlank() }
            val candidate = pathPart ?: extractQueryParam(query, "code") ?: return null
            val code = cleanCode(candidate) ?: return null
            return ParsedJamInvite(code = code, serverUrl = server)
        }

        // 2. Web invite. The official host uses the configured fallback unless
        // an explicit server parameter is present. Custom servers generate the
        // same /invite/<CODE> suffix, so the scanner can recover their base URL
        // instead of accidentally trying to join that code on the default host.
        if (scheme != "https" && scheme != "http") return null
        if (host == HOST && scheme != "https") return null

        val match = INVITE_PATH.matchEntire(uri.path.orEmpty()) ?: return null
        val code = match.groupValues[2].uppercase()
        val basePath = match.groupValues[1].trimEnd('/')

        if (host == HOST && basePath.isEmpty()) {
            return ParsedJamInvite(code = code, serverUrl = server)
        }

        val authority = uri.rawAuthority ?: return null
        val inferredServer = sanitizeServerUrl("$scheme://$authority$basePath") ?: return null
        return ParsedJamInvite(code = code, serverUrl = server ?: inferredServer)
    }

    fun url(code: String, customServer: String? = null): String {
        val base = customServer?.trim()?.trimEnd('/')
        return if (!base.isNullOrBlank() && !base.equals(ORIGIN, ignoreCase = true)) {
            "$base/invite/${code.uppercase()}"
        } else {
            "$ORIGIN/invite/${code.uppercase()}"
        }
    }

    fun schemeUrl(code: String, customServer: String? = null): String {
        val normalizedCode = code.uppercase()
        val base = customServer?.trim()?.trimEnd('/')
        return if (!base.isNullOrBlank()) {
            val encoded = runCatching { URLEncoder.encode(base, "UTF-8") }.getOrDefault(base)
            "bitchord://party/$normalizedCode?server=$encoded"
        } else {
            "bitchord://party/$normalizedCode"
        }
    }

    private fun cleanCode(raw: String): String? {
        val cleaned = raw.filter { it.isLetterOrDigit() }.uppercase()
        return if (cleaned.length == ListenTogether.CODE_LENGTH) cleaned else null
    }

    private fun extractQueryParam(query: String?, paramName: String): String? {
        if (query.isNullOrBlank()) return null
        return query.split('&').asSequence()
            .map { it.split('=', limit = 2) }
            .firstOrNull { it.isNotEmpty() && it[0].equals(paramName, ignoreCase = true) }
            ?.getOrNull(1)
            ?.let { runCatching { URLDecoder.decode(it, "UTF-8") }.getOrDefault(it) }
    }

    /**
     * Use the exact same URL policy as the server settings field. Invite
     * parameters are untrusted input: reject unsupported schemes, user-info,
     * query/fragment-bearing base URLs, invalid ports and malformed paths
     * before the URL can reach the party transport.
     *
     * Production builds additionally refuse loopback/LAN/special-use
     * destinations. Debug builds can still use local party servers for
     * development and device testing.
     */
    internal fun sanitizeServerUrl(
        raw: String?,
        allowLocal: Boolean = BuildConfig.DEBUG,
    ): String? {
        val trimmed = raw?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() } ?: return null
        val normalized = when (
            val result = ListenTogether.parseAndNormalizeServerUrl(
                trimmed,
                allowCleartext = allowLocal,
            )
        ) {
            is ServerUrlValidationResult.Valid -> result.normalizedUrl
            is ServerUrlValidationResult.Invalid -> return null
        }
        val uri = runCatching { URI(normalized) }.getOrNull() ?: return null
        if (uri.rawUserInfo != null) return null
        val host = uri.host?.takeIf { it.isNotBlank() } ?: return null
        if (isMulticastOrUnspecifiedHost(host)) return null
        if (!allowLocal && isPrivateOrSpecialHost(host)) return null
        return normalized
    }

    private fun isMulticastOrUnspecifiedHost(rawHost: String): Boolean {
        val host = rawHost.removePrefix("[").removeSuffix("]").lowercase().trimEnd('.')
        if (host.contains(':') || host.matches(NUMERIC_HOST)) {
            val address = runCatching { InetAddress.getByName(host) }.getOrNull() ?: return false
            return address.isAnyLocalAddress || address.isMulticastAddress
        }
        return false
    }

    private fun isPrivateOrSpecialHost(rawHost: String): Boolean {
        val host = rawHost.removePrefix("[").removeSuffix("]").lowercase().trimEnd('.')
        if (
            host == "localhost" || host.endsWith(".localhost") ||
            host.endsWith(".local") || host.endsWith(".lan") ||
            host.endsWith(".internal") || host.endsWith(".home")
        ) return true

        if (!host.contains(':') && !host.matches(NUMERIC_HOST)) return false
        val address = runCatching { InetAddress.getByName(host) }.getOrNull() ?: return true
        if (
            address.isLoopbackAddress || address.isLinkLocalAddress ||
            address.isSiteLocalAddress || address.isAnyLocalAddress
        ) return true

        val bytes = address.address.map { it.toInt() and 0xff }
        if (bytes.size == 16) {
            // IPv6 unique-local and documentation-only ranges.
            return (bytes[0] and 0xfe) == 0xfc ||
                (bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8)
        }
        if (bytes.size != 4) return true
        val a = bytes[0]
        val b = bytes[1]
        val c = bytes[2]
        return a == 0 || a == 10 || a == 127 || a >= 224 ||
            (a == 100 && b in 64..127) ||
            (a == 169 && b == 254) ||
            (a == 172 && b in 16..31) ||
            (a == 192 && ((b == 0 && (c == 0 || c == 2)) || b == 168 || (b == 88 && c == 99))) ||
            (a == 198 && (b in 18..19 || (b == 51 && c == 100))) ||
            (a == 203 && b == 0 && c == 113)
    }

    private val NUMERIC_HOST = Regex("""(?i)^(?:0x[0-9a-f]+|[0-9]+)(?:\.(?:0x[0-9a-f]+|[0-9]+))*$""")

    private val INVITE_PATH = Regex("""^(.*)/invite/([A-Za-z0-9]{${ListenTogether.CODE_LENGTH}})$""")
}

