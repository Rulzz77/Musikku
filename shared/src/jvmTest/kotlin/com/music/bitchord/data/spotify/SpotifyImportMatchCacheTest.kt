package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SpotifyImportMatchCacheTest {

    @Test
    fun storesAndReturnsConfirmedMatchBySpotifyId() {
        val cache = SpotifyImportMatchCache()
        val song = song("yt-one")

        cache.put("spotify-one", song)

        assertEquals(song, cache.get("spotify-one"))
    }

    @Test
    fun doesNotCacheBlankSpotifyIdsOrBlankVideoIds() {
        val cache = SpotifyImportMatchCache()

        cache.put(null, song("yt-one"))
        cache.put("   ", song("yt-two"))
        cache.put("spotify-three", song(" "))

        assertNull(cache.get(null))
        assertNull(cache.get(" "))
        assertNull(cache.get("spotify-three"))
        assertEquals(0, cache.size())
    }

    @Test
    fun keepsDifferentLanguageMatchesSeparateAndNormalizesNoPreference() {
        val cache = SpotifyImportMatchCache()
        val defaultSong = song("yt-default")
        val englishSong = song("yt-english")

        cache.put("spotify-one", defaultSong, "No Preference")
        cache.put("spotify-one", englishSong, "English")

        assertEquals(defaultSong, cache.get("spotify-one"))
        assertEquals(defaultSong, cache.get("spotify-one", "Multilingual"))
        assertEquals(englishSong, cache.get("spotify-one", "english"))
    }

    @Test
    fun evictsLeastRecentlyUsedEntryWhenCapacityIsExceeded() {
        val cache = SpotifyImportMatchCache(maxEntries = 2)
        val first = song("yt-one")
        val second = song("yt-two")
        val third = song("yt-three")

        cache.put("spotify-one", first)
        cache.put("spotify-two", second)
        assertEquals(first, cache.get("spotify-one"))
        cache.put("spotify-three", third)

        assertEquals(first, cache.get("spotify-one"))
        assertNull(cache.get("spotify-two"))
        assertEquals(third, cache.get("spotify-three"))
        assertEquals(2, cache.size())
    }

    @Test
    fun restoresConfirmedMatchesAndLanguageKeysAfterProcessRestart() {
        val storage = MemoryPersistence()
        val beforeRestart = SpotifyImportMatchCache()
        beforeRestart.attachPersistence(storage)

        val defaultSong = song("yt-default")
        val tamilSong = song("yt-tamil")
        beforeRestart.put("spotify-one", defaultSong)
        beforeRestart.put("spotify-two", tamilSong, "Tamil")
        beforeRestart.flush()

        val afterRestart = SpotifyImportMatchCache()
        afterRestart.attachPersistence(storage)

        assertEquals(defaultSong, afterRestart.get("spotify-one"))
        assertNull(afterRestart.get("spotify-two"))
        assertEquals(tamilSong, afterRestart.get("spotify-two", "tamil"))
    }

    @Test
    fun persistsTheLruOrderAndCapacityWhenRestored() {
        val storage = MemoryPersistence()
        val cache = SpotifyImportMatchCache(maxEntries = 2)
        cache.attachPersistence(storage)

        cache.put("spotify-one", song("yt-one"))
        cache.put("spotify-two", song("yt-two"))
        cache.get("spotify-one") // Make the first entry newer than the second.
        cache.put("spotify-three", song("yt-three"))
        cache.flush()

        assertEquals(listOf("spotify-one", "spotify-three"), storage.entries.map { it.cacheKey })

        val restored = SpotifyImportMatchCache(maxEntries = 2)
        restored.attachPersistence(storage)
        assertEquals("yt-one", restored.get("spotify-one")?.videoId)
        assertNull(restored.get("spotify-two"))
        assertEquals("yt-three", restored.get("spotify-three")?.videoId)
    }

    @Test
    fun checkpointsLargeImportsInBatchesAndFlushesTheRemainder() {
        val storage = MemoryPersistence()
        val cache = SpotifyImportMatchCache()
        cache.attachPersistence(storage)

        repeat(15) { index -> cache.put("spotify-$index", song("yt-$index")) }
        assertEquals(0, storage.saveCount)

        cache.put("spotify-15", song("yt-15"))
        assertEquals(1, storage.saveCount)

        cache.put("spotify-16", song("yt-16"))
        cache.flush()
        assertEquals(2, storage.saveCount)
        assertEquals(17, storage.entries.size)
    }

    private class MemoryPersistence : SpotifyImportMatchCachePersistence {
        var entries: List<SpotifyImportCachedMatch> = emptyList()
            private set
        var saveCount: Int = 0
            private set

        override fun load(): List<SpotifyImportCachedMatch> = entries

        override fun save(entries: List<SpotifyImportCachedMatch>) {
            this.entries = entries.toList()
            saveCount++
        }
    }

    private fun song(videoId: String) = Song(
        videoId = videoId,
        title = videoId,
        artist = "Test Artist",
        thumbnailUrl = null,
    )
}
