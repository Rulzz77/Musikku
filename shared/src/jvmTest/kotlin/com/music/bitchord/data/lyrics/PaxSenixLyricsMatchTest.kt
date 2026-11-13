package com.music.bitchord.data.lyrics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PaxSenixLyricsMatchTest {

    @Test
    fun genericSearchSelectsTanpoTresnamuInsteadOfSameArtistLautKidul() {
        val response = """
            {
              "lyrics": [
                {
                  "id": "tanpo",
                  "title": "Tanpo Tresnamu",
                  "artistName": "Denny Caknan",
                  "durationMs": 281000,
                  "lyrics": "[00:00.00]Biyen seneng bareng"
                },
                {
                  "id": "laut",
                  "title": "Laut Kidul",
                  "artistName": "Denny Caknan",
                  "durationMs": 281000,
                  "lyrics": "[00:00.00]Laut kidul"
                }
              ]
            }
        """.trimIndent()

        val lines = PaxSenix.parseLrcGet(
            raw = response,
            title = "Tanpo Tresnamu",
            artist = "Denny Caknan",
            durationMs = 281_000L,
        )

        assertEquals(listOf("Biyen seneng bareng"), lines?.map { it.text })
    }

    @Test
    fun genericSearchReturnsNoLyricsWhenOnlyAnotherTitleMatches() {
        val response = """
            {
              "lyrics": [{
                "id": "laut",
                "title": "Laut Kidul",
                "artistName": "Denny Caknan",
                "durationMs": 281000,
                "lyrics": "[00:00.00]Laut kidul"
              }]
            }
        """.trimIndent()

        val lines = PaxSenix.parseLrcGet(
            raw = response,
            title = "Tanpo Tresnamu",
            artist = "Denny Caknan",
            durationMs = 281_000L,
        )

        assertNull(lines)
    }

    @Test
    fun anonymousLyricsAreRejectedEvenWhenRuntimeMatchesExactly() {
        val response = """
            {
              "lyrics": [
                "[00:01.00]A different song",
                "[00:39.00]A different song ends"
              ]
            }
        """.trimIndent()

        assertNull(
            PaxSenix.parseLrcGet(
                raw = response,
                title = "Tanpo Tresnamu",
                artist = "Denny Caknan",
                durationMs = 40_000L,
            ),
        )
    }

    @Test
    fun directLyricsRequireMatchingTrackMetadata() {
        val anonymous = """
            {"lyrics":"[00:01.00]Wrong lyrics","durationMs":40000}
        """.trimIndent()
        val identified = """
            {
              "title":"Tanpo Tresnamu",
              "artistName":"Denny Caknan",
              "durationMs":40000,
              "lyrics":"[00:01.00]Biyen seneng"
            }
        """.trimIndent()

        assertNull(PaxSenix.parseLrcGet(anonymous, "Tanpo Tresnamu", "Denny Caknan", 40_000L))
        assertEquals(
            listOf("Biyen seneng"),
            PaxSenix.parseLrcGet(identified, "Tanpo Tresnamu", "Denny Caknan", 40_000L)
                ?.map { it.text },
        )
    }

    @Test
    fun anonymousLyricsAreRejectedWhenTheirRuntimeDoesNotMatch() {
        val response = """
            {
              "lyrics": [
                "[00:01.00]Laut kidul",
                "[00:40.00]Laut kidul ends"
              ]
            }
        """.trimIndent()

        val lines = PaxSenix.parseLrcGet(
            raw = response,
            title = "Tanpo Tresnamu",
            artist = "Denny Caknan",
            durationMs = 200_000L,
        )

        assertNull(lines)
    }
}
