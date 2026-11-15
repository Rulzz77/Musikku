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
    fun evictsLeastRecentlyUsedEntryWhenCapacityIsExceeded() {
        val cache = SpotifyImportMatchCache(maxEntries = 2)
        val first = song("yt-one")
        val second = song("yt-two")
        val third = song("yt-three")

        cache.put("spotify-one", first)
        cache.put("spotify-two", second)
        assertEquals(first, cache.get("spotify-one")) // Refresh first's LRU position.
        cache.put("spotify-three", third)

        assertEquals(first, cache.get("spotify-one"))
        assertNull(cache.get("spotify-two"))
        assertEquals(third, cache.get("spotify-three"))
        assertEquals(2, cache.size())
    }

    private fun song(videoId: String) = Song(
        videoId = videoId,
        title = videoId,
        artist = "Test Artist",
        thumbnailUrl = null,
    )
}
