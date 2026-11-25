package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.Song

/**
 * A confirmed Spotify-to-YouTube Music mapping stored by the platform layer.
 *
 * [cacheKey] includes the normalized language suffix when one was selected.
 * The list passed to [SpotifyImportMatchCachePersistence.save] is ordered
 * oldest-to-newest so restoring it also restores the LRU eviction order.
 */
data class SpotifyImportCachedMatch(
    val cacheKey: String,
    val song: Song,
)

/**
 * Platform-owned storage for the import matcher cache.
 *
 * The shared matcher deliberately knows nothing about Android preferences or
 * desktop files. Android installs its SharedPreferences implementation at
 * application startup; other JVM hosts can keep the process-local default.
 */
interface SpotifyImportMatchCachePersistence {
    fun load(): List<SpotifyImportCachedMatch>
    fun save(entries: List<SpotifyImportCachedMatch>)
}

/**
 * Small LRU cache for confirmed Spotify -> YouTube Music matches.
 *
 * Only positive, identified Spotify tracks are cached. Misses are deliberately
 * not cached so a later retry can recover from a transient search failure or
 * newly available catalogue result.
 *
 * Persisting every single track can rewrite hundreds of rows during a large
 * import. The cache therefore checkpoints in small batches and lets the
 * importer flush at the end (or when the user selects a manual replacement).
 */
internal class SpotifyImportMatchCache(
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES,
) {
    private val entries = object : LinkedHashMap<String, Song>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Song>?): Boolean =
            size > maxEntries
    }

    private var persistence: SpotifyImportMatchCachePersistence? = null
    private var putsSinceCheckpoint = 0

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
            putsSinceCheckpoint++
            if (putsSinceCheckpoint >= PERSIST_EVERY_INSERTS) persistLocked()
        }
    }

    /**
     * Loads the platform's persisted entries once and keeps any newer in-memory
     * values if a host attaches storage after matching has already started.
     */
    fun attachPersistence(storage: SpotifyImportMatchCachePersistence) {
        synchronized(entries) {
            val inMemory = entries.entries.map { SpotifyImportCachedMatch(it.key, it.value) }
            persistence = storage
            val restored = runCatching { storage.load() }.getOrDefault(emptyList())
            entries.clear()
            restored.takeLast(maxEntries).forEach { entry ->
                if (entry.cacheKey.isNotBlank() && entry.song.videoId.isNotBlank()) {
                    entries[entry.cacheKey] = entry.song
                }
            }
            inMemory.forEach { entry ->
                if (entry.cacheKey.isNotBlank() && entry.song.videoId.isNotBlank()) {
                    entries[entry.cacheKey] = entry.song
                }
            }
            putsSinceCheckpoint = 0
            if (inMemory.isNotEmpty()) persistLocked()
        }
    }

    /** Flushes any matches added since the last checkpoint. */
    fun flush() {
        synchronized(entries) { persistLocked() }
    }

    internal fun clear() {
        synchronized(entries) {
            entries.clear()
            persistLocked()
        }
    }

    internal fun size(): Int = synchronized(entries) { entries.size }

    private fun persistLocked() {
        val target = persistence ?: return
        val snapshot = entries.entries.map { (key, song) ->
            SpotifyImportCachedMatch(cacheKey = key, song = song)
        }
        runCatching { target.save(snapshot) }
            .onSuccess { putsSinceCheckpoint = 0 }
    }

    private fun cacheKey(spotifyId: String?, language: String?): String? {
        val id = spotifyId?.trim()?.takeIf(String::isNotEmpty) ?: return null
        val lang = language?.trim()?.takeIf {
            it.isNotEmpty() &&
                !it.equals("No Preference", ignoreCase = true) &&
                !it.equals("Multilingual", ignoreCase = true)
        }?.lowercase()
        return if (lang == null) id else "$id|$lang"
    }

    private companion object {
        const val DEFAULT_MAX_ENTRIES = 512
        const val PERSIST_EVERY_INSERTS = 16
    }
}
