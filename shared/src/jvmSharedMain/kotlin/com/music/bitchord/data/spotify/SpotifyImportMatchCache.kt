package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.Song

/**
 * Small process-local LRU cache for confirmed Spotify -> YouTube Music matches.
 *
 * Only positive, identified Spotify tracks are cached. Misses are deliberately
 * not cached so a later retry can recover from a transient search failure or
 * newly available catalogue result.
 */
internal class SpotifyImportMatchCache(
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES,
) {
    private val entries = object : LinkedHashMap<String, Song>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Song>?): Boolean =
            size > maxEntries
    }

    init {
        require(maxEntries > 0) { "Maximum cache size must be greater than zero" }
    }

    fun get(spotifyId: String?, language: String? = null): Song? {
        val key = cacheKey(spotifyId, language) ?: return null
        return synchronized(entries) { entries[key] }
    }

    fun put(spotifyId: String?, song: Song, language: String? = null) {
        val key = cacheKey(spotifyId, language) ?: return
        if (song.videoId.isBlank()) return
        synchronized(entries) {
            entries[key] = song
        }
    }

    private fun cacheKey(spotifyId: String?, language: String?): String? {
        val id = spotifyId?.trim()?.takeIf(String::isNotEmpty) ?: return null
        val lang = language?.trim()?.lowercase()?.takeIf(String::isNotEmpty)
        return if (lang == null) id else "$id|$lang"
    }

    internal fun clear() {
        synchronized(entries) { entries.clear() }
    }

    internal fun size(): Int = synchronized(entries) { entries.size }

    private companion object {
        const val DEFAULT_MAX_ENTRIES = 512
    }
}
