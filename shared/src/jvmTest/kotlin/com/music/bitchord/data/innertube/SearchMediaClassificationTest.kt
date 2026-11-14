package com.music.bitchord.data.innertube

import com.music.bitchord.data.model.SearchResult
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SearchMediaClassificationTest {

    private fun response(
        type: String?,
        width: Int,
        height: Int,
        rowType: String = "Song",
    ): kotlinx.serialization.json.JsonObject {
        val typeConfig = type?.let {
            """, "navigationEndpoint": { "watchEndpoint": {
                "watchEndpointMusicSupportedConfigs": { "watchEndpointMusicConfig": {
                    "musicVideoType": "$it"
                } }
            } }"""
        }.orEmpty()
        return Json.parseToJsonElement(
            """
            {
              "contents": [{
                "musicResponsiveListItemRenderer": {
                  "playlistItemData": { "videoId": "track-1" },
                  "flexColumns": [
                    { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [{ "text": "Example Track" }] }
                    } },
                    { "musicResponsiveListItemFlexColumnRenderer": {
                      "text": { "runs": [
                        { "text": "$rowType" }, { "text": " • " },
                        { "text": "Example Artist" }, { "text": " • " },
                        { "text": "3:30" }
                      ] }
                    } }
                  ],
                  "thumbnail": { "musicThumbnailRenderer": {
                    "thumbnail": { "thumbnails": [{
                      "url": "https://example.invalid/cover.jpg",
                      "width": $width,
                      "height": $height
                    }] }
                  } }
                  $typeConfig
                }
              }]
            }
            """.trimIndent(),
        ).jsonObject
    }

    @Test
    fun songsSearchKeepsWidescreenTrackEvenWhenYouTubeSaysAudio() {
        val page = InnertubeParser.parseSearchPage(
            response("MUSIC_VIDEO_TYPE_ATV", width = 544, height = 306),
            includeAllTrackTypes = true,
        )

        assertEquals(1, page.rows.size)
        assertTrue((page.rows.single() as SearchResult.Track).song.isVideo)
    }

    @Test
    fun restoresPreviousRuleForSquareArtworkEvenWhenYouTubeSaysMusicVideo() {
        val page = InnertubeParser.parseSearchPage(
            response("MUSIC_VIDEO_TYPE_OMV", width = 544, height = 544),
        )

        assertEquals(1, page.rows.size)
        val song = (page.rows.single() as SearchResult.Track).song
        assertEquals("track-1", song.videoId)
        assertFalse(song.isVideo)
    }

    @Test
    fun explicitVideoSearchStillIncludesSquareArtwork() {
        val page = InnertubeParser.parseSearchPage(
            response("MUSIC_VIDEO_TYPE_OMV", width = 544, height = 544),
            includeVideos = true,
        )

        assertEquals(1, page.rows.size)
        assertTrue((page.rows.single() as SearchResult.Track).song.isVideo)
    }

    @Test
    fun songsSearchKeepsExplicitVideoRowsFromTheMusicCatalogue() {
        val page = InnertubeParser.parseSearchPage(
            response(type = null, width = 544, height = 544, rowType = "Video"),
            includeAllTrackTypes = true,
        )
        assertEquals(1, page.rows.size)
        assertTrue((page.rows.single() as SearchResult.Track).song.isVideo)
    }

    @Test
    fun defaultParserStillUsesTheLegacyAudioOnlyRule() {
        val page = InnertubeParser.parseSearchPage(
            response(type = null, width = 544, height = 544, rowType = "Video"),
        )
        assertTrue(page.rows.isEmpty())
    }

    @Test
    fun musicOnlySearchExcludesPodcastEpisodes() {
        val page = InnertubeParser.parseSearchPage(
            response(
                type = "MUSIC_VIDEO_TYPE_PODCAST_EPISODE",
                width = 544,
                height = 306,
                rowType = "Episode",
            ),
            includeAllTrackTypes = true,
            musicOnly = true,
        )

        assertTrue(page.rows.isEmpty())
    }

    @Test
    fun ordinaryParserCanStillReadPodcastEpisodesOutsideMusicSearch() {
        val page = InnertubeParser.parseSearchPage(
            response(
                type = "MUSIC_VIDEO_TYPE_PODCAST_EPISODE",
                width = 544,
                height = 306,
                rowType = "Episode",
            ),
            includeAllTrackTypes = true,
        )

        assertEquals(1, page.rows.size)
        assertTrue((page.rows.single() as SearchResult.Track).song.isPodcastEpisode)
    }

    @Test
    fun unknownDimensionsDoNotHideTrack() {
        val page = InnertubeParser.parseSearchPage(
            response(type = null, width = 0, height = 0),
        )
        assertEquals(1, page.rows.size)
    }
}
