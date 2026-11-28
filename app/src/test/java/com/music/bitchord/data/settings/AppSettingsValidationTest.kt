package com.music.bitchord.data.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppSettingsValidationTest {

    @Test
    fun `crossfade is bounded to the settings slider range`() {
        assertEquals(0, normalizeCrossfadeSeconds(Int.MIN_VALUE))
        assertEquals(0, normalizeCrossfadeSeconds(0))
        assertEquals(12, normalizeCrossfadeSeconds(12))
        assertEquals(12, normalizeCrossfadeSeconds(Int.MAX_VALUE))
    }

    @Test
    fun `EQ balance rejects non finite values and clamps finite values`() {
        assertEquals(0f, normalizeEqualizerBalance(Float.NaN), 0f)
        assertEquals(0f, normalizeEqualizerBalance(Float.POSITIVE_INFINITY), 0f)
        assertEquals(0f, normalizeEqualizerBalance(Float.NEGATIVE_INFINITY), 0f)
        assertEquals(-1f, normalizeEqualizerBalance(-5f), 0f)
        assertEquals(0.25f, normalizeEqualizerBalance(0.25f), 0f)
        assertEquals(1f, normalizeEqualizerBalance(5f), 0f)
    }

    @Test
    fun `EQ bands replace NaN and infinities with flat gains`() {
        val values = normalizeEqualizerBands(
            listOf(Float.NaN, Float.POSITIVE_INFINITY, -40f, 3f, Float.NEGATIVE_INFINITY),
            count = 6,
            rangeDb = 12f,
        )
        assertEquals(listOf(0f, 0f, -12f, 3f, 0f, 0f), values)
        assertTrue(values.all(Float::isFinite))
    }

    @Test
    fun `scrobble settings match the timing controls`() {
        assertEquals(15, normalizeScrobbleMinDuration(Int.MIN_VALUE))
        assertEquals(30, normalizeScrobbleMinDuration(30))
        assertEquals(120, normalizeScrobbleMinDuration(Int.MAX_VALUE))

        assertEquals(0.5f, normalizeScrobbleDelayPercent(Float.NaN), 0f)
        assertEquals(0.5f, normalizeScrobbleDelayPercent(Float.POSITIVE_INFINITY), 0f)
        assertEquals(0.1f, normalizeScrobbleDelayPercent(0f), 0f)
        assertEquals(0.75f, normalizeScrobbleDelayPercent(0.75f), 0f)
        assertEquals(1f, normalizeScrobbleDelayPercent(1.5f), 0f)

        assertEquals(30, normalizeScrobbleDelaySeconds(Int.MIN_VALUE))
        assertEquals(180, normalizeScrobbleDelaySeconds(180))
        assertEquals(300, normalizeScrobbleDelaySeconds(Int.MAX_VALUE))
    }

    @Test
    fun `Last.fm backup endpoints are limited to official HTTPS providers`() {
        assertTrue(
            AppSettings.isValidImportedPreference(
                "lastfm_endpoint",
                "https://ws.audioscrobbler.com/2.0/",
            ),
        )
        assertTrue(
            AppSettings.isValidImportedPreference(
                "lastfm_endpoint",
                "https://libre.fm/2.0/",
            ),
        )
        assertTrue(AppSettings.isValidImportedPreference("lastfm_endpoint", ""))

        assertFalse(
            AppSettings.isValidImportedPreference(
                "lastfm_endpoint",
                "http://ws.audioscrobbler.com/2.0/",
            ),
        )
        assertFalse(
            AppSettings.isValidImportedPreference(
                "lastfm_endpoint",
                "https://evil.example/2.0/",
            ),
        )
        assertFalse(
            AppSettings.isValidImportedPreference(
                "lastfm_endpoint",
                "https://ws.audioscrobbler.com.evil.example/2.0/",
            ),
        )
        assertFalse(
            AppSettings.isValidImportedPreference(
                "lastfm_endpoint",
                "https://user:pass@ws.audioscrobbler.com/2.0/",
            ),
        )
    }

    @Test
    fun `non finite EQ values are never considered valid imported settings`() {
        assertFalse(AppSettings.isValidImportedPreference("equalizer_balance", Float.NaN))
        assertFalse(AppSettings.isValidImportedPreference("equalizer_balance", Float.POSITIVE_INFINITY))
        assertFalse(AppSettings.isValidImportedPreference("scrobble_delay_percent", Float.NaN))
        assertFalse(AppSettings.isValidImportedPreference("scrobble_delay_percent", 1.1f))
        assertFalse(AppSettings.isValidImportedPreference("crossfade_seconds", 13))
        assertFalse(AppSettings.isValidImportedPreference("scrobble_min_duration", 121))
        assertFalse(AppSettings.isValidImportedPreference("scrobble_delay_seconds", 301))
    }
}
