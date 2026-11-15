package com.music.bitchord.data.spotify

import com.music.bitchord.data.model.ArtistRef
import com.music.bitchord.data.YtMusicRepository
import com.music.bitchord.data.model.BrowseItem
import com.music.bitchord.data.model.BrowseType
import com.music.bitchord.data.model.SearchResult
import com.music.bitchord.data.model.Song
import com.music.bitchord.data.sources.TrackMatcher
import com.music.bitchord.data.innertube.InnertubeParser
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
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
    fun searchParserReadsTrackIdsFromEveryLinerSupportedEndpoint() {
        val cases = listOf(
            "title-run" to "title",
            "row-on-tap" to "onTap",
            "row-navigation-endpoint" to "navigationEndpoint",
        )

        for ((id, location) in cases) {
            val titleRunEndpoint = if (location == "title") {
                """, "navigationEndpoint": {"watchEndpoint": {"videoId": "$id"}}"""
            } else {
                ""
            }
            val rowEndpoint = when (location) {
                "onTap" -> """"onTap": {"watchEndpoint": {"videoId": "$id"}},"""
                "navigationEndpoint" -> """"navigationEndpoint": {"watchEndpoint": {"videoId": "$id"}},"""
                else -> ""
            }
            val response = Json.parseToJsonElement(
                """
                {
                  "contents": [{
                    "musicResponsiveListItemRenderer": {
                      $rowEndpoint
                      "flexColumns": [
                        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [
                          {"text": "Talaga Reumis"$titleRunEndpoint}
                        ]}}},
                        {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [
                          {"text": "Song"}, {"text": " • "},
                          {"text": "Gasentra Pajampangan"}, {"text": " • "},
                          {"text": "4:03"}
                        ]}}}
                      ],
                      "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [
                        {"url": "https://example.invalid/cover.jpg", "width": 544, "height": 544}
                      ]}}}
                    }
                  }]
                }
                """.trimIndent(),
            ).jsonObject

            val result = InnertubeParser.parseSearchPage(
                response,
                includeAllTrackTypes = true,
                musicOnly = true,
            ).rows.single()

            assertEquals(id, spotifyImportCandidate(result)?.videoId, "id location: $location")
        }
    }

    @Test
    fun spotifyTrackFilterKeepsWidescreenCandidatesInsteadOfDroppingThem() {
        val response = Json.parseToJsonElement(
            """
            {
              "contents": [{
                "musicResponsiveListItemRenderer": {
                  "flexColumns": [
                    {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [
                      {"text": "Talaga Reumis", "navigationEndpoint": {
                        "watchEndpoint": {"videoId": "talaga-reumis-widescreen"}
                      }}
                    ]}}},
                    {"musicResponsiveListItemFlexColumnRenderer": {"text": {"runs": [
                      {"text": "Song"}, {"text": " • "},
                      {"text": "Gasentra Pajampangan"}, {"text": " • "},
                      {"text": "4:03"}
                    ]}}}
                  ],
                  "thumbnail": {"musicThumbnailRenderer": {"thumbnail": {"thumbnails": [
                    {"url": "https://example.invalid/widescreen.jpg", "width": 544, "height": 306}
                  ]}}}
                }
              }]
            }
            """.trimIndent(),
        ).jsonObject

        // The ordinary screen parser uses a widescreen-art heuristic and
        // drops this row from Songs. Liner's import keeps the result because
        // it came from the server's dedicated TRACK filter.
        assertTrue(
            InnertubeParser.parseSearchPage(response, musicOnly = true).rows.isEmpty(),
        )

        val importedRow = InnertubeParser.parseSearchPage(
            response,
            includeAllTrackTypes = true,
            musicOnly = true,
        ).rows.single()
        val parsedSong = assertNotNull(spotifyImportCandidate(importedRow))
        assertTrue(parsedSong.isVideo)

        val normalized = YtMusicRepository.normalizeSpotifyImportCandidate(
            parsedSong,
            YtMusicRepository.SpotifyImportSearchKind.TRACK,
        )
        assertEquals("talaga-reumis-widescreen", normalized.videoId)
        assertFalse(normalized.isVideo)
        assertFalse(normalized.isVideoOrigin)
    }

    @Test
    fun videoSearchParserPreservesPromotedVideoCardWithSquareArtwork() {
        val response = Json.parseToJsonElement(
            """
            {
              "contents": [{
                "musicCardShelfRenderer": {
                  "onTap": { "watchEndpoint": { "videoId": "promoted-sundanese-video" } },
                  "title": { "runs": [{ "text": "TALAGA REUMIS (Nining Meida) - Nanih (Pop Sunda Cover)" }] },
                  "subtitle": { "runs": [
                    { "text": "Gasentra Pajampangan" },
                    { "text": " • " },
                    { "text": "6:43" }
                  ] },
                  "thumbnail": { "musicThumbnailRenderer": {
                    "thumbnail": { "thumbnails": [{
                      "url": "https://example.invalid/square-cover.jpg",
                      "width": 544,
                      "height": 544
                    }] }
                  } }
                }
              }]
            }
            """.trimIndent(),
        ).jsonObject

        val rows = InnertubeParser.parseSearchPage(
            response,
            includeVideos = true,
            musicOnly = true,
        ).rows

        val promoted = rows.single()
        assertTrue(promoted is SearchResult.TopTrack)
        val song = assertNotNull(spotifyImportCandidate(promoted))
        assertEquals("promoted-sundanese-video", song.videoId)
        // The server returned this from the dedicated Videos filter, so its
        // square thumbnail must not make the importer classify it as audio.
        assertTrue(song.isVideo)
    }

    @Test
    fun linerSpotifyMatcherUsesWeightedFuzzyTitleAndArtistScoring() {
        val source = SpotifyImportTrack(
            title = "Talaga Reumis",
            artist = "Gasantra Pajampangan, Nanih",
            durationMs = 243_000,
            leadArtist = "Gasantra Pajampangan",
            artistCredits = listOf("Gasantra Pajampangan", "Nanih"),
        )
        val regionalSpelling = Song(
            videoId = "liner-regional-spelling",
            title = "Telaga Reumis",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "4:03",
        )

        val decision = LinerSpotifyMatcher.evaluate(source, listOf(regionalSpelling))
        assertEquals(regionalSpelling, decision.track)
        assertTrue((decision.score ?: 0) >= 75)
        assertEquals(
            "Gasantra Pajampangan Talaga Reumis",
            LinerSpotifyMatcher.searchQuery(source),
        )
    }

    @Test
    fun linerSpotifyMatcherBuildsFallbackQueriesFromSecondarySingers() {
        val tracks = listOf(
            SpotifyImportTrack(
                title = "Jalir Janji",
                artist = "Gasentra Pajampangan, Nina",
                leadArtist = "Gasentra Pajampangan",
                artistCredits = listOf("Gasentra Pajampangan", "Nina"),
            ),
            SpotifyImportTrack(
                title = "Ulah Ceurik",
                artist = "Gasentra Pajampangan, Revina Alvira",
                leadArtist = "Gasentra Pajampangan",
                artistCredits = listOf("Gasentra Pajampangan", "Revina Alvira"),
            ),
            SpotifyImportTrack(
                title = "Talaga Reumis",
                artist = "Gasentra Pajampangan, Nanih",
                leadArtist = "Gasentra Pajampangan",
                artistCredits = listOf("Gasentra Pajampangan", "Nanih"),
            ),
            SpotifyImportTrack(
                title = "Kamana Cintana",
                artist = "Gasentra Pajampangan, Nina",
                leadArtist = "Gasentra Pajampangan",
                artistCredits = listOf("Gasentra Pajampangan", "Nina"),
            ),
            SpotifyImportTrack(
                title = "Bogoh Kasaha",
                artist = "Gasentra Pajampangan, Friska",
                leadArtist = "Gasentra Pajampangan",
                artistCredits = listOf("Gasentra Pajampangan", "Friska"),
            ),
        )

        assertEquals(
            listOf(
                listOf("Nina Jalir Janji"),
                listOf("Revina Alvira Ulah Ceurik"),
                listOf("Nanih Talaga Reumis"),
                listOf("Nina Kamana Cintana"),
                listOf("Friska Bogoh Kasaha"),
            ),
            tracks.map { LinerSpotifyMatcher.alternateArtistSearchQueries(it) },
        )
    }

    @Test
    fun linerSpotifyMatcherRecognizesBothRegionalTitleArtistOrders() {
        fun source(title: String, singer: String, durationMs: Long) = SpotifyImportTrack(
            title = title,
            artist = "Gasentra Pajampangan, $singer",
            durationMs = durationMs,
            leadArtist = "Gasentra Pajampangan",
            artistCredits = listOf("Gasentra Pajampangan", singer),
        )
        fun candidate(id: String, title: String, duration: String) = Song(
            videoId = id,
            title = title,
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = duration,
        )

        val samples = listOf(
            source("Jalir Janji", "Nina", 302_000) to candidate(
                "jalir-janji-nina",
                "JALIR JANJI - Nina (Pop Sunda Cover)",
                "5:02",
            ),
            source("Ulah Ceurik", "Revina Alvira", 270_000) to candidate(
                "ulah-ceurik-revina",
                "Revina Alvira - ULAH CEURIK (Official Music Video)",
                "4:30",
            ),
            source("Talaga Reumis", "Nanih", 403_000) to candidate(
                "talaga-reumis-nanih",
                "TALAGA REUMIS (Nining Meida) - Nanih (Pop Sunda Cover)",
                "6:43",
            ),
            source("Kamana Cintana", "Nina", 360_000) to candidate(
                "kamana-cintana-nina",
                "NINA - KAMANA CINTANA (Official Music Video) | Pop Sunda",
                "6:00",
            ),
            source("Bogoh Kasaha", "Friska", 341_000) to candidate(
                "bogoh-kasaha-friska",
                "BOGOH KASAHA - FRISKA",
                "5:41",
            ),
        )

        for ((spotifyTrack, youtubeTrack) in samples) {
            val decision = LinerSpotifyMatcher.evaluate(spotifyTrack, listOf(youtubeTrack))
            assertEquals(
                youtubeTrack,
                decision.track,
                "failed title/artist order: ${spotifyTrack.title} -> ${youtubeTrack.title}; reason=${decision.reason}, score=${decision.score}",
            )
        }
    }

    @Test
    fun linerSpotifyMatcherRejectsDifferentSingerAndWrongVersion() {
        val source = SpotifyImportTrack(
            title = "Dumes (Live)",
            artist = "Guyon Waton",
            durationMs = 210_000,
            leadArtist = "Guyon Waton",
            artistCredits = listOf("Guyon Waton"),
        )
        val wrongSinger = Song(
            videoId = "liner-wrong-singer",
            title = "Dumes (Live)",
            artist = "Different Singer",
            thumbnailUrl = null,
            durationText = "3:30",
        )
        val wrongVersion = Song(
            videoId = "liner-wrong-version",
            title = "Dumes",
            artist = "Guyon Waton",
            thumbnailUrl = null,
            durationText = "3:30",
        )

        assertNull(LinerSpotifyMatcher.evaluate(source, listOf(wrongSinger)).track)
        assertNull(LinerSpotifyMatcher.evaluate(source, listOf(wrongVersion)).track)
    }

    @Test
    fun linerSpotifyMatcherDoesNotApproveAmbiguousNearTitleCandidates() {
        val source = SpotifyImportTrack(
            title = "Pulang",
            artist = "Insomniacks",
            durationMs = 230_000,
            leadArtist = "Insomniacks",
            artistCredits = listOf("Insomniacks"),
        )
        val first = Song(
            videoId = "liner-pulang-one",
            title = "Pulangx",
            artist = "Insomniacks",
            thumbnailUrl = null,
            durationText = "3:56",
        )
        val second = Song(
            videoId = "liner-pulang-two",
            title = "Pulangy",
            artist = "Insomniacks",
            thumbnailUrl = null,
            durationText = "3:57",
        )

        val decision = LinerSpotifyMatcher.evaluate(source, listOf(first, second))
        assertNull(decision.track)
    }

    @Test
    fun durationOnlyComposerOverrideDoesNotCountAsTrustedArtistCredit() {
        val target = TrackMatcher.Target(
            title = "Terlalu Sayang",
            artist = "Gasentra Pajampangan, Revina Alvira",
            durationSec = 346,
            requiredArtistName = "Gasentra Pajampangan",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Gasentra Pajampangan", "Revina Alvira"),
        )
        val composerOnly = Song(
            videoId = "duration-only-credit",
            title = "Terlalu Sayang",
            artist = "Unrelated Composer",
            thumbnailUrl = null,
            durationText = "5:46",
        )

        // The generic matcher must not treat an uncredited composer as the
        // requested singer. The importer has a separate, last-resort fallback
        // after every credited audio/video candidate has been considered.
        assertNull(TrackMatcher.best(listOf(composerOnly), target))
        assertFalse(TrackMatcher.hasTrustedArtistCredit(composerOnly, target))
        assertEquals(composerOnly, bestSpotifyImportMatch(listOf(composerOnly), target))

        // Spotify import keeps the historical composer/uploader exception only
        // when the runtime is within one second. A wider gap is not reliable
        // enough to silently choose a different recording.
        assertNull(TrackMatcher.best(listOf(composerOnly.copy(durationText = "5:49")), target))
        assertNull(bestSpotifyImportMatch(listOf(composerOnly.copy(durationText = "5:48")), target))
        assertNull(TrackMatcher.best(listOf(composerOnly.copy(isVideo = true)), target))
        assertNull(bestSpotifyImportMatch(listOf(composerOnly.copy(isVideo = true)), target))

        val albumTarget = target.copy(album = "Album Asli")
        assertNull(
            bestSpotifyImportMatch(
                listOf(composerOnly.copy(albumName = "Album Kompilasi")),
                albumTarget,
            ),
        )
        assertEquals(
            composerOnly.copy(albumName = "Album Asli"),
            bestSpotifyImportMatch(listOf(composerOnly.copy(albumName = "Album Asli")), albumTarget),
        )
    }

    @Test
    fun spotifyImportUsesLinerStyleFuzzyTitleAndArtistScoringForRegionalCredits() {
        val target = TrackMatcher.Target(
            title = "Talaga Reumis",
            artist = "Gasantra Pajampangan, Nanih",
            durationSec = 243,
            requiredArtistName = "Gasantra Pajampangan",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Gasantra Pajampangan", "Nanih"),
        )
        val catalogueSpelling = Song(
            videoId = "liner-fuzzy-regional-spelling",
            title = "Telaga Reumis",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "4:03",
        )

        // Liner Desktop scores title + full artist tokens instead of demanding
        // exact strings. This covers a regional title spelling and a transposed
        // letter in a long performer name.
        assertNotNull(TrackMatcher.best(listOf(catalogueSpelling), target))
        assertEquals(
            catalogueSpelling,
            bestSpotifyImportMatch(listOf(catalogueSpelling), target),
        )

        // Fuzzy identity must not become a duration-only shortcut.
        assertNull(
            TrackMatcher.best(
                listOf(catalogueSpelling.copy(durationText = "4:20")),
                target,
            ),
        )
        assertNull(
            TrackMatcher.best(
                listOf(catalogueSpelling.copy(artist = "Unrelated Singer")),
                target,
            ),
        )

        // Keep complete artist-name boundaries: "X Ambassadors" is not
        // the unrelated artist "Ambassadors".
        val xTarget = target.copy(
            title = "Renegades",
            artist = "X Ambassadors",
            requiredArtistName = "X Ambassadors",
            artistCredits = listOf("X Ambassadors"),
        )
        assertNull(
            TrackMatcher.best(
                listOf(catalogueSpelling.copy(
                    title = "Renegades",
                    artist = "Ambassadors",
                    durationText = "4:03",
                )),
                xTarget,
            ),
        )
    }

    @Test
    fun spotifyImportLinerFuzzyMatchingStillRejectsWrongVersion() {
        val target = TrackMatcher.Target(
            title = "Talaga Reumis",
            artist = "Gasantra Pajampangan, Nanih",
            durationSec = 243,
            requiredArtistName = "Gasantra Pajampangan",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Gasantra Pajampangan", "Nanih"),
        )
        val live = Song(
            videoId = "liner-fuzzy-live",
            title = "Telaga Reumis (Live)",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "4:03",
        )
        assertNull(TrackMatcher.best(listOf(live), target))
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
    fun spotifyImportAllowsSecondarySpotifySingersOnVideosWithVisualDurationDrift() {
        val fixtures = listOf(
            "Talaga Reumis" to "Nanih",
            "Kamana Cintana" to "Nina",
            "Bogon Kasaha" to "Friska",
        )

        fixtures.forEachIndexed { index, (title, singer) ->
            val target = TrackMatcher.Target(
                title = title,
                artist = "Gasentra Pajampangan, $singer",
                durationSec = 240,
                requiredArtistName = "Gasentra Pajampangan",
                requireSharedArtist = true,
                requireExactTitle = true,
                artistCredits = listOf("Gasentra Pajampangan", singer),
            )
            val officialVideo = Song(
                videoId = "gasentra-video-$index",
                title = title,
                artist = singer,
                thumbnailUrl = null,
                durationText = "5:10",
                isVideo = true,
            )

            // The YouTube byline may expose only Spotify's secondary vocalist.
            // A video may also run longer because of its visual intro/outro.
            assertNotNull(TrackMatcher.best(listOf(officialVideo), target), title)
            assertEquals(officialVideo, bestSpotifyImportMatch(listOf(officialVideo), target), title)

            // Do not extend this exception to audio-only catalogue tracks.
            assertNull(
                TrackMatcher.best(
                    listOf(officialVideo.copy(videoId = "audio-$index", isVideo = false)),
                    target,
                ),
                title,
            )

            // The video allowance is bounded at 90 seconds, not unlimited.
            assertNotNull(
                TrackMatcher.best(listOf(officialVideo.copy(durationText = "5:30")), target),
                title,
            )
            assertNull(
                TrackMatcher.best(listOf(officialVideo.copy(durationText = "5:31")), target),
                title,
            )

            // A title match and runtime alone must not admit a different singer.
            assertNull(
                TrackMatcher.best(
                    listOf(officialVideo.copy(artist = "Different Singer")),
                    target,
                ),
                title,
            )
        }
    }

    @Test
    fun spotifyImportAllowsFlattenedCollaborativeCreditOnMatchingMusicVideo() {
        val target = TrackMatcher.Target(
            title = "Bogon Kasaha",
            artist = "Gasentra Pajampangan, Friska",
            durationSec = 240,
            requiredArtistName = "Gasentra Pajampangan",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Gasentra Pajampangan", "Friska"),
        )
        // Some catalogue rows flatten both Spotify credits into one byline.
        val flattenedCredit = Song(
            videoId = "bogon-kasaha-flattened-credit",
            title = "Bogon Kasaha",
            artist = "Friska Gasentra",
            thumbnailUrl = null,
            durationText = "5:10",
            isVideo = true,
        )

        assertNotNull(TrackMatcher.best(listOf(flattenedCredit), target))
        assertEquals(flattenedCredit, bestSpotifyImportMatch(listOf(flattenedCredit), target))
    }

    @Test
    fun spotifyImportRejectsWrongVersionEvenWhenVideoCreditAndRuntimeAreClose() {
        val target = TrackMatcher.Target(
            title = "Talaga Reumis",
            artist = "Gasentra Pajampangan, Nanih",
            durationSec = 240,
            requiredArtistName = "Gasentra Pajampangan",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Gasentra Pajampangan", "Nanih"),
        )
        val liveVersion = Song(
            videoId = "talaga-reumis-live",
            title = "Talaga Reumis (Live)",
            artist = "Nanih",
            thumbnailUrl = null,
            durationText = "5:10",
            isVideo = true,
        )

        assertNull(TrackMatcher.best(listOf(liveVersion), target))
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
    fun spotifyImportMatchesRepresentativePlaylistTitleAndCreditStyles() {
        // Verified examples from the supplied Spotify track-ID list:
        // punctuation in ".Feast"/"o,Tuan", commas in long titles, lower-case
        // track names, and regional spelling/diacritic variation.
        val feast = TrackMatcher.Target(
            title = "o,Tuan",
            artist = ".Feast",
            durationSec = 305,
            requiredArtistName = ".Feast",
            requireExactTitle = true,
        )
        val feastCandidate = Song(
            videoId = "playlist-fixture-o-tuan",
            title = "o,Tuan",
            artist = "Feast",
            thumbnailUrl = null,
            durationText = "5:05",
        )

        val hindiaLongTitle = TrackMatcher.Target(
            title = "Berdansalah, Karir Ini Tak Ada Artinya",
            artist = "Hindia",
            durationSec = 224,
            requiredArtistName = "Hindia",
            requireExactTitle = true,
        )
        val hindiaCandidate = Song(
            videoId = "playlist-fixture-berdansalah",
            title = "Berdansalah, Karir Ini Tak Ada Artinya",
            artist = "Hindia",
            thumbnailUrl = null,
            durationText = "3:44",
        )

        val hindiaLowerCase = TrackMatcher.Target(
            title = "everything u are",
            artist = "Hindia",
            durationSec = 236,
            requiredArtistName = "Hindia",
            requireExactTitle = true,
        )
        val hindiaLowerCaseCandidate = Song(
            videoId = "playlist-fixture-everything-u-are",
            title = "Everything U Are",
            artist = "Hindia",
            thumbnailUrl = null,
            durationText = "3:56",
        )

        val nucaCommaTitle = TrackMatcher.Target(
            title = "Masa ini, Nanti, dan Masa Indah Lainnya",
            artist = "Nuca",
            durationSec = 275,
            requiredArtistName = "Nuca",
            requireExactTitle = true,
        )
        val nucaCandidate = Song(
            videoId = "playlist-fixture-masa-ini",
            title = "Masa Ini, Nanti, dan Masa Indah Lainnya",
            artist = "Nuca",
            thumbnailUrl = null,
            durationText = "4:35",
        )

        val boaAccent = TrackMatcher.Target(
            title = "Duvet",
            artist = "bôa",
            durationSec = 200,
            requiredArtistName = "bôa",
            requireExactTitle = true,
        )
        val boaCandidate = Song(
            videoId = "playlist-fixture-duvet",
            title = "Duvet",
            artist = "boa",
            thumbnailUrl = null,
            durationText = "3:20",
        )

        assertNotNull(TrackMatcher.best(listOf(feastCandidate), feast))
        assertNotNull(TrackMatcher.best(listOf(hindiaCandidate), hindiaLongTitle))
        assertNotNull(TrackMatcher.best(listOf(hindiaLowerCaseCandidate), hindiaLowerCase))
        assertNotNull(TrackMatcher.best(listOf(nucaCandidate), nucaCommaTitle))
        assertNotNull(TrackMatcher.best(listOf(boaCandidate), boaAccent))
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
    fun spotifyImportRetainsAlbumBrowseFallbackButNotOtherBrowseTypes() {
        val album = SearchResult.Browse(
            BrowseItem(
                browseId = "MPREb-album-id",
                title = "Album Lagu",
                subtitle = "Album • Band Contoh",
                thumbnailUrl = null,
                type = BrowseType.ALBUM,
            ),
        )
        val artist = SearchResult.Browse(
            BrowseItem(
                browseId = "UC-artist-id",
                title = "Band Contoh",
                subtitle = "Artist",
                thumbnailUrl = null,
                type = BrowseType.ARTIST,
            ),
        )
        val playlist = SearchResult.Browse(
            BrowseItem(
                browseId = "VL-playlist-id",
                title = "Playlist Lagu",
                subtitle = "Playlist",
                thumbnailUrl = null,
                type = BrowseType.PLAYLIST,
            ),
        )
        val track = SearchResult.Track(
            Song(
                videoId = "song-id",
                title = "Lagu",
                artist = "Band Contoh",
                thumbnailUrl = null,
            ),
        )

        assertEquals("MPREb-album-id", spotifyImportAlbumBrowseId(album))
        assertNull(spotifyImportAlbumBrowseId(artist))
        assertNull(spotifyImportAlbumBrowseId(playlist))
        assertNull(spotifyImportAlbumBrowseId(track))
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
    fun artistPageFallbackFindsTheMatchingSecondaryStructuredYoutubeCredit() {
        val song = Song(
            videoId = "secondary-artist-page-song",
            title = "Budak Saha",
            artist = "Primary Label, Friska",
            thumbnailUrl = null,
            artistId = "UCprimary",
            artists = listOf(
                ArtistRef(name = "Primary Label", browseId = "UCprimary"),
                ArtistRef(name = "Friska", browseId = "UCfriska"),
            ),
        )

        assertEquals("UCfriska", spotifyArtistBrowseId(song, "Friska"))
        assertNull(spotifyArtistBrowseId(song, "Unrelated Singer"))
    }

    @Test
    fun spotifyImportPrefersTrustedArtistOverDurationOnlyComposerFallback() {
        val target = TrackMatcher.Target(
            title = "Terlalu Sayang",
            artist = "Gasentra Pajampangan, Revina Alvira",
            durationSec = 346,
            requiredArtistName = "Gasentra Pajampangan",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Gasentra Pajampangan", "Revina Alvira"),
        )
        val composerOnly = Song(
            videoId = "composer-only",
            title = "Terlalu Sayang",
            artist = "Unrelated Composer",
            thumbnailUrl = null,
            durationText = "5:46",
        )
        val officialSinger = Song(
            videoId = "official-singer",
            title = "Terlalu Sayang",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "5:47",
        )
        val officialVideo = officialSinger.copy(
            videoId = "official-video",
            durationText = "6:20",
            isVideo = true,
        )

        assertEquals(
            officialSinger,
            bestSpotifyImportMatch(listOf(composerOnly, officialSinger), target),
        )
        // A credited official video is still preferable to an uncredited audio fallback.
        assertEquals(
            officialVideo,
            bestSpotifyImportMatch(listOf(composerOnly, officialVideo), target),
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
    fun linerSpotifyMatcherBuildsSearchQueryFromLeadArtistAndCleanTitle() {
        val source = SpotifyImportTrack(
            title = "Tanpo Tresnamu (Official Audio)",
            artist = "Denny Caknan, Yeni Inka",
            durationMs = 252_000,
            album = "Album Contoh",
            leadArtist = "Denny Caknan",
            artistCredits = listOf("Denny Caknan", "Yeni Inka"),
        )

        assertEquals("Tanpo Tresnamu", LinerSpotifyMatcher.cleanedTitle(source))
        assertEquals("Denny Caknan Tanpo Tresnamu", LinerSpotifyMatcher.searchQuery(source))
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
    fun artistPageLookupAcceptsOnlyAUniqueNearSpellingAndPrefersExactNames() {
        val near = BrowseItem(
            browseId = "UC-gasentra",
            title = "Gasentra Pajampangan",
            subtitle = "Artist",
            thumbnailUrl = null,
            type = BrowseType.ARTIST,
        )
        val secondNear = near.copy(
            browseId = "UC-other",
            title = "Gasantra Pajanpangan",
        )
        val exact = near.copy(
            browseId = "UC-exact",
            title = "Gasantra Pajampangan",
        )

        assertEquals(
            "UC-gasentra",
            YtMusicRepository.artistPageIdForName("Gasantra Pajampangan", listOf(near)),
        )
        assertNull(
            YtMusicRepository.artistPageIdForName("Gasantra Pajampangan", listOf(near, secondNear)),
        )
        assertEquals(
            "UC-exact",
            YtMusicRepository.artistPageIdForName("Gasantra Pajampangan", listOf(near, exact)),
        )
    }

    @Test
    fun spotifyImportAcceptsSingleCharacterArtistSpellingVariantWithCloseRuntime() {
        val target = TrackMatcher.Target(
            title = "Terlalu Sayang",
            artist = "Gasantra Pajampangan, Revina Alvira",
            durationSec = 346,
            requiredArtistName = "Gasantra Pajampangan",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("Gasantra Pajampangan", "Revina Alvira"),
        )
        val officialRecording = Song(
            videoId = "terlalu-sayang-gasentra",
            title = "Terlalu Sayang",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "5:47",
        )

        assertTrue(TrackMatcher.nearArtistSpelling("Gasantra Pajampangan", "Gasentra Pajampangan"))
        assertNotNull(TrackMatcher.best(listOf(officialRecording), target))
        assertTrue(TrackMatcher.hasTrustedArtistCredit(officialRecording, target))
        assertNull(TrackMatcher.best(listOf(officialRecording.copy(durationText = null)), target))
        // Small uploader/runtime rounding differences are common; the alias
        // remains guarded by a close (eight-second) runtime ceiling.
        assertNotNull(TrackMatcher.best(listOf(officialRecording.copy(durationText = "5:54")), target))
        assertNull(TrackMatcher.best(listOf(officialRecording.copy(durationText = "5:55")), target))
        assertNull(TrackMatcher.best(listOf(officialRecording.copy(durationText = "4:50")), target))
        assertNull(TrackMatcher.best(listOf(officialRecording.copy(title = "Terlalu Sayang (Live)")), target))

        val joinedByline = officialRecording.copy(
            videoId = "terlalu-sayang-gasentra-feat-revina",
            artist = "Gasentra Pajampangan feat. Revina Alvira",
        )
        assertNotNull(TrackMatcher.best(listOf(joinedByline), target))
        assertTrue(TrackMatcher.hasTrustedArtistCredit(joinedByline, target))
    }

    @Test
    fun nearArtistSpellingRejectsShortNamesAndMultipleMisspelledWords() {
        assertFalse(TrackMatcher.nearArtistSpelling("DJ", "DJS"))
        assertFalse(TrackMatcher.nearArtistSpelling("Gasantra Pajampangan", "Gasentro Pajanpangan"))
        assertFalse(TrackMatcher.nearArtistSpelling("Gasantra Pajampangan", "Gasentra"))
    }

    @Test
    fun spotifyImportTreatsOfficialLiveMusicAsUploadPackagingButKeepsRealLiveVersionsDistinct() {
        val target = TrackMatcher.Target(
            title = "Keloas",
            artist = "Rena Movies",
            durationSec = 210,
            requiredArtistName = "Rena Movies",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val officialLabelUpload = Song(
            videoId = "keloas-official-live-music",
            title = "Keloas (Official Live Music)",
            artist = "Rena Movies",
            thumbnailUrl = null,
            durationText = "3:30",
        )
        val actualLivePerformance = officialLabelUpload.copy(
            videoId = "keloas-live-at-stage",
            title = "Keloas (Live at Stage)",
        )

        assertNotNull(TrackMatcher.best(listOf(officialLabelUpload), target))
        assertNull(TrackMatcher.best(listOf(actualLivePerformance), target))
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
    fun spotifyImportHandlesSafeTitleSpellingAndAccentVariants() {
        val titleTarget = TrackMatcher.Target(
            title = "Tanpo Tresnamu",
            artist = "Denny Caknan",
            durationSec = 252,
            requiredArtistName = "Denny Caknan",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val oneLetterCatalogueVariant = Song(
            videoId = "tanpa-tresnamu",
            title = "Tanpa Tresnamu",
            artist = "Denny Caknan",
            thumbnailUrl = null,
            durationText = "4:12",
        )

        assertNotNull(TrackMatcher.best(listOf(oneLetterCatalogueVariant), titleTarget))
        assertNull(
            TrackMatcher.best(
                listOf(oneLetterCatalogueVariant.copy(artist = "Another Singer")),
                titleTarget,
            ),
        )
        assertNull(
            TrackMatcher.best(
                listOf(oneLetterCatalogueVariant.copy(durationText = "4:20")),
                titleTarget,
            ),
        )

        val accentTarget = titleTarget.copy(
            title = "Canción",
            artist = "Banda Ejemplo",
            requiredArtistName = "Banda Ejemplo",
            durationSec = 200,
        )
        val unaccentedCatalogue = oneLetterCatalogueVariant.copy(
            videoId = "cancion-unaccented",
            title = "Cancion",
            artist = "Banda Ejemplo",
            durationText = "3:20",
        )
        assertNotNull(TrackMatcher.best(listOf(unaccentedCatalogue), accentTarget))
    }

    @Test
    fun spotifyImportNormalizesRegionalLanguageVersionAliases() {
        fun target(title: String) = TrackMatcher.Target(
            title = title,
            artist = "Dendi Nata",
            durationSec = 200,
            requiredArtistName = "Dendi Nata",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        fun candidate(title: String) = Song(
            videoId = "abadi-language-version",
            title = title,
            artist = "Dendi Nata",
            thumbnailUrl = null,
            durationText = "3:20",
        )

        assertNotNull(
            TrackMatcher.best(
                listOf(candidate("Abadi (Indonesian Version)")),
                target("Abadi - Indo Version"),
            ),
        )
        assertNotNull(
            TrackMatcher.best(
                listOf(candidate("Abadi - Indo Version")),
                target("Abadi (Indonesian Version)"),
            ),
        )
        assertNull(
            TrackMatcher.best(
                listOf(candidate("Abadi")),
                target("Abadi - Indo Version"),
            ),
        )

        assertNotNull(
            TrackMatcher.best(
                listOf(candidate("Lagu (Javanese Version)")),
                target("Lagu - Jawa Version").copy(title = "Lagu - Jawa Version"),
            ),
        )
        assertNotNull(
            TrackMatcher.best(
                listOf(candidate("Lagu (Sundanese Version)")),
                target("Lagu - Sunda Version").copy(title = "Lagu - Sunda Version"),
            ),
        )
    }

    @Test
    fun spotifyImportAcceptsOfficialFeaturedDescriptionInIndonesianTitle() {
        val target = TrackMatcher.Target(
            title = "Sampai Jadi Debu (Menampilkan Gardika Gigih)",
            artist = "Banda Neira",
            durationSec = 240,
            requiredArtistName = "Banda Neira",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val catalogueTrack = Song(
            videoId = "sampai-jadi-debu-catalogue",
            title = "Sampai Jadi Debu",
            artist = "Banda Neira",
            thumbnailUrl = null,
            durationText = "4:00",
        )

        assertNotNull(TrackMatcher.best(listOf(catalogueTrack), target))
    }

    @Test
    fun spotifyImportPreservesVersionAndReleaseLabelsFromPlaylistSamples() {
        fun target(
            title: String,
            artist: String,
            lead: String,
            credits: List<String> = listOf(lead),
        ) = TrackMatcher.Target(
            title = title,
            artist = artist,
            durationSec = 210,
            requiredArtistName = lead,
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = credits,
        )
        fun candidate(
            id: String,
            title: String,
            artist: String,
        ) = Song(
            videoId = id,
            title = title,
            artist = artist,
            thumbnailUrl = null,
            durationText = "3:30",
        )

        // Remaster and Radio Edit are release/catalogue labels in this matcher,
        // while alternate edits such as Acoustic, Slowed and Extended remain distinct.
        val remaster = target(
            "Please, Please, Please, Let Me Get What I Want - 2011 Remaster",
            "The Smiths",
            "The Smiths",
        )
        assertNotNull(
            TrackMatcher.best(
                listOf(candidate("smiths-remaster-catalogue", "Please, Please, Please, Let Me Get What I Want", "The Smiths")),
                remaster,
            ),
        )

        val radioEdit = target("Dusk Till Dawn (feat. Sia) - Radio Edit", "ZAYN, Sia", "ZAYN", listOf("ZAYN", "Sia"))
        assertNotNull(
            TrackMatcher.best(
                listOf(candidate("dusk-till-dawn-catalogue", "Dusk Till Dawn", "ZAYN, Sia")),
                radioEdit,
            ),
        )

        val extended = target("Somebody's Pleasure (Extended Version)", "Aziz Hedra", "Aziz Hedra")
        val extendedSong = candidate("somebodys-pleasure-extended", "Somebody's Pleasure (Extended Version)", "Aziz Hedra")
        val standardSong = candidate("somebodys-pleasure-standard", "Somebody's Pleasure", "Aziz Hedra")
        assertNotNull(TrackMatcher.best(listOf(extendedSong), extended))
        assertNull(TrackMatcher.best(listOf(standardSong), extended))

        val acoustic = target(
            "Take Me Home (feat. Bebe Rexha) - Acoustic",
            "Cash Cash, Bebe Rexha",
            "Cash Cash",
            listOf("Cash Cash", "Bebe Rexha"),
        )
        val acousticSong = candidate("take-me-home-acoustic", "Take Me Home (Acoustic)", "Cash Cash, Bebe Rexha")
        val originalSong = candidate("take-me-home-original", "Take Me Home", "Cash Cash, Bebe Rexha")
        assertNotNull(TrackMatcher.best(listOf(acousticSong), acoustic))
        assertNull(TrackMatcher.best(listOf(originalSong), acoustic))

        val slowed = target("Heat Waves - Slowed", "Glass Animals", "Glass Animals")
        assertNull(
            TrackMatcher.best(
                listOf(candidate("heat-waves-original", "Heat Waves", "Glass Animals")),
                slowed,
            ),
        )

        val dangdut = target("Nemen - Hiphop Dangdut Version", "NDX A.K.A.", "NDX A.K.A.")
        assertNotNull(
            TrackMatcher.best(
                listOf(candidate("nemen-dangdut", "Nemen - Hiphop Dangdut Version", "NDX A.K.A.")),
                dangdut,
            ),
        )
        assertNull(
            TrackMatcher.best(
                listOf(candidate("nemen-original", "Nemen", "NDX A.K.A.")),
                dangdut,
            ),
        )

        val mashup = target(
            "Die With A Smile x Glimpse Of Us (Mashup)",
            "Luke Willies, OURGRND",
            "Luke Willies",
            listOf("Luke Willies", "OURGRND"),
        )
        assertNotNull(
            TrackMatcher.best(
                listOf(candidate("die-with-a-smile-glimpse-mashup", "Die With A Smile x Glimpse Of Us (Mashup)", "Luke Willies, OURGRND")),
                mashup,
            ),
        )

        val duet = target(
            "Until I Found You (with Em Beihold) - Em Beihold Version",
            "Stephen Sanchez, Em Beihold",
            "Stephen Sanchez",
            listOf("Stephen Sanchez", "Em Beihold"),
        )
        val duetSong = candidate(
            "until-i-found-you-em-beihold",
            "Until I Found You (with Em Beihold) - Em Beihold Version",
            "Stephen Sanchez, Em Beihold",
        )
        val soloSong = candidate("until-i-found-you-solo", "Until I Found You", "Stephen Sanchez")
        assertNotNull(TrackMatcher.best(listOf(duetSong), duet))
        assertNull(TrackMatcher.best(listOf(soloSong), duet))
    }

    @Test
    fun spotifyImportMatchesBrooklynSessionAndYearRemasterPlaylistTitles() {
        val remasterTarget = TrackMatcher.Target(
            title = "Voor Dilan #III: Dulu Kita Masih Remaja - 2018 Remaster",
            artist = "The Panasdalam Bank",
            durationSec = 240,
            requiredArtistName = "The Panasdalam Bank",
            requireSharedArtist = true,
            requireExactTitle = true,
        )
        val remasterCatalogue = Song(
            videoId = "voor-dilan-iii-catalogue",
            title = "Voor Dilan #III: Dulu Kita Masih Remaja",
            artist = "The Panasdalam Bank",
            thumbnailUrl = null,
            durationText = "4:00",
        )

        val sessionTarget = TrackMatcher.Target(
            title = "Location Unknown ◐ (feat. BEKA) - Brooklyn Session",
            artist = "HONNE, BEKA",
            durationSec = 200,
            requiredArtistName = "HONNE",
            requireSharedArtist = true,
            requireExactTitle = true,
            artistCredits = listOf("HONNE", "BEKA"),
        )
        val sessionCatalogue = Song(
            videoId = "location-unknown-brooklyn-session",
            title = "Location Unknown (Brooklyn Session)",
            artist = "HONNE, BEKA",
            thumbnailUrl = null,
            durationText = "3:20",
        )
        val ordinaryRecording = sessionCatalogue.copy(
            videoId = "location-unknown-original",
            title = "Location Unknown",
        )

        assertNotNull(TrackMatcher.best(listOf(remasterCatalogue), remasterTarget))
        assertNotNull(TrackMatcher.best(listOf(sessionCatalogue), sessionTarget))
        assertNull(TrackMatcher.best(listOf(ordinaryRecording), sessionTarget))
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


    @Test
    fun linerSpotifyMatcherPreservesHyphenAndColonInsideSpotifyTitles() {
        val slowed = SpotifyImportTrack(
            title = "Heat Waves - Slowed",
            artist = "Glass Animals",
            durationMs = 180_000,
            leadArtist = "Glass Animals",
            artistCredits = listOf("Glass Animals"),
        )
        assertEquals("Heat Waves - Slowed", LinerSpotifyMatcher.cleanedTitle(slowed))
        assertEquals(
            "Glass Animals Heat Waves - Slowed",
            LinerSpotifyMatcher.searchQuery(slowed),
        )
        val slowedCandidate = Song(
            videoId = "heat-waves-slowed",
            title = "Heat Waves (Slowed)",
            artist = "Glass Animals",
            thumbnailUrl = null,
            durationText = "3:00",
        )
        assertEquals(slowedCandidate, LinerSpotifyMatcher.evaluate(slowed, listOf(slowedCandidate)).track)

        val colonTitle = SpotifyImportTrack(
            title = "Voor Dilan #III: Dulu Kita Masih Remaja",
            artist = "The Panasdalam Bank",
            durationMs = 240_000,
            leadArtist = "The Panasdalam Bank",
            artistCredits = listOf("The Panasdalam Bank"),
        )
        assertEquals(
            "The Panasdalam Bank Voor Dilan #III: Dulu Kita Masih Remaja",
            LinerSpotifyMatcher.searchQuery(colonTitle),
        )
        val colonCandidate = Song(
            videoId = "voor-dilan-iii",
            title = "Voor Dilan #III: Dulu Kita Masih Remaja",
            artist = "The Panasdalam Bank",
            thumbnailUrl = null,
            durationText = "4:00",
        )
        assertEquals(
            colonCandidate,
            LinerSpotifyMatcher.evaluate(colonTitle, listOf(colonCandidate)).track,
        )
    }

    @Test
    fun linerSpotifyMatcherRejectsAnExplicitWrongVocalistAndChoosesCreditedSinger() {
        val source = SpotifyImportTrack(
            title = "Bogoh Kasaha",
            artist = "Gasentra Pajampangan, Friska",
            durationMs = 341_000,
            leadArtist = "Gasentra Pajampangan",
            artistCredits = listOf("Gasentra Pajampangan", "Friska"),
        )
        val wrongSinger = Song(
            videoId = "bogoh-kasaha-nanih",
            title = "Bogoh Kasaha - Nanih",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "5:41",
        )
        val correctSinger = Song(
            videoId = "bogoh-kasaha-friska",
            title = "Bogoh Kasaha - Friska",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "5:41",
        )

        assertNull(LinerSpotifyMatcher.evaluate(source, listOf(wrongSinger)).track)
        assertEquals(
            correctSinger,
            LinerSpotifyMatcher.evaluate(source, listOf(wrongSinger, correctSinger)).track,
        )
    }

    @Test
    fun linerSpotifyMatcherSkipsInvalidTopRankedCandidateAndUsesNextEligibleOne() {
        val source = SpotifyImportTrack(
            title = "Bogoh Kasaha",
            artist = "Gasentra Pajampangan, Friska",
            durationMs = 341_000,
            leadArtist = "Gasentra Pajampangan",
            artistCredits = listOf("Gasentra Pajampangan", "Friska"),
        )
        val higherScoringButConflicting = Song(
            videoId = "wrong-vocalist-higher-score",
            title = "Bogoh Kasaha - Nanih",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "5:41",
        )
        val lowerScoringValid = Song(
            videoId = "valid-next-candidate",
            title = "Bogoh Kas",
            artist = "Friska",
            thumbnailUrl = null,
            durationText = null,
        )

        assertEquals(
            lowerScoringValid,
            LinerSpotifyMatcher.evaluate(
                source,
                listOf(higherScoringButConflicting, lowerScoringValid),
            ).track,
        )
    }

    @Test
    fun spotifyImporterSearchesSecondaryVocalistAfterProvisionalLabelMatch() = runBlocking {
        val source = SpotifyImportTrack(
            title = "Kamana Cintana",
            artist = "Gasentra Pajampangan, Nina",
            durationMs = 360_000,
            leadArtist = "Gasentra Pajampangan",
            artistCredits = listOf("Gasentra Pajampangan", "Nina"),
        )
        val labelOnly = Song(
            videoId = "kamana-label-only",
            title = "Kamana Cintana",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "6:00",
        )
        val singerIdentified = Song(
            videoId = "kamana-nina",
            title = "Nina - Kamana Cintana",
            artist = "Gasentra Pajampangan",
            thumbnailUrl = null,
            durationText = "6:00",
        )
        val searchedQueries = mutableListOf<String>()

        val candidates = SpotifyImporter.searchCandidates(
            source = source,
            searchRaw = { query, kind ->
                searchedQueries += "$query [${kind.name}]"
                when {
                    query == "Gasentra Pajampangan Kamana Cintana" &&
                        kind == YtMusicRepository.SpotifyImportSearchKind.TRACK ->
                        Result.success(listOf(labelOnly))
                    query == "Nina Kamana Cintana" &&
                        kind == YtMusicRepository.SpotifyImportSearchKind.TRACK ->
                        Result.success(listOf(singerIdentified))
                    else -> Result.success(emptyList())
                }
            },
        )

        assertTrue(searchedQueries.any { it.startsWith("Nina Kamana Cintana") })
        assertEquals(singerIdentified, LinerSpotifyMatcher.evaluate(source, candidates).track)
    }

    @Test
    fun spotifyImporterContinuesSearchWhenLanguageFilterRejectsInitialCandidate() = runBlocking {
        val source = SpotifyImportTrack(
            title = "Song",
            artist = "Singer",
            durationMs = 180_000,
            leadArtist = "Singer",
            artistCredits = listOf("Singer"),
        )
        val hindi = Song(
            videoId = "song-hindi",
            title = "Song (Hindi Version)",
            artist = "Singer",
            thumbnailUrl = null,
            durationText = "3:00",
        )
        val tamil = Song(
            videoId = "song-tamil",
            title = "Song (Tamil Version)",
            artist = "Singer",
            thumbnailUrl = null,
            durationText = "3:00",
        )
        val searchedQueries = mutableListOf<String>()

        val candidates = SpotifyImporter.searchCandidates(
            source = source,
            suffix = "Tamil",
            searchRaw = { query, kind ->
                searchedQueries += "$query [${kind.name}]"
                when {
                    query == "Singer Song" &&
                        kind == YtMusicRepository.SpotifyImportSearchKind.TRACK ->
                        Result.success(listOf(hindi))
                    query == "Singer Song Tamil" &&
                        kind == YtMusicRepository.SpotifyImportSearchKind.TRACK ->
                        Result.success(listOf(tamil))
                    else -> Result.success(emptyList())
                }
            },
        )

        assertTrue(searchedQueries.any { it.startsWith("Singer Song Tamil") })
        assertFalse(candidates.any { it.videoId == hindi.videoId })
        assertEquals(tamil, LinerSpotifyMatcher.evaluate(source, candidates).track)
    }

}
