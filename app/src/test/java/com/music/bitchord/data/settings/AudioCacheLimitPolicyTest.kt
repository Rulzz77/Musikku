package com.music.bitchord.data.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioCacheLimitPolicyTest {

    @Test
    fun currentDefaultIsPreservedAndSmallerFloorIsAvailable() {
        assertEquals(512L * 1024 * 1024, AudioCacheLimitPolicy.DEFAULT_LIMIT_BYTES)
        assertEquals(
            AudioCacheLimitPolicy.MIN_LIMIT_BYTES,
            AudioCacheLimitPolicy.clamp(0L),
        )
        assertEquals(
            128L * 1024 * 1024,
            AudioCacheLimitPolicy.clamp(128L * 1024 * 1024),
        )
    }

    @Test
    fun smallerCacheBudgetsAreAvailable() {
        assertEquals(128, AudioCacheLimitPolicy.sliderStopsMb.first())
        listOf(192, 256, 384).forEach { assertTrue(it in AudioCacheLimitPolicy.sliderStopsMb) }
    }

    @Test
    fun everyPreviousFixedSliderValueIsPreserved() {
        (512..10_240 step 512).forEach { oldMegabytes ->
            val index = AudioCacheLimitPolicy.sliderStopsMb.indexOf(oldMegabytes)
            assertTrue("Missing previous cache limit: $oldMegabytes MB", index >= 0)
            assertEquals(
                oldMegabytes.toLong() * 1024 * 1024,
                AudioCacheLimitPolicy.bytesAtSlider(index.toFloat()),
            )
        }
    }

    @Test
    fun customLimitsAreClampedOnlyAtTheConfiguredBounds() {
        assertEquals(
            256L * 1024 * 1024,
            AudioCacheLimitPolicy.clamp(256L * 1024 * 1024),
        )
        assertEquals(
            AudioCacheLimitPolicy.MAX_LIMIT_BYTES,
            AudioCacheLimitPolicy.clamp(AudioCacheLimitPolicy.MAX_LIMIT_BYTES),
        )
        assertEquals(
            AudioCacheLimitPolicy.UNLIMITED_BYTES,
            AudioCacheLimitPolicy.clamp(AudioCacheLimitPolicy.MAX_LIMIT_BYTES + 1),
        )
    }

    @Test
    fun unlimitedHasItsOwnFinalSliderStop() {
        val last = AudioCacheLimitPolicy.sliderStopsMb.lastIndex
        assertEquals(
            AudioCacheLimitPolicy.UNLIMITED_BYTES,
            AudioCacheLimitPolicy.bytesAtSlider(last.toFloat()),
        )
        assertEquals(last.toFloat(), AudioCacheLimitPolicy.sliderIndex(AudioCacheLimitPolicy.UNLIMITED_BYTES))
    }
}
