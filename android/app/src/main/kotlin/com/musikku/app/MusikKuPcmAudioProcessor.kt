package com.musikku.app

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tanh

/** Emits a lightweight waveform from the actual PCM buffers handled by Media3. */
object MusikKuAudioVisualizationEvents {
    @Volatile var eventSink: io.flutter.plugin.common.EventChannel.EventSink? = null
    @Volatile var enabled: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var lastDispatchAtMs = 0L

    fun publish(bars: List<Int>, rms: Double) {
        if (!enabled) return
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - lastDispatchAtMs < 55L) return
        lastDispatchAtMs = now
        mainHandler.post {
            if (enabled) eventSink?.success(mapOf("bars" to bars, "rms" to rms))
        }
    }
}

/**
 * PCM processor for Media3.
 *
 * The leveler uses a per-channel K-weighting approximation (high shelf + RLB
 * high-pass), a 400 ms smoothed energy window, gain attack/release smoothing,
 * and an immediate sample-peak ceiling. This is a real-time short-term
 * loudness leveler; it is deliberately NOT advertised as integrated EBU R128
 * LUFS or ReplayGain because those require track-wide analysis and gating.
 */
@UnstableApi
class MusikKuPcmAudioProcessor : BaseAudioProcessor() {
    @Volatile var normalizationEnabled: Boolean = false

    /**
     * MusikKu Soundstage is a mono-safe psychoacoustic enhancement for the
     * Media3 PCM path. It adds low-level bass harmonics, presence detail and
     * gentle peak control. It is not Dolby decoding or multichannel surround.
     */
    @Volatile var soundStageEnabled: Boolean = false
    @Volatile var soundStageStrength: Int = 85
    @Volatile private var resetGainPending = true

    // Live diagnostics: the UI can now distinguish a saved toggle from PCM
    // samples that actually passed through this processor.
    @Volatile private var pcmConfigured = false
    @Volatile private var configuredFormat = "Belum ada format PCM dari Media3"
    @Volatile private var unsupportedFormatReason = "Menunggu Media3 menyiapkan audio"
    @Volatile private var pcmBuffersProcessed = 0L
    @Volatile private var soundStageBuffersProcessed = 0L
    @Volatile private var lastPcmAtMs = 0L
    @Volatile private var lastInputPeak = 0.0
    @Volatile private var lastOutputPeak = 0.0
    @Volatile private var lastEffectDeltaRms = 0.0

    fun diagnostics(): Map<String, Any?> = mapOf(
        "pcmConfigured" to pcmConfigured,
        "configuredFormat" to configuredFormat,
        "unsupportedFormatReason" to unsupportedFormatReason,
        "pcmBuffersProcessed" to pcmBuffersProcessed,
        "soundStageBuffersProcessed" to soundStageBuffersProcessed,
        "lastPcmAtMs" to lastPcmAtMs,
        "pcmAgeMs" to if (lastPcmAtMs > 0L) {
            (SystemClock.elapsedRealtime() - lastPcmAtMs).coerceAtLeast(0L)
        } else {
            -1L
        },
        "pcmFlowing" to (lastPcmAtMs > 0L &&
            SystemClock.elapsedRealtime() - lastPcmAtMs in 0L..1500L),
        "lastInputPeak" to lastInputPeak,
        "lastOutputPeak" to lastOutputPeak,
        "lastEffectDeltaRms" to lastEffectDeltaRms,
        "enabled" to soundStageEnabled,
        "strength" to soundStageStrength,
    )

    private var sampleRateHz = 48000
    private var channelCount = 2
    private var inputEncoding = C.ENCODING_PCM_16BIT
    private var bytesPerSample = 2
    private var shelfFilters = emptyArray<Biquad>()
    private var highPassFilters = emptyArray<Biquad>()
    private var soundStageStates = emptyArray<SoundStageChannelState>()
    private var smoothedGain = 1.0
    private var smoothedWeightedEnergy = 0.012

