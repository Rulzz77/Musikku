package com.music.bitchord.data.lyrics

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LyricsSourceSequenceTest {

    @Test
    fun automaticLookupSkipsProvidersWithoutVerifiableTrackIdentity() {
        val sources = lyricsSourceSequence(
            order = LyricsSource.offered,
            enabledSources = LyricsSource.offered.toSet(),
        )

        assertFalse(LyricsSource.BETTER_LYRICS in sources)
        assertFalse(LyricsSource.BETTER_LYRICS_PORTATO in sources)
        assertFalse(LyricsSource.LYRICS_PLUS in sources)
        assertFalse(LyricsSource.KUGOU in sources)
        assertTrue(LyricsSource.LRC_RED in sources)
        assertTrue(LyricsSource.BINI_LYRICS in sources)
        assertTrue(LyricsSource.LRCLIB in sources)
    }

    @Test
    fun manualPickerCanStillUseThoseProviders() {
        val sources = lyricsSourceSequence(
            order = LyricsSource.offered,
            enabledSources = LyricsSource.offered.toSet(),
            allowManualOnlySources = true,
        )

        assertTrue(LyricsSource.BETTER_LYRICS in sources)
        assertTrue(LyricsSource.BETTER_LYRICS_PORTATO in sources)
        assertTrue(LyricsSource.LYRICS_PLUS in sources)
        assertTrue(LyricsSource.KUGOU in sources)
    }
}
