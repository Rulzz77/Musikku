package com.musikku.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicLong

/** Local-only crash/ANR detector. No telemetry is sent anywhere. */
class AppHealthMonitor private constructor(private val context: Context) {
    companion object {
        private const val PREFS = "musikku_health"
        private const val KEY_EVENTS = "events"
        private const val MAX_EVENTS = 80
        private const val ANR_TIMEOUT_MS = 6000L
        @Volatile private var instance: AppHealthMonitor? = null
        fun get(context: Context): AppHealthMonitor = instance ?: synchronized(this) {
            instance ?: AppHealthMonitor(context.applicationContext).also { instance = it }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val heartbeat = AtomicLong(0L)
    private var watchdogThread: Thread? = null
    @Volatile private var running = false

    fun start() {
        if (running) return
        running = true
        heartbeat.set(System.nanoTime())
        mainHandler.post(heartbeatRunnable)
        watchdogThread = Thread({
            var last = heartbeat.get()
            var stalledAt = 0L
            while (running) {
                try { Thread.sleep(1500L) } catch (_: InterruptedException) { break }
                val now = heartbeat.get()
                if (now == last) {
                    if (stalledAt == 0L) stalledAt = System.currentTimeMillis()
                    if (System.currentTimeMillis() - stalledAt >= ANR_TIMEOUT_MS) {
                        record("ANR", "Main thread tidak merespons >= ${ANR_TIMEOUT_MS}ms")
                        stalledAt = System.currentTimeMillis() + ANR_TIMEOUT_MS
                    }
                } else {
                    last = now
                    stalledAt = 0L
                }
            }
        }, "MusikKu-ANR-Watchdog").apply { isDaemon = true }
        watchdogThread?.start()
    }

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            heartbeat.set(System.nanoTime())
            mainHandler.postDelayed(this, 1000L)
        }
    }

    fun stop() {
        running = false
        mainHandler.removeCallbacks(heartbeatRunnable)
        watchdogThread?.interrupt()
        watchdogThread = null
    }

    private fun redact(raw: String, maxLength: Int): String {
        var value = raw
        val querySecret = Regex(
            "([?&](?:key|api_key|access_token|refresh_token|token|client_secret)=)[^&#\\s]+",
            RegexOption.IGNORE_CASE,
        )
        value = querySecret.replace(value) { match -> "${match.groupValues[1]}[REDACTED]" }
        value = Regex("\\bBearer\\s+[A-Za-z0-9._~+/-]+=*", RegexOption.IGNORE_CASE)
            .replace(value, "Bearer [REDACTED]")
        value = Regex("\\bAIza[0-9A-Za-z_-]{20,}\\b")
            .replace(value, "[GOOGLE_API_KEY_REDACTED]")
        value = Regex("\\bya29\\.[0-9A-Za-z._-]{20,}\\b")
            .replace(value, "[OAUTH_TOKEN_REDACTED]")
        // YouTube media URLs can carry signed query parameters with changing names.
        value = Regex("(https?://[^\\s?#]+)\\?[^\\s#]*", RegexOption.IGNORE_CASE)
            .replace(value) { match -> "${match.groupValues[1]}?[QUERY_REDACTED]" }
        return value.take(maxLength)
    }

    fun record(kind: String, message: String, throwable: Throwable? = null) {
        val obj = JSONObject().apply {
            put("time", SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US).format(Date()))
            put("kind", redact(kind, 80))
            put("error", redact(message, 1200))
            put("stack", redact(throwable?.stackTraceToString() ?: "", 4000))
            put("platform", "android")
        }
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = JSONArrayCompat(prefs.getString(KEY_EVENTS, null))
        list.add(obj.toString())
        while (list.size > MAX_EVENTS) list.removeFirst()
        prefs.edit().putString(KEY_EVENTS, list.toJson()).apply()
    }

    fun events(): List<Map<String, String>> = JSONArrayCompat(
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_EVENTS, null)
    ).toList().mapNotNull { raw ->
        try {
            val obj = JSONObject(raw)
            mapOf(
                "time" to obj.optString("time"),
                "kind" to obj.optString("kind"),
                "error" to obj.optString("error"),
                "stack" to obj.optString("stack"),
            )
        } catch (_: Exception) { null }
    }.reversed()

    fun clear() {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_EVENTS).apply()
    }

    /** Tiny JSON-array helper so no extra dependency is required. */
    private class JSONArrayCompat(raw: String?) {
        private val values = mutableListOf<String>()
        init {
            if (!raw.isNullOrBlank()) {
                try {
                    val arr = org.json.JSONArray(raw)
                    for (i in 0 until arr.length()) values += arr.optString(i)
                } catch (_: Exception) {}
            }
        }
        val size get() = values.size
        fun add(value: String) { values += value }
        fun removeFirst() { if (values.isNotEmpty()) values.removeAt(0) }
        fun toJson(): String = org.json.JSONArray(values).toString()
        fun toList(): List<String> = values.toList()
    }
}
