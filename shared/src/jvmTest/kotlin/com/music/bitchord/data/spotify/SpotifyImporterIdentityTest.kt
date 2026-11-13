package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.Song
import com.music.bitchord.data.sources.TrackMatcher
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull

class SpotifyImporterIdentityTest {

    @Test
    fun spotifyImportRejectsDifferentSingerEvenWhenTitleAndDurationMatch() {
        val target = TrackMatcher.Target(
            title = "Dumes",
            artist = "Guyon Waton",
            durationSec = 210,
            requireSharedArtist = true,
        )
        val cover = Song(
            videoId = "cover-upload",
            title = "Dumes",
            artist = "Different Singer",
            thumbnailUrl = null,
            durationText = "3:30",
        )

        assertNull(TrackMatcher.best(listOf(cover), target))
    }

    @Test
    fun spotifyImportRejectsSecondaryArtistOnlyEvenWhenTitleAndDurationMatch() {
        val target = TrackMatcher.Target(
            title = "Dumes",
            artist = "Guyon Waton, Denny Caknan",
            durationSec = 210,
            requireSharedArtist = true,
            requirePrimaryArtist = true,
            requireExactTitle = true,
        )
        val secondaryArtistOnly = Song(
            videoId = "secondary-artist-upload",
            title = "Dumes",
            artist = "Denny Caknan",
            thumbnailUrl = null,
            durationText = "3:30",
        )

        assertNull(TrackMatcher.best(listOf(secondaryArtistOnly), target))
    }

    @Test
    fun spotifyImportRejectsLongerTitleContainingRequestedTitle() {
        val target = TrackMatcher.Target(
            title = "Dumes",
            artist = "Guyon Waton",
            durationSec = 210,
            requireSharedArtist = true,
            requirePrimaryArtist = true,
            requireExactTitle = true,
        )
        val differentSong = Song(
            videoId = "longer-title-upload",
            title = "Dumes Bersama",
            artist = "Guyon Waton",
            thumbnailUrl = null,
            durationText = "3:30",
        )

        assertNull(TrackMatcher.best(listOf(differentSong), target))
    }

    @Test
    fun spotifyImportAcceptsTheRequestedSingerWithMatchingRecording() {
        val target = TrackMatcher.Target(
            title = "Dumes",
            artist = "Guyon Waton",
            durationSec = 210,
            requireSharedArtist = true,
            requirePrimaryArtist = true,
            requireExactTitle = true,
        )
        val original = Song(
            videoId = "original-upload",
            title = "Dumes",
            artist = "Guyon Waton",
            thumbnailUrl = null,
            durationText = "3:30",
        )

        assertNotNull(TrackMatcher.best(listOf(original), target))
    }


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
