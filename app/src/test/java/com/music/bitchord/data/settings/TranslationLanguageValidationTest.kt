package com.music.bitchord.data.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TranslationLanguageValidationTest {

    @Test
    fun `follows app locale for blank and canonicalizes supported language codes`() {
        assertEquals("", normalizeTranslationLanguage(""))
        assertEquals("", normalizeTranslationLanguage("   "))
        assertEquals("ja", normalizeTranslationLanguage("JA"))
        assertEquals("zh-CN", normalizeTranslationLanguage("zh-cn"))
        assertEquals("pt", normalizeTranslationLanguage("PT"))
    }

    @Test
    fun `unknown arbitrary or oversized language tags are not accepted`() {
        listOf(
            "unknown",
            "javascript:alert(1)",
            "en-US<script>",
            "x".repeat(100_000),
        ).forEach { raw ->
            assertEquals("", normalizeTranslationLanguage(raw))
            assertFalse(
                AppSettings.isValidImportedPreference("translation_language", raw),
            )
        }
        assertTrue(AppSettings.isValidImportedPreference("translation_language", ""))
        assertTrue(AppSettings.isValidImportedPreference("translation_language", "ja"))
    }
}
