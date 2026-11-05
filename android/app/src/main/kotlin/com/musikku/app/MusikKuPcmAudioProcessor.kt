package com.musikku.app

import android.os.Handler
import android.os.Looper
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
 * PCM16 processor for Media3.
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
    @Volatile private var resetGainPending = true

    private var sampleRateHz = 48000
    private var channelCount = 2
    private var shelfFilters = emptyArray<Biquad>()
    private var highPassFilters = emptyArray<Biquad>()
    private var smoothedGain = 1.0
    private var smoothedWeightedEnergy = 0.012

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
        if (inputAudioFormat.encoding != C.ENCODING_PCM_16BIT) {
            shelfFilters = emptyArray()
            highPassFilters = emptyArray()
            return AudioProcessor.AudioFormat.NOT_SET
        }
        sampleRateHz = inputAudioFormat.sampleRate.coerceAtLeast(8000)
        channelCount = inputAudioFormat.channelCount.coerceIn(1, 8)
        rebuildFilters()
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
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val byteCount = inputBuffer.remaining()
        if (byteCount < 2) return
        if (resetGainPending) {
            smoothedGain = 1.0
            smoothedWeightedEnergy = 0.012
            resetFilters()
            resetGainPending = false
        }

        val analysisInput = inputBuffer.duplicate().order(ByteOrder.nativeOrder())
        val sampleCount = byteCount / 2
        val frameCount = (sampleCount / channelCount).coerceAtLeast(1)
        var weightedSquareSum = 0.0
        var peak = 0.0

        for (index in 0 until sampleCount) {
            val raw = analysisInput.short.toInt()
            val value = raw / 32768.0
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
        for (index in 0 until sampleCount) {
            val raw = outputInput.short.toInt()
            val bucket = min(barsCount - 1, index / bucketSize)
            val magnitude = abs(raw / 32768.0)
            if (magnitude * 100.0 > bars[bucket]) {
                bars[bucket] = (magnitude * 100.0).toInt().coerceIn(0, 100)
            }
            val processed = (raw * gain).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            output.putShort(processed.toShort())
        }
        if (byteCount % 2 != 0) output.put(outputInput.get())
        inputBuffer.position(inputBuffer.limit())
        output.flip()

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
    }
}
