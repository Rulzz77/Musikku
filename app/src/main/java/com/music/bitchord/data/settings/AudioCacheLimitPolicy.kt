package com.music.bitchord.data.settings

import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Storage budget policy shared by Settings and its tests.
 *
 * Smaller choices help devices with limited free space. Every fixed 512 MB
 * stop from the previous slider is retained, so existing custom preferences
 * still map to the same value after the control is upgraded.
 */
internal object AudioCacheLimitPolicy {
    const val DEFAULT_LIMIT_BYTES = 512L * 1024 * 1024
    const val MIN_LIMIT_BYTES = 128L * 1024 * 1024
    const val MAX_LIMIT_BYTES = 10L * 1024 * 1024 * 1024
    const val UNLIMITED_BYTES = Long.MAX_VALUE
    const val UNLIMITED_SLIDER_STOP_MB = 10 * 1024 + 512

    private const val BYTES_PER_MB = 1024L * 1024L

    val sliderStopsMb: List<Int> = buildList {
        addAll(listOf(128, 192, 256, 384, 512, 768))
        addAll((1_024..10_240 step 512).toList())
        add(UNLIMITED_SLIDER_STOP_MB)
    }

    fun clamp(valueBytes: Long): Long =
        if (valueBytes > MAX_LIMIT_BYTES) UNLIMITED_BYTES
        else valueBytes.coerceAtLeast(MIN_LIMIT_BYTES)

    /** Maps a persisted byte limit to the nearest visible slider stop. */
    fun sliderIndex(valueBytes: Long): Float {
        if (valueBytes == UNLIMITED_BYTES) return sliderStopsMb.lastIndex.toFloat()
        return sliderStopsMb.indices.minByOrNull { index ->
            abs(sliderStopsMb[index].toLong() * BYTES_PER_MB - valueBytes)
        }?.toFloat() ?: 0f
    }

    /** Converts a selected slider stop into its byte budget. */
    fun bytesAtSlider(value: Float): Long {
        val index = value.roundToInt().coerceIn(0, sliderStopsMb.lastIndex)
        val megabytes = sliderStopsMb[index]
        return if (megabytes == UNLIMITED_SLIDER_STOP_MB) {
            UNLIMITED_BYTES
        } else {
            megabytes.toLong() * BYTES_PER_MB
        }
    }
}
