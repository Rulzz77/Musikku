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
    @Volatile private var pathPrefix: String? = null
    @Volatile var authHeader: String? = null

    /**
     * Credentials are bound to the configured origin, not merely its hostname.
     * A different port or switching HTTPS to HTTP must never inherit Basic auth.
     */
    fun update(serverUrl: String?, header: String?) {
        val uri = serverUrl?.let(::parseUrl)
        origin = uri?.let(::originOf)
        pathPrefix = uri?.let { decodedNormalizedPath(it.rawPath) }
            ?.trimEnd('/')?.ifEmpty { "/" }
        authHeader = header?.takeIf { it.isNotBlank() && origin != null && pathPrefix != null }
    }

    fun shouldAuthorize(requestUrl: String): Boolean {
        val expectedOrigin = origin ?: return false
        val expectedPath = pathPrefix ?: return false
        val header = authHeader ?: return false
        if (header.isBlank()) return false
        val request = parseUrl(requestUrl) ?: return false
        if (originOf(request) != expectedOrigin) return false
        val path = decodedNormalizedPath(request.rawPath) ?: return false
        return expectedPath == "/" || path == expectedPath || path.startsWith(expectedPath + "/")
    }

    private fun parseUrl(raw: String): java.net.URI? = runCatching {
        java.net.URI(raw).also { uri ->
            require(!uri.isOpaque && uri.userInfo == null)
            require(uri.rawQuery == null && uri.rawFragment == null)
            require(uri.host.isNullOrBlank().not())
            require(uri.scheme.equals("https", true) || uri.scheme.equals("http", true))
            require(uri.port in -1..65535)
            require(uri.normalize().rawPath == uri.rawPath)
        }
    }.getOrNull()

    private fun originOf(uri: java.net.URI): String {
        val scheme = uri.scheme.lowercase(java.util.Locale.ROOT)
        val port = uri.port
        val effectivePort = if (port >= 0) port else if (scheme == "https") 443 else 80
        return scheme + "://" + uri.host.lowercase(java.util.Locale.ROOT) + ":" + effectivePort
    }

    private fun decodedNormalizedPath(rawPath: String?): String? = runCatching {
        val raw = rawPath.orEmpty().ifEmpty { "/" }
        val decoded = java.net.URLDecoder.decode(
            raw.replace("+", "%2B"),
            Charsets.UTF_8.name(),
        )
        require(decoded.none { it == '\\' || it.code < 0x20 || it.code == 0x7f })
        val segments = ArrayDeque<String>()
        decoded.split('/').forEach { segment ->
            when (segment) {
                "", "." -> Unit
                ".." -> {
                    require(segments.isNotEmpty())
                    segments.removeLast()
                }
                else -> segments.addLast(segment)
            }
        }
        "/" + segments.joinToString("/")
    }.getOrNull()
}
