package com.music.bitchord.data.webdav

import com.music.bitchord.data.model.Song
import java.util.Locale

/**
 * WebDAV music library configuration and mapping.
 *
 * A WebDAV server is treated as a remote folder of audio files: tracks are
 * listed with PROPFIND, streamed over plain HTTPS with Basic auth, and shown
 * in the same Songs / Artists / Albums view as on-device files.
 */
object WebDavConfig {

    const val BROWSE_ID = "local:webdav"

    val audioExtensions = setOf(
        "mp3", "m4a", "flac", "ogg", "opus", "aac", "wav", "wma", "aif", "aiff", "webm",
    )

    fun normalizeUrl(raw: String): String {
        val trimmed = raw.trim().trimEnd('/')
        if (trimmed.isEmpty()) return ""
        return if (trimmed.startsWith("http://", ignoreCase = true) ||
            trimmed.startsWith("https://", ignoreCase = true)
        ) {
            trimmed
        } else {
            "https://$trimmed"
        }
    }

    fun isConfigured(url: String): Boolean = originOf(url) != null

    /** Canonical URL origin, used to fence credentials and server-provided hrefs. */
    fun originOf(raw: String): String? = runCatching {
        val uri = java.net.URI(normalizeUrl(raw))
        val scheme = uri.scheme?.lowercase(Locale.ROOT) ?: return null
        if (scheme != "http" && scheme != "https") return null
        if (uri.isOpaque || uri.userInfo != null || uri.host.isNullOrBlank()) return null
        if (uri.port !in -1..65535 || uri.normalize().rawPath != uri.rawPath) return null
        val port = uri.port.takeIf { it >= 0 } ?: if (scheme == "https") 443 else 80
        scheme + "://" + uri.host.lowercase(Locale.ROOT) + ":" + port
    }.getOrNull()

    fun sameOrigin(first: String, second: String): Boolean =
        originOf(first) != null && originOf(first) == originOf(second)

    /**
     * Decode path separators/dot-segments before binding credentials. Some
     * servers decode %2F and %2E%2E before filesystem lookup; comparing only
     * raw URI paths would let a crafted href escape the configured folder.
     */
    private fun decodedNormalizedPath(rawPath: String?): String? = runCatching {
        val raw = rawPath.orEmpty().ifEmpty { "/" }
        val decoded = java.net.URLDecoder.decode(
            raw.replace("+", "%2B"),
            Charsets.UTF_8.name(),
        )
        require(decoded.none { it == '\\\\' || it.code < 0x20 || it.code == 0x7f })
        val stack = ArrayDeque<String>()
        decoded.split('/').forEach { segment ->
            when (segment) {
                "", "." -> Unit
                ".." -> {
                    require(stack.isNotEmpty()) { "WebDAV path escapes its root" }
                    stack.removeLast()
                }
                else -> stack.addLast(segment)
            }
        }
        "/" + stack.joinToString("/")
    }.getOrNull()

    /** The credential binding includes the selected WebDAV folder, not just its domain. */
    fun credentialBindingKey(raw: String): String? {
        val normalized = normalizeUrl(raw)
        val origin = originOf(normalized) ?: return null
        val uri = runCatching { java.net.URI(normalized) }.getOrNull() ?: return null
        val path = decodedNormalizedPath(uri.rawPath) ?: return null
        return origin + path.trimEnd('/').ifEmpty { "/" }
    }

    /** True when [target] is the configured root folder or a descendant of it. */
    fun isWithinBasePath(baseUrl: String, targetUrl: String): Boolean {
        if (!sameOrigin(baseUrl, targetUrl)) return false
        val baseUri = runCatching { java.net.URI(normalizeUrl(baseUrl)) }.getOrNull() ?: return false
        val targetUri = runCatching { java.net.URI(targetUrl) }.getOrNull() ?: return false
        val basePath = decodedNormalizedPath(baseUri.rawPath) ?: return false
        val targetPath = decodedNormalizedPath(targetUri.rawPath) ?: return false
        return basePath == "/" || targetPath == basePath || targetPath.startsWith(basePath.trimEnd('/') + "/")
    }

    fun basicAuthHeader(username: String, password: String): String? {
        if (username.isBlank() && password.isBlank()) return null
        val credentials = "$username:$password"
        val encoded = java.util.Base64.getEncoder()
            .encodeToString(credentials.toByteArray(Charsets.UTF_8))
        return "Basic $encoded"
    }

    fun hostOf(url: String): String? = runCatching {
        java.net.URI(normalizeUrl(url)).host?.lowercase(Locale.ROOT)
    }.getOrNull()?.takeIf { it.isNotBlank() && originOf(url) != null }

    fun isAudioFile(name: String): Boolean {
        val ext = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
        return ext in audioExtensions
    }

    /**
     * Stable track id for a remote file. Prefixed so it never collides with a
     * YouTube id, a MediaStore content URI, or a module source key.
     */
    fun idFor(fileUrl: String): String = "webdav:$fileUrl"

    fun isWebDavId(videoId: String): Boolean = videoId.startsWith("webdav:")

    fun fileUrlOf(videoId: String): String? =
        videoId.removePrefix("webdav:").takeIf { isWebDavId(videoId) && it.startsWith("http") }

    /**
     * A row for a remote file. Title/artist come from the filename —
     * "Artist - Title.ext" splits, anything else is a title by an unknown
     * artist — and the parent folder names the album when there is one.
     */
    fun songFor(fileUrl: String, albumName: String? = null): Song {
        val decoded = runCatching {
            java.net.URLDecoder.decode(fileUrl.substringAfterLast('/'), "UTF-8")
        }.getOrDefault(fileUrl.substringAfterLast('/'))
        return com.music.bitchord.data.remote.RemoteSong.build(
            videoId = idFor(fileUrl),
            streamUrl = fileUrl,
            fileName = decoded,
            albumName = albumName,
            source = "WebDAV",
            browseId = BROWSE_ID,
        )
    }
}

/** Publishes the saved server's credentials to the shared HTTP client. */
fun WebDavAuth.update(url: String, username: String, password: String) =
    update(url.takeIf { WebDavConfig.isConfigured(it) }, WebDavConfig.basicAuthHeader(username, password))
