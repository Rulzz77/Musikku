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
}
