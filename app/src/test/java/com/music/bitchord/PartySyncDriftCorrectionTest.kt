package com.music.bitchord

import com.music.bitchord.playback.partySyncRequiresSeek
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PartySyncDriftCorrectionTest {

    @Test
    fun `ordinary decoder jitter is tolerated without corrective seeking`() {
        assertFalse(partySyncRequiresSeek(0L))
        assertFalse(partySyncRequiresSeek(80L))
        assertFalse(partySyncRequiresSeek(-80L))
        assertFalse(partySyncRequiresSeek(500L))
        assertFalse(partySyncRequiresSeek(-500L))
        assertFalse(partySyncRequiresSeek(1_200L))
        assertFalse(partySyncRequiresSeek(-1_200L))
    }

    @Test
    fun `only drift beyond the guarded seek threshold is corrected`() {
        assertTrue(partySyncRequiresSeek(1_201L))
        assertTrue(partySyncRequiresSeek(-1_201L))
        assertTrue(partySyncRequiresSeek(2_500L))
        assertTrue(partySyncRequiresSeek(-2_500L))
    }
}
