package com.music.bitchord

import com.music.bitchord.data.model.Song
import com.music.bitchord.data.spotify.appendUniqueImportedTracks
import com.music.bitchord.data.spotify.dedupeSongs
import org.junit.Assert.assertEquals
import org.junit.Test

class ImportedPlaylistTracksTest {

    private fun song(id: String, title: String = id) = Song(
        videoId = id,
        title = title,
        artist = "Artist",
        thumbnailUrl = null,
    )

    @Test
    fun `new tracks append after existing tracks in selection order`() {
        val existing = listOf(song("old"))
        val incoming = listOf(song("new-a"), song("new-b"))

        val (result, added) = appendUniqueImportedTracks(existing, incoming)

        assertEquals(2, added)
        assertEquals(listOf("old", "new-a", "new-b"), result.map { it.videoId })
    }

    @Test
    fun `existing and repeated incoming tracks are not duplicated`() {
        val existing = listOf(song("already"))
        val incoming = listOf(song("already"), song("fresh"), song("fresh"))

        val (result, added) = appendUniqueImportedTracks(existing, incoming)

        assertEquals(1, added)
        assertEquals(listOf("already", "fresh"), result.map { it.videoId })
    }

    @Test
    fun `blank video ids are ignored`() {
        val (result, added) = appendUniqueImportedTracks(emptyList(), listOf(song(""), song("valid")))

        assertEquals(1, added)
        assertEquals(listOf("valid"), result.map { it.videoId })
    }
    @Test
    fun `saving an imported playlist removes duplicate video ids and blank ids`() {
        val songs = listOf(song("one"), song("two"), song("one", "Duplicate title"), song(""))

        assertEquals(listOf("one", "two"), dedupeSongs(songs).map { it.videoId })
    }

    @Test
    fun `duplicate video ids with surrounding whitespace are not appended twice`() {
        val existing = listOf(song("known"))
        val incoming = listOf(song(" known "), song("fresh"))

        val (result, added) = appendUniqueImportedTracks(existing, incoming)

        assertEquals(1, added)
        assertEquals(listOf("known", "fresh"), result.map { it.videoId })
    }
}
