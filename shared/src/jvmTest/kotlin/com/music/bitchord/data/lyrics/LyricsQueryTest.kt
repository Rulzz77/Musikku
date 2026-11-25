package com.music.bitchord.data.lyrics

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LyricsQueryTest {

    @Test
    fun acceptsSameRecordingWithVideoPackagingAndTopicArtist() {
        assertTrue(
            lyricsCandidateMatches(
                title = "Golden Hour (Official Audio)",
                artist = "JVKE - Topic",
                durationMs = 209_000,
                candidateTitle = "golden hour",
                candidateArtist = "JVKE",
                candidateDurationMs = 210_000,
                durationToleranceMs = 3_000,
            ),
        )
    }

    @Test
    fun rejectsDifferentTitleEvenWhenArtistAndDurationMatch() {
        assertFalse(
            lyricsCandidateMatches(
                title = "Golden Hour",
                artist = "JVKE",
                durationMs = 209_000,
                candidateTitle = "Golden",
                candidateArtist = "JVKE",
                candidateDurationMs = 209_000,
            ),
        )
    }

    @Test
    fun rejectsDifferentArtistEvenWhenTitleAndDurationMatch() {
        assertFalse(
            lyricsCandidateMatches(
                title = "Golden Hour",
                artist = "JVKE",
                durationMs = 209_000,
                candidateTitle = "Golden Hour",
                candidateArtist = "Cover Singer",
                candidateDurationMs = 209_000,
            ),
        )
    }

    @Test
    fun rejectsDifferentRuntimeRecording() {
        assertFalse(
            lyricsCandidateMatches(
                title = "Golden Hour",
                artist = "JVKE",
                durationMs = 209_000,
                candidateTitle = "Golden Hour",
                candidateArtist = "JVKE",
                candidateDurationMs = 245_000,
                durationToleranceMs = 3_000,
            ),
        )
    }

    @Test
    fun acceptsFeaturedArtistAsPartOfTheCredit() {
        assertTrue(
            lyricsCandidateMatches(
                title = "Dracula",
                artist = "Tame Impala, JENNIE",
                durationMs = 205_000,
                candidateTitle = "Dracula",
                candidateArtist = "Tame Impala feat. JENNIE",
                candidateDurationMs = 205_000,
            ),
        )
    }
}
