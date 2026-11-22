package com.music.bitchord

import com.music.bitchord.ui.components.SUPPORTED_LANGUAGES
import com.music.bitchord.ui.components.languageDisplayNameRes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class LocalizationTest {

    @Test
    fun supportedLanguages_containsIndonesian() {
        val idLanguage = SUPPORTED_LANGUAGES.firstOrNull { it.tag == "id" }
        assertNotNull("Indonesian must be available in the app language picker", idLanguage)
        assertEquals(R.string.indonesian, idLanguage?.nameRes)
        assertEquals(R.string.indonesian, languageDisplayNameRes("id"))
        assertEquals(R.string.indonesian, languageDisplayNameRes("in"))
    }

    @Test
    fun indonesianSharedComposeResourcesContainsEveryBaseKey() {
        val workingDirectory = File(".").canonicalFile
        // Gradle may run this test with either the repository root or app/ as
        // its working directory; sharedUi is a sibling of app, never below it.
        val projectRoot = if (File(workingDirectory, "sharedUi").isDirectory) {
            workingDirectory
        } else {
            workingDirectory.parentFile ?: workingDirectory
        }
        val resourceRoot = File(projectRoot, "sharedUi/src/commonMain/composeResources")
        val baseFile = File(resourceRoot, "values/strings.xml")
        val indonesianFile = File(resourceRoot, "values-id/strings.xml")

        assertTrue("Shared Compose base strings must exist", baseFile.exists())
        assertTrue("Indonesian shared Compose strings must exist", indonesianFile.exists())

        val factory = DocumentBuilderFactory.newInstance()
        val builder = factory.newDocumentBuilder()
        val baseDoc = builder.parse(baseFile)
        val indonesianDoc = builder.parse(indonesianFile)

        fun keys(document: org.w3c.dom.Document): Set<String> {
            val result = mutableSetOf<String>()
            for (tagName in listOf("string", "plurals", "string-array")) {
                val nodes = document.getElementsByTagName(tagName)
                for (index in 0 until nodes.length) {
                    val element = nodes.item(index) as org.w3c.dom.Element
                    if (element.getAttribute("translatable") == "false") continue
                    element.getAttribute("name").takeIf { it.isNotBlank() }?.let(result::add)
                }
            }
            return result
        }

        val missingKeys = keys(baseDoc) - keys(indonesianDoc)
        assertTrue(
            "Indonesian shared Compose catalogue is missing " + missingKeys.size + " keys: " + missingKeys,
            missingKeys.isEmpty(),
        )
    }

    @Test
    fun indonesianCommonUiLabelsAreTranslated() {
        val workingDirectory = File(".").canonicalFile
        val projectRoot = if (File(workingDirectory, "sharedUi").isDirectory) {
            workingDirectory
        } else {
            workingDirectory.parentFile ?: workingDirectory
        }
        val appStrings = File(projectRoot, "app/src/main/res/values-id/strings.xml")
        val sharedStrings = File(projectRoot, "sharedUi/src/commonMain/composeResources/values-id/strings.xml")
        assertTrue("Indonesian Android strings must exist", appStrings.exists())
        assertTrue("Indonesian shared player strings must exist", sharedStrings.exists())

        fun value(file: File, key: String): String {
            val document = DocumentBuilderFactory.newInstance()
                .newDocumentBuilder()
                .parse(file)
            val nodes = document.getElementsByTagName("string")
            for (index in 0 until nodes.length) {
                val element = nodes.item(index) as org.w3c.dom.Element
                if (element.getAttribute("name") == key) return element.textContent.trim()
            }
            throw AssertionError("Missing Indonesian string '$key' in $file")
        }

        val appExpected = mapOf(
            "settings_search_hint" to "Cari pengaturan",
            "auto_empty_liked_title" to "Belum ada lagu yang disukai",
            "cast_dialog_subtitle" to "Putar melalui Chromecast atau speaker Google Cast",
            "switch_to_grid_view" to "Beralih ke tampilan kisi",
            "listen_together_server_online" to "Daring · %1\$d ms",
            "queue_like_sign_in" to "Masuk untuk menyukai lagu daring",
        )
        appExpected.forEach { (key, expected) ->
            assertEquals("Incorrect Indonesian Android string: $key", expected, value(appStrings, key))
        }

        val sharedExpected = mapOf(
            "audio_output" to "Keluaran audio",
            "lyrics_offset_description" to "Nilai positif membuat lirik muncul lebih lambat",
            "personal_phone" to "Ponsel milik %1\$s",
        )
        sharedExpected.forEach { (key, expected) ->
            assertEquals("Incorrect Indonesian shared player string: $key", expected, value(sharedStrings, key))
        }
    }

    @Test
    fun supportedLanguages_containsVietnamese() {
        val viLanguage = SUPPORTED_LANGUAGES.firstOrNull { it.tag == "vi" }
        assertNotNull("Vietnamese language must be in SUPPORTED_LANGUAGES", viLanguage)
        assertEquals(R.string.vietnamese, viLanguage?.nameRes)
        assertEquals(R.string.vietnamese, languageDisplayNameRes("vi"))
    }

    @Test
    fun localesConfig_matchesSupportedLanguages() {
        val projectRoot = File(".").canonicalFile
        val resDir = if (File(projectRoot, "app/src/main/res").exists()) {
            File(projectRoot, "app/src/main/res")
        } else {
            File(projectRoot, "src/main/res")
        }
        val localesConfigFile = File(resDir, "xml/locales_config.xml")
        assertTrue("locales_config.xml must exist", localesConfigFile.exists())

        val factory = DocumentBuilderFactory.newInstance()
        val builder = factory.newDocumentBuilder()
        val doc = builder.parse(localesConfigFile)
        val localeNodes = doc.getElementsByTagName("locale")

        val configuredLocales = mutableListOf<String>()
        for (i in 0 until localeNodes.length) {
            val node = localeNodes.item(i)
            val name = node.attributes.getNamedItem("android:name")?.nodeValue
            if (name != null) configuredLocales.add(name)
        }

        assertTrue("locales_config.xml must include 'vi'", configuredLocales.contains("vi"))

        for (lang in SUPPORTED_LANGUAGES) {
            assertTrue(
                "locales_config.xml must include '${lang.tag}'",
                configuredLocales.contains(lang.tag),
            )
        }
    }
}
