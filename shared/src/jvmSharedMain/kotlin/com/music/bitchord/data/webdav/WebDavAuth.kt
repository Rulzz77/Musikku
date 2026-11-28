package com.music.bitchord.data.webdav

/**
 * In-memory credentials for [com.music.bitchord.data.Http]'s interceptor.
 *
 * Held outside SharedPreferences so the network layer never touches prefs:
 * [com.music.bitchord.data.settings.AppSettings] publishes here on init and
 * on every WebDAV edit.
 */
object WebDavAuth {
    /** Canonical origin (scheme + host + effective port), never just hostname. */
    @Volatile private var origin: String? = null
    @Volatile var authHeader: String? = null

    /**
     * Credentials are bound to the configured origin, not merely its hostname.
     * A different port or switching HTTPS to HTTP must never inherit Basic auth.
     */
    fun update(serverUrl: String?, header: String?) {
        origin = originOf(serverUrl)
        authHeader = header?.takeIf { it.isNotBlank() && origin != null }
    }

    fun shouldAuthorize(requestUrl: String): Boolean {
        val expected = origin ?: return false
        val header = authHeader ?: return false
        if (header.isBlank()) return false
        return originOf(requestUrl) == expected
    }

    private fun originOf(raw: String?): String? = runCatching {
        val uri = java.net.URI(raw ?: return null)
        val scheme = uri.scheme?.lowercase(java.util.Locale.ROOT) ?: return null
        if (scheme != "https" && scheme != "http") return null
        if (uri.isOpaque || uri.userInfo != null || uri.host.isNullOrBlank()) return null
        val port = uri.port
        if (port !in -1..65535) return null
        val effectivePort = if (port >= 0) port else if (scheme == "https") 443 else 80
        scheme + "://" + uri.host.lowercase(java.util.Locale.ROOT) + ":" + effectivePort
    }.getOrNull()
}
