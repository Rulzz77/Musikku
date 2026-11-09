package com.musikku.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.MediaCodecList
import android.media.audiofx.AudioEffect
import android.media.Spatializer
import android.os.Build
import androidx.annotation.RequiresApi

/**
 * Reports whether the Android device exposes the platform decoders and
 * spatialization path needed for genuine Dolby Atmos playback.
 *
 * This is capability detection only. It does not install Dolby technology,
 * unlock OEM sound modes, or convert stereo audio into Dolby Atmos.
 */
object DolbyAtmosCapabilityProbe {
    private const val MIME_E_AC3 = "audio/eac3"
    private const val MIME_AC4 = "audio/ac4"

    fun snapshot(context: Context): Map<String, Any?> {
        val decoders = runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
                .asSequence()
                .filterNot { it.isEncoder }
                .flatMap { codec ->
                    codec.supportedTypes.asSequence()
                        .filter { it.equals(MIME_E_AC3, ignoreCase = true) || it.equals(MIME_AC4, ignoreCase = true) }
                        .map { mime ->
                            val maxChannels = runCatching {
                                codec.getCapabilitiesForType(mime).audioCapabilities?.maxInputChannelCount ?: 0
                            }.getOrDefault(0)
                            mapOf(
                                "name" to codec.name,
                                "mimeType" to mime,
                                "maxInputChannels" to maxChannels,
                                "hardwareAccelerated" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    runCatching { codec.isHardwareAccelerated }.getOrDefault(false)
                                } else {
                                    false
                                },
                                "vendorCodec" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    runCatching { codec.isVendor }.getOrDefault(false)
                                } else {
                                    false
                                },
                            )
                        }
                }
                .toList()
        }.getOrDefault(emptyList())

        val hasEac3 = decoders.any { it["mimeType"]?.toString()?.equals(MIME_E_AC3, true) == true }
        val hasAc4 = decoders.any { it["mimeType"]?.toString()?.equals(MIME_AC4, true) == true }
        val spatializer = spatializerSnapshot(context)
        // Some OEMs expose a system Dolby processing effect. Listing it is only
        // a hint: Android does not provide a universal public switch for it.
        val oemDolbyEffects = runCatching {
            AudioEffect.queryEffects()
                ?.filter { descriptor ->
                    descriptor.name.contains("dolby", ignoreCase = true) ||
                        descriptor.implementor.contains("dolby", ignoreCase = true)
                }
                ?.map { descriptor ->
                    mapOf(
                        "name" to descriptor.name,
                        "implementor" to descriptor.implementor,
                        "uuid" to descriptor.uuid.toString(),
                    )
                }
                .orEmpty()
        }.getOrDefault(emptyList())
        val spatializerReadyForMultichannel =
            spatializer["supported"] == true &&
            spatializer["available"] == true &&
            spatializer["enabled"] == true &&
            spatializer["canSpatialize51"] == true

        return mapOf(
            "apiLevel" to Build.VERSION.SDK_INT,
            "eac3DecoderAvailable" to hasEac3,
            "ac4DecoderAvailable" to hasAc4,
            // Dolby's Android guide uses these MIME capabilities to identify
            // devices that can decode Dolby Digital Plus/Atmos and AC-4.
            "dolbyCodecCandidates" to decoders,
            "oemDolbyEffects" to oemDolbyEffects,
            "oemDolbyEffectCandidateDetected" to oemDolbyEffects.isNotEmpty(),
            "spatializer" to spatializer,
            "dolbyDecoderCandidateDetected" to (hasEac3 || hasAc4),
            "nativeMultichannelSpatializationReady" to spatializerReadyForMultichannel,
            "note" to "Capability hints only. They do not prove OEM Dolby licensing, an enabled Dolby mode, or that the current audio source contains Atmos metadata.",
        )
    }

    private fun spatializerSnapshot(context: Context): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S_V2) {
            return mapOf(
                "supported" to false,
                "available" to false,
                "enabled" to false,
                "canSpatializeStereo" to false,
                "canSpatialize51" to false,
                "reason" to "Android Spatializer API requires Android 12L / API 32 or newer.",
            )
        }
        return spatializerSnapshotApi32(context)
    }

    @RequiresApi(Build.VERSION_CODES.S_V2)
    private fun spatializerSnapshotApi32(context: Context): Map<String, Any?> {
        return runCatching {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val spatializer = audioManager.spatializer
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build()

            fun canSpatialize(channelMask: Int): Boolean = runCatching {
                val format = AudioFormat.Builder()
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(48_000)
                    .setChannelMask(channelMask)
                    .build()
                spatializer.canBeSpatialized(attributes, format)
            }.getOrDefault(false)

            val level = spatializer.immersiveAudioLevel
            val supported = level != Spatializer.SPATIALIZER_IMMERSIVE_LEVEL_NONE
            val available = spatializer.isAvailable
            val enabled = spatializer.isEnabled
            mapOf(
                "supported" to supported,
                "immersiveAudioLevel" to level,
                "available" to available,
                "enabled" to enabled,
                "canSpatializeStereo" to canSpatialize(AudioFormat.CHANNEL_OUT_STEREO),
                "canSpatialize51" to canSpatialize(AudioFormat.CHANNEL_OUT_5POINT1),
                "headTrackerAvailable" to spatializer.isHeadTrackerAvailable,
                "reason" to if (!supported) {
                    "Perangkat tidak melaporkan dukungan Android Spatializer."
                } else if (!available) {
                    "Spatializer tidak tersedia untuk rute output aktif saat pemeriksaan."
                } else if (!enabled) {
                    "Spatializer didukung tetapi dinonaktifkan di pengaturan sistem."
                } else {
                    "Status Spatializer mengikuti Android dan perangkat output."
                },
            )
        }.getOrElse { error ->
            mapOf(
                "supported" to false,
                "available" to false,
                "enabled" to false,
                "canSpatializeStereo" to false,
                "canSpatialize51" to false,
                "reason" to (error.message ?: "Gagal membaca status Spatializer."),
            )
        }
    }
}
