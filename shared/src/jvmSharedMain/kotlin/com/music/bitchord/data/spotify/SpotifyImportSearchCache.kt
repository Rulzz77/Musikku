package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.Song
import kotlinx.coroutines.CompletableDeferred

/**
 * Shares identical Spotify-import catalogue searches inside one import batch.
 *
 * Each instance is deliberately short-lived: [SpotifyImporter.resolveToSongs]
 * creates one per playlist import, so account changes and later catalogue
 * updates are never hidden by a process-wide search cache.
 *
 * Successful empty responses are cached too. Failures are not cached, allowing
 * a later track/retry to try the same request again. Concurrent callers for
 * the same normalized query and filter await the same in-flight request.
 */
internal class SpotifyImportSearchCache(
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES,
) {
    private data class SearchKey(
        val query: String,
        val kind: YtMusicRepository.SpotifyImportSearchKind,
    )

    private val lock = Any()
    private val results = object : LinkedHashMap<SearchKey, List<Song>>(16, 0.75f, true) {
        override fun removeEldestEntry(
            eldest: MutableMap.MutableEntry<SearchKey, List<Song>>?,
        ): Boolean = size > maxEntries
    }
    private val inFlight = HashMap<SearchKey, CompletableDeferred<Result<List<Song>>>>()

    init {
        require(maxEntries > 0) { "Maximum search cache size must be greater than zero" }
    }

    /**
     * Returns a successful cached response or runs [loader] once for all
     * concurrent callers with the same normalized query and search kind.
     */
    suspend fun search(
        query: String,
        kind: YtMusicRepository.SpotifyImportSearchKind,
        loader: suspend (
            String,
            YtMusicRepository.SpotifyImportSearchKind,
        ) -> Result<List<Song>>,
    ): Result<List<Song>> {
        val cleanQuery = query.trim().replace(WHITESPACE, " ")
        if (cleanQuery.isEmpty()) return Result.success(emptyList())

        val key = SearchKey(cleanQuery.lowercase(), kind)
        var isOwner = false
        val pending = synchronized(lock) {
            val cached = results[key]
            if (cached != null) {
                return Result.success(cached)
            }

            inFlight[key] ?: CompletableDeferred<Result<List<Song>>>().also {
                inFlight[key] = it
                isOwner = true
            }
        }

        if (!isOwner) return pending.await()

        try {
            val loaded = loader(cleanQuery, kind)
            if (loaded.isSuccess) {
                // Do not retain a caller-owned mutable list.
                val snapshot = loaded.getOrThrow().toList()
                synchronized(lock) { results[key] = snapshot }
                val successful = Result.success(snapshot)
                pending.complete(successful)
                return successful
            }

            // Transient errors must remain retryable; share this failure with
            // current waiters but leave the LRU cache untouched.
            pending.complete(loaded)
            return loaded
        } catch (failure: Throwable) {
            // Never strand waiters if a request is cancelled or unexpectedly
            // throws instead of returning Result.failure(...).
            pending.completeExceptionally(failure)
            throw failure
        } finally {
            synchronized(lock) {
                if (inFlight[key] === pending) inFlight.remove(key)
            }
        }
    }

    private companion object {
        const val DEFAULT_MAX_ENTRIES = 128
        val WHITESPACE = Regex("\\s+")
    }
}
