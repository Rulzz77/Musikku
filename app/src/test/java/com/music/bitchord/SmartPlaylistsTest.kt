package com.music.bitchord.data.stats

import com.music.bitchord.data.model.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SmartPlaylistsTest {

    private fun track(
        id: String,
        artist: String = "Artist",
        plays: Int,
        ms: Long,
        lastPlayedAt: Long,
    ) = RankedSong(
        song = Song(
            videoId = id,
            title = id,
            artist = artist,
            thumbnailUrl = null,
        ),
        ms = ms,
        plays = plays,
        lastPlayedAt = lastPlayedAt,
    )

    @Test
    fun builtInsUseTheirOwnSortOrder() {
        val tracks = listOf(
            track("recent", plays = 2, ms = 120_000, lastPlayedAt = 900),
            track("popular", plays = 9, ms = 240_000, lastPlayedAt = 500),
            track("longest", plays = 3, ms = 600_000, lastPlayedAt = 700),
        )

        val items = buildSmartPlaylistItems(tracks, emptyList(), nowMs = 1_000)

        assertEquals("popular", items.single { it.id == "most_played" }.tracks.first().song.videoId)
        assertEquals("recent", items.single { it.id == "recently_played" }.tracks.first().song.videoId)
        assertEquals("longest", items.single { it.id == "most_listened" }.tracks.first().song.videoId)
    }

    @Test
    fun customRuleFiltersArtistAndMinimumPlaysBeforeSorting() {
        val tracks = listOf(
            track("one", artist = "The Blue Band", plays = 1, ms = 300_000, lastPlayedAt = 700),
            track("two", artist = "Blue Sky", plays = 4, ms = 200_000, lastPlayedAt = 900),
            track("three", artist = "Red Band", plays = 8, ms = 900_000, lastPlayedAt = 950),
        )
        val rule = SmartPlaylistRule(
            id = "blue",
            name = "Blue favourites",
            artistContains = "blue",
            minimumPlays = 2,
            sort = SmartPlaylistSort.RECENTLY_PLAYED,
        )

        val result = applySmartPlaylistRule(tracks, rule)

        assertEquals(listOf("two"), result.map { it.song.videoId })
    }

    @Test
    fun forgottenTracksRequireThirtyDaysAndSortOldestFirst() {
        val now = 2_000_000_000_000L
        val thirtyDays = 30L * 24L * 60L * 60L * 1000L
        val tracks = listOf(
            track("new", plays = 3, ms = 100_000, lastPlayedAt = now - thirtyDays + 1),
            track("older", plays = 2, ms = 200_000, lastPlayedAt = now - thirtyDays * 2),
            track("boundary", plays = 1, ms = 150_000, lastPlayedAt = now - thirtyDays),
        )

        val forgotten = buildSmartPlaylistItems(tracks, emptyList(), now)
            .single { it.id == "forgotten_tracks" }

        assertEquals(listOf("older", "boundary"), forgotten.tracks.map { it.song.videoId })
    }

    @Test
    fun savedRulesRemainVisibleBeforeAnyTrackHasBeenListenedTo() {
        val rule = SmartPlaylistRule(id = "rule-1", name = "My mix")

        val items = buildSmartPlaylistItems(emptyList(), listOf(rule), nowMs = 1_000)

        assertEquals(1, items.size)
        assertEquals("My mix", items.single().title)
        assertTrue(items.single().tracks.isEmpty())
        assertFalse(items.single().rule == null)
    }

    @Test
    fun customResultsAreCappedAtOneHundredTracks() {
        val tracks = (1..140).map { index ->
            track("track-$index", plays = index, ms = index * 1_000L, lastPlayedAt = index.toLong())
        }
        val result = applySmartPlaylistRule(
            tracks,
            SmartPlaylistRule(name = "Everything", minimumPlays = 1),
        )

        assertEquals(100, result.size)
        assertEquals("track-140", result.first().song.videoId)
    }
}