    /** Per-channel state; no allocation is performed inside the audio loop. */
    private class SoundStageChannelState(sampleRate: Int) {
        private val safeRate = sampleRate.coerceAtLeast(8000).toDouble()
        // Three deliberately audible bands for small mono speakers:
        // 85-180 Hz adds body, 900-4.5 kHz moves vocals forward, and >6.5 kHz
        // adds a restrained amount of articulation. The bass harmonics path
        // synthesizes upper harmonics rather than trying to boost inaudible sub-bass.
        private val bassAlpha = 1.0 - exp(-2.0 * PI * 180.0 / safeRate)
        private val bassSubAlpha = 1.0 - exp(-2.0 * PI * 85.0 / safeRate)
        private val dcAlpha = 1.0 - exp(-2.0 * PI * 30.0 / safeRate)
        private val presenceLowAlpha = 1.0 - exp(-2.0 * PI * 900.0 / safeRate)
        private val presenceHighAlpha = 1.0 - exp(-2.0 * PI * 4500.0 / safeRate)
        private val detailAlpha = 1.0 - exp(-2.0 * PI * 6500.0 / safeRate)
        private val attackAlpha = 1.0 - exp(-1.0 / (safeRate * 0.004))
        private val releaseAlpha = 1.0 - exp(-1.0 / (safeRate * 0.110))
        private var bassLow = 0.0
        private var bassSubLow = 0.0
        private var rectifiedDc = 0.0
        private var presenceLow = 0.0
        private var presenceHigh = 0.0
        private var detailLow = 0.0
        private var peakEnvelope = 0.0
        private var compressorGain = 1.0

        fun process(input: Double, amount: Double): Double {
            if (amount <= 0.0) return input

            // Bass perception: extract the low band, full-wave rectify it and
            // remove its DC component. The remaining low-level even harmonic
            // helps tiny speakers suggest bass without boosting inaudible sub-bass.
            bassLow += bassAlpha * (input - bassLow)
            bassSubLow += bassSubAlpha * (input - bassSubLow)
            val bassBody = bassLow - bassSubLow
            val rectified = abs(bassLow)
            rectifiedDc += dcAlpha * (rectified - rectifiedDc)
            val bassHarmonic = rectified - rectifiedDc

            // A true band-pass style vocal/presence lift (roughly 900 Hz to
            // 4.5 kHz), rather than boosting every frequency above 1.9 kHz.
            presenceLow += presenceLowAlpha * (input - presenceLow)
            presenceHigh += presenceHighAlpha * (input - presenceHigh)
            val presence = presenceHigh - presenceLow
            detailLow += detailAlpha * (input - detailLow)
            val detail = input - detailLow

            // Stronger but still headroom-managed profile. At 70% this now
            // gives a clear mid-bass body and vocal presence lift on compact
            // mono speakers instead of the nearly inaudible previous profile.
            var output = input +
                bassBody * (0.36 * amount) +
                bassHarmonic * (1.25 * amount) +
                presence * (0.28 * amount) +
                detail * (0.12 * amount)

            // More useful peak control for compact speakers, without the
            // aggressive pumping of a hard compressor.
            val level = abs(output)
            val envelopeCoefficient = if (level > peakEnvelope) attackAlpha else releaseAlpha
            peakEnvelope += (level - peakEnvelope) * envelopeCoefficient
            val threshold = 0.48
            val ratio = 1.75
            val targetGain = if (peakEnvelope > threshold) {
                (threshold + (peakEnvelope - threshold) / ratio) / peakEnvelope.coerceAtLeast(1e-6)
            } else {
                1.0
            }
            val gainCoefficient = if (targetGain < compressorGain) 0.24 else 0.025
            compressorGain += (targetGain - compressorGain) * gainCoefficient
            output *= compressorGain

            // Smooth saturation above the normal operating range; this avoids
            // a hard digital edge while retaining headroom for the Android sink.
            val magnitude = abs(output)
            if (magnitude > 0.90) {
                val limited = 0.90 + 0.10 * tanh((magnitude - 0.90) / 0.10)
                output = if (output < 0.0) -limited else limited
            }
            return output
        }

