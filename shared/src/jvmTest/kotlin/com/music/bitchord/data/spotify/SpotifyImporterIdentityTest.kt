package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.BrowseItem
import com.music.bitchord.data.model.BrowseType
import com.music.bitchord.data.model.SearchResult
import com.music.bitchord.data.model.Song
import com.music.bitchord.data.sources.TrackMatcher
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SpotifyImporterIdentityTest {

    @Test
    fun spotifyImportCanUsePromotedTopTrackFromAllSearch() {
        val promoted = Song(
            videoId = "promoted-track",
            title = "Tanpo Tresnamu",
            artist = "Denny Caknan",
            thumbnailUrl = null,
            durationText = "4:12",
        )

        assertEquals(promoted, spotifyImportCandidate(SearchResult.TopTrack(promoted)))
    }

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
            requiredArtistName = "Guyon Waton",
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
            requiredArtistName = "Guyon Waton",
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
    fun spotifyImportMatchesWholeLeadArtistNamesWithPunctuation() {
        val acdcTarget = TrackMatcher.Target(
            title = "Back In Black",
            artist = "AC/DC",
            durationSec = 255,
            requiredArtistName = "AC/DC",
            requireExactTitle = true,
        )
        val acdc = Song(
            videoId = "acdc-upload",
            title = "Back In Black",
            artist = "AC/DC",
            thumbnailUrl = null,
            durationText = "4:20",
        )
        val xTarget = TrackMatcher.Target(
            title = "Renegades",
            artist = "X Ambassadors",
            durationSec = 195,
            requiredArtistName = "X Ambassadors",
            requireExactTitle = true,
        )
        val xAmbassadors = Song(
            videoId = "x-ambassadors-upload",
            title = "Renegades",
            artist = "X Ambassadors",
            thumbnailUrl = null,
            durationText = "3:15",
        )

        val unrelatedBandWithSimilarName = Song(
            videoId = "ambassadors-upload",
            title = "Renegades",
            artist = "Ambassadors",
            thumbnailUrl = null,
            durationText = "3:15",
        )

        assertNotNull(TrackMatcher.best(listOf(acdc), acdcTarget))
        assertNotNull(TrackMatcher.best(listOf(xAmbassadors), xTarget))
        assertNull(TrackMatcher.best(listOf(unrelatedBandWithSimilarName), xTarget))
        assertTrue(TrackMatcher.queries(xTarget).first().contains("x ambassadors"))
    }

    @Test
    fun spotifyImportMatchesLongArtistNamesWhenYouTubeDropsSpaces() {
        val target = TrackMatcher.Target(
            title = "Dumes",
            artist = "Guyon Waton",
            durationSec = 210,
            requiredArtistName = "Guyon Waton",
            requireExactTitle = true,
        )
        val youtubeSpelling = Song(
            videoId = "compact-artist-upload",
            title = "Dumes",
            artist = "GUYONWATON",
            thumbnailUrl = null,
            durationText = "3:30",
        )
        assertNotNull(TrackMatcher.best(listOf(youtubeSpelling), target))

        val ndxTarget = TrackMatcher.Target(
            title = "Kimcil Kepolen",
            artist = "NDX A.K.A.",
            durationSec = 230,
            requiredArtistName = "NDX A.K.A.",
            requireExactTitle = true,
        )
        val ndxSpelling = youtubeSpelling.copy(
            videoId = "ndx-upload",
            title = "Kimcil Kepolen",
            artist = "NDXAKA",
            durationText = "3:50",
        )
        assertNotNull(TrackMatcher.best(listOf(ndxSpelling), ndxTarget))
    }

    @Test
    fun artistPageFallbackOnlyUsesTheExactRequestedPerformer() {
        val correctArtist = SearchResult.Browse(
            BrowseItem(
                browseId = "artist-guyon-waton",
                title = "GUYONWATON",
                subtitle = "Artist",
                thumbnailUrl = null,
                type = BrowseType.ARTIST,
            ),
        )
        val partialName = SearchResult.Browse(
            BrowseItem(
                browseId = "artist-waton",
                title = "Waton",
                subtitle = "Artist",
                thumbnailUrl = null,
                type = BrowseType.ARTIST,
            ),
        )
        val album = SearchResult.Browse(
            BrowseItem(
                browseId = "album-guyon",
                title = "Guyon Waton",
                subtitle = "Album",
                thumbnailUrl = null,
                type = BrowseType.ALBUM,
            ),
        )

        assertEquals(
            "artist-guyon-waton",
            spotifyArtistBrowseId(correctArtist, "Guyon Waton"),
        )
        assertNull(spotifyArtistBrowseId(partialName, "Guyon Waton"))
        assertNull(spotifyArtistBrowseId(album, "Guyon Waton"))
    }

    @Test
    fun spotifyImportPrefersAudioWhenA matchingVideoIsAlsoPresent() {
        val target = TrackMatcher.Target(
            title = "Dumes",
            artist = "Guyon Waton",
            durationSec = 210,
            requiredArtistName = "Guyon Waton",
            requireExactTitle = true,
        )
        val video = Song(
            videoId = "video-copy",
            title = "Dumes",
            artist = "Guyon Waton",
            thumbnailUrl = null,
            durationText = "3:30",
            isVideo = true,
        )
        val audio = video.copy(videoId = "audio-copy", isVideo = false)

        assertEquals(audio, bestSpotifyImportMatch(listOf(video, audio), target))
    }

    @Test
    fun spotifyImportAcceptsTheRequestedSingerWithMatchingRecording() {
        val target = TrackMatcher.Target(
            title = "Dumes",
            artist = "Guyon Waton",
            durationSec = 210,
            requireSharedArtist = true,
            requiredArtistName = "Guyon Waton",
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
