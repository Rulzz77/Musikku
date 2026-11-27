package com.music.bitchord.data.canvas

import okhttp3.Request
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.concurrent.TimeUnit

class CanvasHttpTest {

    @Test
    fun `every canvas request uses the isolated six second timeout`() {
        val request = Request.Builder()
            .url("https://example.com/canvas")
            .build()

        val call = canvasCall(request)

        assertEquals(
            CANVAS_REQUEST_TIMEOUT_MS,
            TimeUnit.NANOSECONDS.toMillis(call.timeout().timeoutNanos()),
        )
    }
}
