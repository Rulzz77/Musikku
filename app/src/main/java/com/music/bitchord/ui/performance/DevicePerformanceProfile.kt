package com.music.bitchord.ui.performance

import android.app.ActivityManager
import android.content.Context
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf

/**
 * A conservative, process-lifetime profile for devices with very little memory.
 *
 * Decorative motion and backdrop effects are the first things to shed: they
 * compete with scrolling and image decoding but are not needed for audio
 * playback. The actual video player and audio pipeline are deliberately left
 * alone.
 */
@Immutable
internal data class DevicePerformanceProfile(
    val isLowEnd: Boolean,
) {
    val reduceExpensiveVisualEffects: Boolean get() = isLowEnd
    val disableDecorativeVideo: Boolean get() = isLowEnd

    companion object {
        fun detect(context: Context): DevicePerformanceProfile {
            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return DevicePerformanceProfile(isLowEnd = false)
            val memory = ActivityManager.MemoryInfo()
            manager.getMemoryInfo(memory)
            return DevicePerformanceProfile(
                isLowEnd = DevicePerformancePolicy.isLowEnd(
                    isLowRamDevice = manager.isLowRamDevice,
                    totalRamBytes = memory.totalMem,
                    appMemoryClassMb = manager.memoryClass,
                ),
            )
        }
    }
}

/** Shared once at the Activity root; no per-frame device probing. */
internal val LocalDevicePerformanceProfile = staticCompositionLocalOf {
    DevicePerformanceProfile(isLowEnd = false)
}

/** Pure thresholds, kept separate so the classification is deterministic in tests. */
internal object DevicePerformancePolicy {
    private const val LOW_RAM_BYTES = 3L * 1024L * 1024L * 1024L
    private const val LOW_APP_MEMORY_CLASS_MB = 192

    fun isLowEnd(
        isLowRamDevice: Boolean,
        totalRamBytes: Long,
        appMemoryClassMb: Int,
    ): Boolean =
        isLowRamDevice ||
            (totalRamBytes > 0L && totalRamBytes <= LOW_RAM_BYTES) ||
            (appMemoryClassMb > 0 && appMemoryClassMb <= LOW_APP_MEMORY_CLASS_MB)
}
