package com.music.bitchord.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppUpdateCheckerTest {

    @Test
    fun `selects the APK matching the first supported device ABI`() {
        val arm64Hash = "a".repeat(64)
        val universalHash = "b".repeat(64)
        val release = releaseJson(
            asset("MusikKu-universal.apk", universalHash),
            asset("MusikKu-armeabi-v7a.apk", "c".repeat(64)),
            asset("MusikKu-arm64-v8a.apk", arm64Hash),
        )

        val selected = AppUpdateChecker.selectApkAsset(
            release = release,
            supportedAbis = listOf("arm64-v8a", "armeabi-v7a"),
        )

        assertNotNull(selected)
        assertEquals("arm64-v8a", selected?.variant)
        assertEquals(arm64Hash, selected?.sha256)
        assertTrue(selected?.url?.endsWith("MusikKu-arm64-v8a.apk") == true)
    }

    @Test
    fun `falls back to a verified universal APK when no ABI matches`() {
        val universalHash = "d".repeat(64)
        val release = releaseJson(
            asset("MusikKu-universal.apk", universalHash),
            asset("MusikKu-x86_64.apk", "e".repeat(64)),
        )

        val selected = AppUpdateChecker.selectApkAsset(
            release = release,
            supportedAbis = listOf("riscv64"),
        )

        assertEquals("universal", selected?.variant)
        assertEquals(universalHash, selected?.sha256)
    }

    @Test
    fun `ignores assets without a valid uploaded SHA-256 digest`() {
        val release = releaseJson(
            asset("MusikKu-arm64-v8a.apk", digest = null),
            asset("MusikKu-armeabi-v7a.apk", "not-a-hash"),
            asset("MusikKu-universal.apk", "f".repeat(64), state = "new"),
        )

        val selected = AppUpdateChecker.selectApkAsset(
            release = release,
            supportedAbis = listOf("arm64-v8a", "armeabi-v7a"),
        )

        assertNull(selected)
    }

    @Test
    fun `only accepts HTTPS GitHub release asset URLs`() {
        val release = releaseJson(
            asset(
                name = "MusikKu-arm64-v8a.apk",
                digest = "1".repeat(64),
                url = "http://example.invalid/MusikKu-arm64-v8a.apk",
            ),
        )

        val selected = AppUpdateChecker.selectApkAsset(
            release = release,
            supportedAbis = listOf("arm64-v8a"),
        )

        assertNull(selected)
    }

    @Test
    fun `checksum comparison accepts case differences but rejects mismatch`() {
        val expected = "abcdef0123456789".repeat(4)
        assertTrue(AppUpdateChecker.sha256Matches(expected, expected.uppercase()))
        assertFalse(AppUpdateChecker.sha256Matches(expected, "0".repeat(64)))
        assertFalse(AppUpdateChecker.sha256Matches("short", expected))
    }

    private fun releaseJson(vararg assets: String) =
        Json.parseToJsonElement(
            """{"assets":[${assets.joinToString(",")}]}""",
        ).jsonObject

    private fun asset(
        name: String,
        digest: String?,
        state: String = "uploaded",
        url: String = "https://github.com/Rulzz77/Musikku/releases/download/v0.1.93/$name",
    ): String {
        val digestJson = digest?.let { """"digest":"sha256:$it",""" } ?: ""
        return """{"name":"$name","browser_download_url":"$url",$digestJson"state":"$state"}"""
    }
}
