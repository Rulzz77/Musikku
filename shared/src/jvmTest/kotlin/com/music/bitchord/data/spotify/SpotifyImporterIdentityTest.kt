package com.music.bitchord.data.spotify

import kotlin.test.Test
import kotlin.test.assertEquals

class SpotifyImporterIdentityTest {

    @Test
    fun sameTitleAndArtistWithDifferentSpotifyIdsAreKept() {
        val tracks = listOf(
            SpotifyImportTrack("Dumes", "Guyon Waton", spotifyId = "spotify-a"),
            SpotifyImportTrack("Dumes", "Guyon Waton", spotifyId = "spotify-b"),
        )

        assertEquals(listOf("spotify-a", "spotify-b"), distinctSpotifyImportTracks(tracks).map { it.spotifyId })
    }

    @Test
    fun repeatedSpotifyIdIsOnlyImportedOnce() {
        val tracks = listOf(
            SpotifyImportTrack("Dumes", "Guyon Waton", spotifyId = "spotify-a"),
            SpotifyImportTrack("Dumes (Remastered)", "Guyon Waton", spotifyId = "spotify-a"),
        )

        assertEquals(1, distinctSpotifyImportTracks(tracks).size)
    }

    @Test
    fun missingSpotifyIdsUseDurationAndAlbumToKeepDistinctVersions() {
        val tracks = listOf(
            SpotifyImportTrack("Dumes", "Guyon Waton", durationMs = 210_000, album = "Album A"),
            SpotifyImportTrack("Dumes", "Guyon Waton", durationMs = 245_000, album = "Album B"),
        )

        assertEquals(2, distinctSpotifyImportTracks(tracks).size)
    }
}
