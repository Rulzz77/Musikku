package com.music.bitchord

import com.music.bitchord.data.canvas.isAllowedSpotifyNavigation
import com.music.bitchord.data.canvas.isSpotifyPlayerOrigin
import com.music.bitchord.data.canvas.isValidSpotifyAccessToken
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SpotifyTokenWebViewSecurityTest {

    @Test
    fun `only the exact Spotify player origin can report access tokens`() {
        assertTrue(isSpotifyPlayerOrigin("https://open.spotify.com/"))
        assertTrue(isSpotifyPlayerOrigin("https://open.spotify.com:443/api/token"))
        assertFalse(isSpotifyPlayerOrigin("http://open.spotify.com/"))
        assertFalse(isSpotifyPlayerOrigin("https://open.spotify.com.evil.example/"))
        assertFalse(isSpotifyPlayerOrigin("https://open.spotify.com@evil.example/"))
        assertFalse(isSpotifyPlayerOrigin("https://accounts.spotify.com/"))
        assertFalse(isSpotifyPlayerOrigin("https://open.spotify.com:444/"))
        assertFalse(isSpotifyPlayerOrigin(null))
    }

    @Test
    fun `top level WebView navigation stays within Spotify login and player origins`() {
        assertTrue(isAllowedSpotifyNavigation("https://open.spotify.com/"))
        assertTrue(isAllowedSpotifyNavigation("https://accounts.spotify.com/login"))
        assertFalse(isAllowedSpotifyNavigation("http://open.spotify.com/"))
        assertFalse(isAllowedSpotifyNavigation("https://evil.example/"))
        assertFalse(isAllowedSpotifyNavigation("https://open.spotify.com.evil.example/"))
        assertFalse(isAllowedSpotifyNavigation("https://user:pass@open.spotify.com/"))
        assertFalse(isAllowedSpotifyNavigation("https://open.spotify.com:444/"))
        assertFalse(isAllowedSpotifyNavigation("javascript:alert(1)"))
    }

    @Test
    fun `Spotify access token candidate rejects malformed and unbounded payloads`() {
        assertTrue(isValidSpotifyAccessToken("BQDAbcdefghijklmnopqrstuvwxyz_1234567890"))
        assertTrue(isValidSpotifyAccessToken("eyJhbGciOiJub25lIn0.abc_def-1234567890"))
        assertFalse(isValidSpotifyAccessToken(""))
        assertFalse(isValidSpotifyAccessToken("short"))
        assertFalse(isValidSpotifyAccessToken("token with spaces"))
        assertFalse(isValidSpotifyAccessToken("<script>alert(1)</script>"))
        assertFalse(isValidSpotifyAccessToken("x".repeat(4_097)))
    }
}
