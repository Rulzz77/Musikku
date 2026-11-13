package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.ArtistRef
import com.music.bitchord.data.model.BrowseItem
import com.music.bitchord.data.model.BrowseType
import com.music.bitchord.data.model.SearchResult
import com.music.bitchord.data.model.Song
import com.music.bitchord.data.sources.TrackMatcher
import com.music.bitchord.data.innertube.InnertubeParser
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SpotifyImporterIdentityTest {

    @Test
    fun allSearchParserPreservesPromotedTrackForSpotifyImport() {
        val response = Json.parseToJsonElement(
            """
            {
              "contents": [{
                "musicCardShelfRenderer": {
                  "onTap": { "watchEndpoint": { "videoId": "promoted-track" } },
                  "title": { "runs": [{ "text": "Tanpo Tresnamu" }] },
                  "subtitle": { "runs": [
                    { "text": "Song" },
                    { "text": " • " },
                    { "text": "Denny Caknan" },
                    { "text": " • " },
                    { "text": "4:12" }
                  ] },
                  "thumbnail": { "musicThumbnailRenderer": {
                    "thumbnail": { "thumbnails": [{
                      "url": "https://example.invalid/cover.jpg",
                      "width": 544,
                      "height": 544
                    }] }
                  } }
                }
              }]
            }
            """.trimIndent(),
        ).jsonObject

        val result = InnertubeParser.parseSearchPage(response).rows.single()
        assertTrue(result is SearchResult.TopTrack)
        assertEquals("promoted-track", spotifyImportCandidate(result)?.videoId)
    }

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
        val collaborationCredit = youtubeSpelling.copy(
            videoId = "collaboration-upload",
            artist = "GUYONWATON x Denny Caknan",
        )
        assertNotNull(TrackMatcher.best(listOf(collaborationCredit), target))

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

        val accentTarget = TrackMatcher.Target(
            title = "Halo",
            artist = "Beyoncé",
            durationSec = 260,
            requiredArtistName = "Beyoncé",
            requireExactTitle = true,
        )
        val unaccentedCredit = youtubeSpelling.copy(
            videoId = "beyonce-upload",
            title = "Halo",
            artist = "Beyonce",
            durationText = "4:20",
        )
        assertNotNull(TrackMatcher.best(listOf(unaccentedCredit), accentTarget))
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

        val matchingTrack = Song(
            videoId = "artist-track",
            title = "Dumes",
            artist = "GUYONWATON",
            thumbnailUrl = null,
            artistId = "artist-from-track-credit",
            artists = listOf(ArtistRef(name = "GUYONWATON", browseId = "artist-from-track-credit")),
        )
        assertEquals(
            "artist-from-track-credit",
            spotifyArtistBrowseId(matchingTrack, "Guyon Waton"),
        )
    }

    @Test
    fun spotifyImportPrefersAudioWhenAMatchingVideoIsAlsoPresent() {
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
    fun spotifyImportSearchIncludesOriginalSpotifyTitleAndFullArtistText() {
        val target = TrackMatcher.Target(
            title = "Tanpo Tresnamu (Official Audio)",
            artist = "Denny Caknan, Yeni Inka",
            durationSec = 252,
            album = "Album Contoh",
            requiredArtistName = "Denny Caknan",
            requireExactTitle = true,
        )

        val queries = spotifyImportSearchQueries(target)

        assertEquals("Tanpo Tresnamu (Official Audio) Denny Caknan", queries.first())
        assertTrue("Tanpo Tresnamu (Official Audio) Denny Caknan, Yeni Inka" in queries)
        assertTrue("Tanpo Tresnamu (Official Audio) Denny Caknan" in queries)
        assertTrue("Tanpo Tresnamu (Official Audio)" in queries)
        assertTrue(TrackMatcher.queries(target).all { it in queries })
        assertEquals(queries.size, queries.distinct().size)
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
    fun spotifyImportAcceptsSecondarySpotifySingerCreditOnlyWithExactRuntime() {
        val target = TrackMatcher.Target(
            title = "Budak Saha",
            artist = "Gasentra Pajampangan, Friska",
            durationSec = 287,
            requiredArtistName = "Gasentra Pajampangan",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Gasentra Pajampangan", "Friska"),
        )
        val singerFiledByYouTube = Song(
            videoId = "budak-saha-friska-gasentra",
            title = "Budak Saha",
            artist = "Friska Gasentra",
            thumbnailUrl = null,
            durationText = "4:47",
        )

        assertNotNull(TrackMatcher.best(listOf(singerFiledByYouTube), target))
        // An exact full-name match to another structured Spotify performer is
        // accepted only while title/version and runtime remain identical.
        assertNotNull(TrackMatcher.best(listOf(singerFiledByYouTube.copy(
            videoId = "budak-saha-friska-only",
            artist = "Friska",
        )), target))
        assertNull(TrackMatcher.best(listOf(singerFiledByYouTube.copy(
            videoId = "budak-saha-friska-only-too-long",
            artist = "Friska",
            durationText = "4:35",
        )), target))
        assertNull(TrackMatcher.best(listOf(singerFiledByYouTube.copy(
            videoId = "budak-saha-unrelated",
            artist = "Denny Caknan",
        )), target))
        assertNull(TrackMatcher.best(listOf(singerFiledByYouTube.copy(durationText = "4:35")), target))
        assertNull(TrackMatcher.best(listOf(singerFiledByYouTube.copy(durationText = null)), target))
    }

    @Test
    fun spotifyImportPreservesRealTitlesContainingWith() {
        val withOrWithout = TrackMatcher.Target(
            title = "With or Without You",
            artist = "U2",
            durationSec = 210,
            requiredArtistName = "U2",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val u2 = Song(
            videoId = "with-or-without-you",
            title = "With or Without You",
            artist = "U2",
            thumbnailUrl = null,
            durationText = "3:30",
        )
        val dancingWithMyself = u2.copy(
            videoId = "dancing-with-myself",
            title = "Dancing With Myself",
            artist = "Billy Idol",
        )
        val dancingTarget = withOrWithout.copy(
            title = "Dancing With Myself",
            artist = "Billy Idol",
            requiredArtistName = "Billy Idol",
        )

        assertNotNull(TrackMatcher.best(listOf(u2), withOrWithout))
        assertNotNull(TrackMatcher.best(listOf(dancingWithMyself), dancingTarget))
    }

    @Test
    fun spotifyImportStripsWithOnlyWhenTheSuffixIsACreditedArtist() {
        val withGuest = TrackMatcher.Target(
            title = "Song",
            artist = "Lead, Guest Artist",
            durationSec = 200,
            requiredArtistName = "Lead",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Lead", "Guest Artist"),
        )
        val candidate = Song(
            videoId = "song-with-guest",
            title = "Song with Guest Artist",
            artist = "Lead",
            thumbnailUrl = null,
            durationText = "3:20",
        )
        assertNotNull(TrackMatcher.best(listOf(candidate), withGuest))

        val noGuestCredit = withGuest.copy(
            artist = "Lead",
            artistCredits = listOf("Lead"),
        )
        assertNull(TrackMatcher.best(listOf(candidate), noGuestCredit))
    }

    @Test
    fun spotifyImportKeepsSongTitleAfterFeaturedArtistPrefix() {
        val target = TrackMatcher.Target(
            title = "Bubrah",
            artist = "Northsle, Agiff",
            durationSec = 200,
            requiredArtistName = "Northsle",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val prefixedUpload = Song(
            videoId = "northsle-agiff-bubrah",
            title = "Northsle feat. Agiff - Bubrah",
            // YouTube's structured byline sometimes carries only the lead.
            artist = "Northsle",
            thumbnailUrl = null,
            durationText = "3:20",
        )
        val unrelatedSinger = prefixedUpload.copy(
            videoId = "unrelated-singer",
            artist = "Unrelated Singer",
        )

        assertNotNull(TrackMatcher.best(listOf(prefixedUpload), target))
        assertNull(TrackMatcher.best(listOf(unrelatedSinger), target))
    }

    @Test
    fun spotifyImportDoesNotSplitCommasInsideStructuredArtistNames() {
        val target = TrackMatcher.Target(
            title = "September",
            artist = "Earth, Wind & Fire, Guest Artist",
            durationSec = 215,
            requiredArtistName = "Earth, Wind & Fire",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Earth, Wind & Fire", "Guest Artist"),
        )
        val canonical = Song(
            videoId = "earth-wind-fire-september",
            title = "September",
            artist = "Earth, Wind & Fire",
            thumbnailUrl = null,
            durationText = "3:35",
            artists = listOf(ArtistRef(name = "Earth, Wind & Fire", browseId = "earth-wind-fire")),
        )
        val reorderedButUnrelated = canonical.copy(
            videoId = "misread-artist",
            artist = "Wind Fire Earth",
            artists = listOf(ArtistRef(name = "Wind Fire Earth", browseId = null)),
        )

        assertNotNull(TrackMatcher.best(listOf(canonical), target))
        assertNull(TrackMatcher.best(listOf(reorderedButUnrelated), target))
    }

    @Test
    fun spotifyImportSeparatesDjKoploFromOriginalAndBreakbeat() {
        val target = TrackMatcher.Target(
            title = "Satu Rasa (DJ Koplo)",
            artist = "Band Contoh",
            durationSec = 210,
            requiredArtistName = "Band Contoh",
            requireExactTitle = true,
        )
        val original = Song(
            videoId = "original",
            title = "Satu Rasa",
            artist = "Band Contoh",
            thumbnailUrl = null,
            durationText = "3:30",
        )
        val breakbeat = original.copy(videoId = "breakbeat", title = "Satu Rasa (DJ Breakbeat)")
        val koplo = original.copy(videoId = "koplo", title = "Satu Rasa (DJ Koplo)")

        assertNull(TrackMatcher.best(listOf(original), target))
        assertNull(TrackMatcher.best(listOf(breakbeat), target))
        assertEquals(koplo, TrackMatcher.best(listOf(original, breakbeat, koplo), target))
    }

    @Test
    fun spotifyImportRecognizesUnbracketedDjSuffixes() {
        val target = TrackMatcher.Target(
            title = "Satu Rasa DJ Koplo Remix",
            artist = "Band Contoh",
            durationSec = 210,
            requiredArtistName = "Band Contoh",
            requireExactTitle = true,
        )
        val original = Song(
            videoId = "original",
            title = "Satu Rasa",
            artist = "Band Contoh",
            thumbnailUrl = null,
            durationText = "3:30",
        )
        val sameDjEdit = original.copy(videoId = "dj-edit", title = "Satu Rasa DJ Koplo Remix")

        assertNull(TrackMatcher.best(listOf(original), target))
        assertEquals(sameDjEdit, TrackMatcher.best(listOf(original, sameDjEdit), target))
    }

    @Test
    fun spotifyImportSeparatesLanguageVersionsForNonJavaneseTracks() {
        val target = TrackMatcher.Target(
            title = "Butter (Japanese Version)",
            artist = "BTS",
            durationSec = 164,
            requiredArtistName = "BTS",
            requireExactTitle = true,
        )
        val original = Song(
            videoId = "english",
            title = "Butter",
            artist = "BTS",
            thumbnailUrl = null,
            durationText = "2:44",
        )
        val korean = original.copy(videoId = "korean", title = "Butter (Korean Version)")
        val japanese = original.copy(videoId = "japanese", title = "Butter (Japanese Version)")

        assertNull(TrackMatcher.best(listOf(original), target))
        assertNull(TrackMatcher.best(listOf(korean), target))
        assertEquals(japanese, TrackMatcher.best(listOf(original, korean, japanese), target))
    }

    @Test
    fun spotifyImportDoesNotTreatDjArtistPrefixAsARecordingVersion() {
        val target = TrackMatcher.Target(
            title = "Taki Taki",
            artist = "DJ Snake",
            durationSec = 212,
            requiredArtistName = "DJ Snake",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val artistPrefixedUpload = Song(
            videoId = "dj-snake-taki-taki",
            title = "DJ Snake - Taki Taki (Official Audio)",
            artist = "DJ Snake",
            thumbnailUrl = null,
            durationText = "3:32",
        )

        assertNotNull(TrackMatcher.best(listOf(artistPrefixedUpload), target))

        val remixTarget = target.copy(title = "Taki Taki (DJ Snake Remix)")
        val original = artistPrefixedUpload.copy(videoId = "original", title = "Taki Taki")
        val remix = artistPrefixedUpload.copy(videoId = "remix", title = "Taki Taki (DJ Snake Remix)")
        assertNull(TrackMatcher.best(listOf(original), remixTarget))
        assertNotNull(TrackMatcher.best(listOf(remix), remixTarget))
    }

    @Test
    fun languageNamesInOrdinaryPackagingDoNotBecomeVersionMarkers() {
        val target = TrackMatcher.Target(
            title = "Song",
            artist = "Band",
            durationSec = 210,
            requiredArtistName = "Band",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val packaging = Song(
            videoId = "hindi-medium-packaging",
            title = "Song (Hindi Medium)",
            artist = "Band",
            thumbnailUrl = null,
            durationText = "3:30",
        )
        val hindiVersion = packaging.copy(videoId = "hindi-version", title = "Song (Hindi Version)")

        assertNotNull(TrackMatcher.best(listOf(packaging), target))
        val versionTarget = target.copy(title = "Song (Hindi Version)")
        assertNull(TrackMatcher.best(listOf(packaging), versionTarget))
        assertNotNull(TrackMatcher.best(listOf(hindiVersion), versionTarget))
    }

    @Test
    fun spotifyImportDoesNotTreatSlowedAndSpedUpAsTheSameVersion() {
        val target = TrackMatcher.Target(
            title = "Roses (Sped Up)",
            artist = "Saint Jhn",
            durationSec = 150,
            requiredArtistName = "Saint Jhn",
            requireExactTitle = true,
        )
        val slowed = Song(
            videoId = "slowed",
            title = "Roses (Slowed + Reverb)",
            artist = "Saint Jhn",
            thumbnailUrl = null,
            durationText = "2:30",
        )

        assertNull(TrackMatcher.best(listOf(slowed), target))
        val speedUpSpelling = slowed.copy(videoId = "speed-up", title = "Roses (Speed Up)")
        assertNotNull(TrackMatcher.best(listOf(speedUpSpelling), target))
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
    fun genericGenreLabelsDoNotBecomeAlternateVersionsWithoutAnEditMarker() {
        val target = TrackMatcher.Target(
            title = "Song",
            artist = "Band",
            durationSec = 210,
            requiredArtistName = "Band",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val houseMusic = Song(
            videoId = "house-music",
            title = "Song (House Music)",
            artist = "Band",
            thumbnailUrl = null,
            durationText = "3:30",
        )
        assertNotNull(TrackMatcher.best(listOf(houseMusic), target))

        val djTarget = target.copy(title = "Song (DJ House Remix)")
        val original = houseMusic.copy(videoId = "original", title = "Song")
        val djHouse = houseMusic.copy(videoId = "dj-house", title = "Song (DJ House Remix)")
        assertNull(TrackMatcher.best(listOf(original), djTarget))
        assertEquals(djHouse, TrackMatcher.best(listOf(original, djHouse), djTarget))
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
