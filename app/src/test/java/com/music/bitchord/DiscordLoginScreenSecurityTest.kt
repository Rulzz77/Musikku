package com.music.bitchord

import com.music.bitchord.auth.isDiscordTokenCandidate
import com.music.bitchord.auth.isSignedIn
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DiscordLoginScreenSecurityTest {

    @Test
    fun `only the signed in Discord HTTPS origin is trusted for token alerts`() {
        assertTrue(isSignedIn("https://discord.com/app"))
        assertTrue(isSignedIn("https://discord.com/channels/@me"))
        assertTrue(isSignedIn("https://discord.com:443/app"))

        assertFalse(isSignedIn(null))
        assertFalse(isSignedIn("https://discord.com/login"))
        assertFalse(isSignedIn("https://discord.com/register"))
        assertFalse(isSignedIn("http://discord.com/app"))
        assertFalse(isSignedIn("https://discord.com.evil.example/app"))
        assertFalse(isSignedIn("https://discord.com@evil.example/app"))
        assertFalse(isSignedIn("https://evil.example/app"))
        assertFalse(isSignedIn("https://discord.com:444/app"))
    }

    @Test
    fun `rejects empty short oversized and non token alert values`() {
        assertTrue(isDiscordTokenCandidate("MTIzNDU2Nzg5MDEyMzQ1Njc4OTA"))
        assertTrue(isDiscordTokenCandidate("mfa.a1b2_c3-d4.e5f6g7h8"))
        assertFalse(isDiscordTokenCandidate(null))
        assertFalse(isDiscordTokenCandidate(""))
        assertFalse(isDiscordTokenCandidate("short"))
        assertFalse(isDiscordTokenCandidate("this has whitespace and cannot be a token"))
        assertFalse(isDiscordTokenCandidate("<script>alert(1)</script>"))
        assertFalse(isDiscordTokenCandidate("x".repeat(4_097)))
    }
}
