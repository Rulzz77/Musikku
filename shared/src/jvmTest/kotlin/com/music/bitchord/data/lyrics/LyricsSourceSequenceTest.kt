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
    fun durationlessLookupOnlyUsesExactVideoProvidersThatAreEnabled() {
        val all = LyricsSource.offered.toSet()
        val sources = lyricsSourceSequenceForDuration(
            order = LyricsSource.offered,
            enabledSources = all,
            durationMs = 0L,
        )

        assertTrue(sources.isNotEmpty())
        assertTrue(sources.all {
            it == LyricsSource.YOUTUBE_TRANSCRIPT || it == LyricsSource.YOUTUBE_MUSIC
        })
        assertTrue(LyricsSource.LRCLIB !in sources)
        assertTrue(LyricsSource.LRC_RED !in sources)
        assertTrue(LyricsSource.BINI_LYRICS !in sources)
    }

    @Test
    fun durationlessLookupStillRespectsDisabledExactVideoProviders() {
        val sources = lyricsSourceSequenceForDuration(
            order = LyricsSource.offered,
            enabledSources = setOf(LyricsSource.LRCLIB, LyricsSource.YOUTUBE_MUSIC),
            durationMs = 0L,
        )

        assertEquals(listOf(LyricsSource.YOUTUBE_MUSIC), sources)
    }

    @Test
    fun aKnownDurationRestoresTheConfiguredProviderSequence() {
        val sources = lyricsSourceSequenceForDuration(
            order = LyricsSource.offered,
            enabledSources = LyricsSource.offered.toSet(),
            durationMs = 210_000L,
        )

        assertTrue(LyricsSource.LRCLIB in sources)
        assertTrue(LyricsSource.LRC_RED in sources)
        assertTrue(LyricsSource.YOUTUBE_MUSIC in sources)
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
