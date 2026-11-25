package com.music.bitchord

import com.music.bitchord.data.PlaylistFolder
import com.music.bitchord.data.assignPlaylistToFolder
import com.music.bitchord.data.mergePlaylistFolders
import com.music.bitchord.data.normalizePlaylistFolders
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlaylistFoldersTest {

    @Test
    fun `normalization removes blank and duplicate folder ids and duplicate playlist membership`() {
        val normalized = normalizePlaylistFolders(
            listOf(
                PlaylistFolder(" first ", " Favourites ", listOf(" playlist:a ", "playlist:a", "")),
                PlaylistFolder("first", "Duplicate id", listOf("playlist:b")),
                PlaylistFolder("second", "Road trips", listOf("playlist:a", "playlist:b")),
                PlaylistFolder("third", "  ", listOf("playlist:c")),
            ),
        )

        assertEquals(
            listOf(
                PlaylistFolder("first", "Favourites", listOf("playlist:a")),
                PlaylistFolder("second", "Road trips", listOf("playlist:b")),
            ),
            normalized,
        )
    }

    @Test
    fun `assigning a playlist moves it out of its previous folder`() {
        val folders = listOf(
            PlaylistFolder("one", "One", listOf("playlist:a", "playlist:b")),
            PlaylistFolder("two", "Two", listOf("playlist:c")),
        )

        val moved = assignPlaylistToFolder(folders, "two", "playlist:a")

        assertEquals(listOf("playlist:b"), moved[0].playlistBrowseIds)
        assertEquals(listOf("playlist:c", "playlist:a"), moved[1].playlistBrowseIds)
        assertEquals(
            1,
            moved.sumOf { folder -> folder.playlistBrowseIds.count { it == "playlist:a" } },
        )
    }

    @Test
    fun `merge combines memberships without duplicating playlist references`() {
        val merged = mergePlaylistFolders(
            current = listOf(PlaylistFolder("mix", "My Mix", listOf("playlist:a"))),
            incoming = listOf(
                PlaylistFolder("mix", "Renamed in backup", listOf("playlist:a", "playlist:b")),
                PlaylistFolder("new", "Workout", listOf("playlist:c")),
            ),
        )

        assertEquals(
            listOf(
                PlaylistFolder("mix", "My Mix", listOf("playlist:a", "playlist:b")),
                PlaylistFolder("new", "Workout", listOf("playlist:c")),
            ),
            merged,
        )
    }

    @Test
    fun `normalization keeps playlists in only their first folder`() {
        val normalized = normalizePlaylistFolders(
            listOf(
                PlaylistFolder("first", "First", listOf("playlist:a")),
                PlaylistFolder("second", "Second", listOf("playlist:a", "playlist:b")),
            ),
        )

        assertEquals(listOf("playlist:a"), normalized[0].playlistBrowseIds)
        assertEquals(listOf("playlist:b"), normalized[1].playlistBrowseIds)
        assertFalse(normalized[1].playlistBrowseIds.contains("playlist:a"))
        assertTrue(normalized.all { it.title.isNotBlank() })
    }

    @Test
    fun `deleting a folder from a collection leaves other folders and playlist references intact`() {
        val folders = listOf(
            PlaylistFolder("one", "One", listOf("playlist:a")),
            PlaylistFolder("two", "Two", listOf("playlist:b")),
        )

        val afterDelete = folders.filterNot { it.id == "one" }

        assertEquals(listOf(PlaylistFolder("two", "Two", listOf("playlist:b"))), afterDelete)
        assertEquals("playlist:a", folders.first().playlistBrowseIds.single())
    }
}
