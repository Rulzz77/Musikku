package com.music.bitchord.data.spotify

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalPlaylistIdTest {

    @Test
    fun `locally saved Spotify playlists receive distinct stable-format IDs`() {
        val first = LocalPlaylistStore.newLocalPlaylistId()
        val second = LocalPlaylistStore.newLocalPlaylistId()

        assertNotEquals(first, second)
        assertTrue(first.startsWith("sp_local_"))
        assertTrue(second.startsWith("sp_local_"))
        assertEquals("sp_local_".length + 32, first.length)
        assertEquals("sp_local_".length + 32, second.length)
    }
}