        fun clear() {
            bassLow = 0.0
            bassSubLow = 0.0
            rectifiedDc = 0.0
            presenceLow = 0.0
            presenceHigh = 0.0
            detailLow = 0.0
            peakEnvelope = 0.0
            compressorGain = 1.0
        }
    }

    private class Biquad(
        private val b0: Double,
        private val b1: Double,
        private val b2: Double,
        private val a1: Double,
        private val a2: Double,
    ) {
        private var x1 = 0.0
        private var x2 = 0.0
        private var y1 = 0.0
        private var y2 = 0.0

        fun process(input: Double): Double {
            val output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = input
            y2 = y1
            y1 = output
            return output
        }

        fun clear() {
            x1 = 0.0
            x2 = 0.0
            y1 = 0.0
            y2 = 0.0
        }

        companion object {
            fun highPass(sampleRate: Int, frequency: Double = 38.135, q: Double = 0.5): Biquad {
                val safeRate = sampleRate.coerceAtLeast(8000).toDouble()
                val omega = 2.0 * PI * frequency.coerceIn(10.0, safeRate * 0.20) / safeRate
                val cosine = cos(omega)
                val alpha = sin(omega) / (2.0 * q)
                val a0 = 1.0 + alpha
                val b0 = (1.0 + cosine) / 2.0
                val b1 = -(1.0 + cosine)
                val b2 = b0
                val a1 = -2.0 * cosine
                val a2 = 1.0 - alpha
                return Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
            }

            fun highShelf(
                sampleRate: Int,
                frequency: Double = 1500.0,
                gainDb: Double = 4.0,
                slope: Double = 1.0,
            ): Biquad {
                val safeRate = sampleRate.coerceAtLeast(8000).toDouble()
                val omega = 2.0 * PI * frequency.coerceIn(100.0, safeRate * 0.40) / safeRate
                val cosine = cos(omega)
                val sine = sin(omega)
                val amplitude = 10.0.pow(gainDb / 40.0)
                val slopeSafe = slope.coerceIn(0.1, 1.0)
                val alpha = sine / 2.0 * sqrt(
                    ((amplitude + 1.0 / amplitude) * (1.0 / slopeSafe - 1.0) + 2.0)
                        .coerceAtLeast(0.0),
                )
                val twoRootAAlpha = 2.0 * sqrt(amplitude) * alpha
                val b0 = amplitude * ((amplitude + 1.0) + (amplitude - 1.0) * cosine + twoRootAAlpha)
                val b1 = -2.0 * amplitude * ((amplitude - 1.0) + (amplitude + 1.0) * cosine)
                val b2 = amplitude * ((amplitude + 1.0) + (amplitude - 1.0) * cosine - twoRootAAlpha)
                val a0 = (amplitude + 1.0) - (amplitude - 1.0) * cosine + twoRootAAlpha
                val a1 = 2.0 * ((amplitude - 1.0) - (amplitude + 1.0) * cosine)
                val a2 = (amplitude + 1.0) - (amplitude - 1.0) * cosine - twoRootAAlpha
                return Biquad(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
            }
        }
    }

    /** Request a per-track gain/filter reset without crossing audio-thread ownership. */
    fun resetForNewTrack() {
        resetGainPending = true
    }

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        val encodingName = when (inputAudioFormat.encoding) {
            C.ENCODING_PCM_16BIT -> "PCM16"
            C.ENCODING_PCM_FLOAT -> "PCM Float32"
            else -> "encoding ${inputAudioFormat.encoding}"
        }
        configuredFormat = "${inputAudioFormat.sampleRate} Hz · ${inputAudioFormat.channelCount} kanal · $encodingName"
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT &&
            inputAudioFormat.encoding != C.ENCODING_PCM_FLOAT) {
            pcmConfigured = false
            unsupportedFormatReason = "Format audio Media3 belum didukung: ${inputAudioFormat.encoding}."
            shelfFilters = emptyArray()
            highPassFilters = emptyArray()
            soundStageStates = emptyArray()
            return AudioProcessor.AudioFormat.NOT_SET
        }
        sampleRateHz = inputAudioFormat.sampleRate.coerceAtLeast(8000)
        // Preserve the decoder's exact PCM channel count for the Media3 sink;
        // do not downmix or clamp channels inside this processor.
        if (inputAudioFormat.channelCount !in 1..24) {
            pcmConfigured = false
            unsupportedFormatReason = "Jumlah kanal PCM tidak didukung: ${inputAudioFormat.channelCount}."
            shelfFilters = emptyArray()
            highPassFilters = emptyArray()
            soundStageStates = emptyArray()
            return AudioProcessor.AudioFormat.NOT_SET
        }
        channelCount = inputAudioFormat.channelCount
        inputEncoding = inputAudioFormat.encoding
        bytesPerSample = if (inputEncoding == C.ENCODING_PCM_FLOAT) 4 else 2
        rebuildFilters()
        soundStageStates = Array(channelCount) { SoundStageChannelState(sampleRateHz) }
        pcmConfigured = true
        unsupportedFormatReason = ""
        return inputAudioFormat
    }

    private fun rebuildFilters() {
        shelfFilters = Array(channelCount) { Biquad.highShelf(sampleRateHz) }
        highPassFilters = Array(channelCount) { Biquad.highPass(sampleRateHz) }
        resetGainPending = true
    }

    private fun resetFilters() {
        shelfFilters.forEach { it.clear() }
        highPassFilters.forEach { it.clear() }
        soundStageStates.forEach { it.clear() }
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val byteCount = inputBuffer.remaining()
        if (byteCount < bytesPerSample || byteCount % bytesPerSample != 0) return
        if (resetGainPending) {
            smoothedGain = 1.0
            smoothedWeightedEnergy = 0.012
            resetFilters()
            resetGainPending = false
        }

        val analysisInput = inputBuffer.duplicate().order(ByteOrder.nativeOrder())
        val sampleCount = byteCount / bytesPerSample
        val frameCount = (sampleCount / channelCount).coerceAtLeast(1)
        var weightedSquareSum = 0.0
        var peak = 0.0

        for (index in 0 until sampleCount) {
            val value = if (inputEncoding == C.ENCODING_PCM_FLOAT) {
                analysisInput.float.toDouble().coerceIn(-1.0, 1.0)
            } else {
                analysisInput.short.toInt() / 32768.0
            }
            peak = max(peak, abs(value))
            val channel = index % channelCount
            val shelf = shelfFilters.getOrNull(channel)
            val highPass = highPassFilters.getOrNull(channel)
            val weighted = if (shelf != null && highPass != null) {
                highPass.process(shelf.process(value))
            } else {
                value
            }
            weightedSquareSum += weighted * weighted
        }

        val weightedRms = sqrt(weightedSquareSum / sampleCount.coerceAtLeast(1))
        val bufferSeconds = frameCount.toDouble() / sampleRateHz.coerceAtLeast(8000)
        val gain = if (normalizationEnabled) {
            // Approximately 400 ms short-term loudness memory. It avoids the
            // syllable-by-syllable pumping of a per-buffer RMS controller.
            val energy = weightedRms * weightedRms
            val windowAlpha = 1.0 - exp(-bufferSeconds / 0.4)
            smoothedWeightedEnergy += (energy - smoothedWeightedEnergy) * windowAlpha
            val smoothedRms = sqrt(smoothedWeightedEnergy.coerceAtLeast(0.0))

            // Keep silence/noise from being boosted aggressively. Positive gain
            // is capped at +5.1 dB and attenuation at -12 dB.
            val targetRms = 0.105
            val desired = if (smoothedRms < 0.004) {
                1.0
            } else {
                (targetRms / smoothedRms).coerceIn(0.251, 1.8)
            }
            val peakCeilingGain = if (peak > 0.0001) 0.90 / peak else 1.8
            val peakSafeDesired = min(desired, peakCeilingGain)
            val gainAlpha = if (peakSafeDesired < smoothedGain) 0.28 else 0.035
            smoothedGain += (peakSafeDesired - smoothedGain) * gainAlpha
            min(smoothedGain.coerceIn(0.251, 1.8), peakCeilingGain)
        } else {
            smoothedGain = 1.0
            smoothedWeightedEnergy = 0.012
            1.0
        }

        val barsCount = 48
        val bars = IntArray(barsCount)
        val bucketSize = max(1, sampleCount / barsCount)
        val outputInput = inputBuffer.duplicate().order(ByteOrder.nativeOrder())
        val output = replaceOutputBuffer(byteCount).order(ByteOrder.nativeOrder())
        val applySoundStage = soundStageEnabled
        // A perceptual curve makes the middle of the slider useful; a linear
        // 70% setting previously produced only a barely measurable change.
        val linearStrength = soundStageStrength.coerceIn(0, 100) / 100.0
        val soundAmount = linearStrength.pow(0.75).coerceIn(0.0, 1.0)
        var effectDeltaSquareSum = 0.0
        var outputPeak = 0.0
        for (index in 0 until sampleCount) {
            val inputSample = if (inputEncoding == C.ENCODING_PCM_FLOAT) {
                outputInput.float.toDouble().coerceIn(-1.0, 1.0)
            } else {
                outputInput.short.toInt() / 32768.0
            }
            val bucket = min(barsCount - 1, index / bucketSize)
            val magnitude = abs(inputSample)
            if (magnitude * 100.0 > bars[bucket]) {
                bars[bucket] = (magnitude * 100.0).toInt().coerceIn(0, 100)
            }

            val drySample = inputSample * gain
            var sample = drySample
            if (applySoundStage && soundAmount > 0.0) {
                val channel = index % channelCount
                sample = soundStageStates.getOrNull(channel)?.process(sample, soundAmount) ?: sample
                val delta = sample - drySample
                effectDeltaSquareSum += delta * delta
            }
            outputPeak = max(outputPeak, abs(sample))
            if (inputEncoding == C.ENCODING_PCM_FLOAT) {
                output.putFloat(sample.toFloat().coerceIn(-1f, 1f))
            } else {
                val processed = (sample * 32768.0).toInt()
                    .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                output.putShort(processed.toShort())
            }
        }
        inputBuffer.position(inputBuffer.limit())
        output.flip()

        pcmBuffersProcessed += 1L
        if (applySoundStage && soundAmount > 0.0) {
            soundStageBuffersProcessed += 1L
            lastEffectDeltaRms = sqrt(effectDeltaSquareSum / sampleCount.coerceAtLeast(1))
        } else {
            lastEffectDeltaRms = 0.0
        }
        lastInputPeak = peak
        lastOutputPeak = outputPeak
        lastPcmAtMs = SystemClock.elapsedRealtime()

        if (MusikKuAudioVisualizationEvents.enabled) {
            MusikKuAudioVisualizationEvents.publish(bars.toList(), weightedRms)
        }
    }

    override fun onFlush() {
        resetGainPending = true
    }

    override fun onReset() {
        resetGainPending = true
        shelfFilters = emptyArray()
        highPassFilters = emptyArray()
        soundStageStates = emptyArray()
        inputEncoding = C.ENCODING_PCM_16BIT
        bytesPerSample = 2
        pcmConfigured = false
        configuredFormat = "Belum ada format PCM dari Media3"
        unsupportedFormatReason = "Menunggu Media3 menyiapkan audio"
    }
}
