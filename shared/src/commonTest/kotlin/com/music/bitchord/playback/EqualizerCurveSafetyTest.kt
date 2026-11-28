package com.music.bitchord.playback

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class EqualizerCurveSafetyTest {

    @Test
    fun `curve construction replaces non finite gains and Q values before calculating preamp`() {
        val gains = FloatArray(EqLayout.SLOTS) { index ->
            when (index % 4) {
                0 -> Float.NaN
                1 -> Float.POSITIVE_INFINITY
                2 -> Float.NEGATIVE_INFINITY
                else -> 40f
            }
        }
        val qs = FloatArray(EqLayout.SLOTS) { index ->
            when (index % 4) {
                0 -> Float.NaN
                1 -> Float.POSITIVE_INFINITY
                2 -> -1f
                else -> 1f
            }
        }

        val curve = EqCurve.of(gains, qs)

        assertTrue(curve.gainsDb.all(Float::isFinite))
        assertTrue(curve.qs.all(Float::isFinite))
        assertTrue(curve.preampDb.isFinite())
        assertEquals(0f, curve.gainsDb[0], 0f)
        assertEquals(0f, curve.gainsDb[1], 0f)
        assertEquals(0f, curve.gainsDb[2], 0f)
        assertEquals(EqLayout.MANUAL_RANGE_DB, curve.gainsDb[3], 0f)
        assertEquals(0.707f, curve.qs[0], 0f)
        assertEquals(0.707f, curve.qs[1], 0f)
        assertEquals(0.707f, curve.qs[2], 0f)
    }

    @Test
    fun `curve construction pads short arrays without producing non finite DSP values`() {
        val curve = EqCurve.of(floatArrayOf(3f), floatArrayOf(Float.NaN))

        assertEquals(EqLayout.SLOTS, curve.gainsDb.size)
        assertEquals(EqLayout.SLOTS, curve.qs.size)
        assertTrue(curve.gainsDb.all(Float::isFinite))
        assertTrue(curve.qs.all(Float::isFinite))
        assertTrue(curve.preampDb.isFinite())
        assertEquals(3f, curve.gainsDb[0], 0f)
        assertEquals(0f, curve.gainsDb[1], 0f)
    }
}
