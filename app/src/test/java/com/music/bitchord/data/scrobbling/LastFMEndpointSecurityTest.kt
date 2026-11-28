package com.music.bitchord.data.scrobbling

import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

class LastFMEndpointSecurityTest {

    @Test
    fun `only official HTTPS Last.fm and Libre FM endpoints are accepted`() {
        listOf(
            "https://ws.audioscrobbler.com/2.0/",
            "https://ws.audioscrobbler.com",
            "https://ws.audioscrobbler.com:443/2.0",
        ).forEach { raw ->
            assertEquals(LastFM.DEFAULT_API_ENDPOINT, LastFM.normalizeEndpoint(raw))
        }

        listOf(
            "https://libre.fm/2.0/",
            "https://libre.fm",
            "https://libre.fm:443/2.0",
        ).forEach { raw ->
            assertEquals(LastFM.LIBREFM_API_ENDPOINT, LastFM.normalizeEndpoint(raw))
        }
    }

    @Test
    fun `rejects arbitrary hosts cleartext and credential-bearing URLs`() {
        listOf(
            "http://ws.audioscrobbler.com/2.0/",
            "http://libre.fm/2.0/",
            "https://evil.example/2.0/",
            "https://ws.audioscrobbler.com.evil.example/2.0/",
            "https://audioscrobbler.com/2.0/",
            "https://user:pass@ws.audioscrobbler.com/2.0/",
            "https://ws.audioscrobbler.com:8443/2.0/",
            "https://ws.audioscrobbler.com/steal",
            "https://ws.audioscrobbler.com/2.0/?redirect=https://evil.example",
            "https://ws.audioscrobbler.com/2.0/#fragment",
            "javascript:alert(1)",
            "file:///tmp/lastfm",
            "",
        ).forEach { raw ->
            try {
                LastFM.normalizeEndpoint(raw)
                fail("unsafe endpoint should be rejected: $raw")
            } catch (_: IllegalArgumentException) {
                // Expected: only the official HTTPS endpoints can receive a signed request.
            }
        }
    }
}
