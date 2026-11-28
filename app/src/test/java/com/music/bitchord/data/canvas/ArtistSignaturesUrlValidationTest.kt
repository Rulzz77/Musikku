package com.music.bitchord.data.canvas

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ArtistSignaturesUrlValidationTest {

    @Test
    fun `accepts normal manually configured HTTP and HTTPS API origins`() {
        assertTrue(ArtistSignatureRepository.isValidBaseUrl("https://signatures.example.com"))
        assertTrue(ArtistSignatureRepository.isValidBaseUrl("https://signatures.example.com/api/v1"))
        assertTrue(ArtistSignatureRepository.isValidBaseUrl("http://192.168.1.10:8080"))
        assertTrue(ArtistSignatureRepository.isValidBaseUrl("http://localhost:8080"))
    }

    @Test
    fun `rejects malformed or credential-bearing endpoints`() {
        listOf(
            "",
            "not a URL",
            "javascript:alert(1)",
            "file:///etc/passwd",
            "ftp://signatures.example.com",
            "https://user:pass@signatures.example.com",
            "https://signatures.example.com:99999",
            "https://signatures.example.com/api?token=abc",
            "https://signatures.example.com/api#fragment",
            "https://signatures.example.com/../admin",
            "x".repeat(501),
        ).forEach { assertFalse(ArtistSignatureRepository.isValidBaseUrl(it)) }
    }
}
