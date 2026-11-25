package com.music.bitchord.data.spotify

import com.music.bitchord.data.YtMusicRepository
import com.music.bitchord.data.model.Song
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SpotifyImporterAlbumFallbackTest {

    @Test
    fun usesSpotifyAlbumAsSearchContextWhenStandardQueriesCannotResolveTrack() = runBlocking {
        val source = SpotifyImportTrack(
            title = "The Song",
            artist = "Singer",
            durationMs = 180_000,
            album = "Studio Collection",
            leadArtist = "Singer",
            artistCredits = listOf("Singer"),
        )
        val albumCandidate = Song(
            videoId = "the-song-album-result",
            title = "The Song",
            artist = "Singer",
            thumbnailUrl = null,
            durationText = "3:00",
            albumName = "Studio Collection",
        )
        val searched = mutableListOf<Pair<String, YtMusicRepository.SpotifyImportSearchKind>>()

        val candidates = SpotifyImporter.searchCandidates(source) { query, kind ->
            searched += query to kind
            if (
                query == "Singer The Song Studio Collection" &&
                kind == YtMusicRepository.SpotifyImportSearchKind.TRACK
            ) {
                Result.success(listOf(albumCandidate))
            } else {
                Result.success(emptyList())
            }
        }

        assertTrue(
            searched.any {
                it.first == "Singer The Song Studio Collection" &&
                    it.second == YtMusicRepository.SpotifyImportSearchKind.TRACK
            },
        )
        assertEquals(albumCandidate, LinerSpotifyMatcher.evaluate(source, candidates).track)
    }

    @Test
    fun albumFallbackDoesNotRunAfterAConfidentStandardMatch() = runBlocking {
        val source = SpotifyImportTrack(
            title = "The Song",
            artist = "Singer",
            durationMs = 180_000,
            album = "Studio Collection",
            leadArtist = "Singer",
            artistCredits = listOf("Singer"),
        )
        val exact = Song(
            videoId = "the-song-exact",
            title = "The Song",
            artist = "Singer",
            thumbnailUrl = null,
            durationText = "3:00",
        )
        val searched = mutableListOf<String>()

        SpotifyImporter.searchCandidates(source) { query, kind ->
            searched += query
            if (query == "Singer The Song" && kind == YtMusicRepository.SpotifyImportSearchKind.TRACK) {
                Result.success(listOf(exact))
            } else {
                Result.success(emptyList())
            }
        }

        assertFalse(searched.any { it == "Singer The Song Studio Collection" })
    }

    @Test
    fun albumContextDoesNotAllowAnIncorrectRecordingVersion() = runBlocking {
        val source = SpotifyImportTrack(
            title = "The Song",
            artist = "Singer",
            durationMs = 180_000,
            album = "Studio Collection",
            leadArtist = "Singer",
            artistCredits = listOf("Singer"),
        )
        val wrongVersion = Song(
            videoId = "the-song-remix",
            title = "The Song (Remix)",
            artist = "Singer",
            thumbnailUrl = null,
            durationText = "3:00",
            albumName = "Studio Collection",
        )

        val candidates = SpotifyImporter.searchCandidates(source) { query, kind ->
            if (
                query == "Singer The Song Studio Collection" &&
                kind == YtMusicRepository.SpotifyImportSearchKind.TRACK
            ) {
                Result.success(listOf(wrongVersion))
            } else {
                Result.success(emptyList())
            }
        }

        assertTrue(candidates.any { it.videoId == wrongVersion.videoId })
        assertNull(LinerSpotifyMatcher.evaluate(source, candidates).track)
    }
}
