package com.music.bitchord

import com.music.bitchord.data.lyrics.CommunityTtmlLyricsStore
import java.io.File
import kotlin.io.path.createTempDirectory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CommunityTtmlLyricsStoreTest {

    private val validTtml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"
            xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
          <head>
            <metadata>
              <ttm:agent type="person" xml:id="v1" />
            </metadata>
          </head>
          <body>
            <div>
              <p begin="1.0" end="2.0" ttm:agent="v1">
                <span begin="1.0" end="1.5">community </span><span begin="1.5" end="2.0">lyrics</span>
              </p>
            </div>
          </body>
        </tt>
    """.trimIndent()

    @Test
    fun `stores and reads timed TTML for the matching track`() {
        val root = tempDirectory("community-ttml")
        assertTrue(CommunityTtmlLyricsStore.save(root, "video-id-1", validTtml))

        val lines = CommunityTtmlLyricsStore.read(root, "video-id-1")
        assertNotNull(lines)
        val sung = lines!!.filter { it.text.isNotBlank() }.single()
        assertEquals("community lyrics", sung.text)
        assertTrue(sung.isWordSynced)
        assertNull(CommunityTtmlLyricsStore.read(root, "different-track"))
    }

    @Test
    fun `rejects invalid or oversized TTML`() {
        val root = tempDirectory("community-ttml-invalid")
        assertFalse(CommunityTtmlLyricsStore.save(root, "video-id-2", "<not-ttml/>"))
        assertFalse(
            CommunityTtmlLyricsStore.save(
                root,
                "video-id-3",
                validTtml + " ".repeat(CommunityTtmlLyricsStore.MAX_TTML_BYTES),
            ),
        )
        assertNull(CommunityTtmlLyricsStore.read(root, "video-id-2"))
    }

    @Test
    fun `can remove an imported track override`() {
        val root = tempDirectory("community-ttml-remove")
        assertTrue(CommunityTtmlLyricsStore.save(root, "video-id-4", validTtml))
        assertTrue(CommunityTtmlLyricsStore.has(root, "video-id-4"))
        assertTrue(CommunityTtmlLyricsStore.remove(root, "video-id-4"))
        assertFalse(CommunityTtmlLyricsStore.has(root, "video-id-4"))
    }

    private fun tempDirectory(prefix: String): File =
        createTempDirectory(prefix).toFile().also { it.deleteOnExit() }
}
