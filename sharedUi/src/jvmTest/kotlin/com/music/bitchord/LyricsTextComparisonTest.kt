package com.music.bitchord

import com.music.bitchord.ui.player.differsFromLyrics
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LyricsTextComparisonTest {
    @Test
    fun ignoresCaseAndWhitespaceWhenCheckingForDuplicateLyrics() {
        assertFalse("hello world".differsFromLyrics("HELLOWORLD"))
    }

    @Test
    fun ignoresInvisibleFormattingMarks() {
        val withMarks = "hel\u200Blo\u200Ewo\u200Frld\u2060\uFEFF"
        assertFalse(withMarks.differsFromLyrics("hello world"))
    }

    @Test
    fun preservesJoinersThatCanChangeShaping() {
        assertTrue("می\u200Cروم".differsFromLyrics("میروم"))
        assertTrue("👩\u200D🎤".differsFromLyrics("👩🎤"))
    }

    @Test
    fun keepsPunctuationDifferencesVisible() {
        assertTrue("dont stop".differsFromLyrics("don't stop"))
    }

    @Test
    fun keepsGenuinelyDifferentLyricsVisible() {
        assertTrue("hello world".differsFromLyrics("hello there"))
    }
}
