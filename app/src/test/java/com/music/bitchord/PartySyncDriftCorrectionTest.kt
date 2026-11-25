package com.music.bitchord

import com.music.bitchord.playback.partySyncSpeedMultiplier
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PartySyncDriftCorrectionTest {

    @Test
    fun `small drift stays at the user playback speed`() {
        assertNull(partySyncSpeedMultiplier(0L))
        assertNull(partySyncSpeedMultiplier(80L))
        assertNull(partySyncSpeedMultiplier(-80L))
    }

    @Test
    fun `a listener behind the party is gently sped up`() {
        assertEquals(1.01f, partySyncSpeedMultiplier(-100L)!!, 0.0001f)
        assertEquals(1.04f, partySyncSpeedMultiplier(-1_200L)!!, 0.0001f)
    }

    @Test
    fun `a listener ahead of the party is gently slowed down`() {
        assertEquals(0.99f, partySyncSpeedMultiplier(100L)!!, 0.0001f)
        assertEquals(0.96f, partySyncSpeedMultiplier(1_200L)!!, 0.0001f)
    }
}