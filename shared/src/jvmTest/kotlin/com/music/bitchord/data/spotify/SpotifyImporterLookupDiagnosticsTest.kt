package com.music.bitchord.data.spotify

import com.music.bitchord.data.YtMusicRepository
import com.music.bitchord.data.model.Song
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SpotifyImporterLookupDiagnosticsTest {

    @Test
    fun completedEmptySearchIsReportedAsUnmatchedNotLookupFailure() = runBlocking {
        val source = SpotifyImportTrack(
            title = "The Song",
            artist = "Singer",
            durationMs = 180_000,
            spotifyId = "diagnostic-empty-search-track",
            leadArtist = "Singer",
            artistCredits = listOf("Singer"),
        )
        var lookupFailures = emptyList<SpotifyImportTrack>()

        val (songs, unmatched) = SpotifyImporter.resolveToSongsWithDiagnostics(
            tracks = listOf(source),
            searchRaw = { _, _ -> Result.success(emptyList()) },
            onLookupFailures = { lookupFailures = it },
            onProgress = { _, _ -> },
        )

        assertTrue(songs.isEmpty())
        assertEquals(listOf(source), unmatched)
        assertTrue(lookupFailures.isEmpty())
    }

    @Test
    fun failedSearchIsReportedAsRetryableLookupFailure() = runBlocking {
        val source = SpotifyImportTrack(
            title = "The Song",
            artist = "Singer",
            durationMs = 180_000,
            spotifyId = "diagnostic-failed-search-track",
            leadArtist = "Singer",
            artistCredits = listOf("Singer"),
        )
        var lookupFailures = emptyList<SpotifyImportTrack>()

        val (songs, unmatched) = SpotifyImporter.resolveToSongsWithDiagnostics(
            tracks = listOf(source),
            searchRaw = { _, _ -> Result.failure(IllegalStateException("HTTP 503")) },
            onLookupFailures = { lookupFailures = it },
            onProgress = { _, _ -> },
        )

        assertTrue(songs.isEmpty())
        assertEquals(listOf(source), unmatched)
        assertEquals(listOf(source), lookupFailures)
    }

    @Test
    fun partialLookupFailureIsNotHiddenByAnUnrelatedCandidate() = runBlocking {
        val source = SpotifyImportTrack(
            title = "The Song",
            artist = "Singer",
            durationMs = 180_000,
            spotifyId = "diagnostic-partial-search-track",
            leadArtist = "Singer",
            artistCredits = listOf("Singer"),
        )
        val unrelated = Song(
            videoId = "unrelated-search-result",
            title = "Different Song",
            artist = "Different Artist",
            thumbnailUrl = null,
            durationText = "3:00",
        )
        var lookupFailures = emptyList<SpotifyImportTrack>()

        val (songs, unmatched) = SpotifyImporter.resolveToSongsWithDiagnostics(
            tracks = listOf(source),
            searchRaw = { query, kind ->
                when {
                    query == "Singer The Song" &&
                        kind == YtMusicRepository.SpotifyImportSearchKind.TRACK ->
                        Result.success(listOf(unrelated))
                    query == "Singer The Song" &&
                        kind == YtMusicRepository.SpotifyImportSearchKind.ALL ->
                        Result.failure(IllegalStateException("timeout"))
                    else -> Result.success(emptyList())
                }
            },
            onLookupFailures = { lookupFailures = it },
            onProgress = { _, _ -> },
        )

        assertTrue(songs.isEmpty())
        assertEquals(listOf(source), unmatched)
        assertEquals(listOf(source), lookupFailures)
    }
}
