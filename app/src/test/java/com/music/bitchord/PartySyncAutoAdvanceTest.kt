package com.music.bitchord

import com.music.bitchord.playback.partyAutoAdvanceIsForward
import com.music.bitchord.playback.partyAutoAdvanceSnapshot
import com.music.bitchord.playback.PartyAutoAdvanceSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
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
    fun `a repeated song id is accepted only when the local queue proves a second occurrence`() {
        assertTrue(partyAutoAdvanceIsForward("same-track", "same-track", 4, 4, 2, 5))
        assertFalse(partyAutoAdvanceIsForward("same-track", "same-track", 4, 4, 4, 4))
    }

    @Test
    fun `local queue order can verify a new item before the server queue echo`() {
        assertTrue(partyAutoAdvanceIsForward("track-a", "track-b", 0, -1, 2, 3))
        assertFalse(partyAutoAdvanceIsForward("track-c", "track-b", 2, -1, 4, 3))
    }

    @Test
    fun `an empty party can be seeded with its first automatic track`() {
        assertTrue(partyAutoAdvanceIsForward(null, "track-a", -1, -1))
    }

    @Test
    fun `leader failover retains the origin destination and playback sequence`() {
        // A follower has already reached B and paused. When it becomes leader,
        // it must publish the same guarded transition rather than an empty one.
        assertEquals(
            PartyAutoAdvanceSnapshot("track-a", "track-b", 27L, 9L),
            partyAutoAdvanceSnapshot("track-a", "track-b", 27L, 9L, 0, 1, 2, 3),
        )
    }

    @Test
    fun `leader failover cannot stage an item that is no longer next`() {
        assertNull(partyAutoAdvanceSnapshot("track-c", "track-b", 28L, 9L, 2, 1, 4, 3))
    }
}
