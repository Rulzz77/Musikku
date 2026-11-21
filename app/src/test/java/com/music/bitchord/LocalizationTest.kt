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
        val projectRoot = File(".").canonicalFile
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
