package com.music.bitchord.data.listentogether

/**
 * Whether an untrusted party avatar/thumbnail may be handed to the platform
 * image loader. The server also enforces this policy, but clients must defend
 * themselves when joining older or self-hosted servers that have not updated.
 *
 * This is intentionally a syntactic check: image requests are still made
 * directly by the platform, never proxied through the party server.
 */
fun isSafePartyImageUrl(raw: String?): Boolean {
    val value = raw?.trim()?.takeIf { it.isNotEmpty() && it.length <= 4_096 } ?: return false
    if (value.any { it.isWhitespace() || it.code < 0x20 }) return false

    val schemeEnd = value.indexOf("://")
    if (schemeEnd <= 0) return false
    val scheme = value.substring(0, schemeEnd).lowercase()
    if (scheme != "http" && scheme != "https") return false

    val authority = value.substring(schemeEnd + 3).takeWhile { it != '/' && it != '?' && it != '#' }
    if (authority.isEmpty() || '@' in authority || '\\' in authority) return false

    val host: String
    val port: String?
    if (authority.startsWith("[")) {
        val close = authority.indexOf(']')
        if (close <= 1) return false
        host = authority.substring(1, close).lowercase()
        val suffix = authority.substring(close + 1)
        if (suffix.isNotEmpty() && !suffix.startsWith(":")) return false
        port = suffix.removePrefix(":").takeIf { suffix.isNotEmpty() }
        if (':' !in host || !isSafePartyIpv6Host(host)) return false
    } else {
        if (authority.count { it == ':' } > 1) return false
        val colon = authority.lastIndexOf(':')
        host = (if (colon >= 0) authority.substring(0, colon) else authority)
            .lowercase()
            .removeSuffix(".")
        port = if (colon >= 0) authority.substring(colon + 1) else null
        if (host.isEmpty() || !isSafePartyDnsOrIpv4Host(host)) return false
    }

    if (port != null) {
        if (port.isEmpty() || port.any { it !in '0'..'9' }) return false
        val number = port.toIntOrNull() ?: return false
        if (number !in 1..65_535) return false
    }
    return true
}

private fun isSafePartyDnsOrIpv4Host(host: String): Boolean {
    if (
        host == "localhost" || host.endsWith(".localhost") ||
        host.endsWith(".local") || host.endsWith(".lan") ||
        host.endsWith(".internal") || host.endsWith(".home") ||
        host.endsWith(".localdomain")
    ) return false

    val ipv4 = parseCanonicalIpv4(host)
    if (ipv4 != null) return isPublicPartyIpv4(ipv4)

    // Reject numeric/hex IPv4 spellings (127.1, 0x7f000001, 0177.0.0.1)
    // instead of relying on how different URL stacks canonicalise them.
    if (host.all { it in '0'..'9' || it == '.' || it in 'a'..'f' || it == 'x' }) return false
    if (!host.contains('.')) return false
    val labels = host.split('.')
    if (labels.any { label ->
            label.isEmpty() || label.length > 63 ||
                label.first() == '-' || label.last() == '-' ||
                label.any { it !in 'a'..'z' && it !in '0'..'9' && it != '-' }
        }) return false
    return true
}

private fun parseCanonicalIpv4(host: String): List<Int>? {
    val parts = host.split('.')
    if (parts.size != 4 || parts.any { it.isEmpty() || it.length > 3 }) return null
    val bytes = parts.map { part ->
        if (part.any { it !in '0'..'9' }) return null
        if (part.length > 1 && part.startsWith('0')) return null
        part.toIntOrNull()?.takeIf { it in 0..255 } ?: return null
    }
    return bytes
}

private fun isPublicPartyIpv4(bytes: List<Int>): Boolean {
    val a = bytes[0]
    val b = bytes[1]
    val c = bytes[2]
    return a != 0 && a != 10 && a != 127 && a < 224 &&
        !(a == 100 && b in 64..127) &&
        !(a == 169 && b == 254) &&
        !(a == 172 && b in 16..31) &&
        !(a == 192 && ((b == 0 && c in 0..2) || b == 168 || (b == 88 && c == 99))) &&
        !(a == 198 && (b in 18..19 || (b == 51 && c == 100))) &&
        !(a == 203 && b == 0 && c == 113)
}

private fun isSafePartyIpv6Host(host: String): Boolean {
    if (host == "::" || host == "::1" || host.startsWith("::") ||
        host.startsWith("fc") || host.startsWith("fd") || host.startsWith("ff") ||
        host.startsWith("2001:db8:") ||
        host.startsWith("fe80:") || host.startsWith("fe90:") ||
        host.startsWith("fea0:") || host.startsWith("feb0:") ||
        host.startsWith("fe8") || host.startsWith("fe9") ||
        host.startsWith("fea") || host.startsWith("feb")
    ) return false
    if (host.any { it !in '0'..'9' && it !in 'a'..'f' && it != ':' }) return false
    if (host.split(':').all { it.isEmpty() || it == "0" }) return false
    return true
}
