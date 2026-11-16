package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.Song
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

class SpotifyImportSearchCacheTest {

    @Test
    fun reusesSuccessfulSearchesWithNormalizedQueryAndSameFilter() = runBlocking {
        val cache = SpotifyImportSearchCache()
        val calls = AtomicInteger()
        val expected = listOf(song("yt-one"))

        val first = cache.search("  Denny   Caknan  ", YtMusicRepository.SpotifyImportSearchKind.TRACK) { _, _ ->
            calls.incrementAndGet()
            Result.success(expected)
        }
        val second = cache.search("denny caknan", YtMusicRepository.SpotifyImportSearchKind.TRACK) { _, _ ->
            calls.incrementAndGet()
            Result.success(listOf(song("unexpected")))
        }

        assertEquals(expected, first.getOrThrow())
        assertEquals(expected, second.getOrThrow())
        assertEquals(1, calls.get())
    }

    @Test
    fun keepsDifferentSearchFiltersSeparateAndCachesSuccessfulEmptyResults() = runBlocking {
        val cache = SpotifyImportSearchCache()
        val calls = AtomicInteger()

        repeat(2) {
            val empty = cache.search("same query", YtMusicRepository.SpotifyImportSearchKind.TRACK) { _, _ ->
                calls.incrementAndGet()
                Result.success(emptyList())
            }
            assertTrue(empty.getOrThrow().isEmpty())
        }
        val allFilter = cache.search("same query", YtMusicRepository.SpotifyImportSearchKind.ALL) { _, _ ->
            calls.incrementAndGet()
            Result.success(listOf(song("yt-all")))
        }

        assertEquals("yt-all", allFilter.getOrThrow().single().videoId)
        assertEquals(2, calls.get())
    }

    @Test
    fun concurrentIdenticalSearchesShareOneInFlightRequest() = runBlocking {
        val cache = SpotifyImportSearchCache()
        val calls = AtomicInteger()
        val gate = CompletableDeferred<Unit>()
        val loader: suspend (
            String,
            YtMusicRepository.SpotifyImportSearchKind,
        ) -> Result<List<Song>> = { _, _ ->
            calls.incrementAndGet()
            gate.await()
            Result.success(listOf(song("yt-shared")))
        }

        val first = async(start = CoroutineStart.UNDISPATCHED) {
            cache.search("shared query", YtMusicRepository.SpotifyImportSearchKind.TRACK, loader)
        }
        val second = async(start = CoroutineStart.UNDISPATCHED) {
            cache.search("SHARED   QUERY", YtMusicRepository.SpotifyImportSearchKind.TRACK, loader)
        }

        assertEquals(1, calls.get())
        gate.complete(Unit)
        assertEquals("yt-shared", first.await().getOrThrow().single().videoId)
        assertEquals("yt-shared", second.await().getOrThrow().single().videoId)
        assertEquals(1, calls.get())
    }

    @Test
    fun doesNotCacheFailedRequestsSoTheyCanBeRetried() = runBlocking {
        val cache = SpotifyImportSearchCache()
        val calls = AtomicInteger()

        val failed = cache.search("retry me", YtMusicRepository.SpotifyImportSearchKind.TRACK) { _, _ ->
            calls.incrementAndGet()
            Result.failure(IOException("temporary network failure"))
        }
        val retried = cache.search("retry me", YtMusicRepository.SpotifyImportSearchKind.TRACK) { _, _ ->
            calls.incrementAndGet()
            Result.success(listOf(song("yt-recovered")))
        }

        assertTrue(failed.isFailure)
        assertEquals("yt-recovered", retried.getOrThrow().single().videoId)
        assertEquals(2, calls.get())
    }

    @Test
    fun evictsLeastRecentlyUsedQueriesWhenCapacityIsExceeded() = runBlocking {
        val cache = SpotifyImportSearchCache(maxEntries = 2)
        val calls = AtomicInteger()

        suspend fun load(query: String) = cache.search(
            query,
            YtMusicRepository.SpotifyImportSearchKind.TRACK,
        ) { _, _ ->
            val number = calls.incrementAndGet()
            Result.success(listOf(song("yt-$number")))
        }

        load("first")
        load("second")
        load("first") // Refresh the first query's LRU position.
        load("third")
        load("second") // The second query should have been evicted.

        assertEquals(4, calls.get())
    }

    private fun song(videoId: String) = Song(
        videoId = videoId,
        title = videoId,
        artist = "Test Artist",
        thumbnailUrl = null,
    )
}
