package com.musikku.app

import android.os.Handler
import android.os.Looper
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
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
            if (enabled) {
                eventSink?.success(mapOf("bars" to bars, "rms" to rms))
            }
        }
    }
}

@UnstableApi
class MusikKuPcmAudioProcessor : BaseAudioProcessor() {
    @Volatile var normalizationEnabled: Boolean = false
    private var smoothedGain = 1.0

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat): AudioProcessor.AudioFormat {
        // Preserve all formats untouched unless the buffer is signed PCM16.
        return if (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT) {
            inputAudioFormat
        } else {
            AudioProcessor.AudioFormat.NOT_SET
        }
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val byteCount = inputBuffer.remaining()
        if (byteCount < 2) return

        val input = inputBuffer.duplicate().order(ByteOrder.nativeOrder())
        val sampleCount = byteCount / 2
        var squareSum = 0.0
        for (index in 0 until sampleCount) {
            val sample = input.short.toInt()
            val normalized = sample / 32768.0
            squareSum += normalized * normalized
        }
        val rms = sqrt(squareSum / sampleCount.coerceAtLeast(1))

        val gain = if (normalizationEnabled) {
            // Smooth gain changes to avoid audible pumping. Loud sections are
            // attenuated quickly; quieter sections recover more gradually.
            val target = 0.115
            val desired = (target / max(rms, 0.035)).coerceIn(0.72, 1.65)
            val amount = if (desired < smoothedGain) 0.24 else 0.035
            smoothedGain += (desired - smoothedGain) * amount
            smoothedGain
        } else {
            smoothedGain = 1.0
            1.0
        }

        val barsCount = 48
        val bars = IntArray(barsCount)
        val bucketSize = max(1, sampleCount / barsCount)
        val analyze = inputBuffer.duplicate().order(ByteOrder.nativeOrder())
        val output = replaceOutputBuffer(byteCount).order(ByteOrder.nativeOrder())
        for (index in 0 until sampleCount) {
            val raw = analyze.short.toInt()
            val bucket = min(barsCount - 1, index / bucketSize)
            val magnitude = abs(raw / 32768.0)
            if (magnitude * 100.0 > bars[bucket]) {
                bars[bucket] = (magnitude * 100.0).toInt().coerceIn(0, 100)
            }
            val processed = (raw * gain).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
            output.putShort(processed.toShort())
        }
        if (byteCount % 2 != 0) output.put(inputBuffer.get())
        inputBuffer.position(inputBuffer.limit())
        output.flip()

        if (MusikKuAudioVisualizationEvents.enabled) {
            MusikKuAudioVisualizationEvents.publish(bars.toList(), rms)
        }
    }

    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        smoothedGain = 1.0
    }

    override fun onReset() {
        smoothedGain = 1.0
    }
}
