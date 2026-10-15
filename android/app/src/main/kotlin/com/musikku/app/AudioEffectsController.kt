package com.musikku.app

import android.media.audiofx.Equalizer
import android.util.Log
import java.util.Locale

/**
 * Best-effort Android output equalizer.
 *
 * The YouTube player is rendered through a WebView, so it does not expose a
 * stable MediaPlayer/AudioTrack session ID to this Flutter bridge. Android
 * therefore only lets us attempt an output-mix equalizer here. Unsupported
 * devices fail gracefully and simply keep the preset as a saved preference.
 */
class AudioEffectsController {
    companion object {
        private const val TAG = "MusikKuAudio"
    }

    private var equalizer: Equalizer? = null

    @Synchronized
    fun applyPreset(name: String): Boolean {
        return try {
            val normalized = name.trim().lowercase(Locale.ROOT)

            // Preset Flat harus benar-benar netral. Sebagian implementasi
            // vendor dapat mengubah loudness ketika output-mix Equalizer aktif,
            // walaupun semua band terlihat 0 dB.
            if (normalized == "flat") {
                release()
                Log.d(TAG, "EQ preset=Flat -> output EQ disabled")
                return true
            }

            val eq = equalizer ?: Equalizer(0, 0).also { equalizer = it }
            eq.enabled = true
            val configured = applyDevicePreset(eq, normalized)

            Log.d(TAG, "EQ preset=$name applied=$configured")
            configured
        } catch (e: Throwable) {
            Log.w(TAG, "Equalizer unsupported: $e")
            release()
            false
        }
    }

    private fun applyDevicePreset(eq: Equalizer, normalized: String): Boolean {
        // Prefer a vendor preset when the device exposes one.
        for (index in 0 until eq.numberOfPresets.toInt()) {
            val preset = eq.getPresetName(index.toShort()).toString()
                .lowercase(Locale.ROOT)
            if (normalized == "flat" &&
                (preset.contains("normal") || preset.contains("flat"))) {
                eq.usePreset(index.toShort())
                return true
            }
            if (normalized.contains("bass") && preset.contains("bass")) {
                eq.usePreset(index.toShort())
                return true
            }
            if (normalized.contains("pop") && preset.contains("pop")) {
                eq.usePreset(index.toShort())
                return true
            }
            if (normalized.contains("rock") && preset.contains("rock")) {
                eq.usePreset(index.toShort())
                return true
            }
            if (normalized.contains("vocal") &&
                (preset.contains("vocal") || preset.contains("speech"))) {
                eq.usePreset(index.toShort())
                return true
            }
            if (normalized.contains("electronic") &&
                (preset.contains("dance") || preset.contains("electronic"))) {
                eq.usePreset(index.toShort())
                return true
            }
        }

        // Fall back to a small manual 5-band curve when the device doesn't
        // expose the requested named preset.
        val bands = eq.numberOfBands.toInt()
        if (bands <= 0) {
            return false
        }

        val pattern = when {
            normalized.contains("bass") -> intArrayOf(650, 300, 0, -100, -150)
            normalized.contains("pop") -> intArrayOf(250, 100, 0, 200, 300)
            normalized.contains("rock") -> intArrayOf(450, 150, -50, 250, 400)
            normalized.contains("vocal") -> intArrayOf(-150, 0, 250, 350, 200)
            normalized.contains("electronic") -> intArrayOf(450, 100, -100, 250, 450)
            else -> intArrayOf(0, 0, 0, 0, 0)
        }

        val range = eq.bandLevelRange
        val min = range[0].toInt()
        val max = range[1].toInt()

        for (i in 0 until bands) {
            val source = pattern.getOrElse(i) { 0 }
            val level = source.coerceIn(min, max).toShort()
            eq.setBandLevel(i.toShort(), level)
        }

        return true
    }

    @Synchronized
    fun release() {
        try {
            equalizer?.enabled = false
        } catch (_: Throwable) {
        }

        try {
            equalizer?.release()
        } catch (_: Throwable) {
        }

        equalizer = null
    }
}
