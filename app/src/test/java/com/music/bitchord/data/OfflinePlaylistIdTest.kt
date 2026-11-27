package com.music.bitchord.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class OfflinePlaylistIdTest {

    @Test
    fun `new playlists receive unique stable-format identifiers`() {
        val first = OfflinePlaylists.newPlaylistId()
        val second = OfflinePlaylists.newPlaylistId()

        assertNotEquals(first, second)
        assertTrue(first.startsWith("p"))
        assertTrue(second.startsWith("p"))
        assertEquals(33, first.length)
        assertEquals(33, second.length)
    }
}
