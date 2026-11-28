package com.music.bitchord.data.settings

import kotlin.test.Test
import kotlin.test.assertEquals

class LyricsBackgroundModeTest {

    @Test
    fun everyCurrentModeCanBeRestoredFromItsStoredName() {
        LyricsBackgroundMode.entries.forEach { mode ->
            assertEquals(mode, lyricsBackgroundModeFromStoredName(mode.name))
        }
    }

    @Test
    fun retiredTransparentModeFallsBackToDynamic() {
        assertEquals(
            LyricsBackgroundMode.DYNAMIC_KAWARP,
            lyricsBackgroundModeFromStoredName("TRANSPARENT"),
        )
    }

    @Test
    fun missingOrUnknownModeFallsBackToDynamic() {
        assertEquals(
            LyricsBackgroundMode.DYNAMIC_KAWARP,
            lyricsBackgroundModeFromStoredName(null),
        )
        assertEquals(
            LyricsBackgroundMode.DYNAMIC_KAWARP,
            lyricsBackgroundModeFromStoredName("NOT_A_REAL_MODE"),
        )
    }
}
