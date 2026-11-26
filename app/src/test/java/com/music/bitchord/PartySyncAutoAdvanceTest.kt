package com.music.bitchord

import com.music.bitchord.playback.partyAutoAdvanceIsForward
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PartySyncAutoAdvanceTest {

    @Test
    fun `leader may advance to a later item in the shared queue`() {
        assertTrue(partyAutoAdvanceIsForward("track-a", "track-b", 0, 1))
        assertTrue(partyAutoAdvanceIsForward("track-b", "track-c", 1, 2))
    }

    @Test
    fun `late automatic transition cannot move the party backwards`() {
        // Another device has already advanced to C while this device only just
        // finished A and is reporting B.
        assertFalse(partyAutoAdvanceIsForward("track-c", "track-b", 2, 1))
    }

    @Test
    fun `duplicate or unknown queue positions are not accepted as advances`() {
        assertFalse(partyAutoAdvanceIsForward("track-b", "track-b", 1, 1))
        assertFalse(partyAutoAdvanceIsForward("track-b", "track-a", -1, -1))
        assertFalse(partyAutoAdvanceIsForward("track-b", "track-c", 1, -1))
    }

    @Test
    fun `an empty party can be seeded with its first automatic track`() {
        assertTrue(partyAutoAdvanceIsForward(null, "track-a", -1, -1))
    }
}
