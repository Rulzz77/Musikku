package com.music.bitchord.ui.performance

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DevicePerformanceProfileTest {
    @Test
    fun lowRamFlagAlwaysSelectsLiteVisualProfile() {
        assertTrue(
            DevicePerformancePolicy.isLowEnd(
                isLowRamDevice = true,
                totalRamBytes = 8L * 1024L * 1024L * 1024L,
                appMemoryClassMb = 512,
            ),
        )
    }

    @Test
    fun threeGiBOrLessSelectsLiteVisualProfile() {
        val gib = 1024L * 1024L * 1024L
        assertTrue(DevicePerformancePolicy.isLowEnd(false, 2L * gib, 256))
        assertTrue(DevicePerformancePolicy.isLowEnd(false, 3L * gib, 256))
        assertFalse(DevicePerformancePolicy.isLowEnd(false, 4L * gib, 256))
    }

    @Test
    fun smallAppHeapSelectsLiteVisualProfileWhenTotalRamIsUnavailable() {
        assertTrue(DevicePerformancePolicy.isLowEnd(false, 0L, 128))
        assertTrue(DevicePerformancePolicy.isLowEnd(false, 0L, 192))
        assertFalse(DevicePerformancePolicy.isLowEnd(false, 0L, 256))
    }

    @Test
    fun unknownCapacityDoesNotMisclassifyDeviceAsLowEnd() {
        assertFalse(DevicePerformancePolicy.isLowEnd(false, 0L, 0))
    }
}
