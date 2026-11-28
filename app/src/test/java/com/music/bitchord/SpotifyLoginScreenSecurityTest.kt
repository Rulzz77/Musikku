package com.music.bitchord

import com.music.bitchord.auth.isSpotifyPlayerLanding
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpotifyLoginScreenSecurityTest {

    @Test
    fun `only exact Spotify player origin completes login`() {
        assertTrue(isSpotifyPlayerLanding("https://open.spotify.com/"))
        assertTrue(isSpotifyPlayerLanding("https://open.spotify.com:443/"))
        assertFalse(isSpotifyPlayerLanding(null))
        assertFalse(isSpotifyPlayerLanding("http://open.spotify.com/"))
        assertFalse(isSpotifyPlayerLanding("https://open.spotify.com.evil.example/"))
        assertFalse(isSpotifyPlayerLanding("https://open.spotify.com@evil.example/"))
        assertFalse(isSpotifyPlayerLanding("https://accounts.spotify.com/"))
        assertFalse(isSpotifyPlayerLanding("https://open.spotify.com:444/"))
        assertFalse(isSpotifyPlayerLanding("https://user:pass@open.spotify.com/"))
    }
}
