package com.music.bitchord.data.stats

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ListeningStatsFormatTest {

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    @Test
    fun olderTrackEntriesDecodeWithNewPlaybackFieldsDefaulted() {
        val legacy = """
            {
              "id": "legacy-video",
              "title": "Legacy song",
              "artist": "Artist",
              "ms": 120000,
              "plays": 2,
              "last": 1700000000000
            }
        """.trimIndent()

        val restored = json.decodeFromString<TrackEntry>(legacy)

        assertEquals("legacy-video", restored.id)
        assertNull(restored.releaseYear)
        assertNull(restored.downloadFormat)
        assertNull(restored.trackNumber)
        assertFalse(restored.isPodcastEpisode)
    }

    @Test
    fun playbackMetadataSurvivesListeningBucketSerialization() {
        val original = TrackEntry(
            id = "local-podcast-episode",
            title = "Episode",
            artist = "Podcast",
            releaseYear = 2021,
            localUri = "content://media/external/audio/media/88",
            localPath = "/storage/emulated/0/Podcasts/episode.m4a",
            sourceQuality = "LOSSLESS",
            sourceHiRes = true,
            isExplicit = false,
            downloadFormat = "FLAC",
            trackNumber = 7,
            isPodcastEpisode = true,
            ms = 360_000,
            plays = 1,
            last = 1_700_000_000_000,
        )

        val encoded = json.encodeToString(TrackEntry.serializer(), original)
        val restored = json.decodeFromString<TrackEntry>(encoded)

        assertEquals(original.releaseYear, restored.releaseYear)
        assertEquals(original.localUri, restored.localUri)
        assertEquals(original.localPath, restored.localPath)
        assertEquals(original.sourceQuality, restored.sourceQuality)
        assertEquals(original.downloadFormat, restored.downloadFormat)
        assertEquals(original.trackNumber, restored.trackNumber)
        assertTrue(restored.isPodcastEpisode)
    }
}
