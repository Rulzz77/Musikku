package com.music.bitchord

import com.music.bitchord.auth.isYouTubeMusicOrigin
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class YtMusicLoginScreenSecurityTest {

    @Test
    fun `only exact HTTPS YouTube Music origin is accepted for session capture`() {
        assertTrue(isYouTubeMusicOrigin("https://music.youtube.com/"))
        assertTrue(isYouTubeMusicOrigin("https://music.youtube.com:443/watch?v=abc"))
        assertFalse(isYouTubeMusicOrigin(null))
        assertFalse(isYouTubeMusicOrigin("http://music.youtube.com/"))
        assertFalse(isYouTubeMusicOrigin("https://music.youtube.com.evil.example/"))
        assertFalse(isYouTubeMusicOrigin("https://music.youtube.com@evil.example/"))
        assertFalse(isYouTubeMusicOrigin("https://youtube.com/"))
        assertFalse(isYouTubeMusicOrigin("https://music.youtube.com:444/"))
        assertFalse(isYouTubeMusicOrigin("https://user:pass@music.youtube.com/"))
    }
}
