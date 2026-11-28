package com.music.bitchord.data.sources.module

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.InetAddress

class QuickJsNetworkPolicyTest {

    @Test
    fun `rejects loopback private link local and special use IPv4 addresses`() {
        val blocked = listOf(
            "0.0.0.0",
            "10.1.2.3",
            "100.64.0.1",
            "127.0.0.1",
            "169.254.169.254",
            "172.16.0.1",
            "172.31.255.254",
            "192.0.2.1",
            "192.168.1.1",
            "198.18.0.1",
            "198.51.100.1",
            "203.0.113.1",
            "224.0.0.1",
            "255.255.255.255",
        )

        blocked.forEach { address ->
            assertTrue(
                "$address must not be reachable from an add-on",
                QuickJsExecutor.isBlockedModuleAddress(InetAddress.getByName(address)),
            )
        }
    }

    @Test
    fun `rejects private and special use IPv6 addresses`() {
        val blocked = listOf(
            "::",
            "::1",
            "fc00::1",
            "fd12:3456::1",
            "fe80::1",
            "fec0::1",
            "2001:db8::1",
            "::ffff:10.0.0.1",
        )

        blocked.forEach { address ->
            assertTrue(
                "$address must not be reachable from an add-on",
                QuickJsExecutor.isBlockedModuleAddress(InetAddress.getByName(address)),
            )
        }
    }

    @Test
    fun `allows normal public resolver addresses`() {
        listOf("8.8.8.8", "1.1.1.1", "2606:4700:4700::1111").forEach { address ->
            assertFalse(
                "$address should remain usable by an add-on",
                QuickJsExecutor.isBlockedModuleAddress(InetAddress.getByName(address)),
            )
        }
    }

    @Test
    fun `module fetch requires public HTTPS URLs without embedded credentials`() {
        assertEquals(
            "https://example.com/index.json",
            QuickJsExecutor.validateModuleFetchUrl("https://example.com/index.json"),
        )
        assertThrows(IllegalArgumentException::class.java) {
            QuickJsExecutor.validateModuleFetchUrl("http://example.com/index.json")
        }
        assertThrows(IllegalArgumentException::class.java) {
            QuickJsExecutor.validateModuleFetchUrl("https://user:pass@example.com/index.json")
        }
        assertThrows(IllegalArgumentException::class.java) {
            QuickJsExecutor.validateModuleFetchUrl("https://localhost/index.json")
        }
    }
}
