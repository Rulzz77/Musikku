package com.music.bitchord.data.listentogether

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PartyImageUrlTest {

    @Test
    fun `accepts normal public HTTP and HTTPS image URLs`() {
        assertTrue(isSafePartyImageUrl("https://i.ytimg.com/vi/abc/hqdefault.jpg"))
        assertTrue(isSafePartyImageUrl("https://cdn.example.com:8443/avatar.webp?size=96"))
        assertTrue(isSafePartyImageUrl("http://images.example.net/cover.png"))
        assertTrue(isSafePartyImageUrl("https://[2606:4700:4700::1111]/image.png"))
        assertTrue(isSafePartyImageUrl("https://192.0.1.1/image.png"))
    }

    @Test
    fun `rejects non HTTP schemes malformed URLs and embedded credentials`() {
        listOf(
            null,
            "",
            "javascript:alert(1)",
            "data:image/png;base64,AAAA",
            "file:///etc/passwd",
            "ftp://example.com/image.png",
            "https://user:pass@example.com/image.png",
            "https://example.com:99999/image.png",
            "https://example.com:0/image.png",
            "https://example.com\\\\image.png",
            "https://example.com/${"x".repeat(4_100)}",
        ).forEach { assertFalse(isSafePartyImageUrl(it), "unexpectedly accepted: $it") }
    }

    @Test
    fun `rejects local private and special use IPv4 destinations`() {
        listOf(
            "https://localhost/image.png",
            "https://printer.local/image.png",
            "https://host.lan/image.png",
            "https://127.0.0.1/image.png",
            "https://127.1/image.png",
            "https://0x7f000001/image.png",
            "https://10.0.0.8/image.png",
            "https://100.64.0.1/image.png",
            "https://169.254.169.254/latest/meta-data/",
            "https://172.16.0.1/image.png",
            "https://192.168.1.1/image.png",
            "https://198.18.0.1/image.png",
            "https://203.0.113.1/image.png",
        ).forEach { assertFalse(isSafePartyImageUrl(it), "unexpectedly accepted: $it") }
    }

    @Test
    fun `rejects local and special use IPv6 destinations`() {
        listOf(
            "https://[::]/image.png",
            "https://[::1]/image.png",
            "https://[::ffff:192.168.1.2]/image.png",
            "https://[fc00::1]/image.png",
            "https://[fd00::1]/image.png",
            "https://[fe80::1]/image.png",
            "https://[fec0::1]/image.png",
            "https://[ff02::1]/image.png",
            "https://[2001:db8::1]/image.png",
        ).forEach { assertFalse(isSafePartyImageUrl(it), "unexpectedly accepted: $it") }
    }
}
