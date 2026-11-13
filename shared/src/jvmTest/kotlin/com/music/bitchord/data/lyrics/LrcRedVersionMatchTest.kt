package com.music.bitchord.data.lyrics

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class LrcRedVersionMatchTest {

    @Test
    fun djKoploDoesNotMatchTheOriginalRecording() {
        val original = LrcRed.Hit(
            isrc = "USRC17607839",
            title = "Banyu Langit",
            artist = "Didi Kempot",
            duration = 244.0,
        )

        assertNull(
            LrcRed.best(listOf(original), "Banyu Langit (DJ Koplo)", "Didi Kempot", 244_000L),
        )
    }

    @Test
    fun djBreakbeatSelectsTheMatchingEditNotTheOriginal() {
        val original = LrcRed.Hit(
            isrc = "USRC17607839",
            title = "Sewu Kuto",
            artist = "Didi Kempot",
            duration = 250.0,
        )
        val djEdit = LrcRed.Hit(
            isrc = "USRC17607840",
            title = "Sewu Kuto [DJ Breakbeat]",
            artist = "Didi Kempot",
            duration = 250.0,
        )

        assertEquals(
            "USRC17607840",
            LrcRed.best(
                listOf(original, djEdit),
                "Sewu Kuto (DJ Breakbeat)",
                "Didi Kempot",
                250_000L,
            )?.isrc,
        )
    }

    @Test
    fun remasterSpellingVariantsShareOneVersionIdentity() {
        val remaster = LrcRed.Hit(
            isrc = "USRC17607841",
            title = "Golden Hour (2011 Remaster)",
            artist = "JVKE",
            duration = 209.0,
        )

        assertEquals(
            "USRC17607841",
            LrcRed.best(
                listOf(remaster),
                "Golden Hour (Remastered 2011)",
                "JVKE",
                209_000L,
            )?.isrc,
        )
    }

    @Test
    fun missingArtistCreditCannotSeedAnIsrc() {
        val anonymousArtist = LrcRed.Hit(
            isrc = "USRC17607842",
            title = "Golden Hour",
            artist = "",
            duration = 209.0,
        )

        assertNull(LrcRed.best(listOf(anonymousArtist), "Golden Hour", "JVKE", 209_000L))
    }
}
