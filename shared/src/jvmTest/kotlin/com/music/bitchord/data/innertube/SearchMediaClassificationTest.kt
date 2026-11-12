package com.music.bitchord.data.innertube

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class SearchMediaClassificationTest {

    private fun response(type: String?, width: Int, height: Int): kotlinx.serialization.json.JsonObject {
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
                        { "text": "Song" }, { "text": " • " },
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
    fun audioTrackWithWidescreenArtworkRemainsInSongsSearch() {
        val page = InnertubeParser.parseSearchPage(
            response("MUSIC_VIDEO_TYPE_ATV", width = 544, height = 306),
        )

        assertEquals(1, page.rows.size)
        val song = (page.rows.single() as SearchResult.Track).song
        assertEquals("track-1", song.videoId)
        assertFalse(song.isVideo)
    }

    @Test
    fun officialMusicVideoWithSquareArtworkStaysOutOfSongsSearch() {
        val page = InnertubeParser.parseSearchPage(
            response("MUSIC_VIDEO_TYPE_OMV", width = 544, height = 544),
        )

        assertTrue(page.rows.isEmpty())
    }

    @Test
    fun explicitVideoSearchIncludesVideoEvenWhenArtworkIsSquare() {
        val page = InnertubeParser.parseSearchPage(
            response("MUSIC_VIDEO_TYPE_OMV", width = 544, height = 544),
            includeVideos = true,
        )

        assertEquals(1, page.rows.size)
        assertTrue((page.rows.single() as SearchResult.Track).song.isVideo)
    }

    @Test
    fun missingMediaTypeDoesNotInferVideoFromWidescreenArtwork() {
        val page = InnertubeParser.parseSearchPage(
            response(type = null, width = 544, height = 306),
        )

        assertEquals(1, page.rows.size)
        assertFalse((page.rows.single() as SearchResult.Track).song.isVideo)
    }
}
