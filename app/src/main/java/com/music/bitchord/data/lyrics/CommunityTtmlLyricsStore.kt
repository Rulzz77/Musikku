package com.music.bitchord.data.lyrics

import java.io.File
import java.security.MessageDigest

/**
 * Per-track local overrides imported by the listener.
 *
 * The original TTML is kept rather than flattening it to LRC so the shared
 * parser can retain syllable timing, background vocals, duet agents,
 * transliterations, and song-part metadata on every playback.
 */
internal object CommunityTtmlLyricsStore {
    const val MAX_TTML_BYTES = 1_048_576

    fun save(filesDir: File, trackId: String, ttml: String): Boolean {
        val bytes = ttml.toByteArray(Charsets.UTF_8)
        if (bytes.isEmpty() || bytes.size > MAX_TTML_BYTES) return false
        if (parse(ttml) == null) return false

        val destination = fileFor(filesDir, trackId)
        val parent = destination.parentFile ?: return false
        if (!parent.exists() && !parent.mkdirs()) return false
        val temporary = File(parent, "${destination.name}.tmp")

        return try {
            temporary.writeBytes(bytes)
            if (!temporary.renameTo(destination)) {
                temporary.copyTo(destination, overwrite = true)
                temporary.delete()
            }
            destination.isFile && destination.length() == bytes.size.toLong()
        } catch (_: Exception) {
            false
        } finally {
            temporary.delete()
        }
    }

    fun read(filesDir: File, trackId: String): List<LyricLine>? {
        val file = fileFor(filesDir, trackId)
        if (!file.isFile || file.length() !in 1..MAX_TTML_BYTES.toLong()) return null
        val ttml = runCatching { file.readText(Charsets.UTF_8) }.getOrNull() ?: return null
        return parse(ttml)
    }

    fun has(filesDir: File, trackId: String): Boolean =
        fileFor(filesDir, trackId).let { it.isFile && it.length() in 1..MAX_TTML_BYTES.toLong() }

    fun remove(filesDir: File, trackId: String): Boolean {
        val file = fileFor(filesDir, trackId)
        return !file.exists() || file.delete()
    }

    /** Hashing the provider ID keeps arbitrary track IDs out of filesystem paths. */
    internal fun fileFor(filesDir: File, trackId: String): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(trackId.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }
        return File(File(filesDir, "community-lyrics"), "$digest.ttml")
    }

    private fun parse(ttml: String): List<LyricLine>? {
        if (ttml.isBlank() || ttml.toByteArray(Charsets.UTF_8).size > MAX_TTML_BYTES) return null
        val parsed = TtmlLyrics.parse(ttml)
        return parsed.takeIf { lines -> lines.any { it.text.isNotBlank() } }
    }
}
