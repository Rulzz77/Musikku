package com.musikku.app

import android.content.Context
import android.net.TrafficStats
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Mencatat trafik jaringan UID aplikasi dari TrafficStats Android.
 * Pengukuran mencakup Wi-Fi + seluler, termasuk streaming, pencarian, dan gambar.
 * Total disimpan lokal; bukan pembacaan kuota operator.
 */
object DataUsageTracker {
    private const val PREFS_NAME = "musikku_data_usage_v1"
    private const val KEY_LAST_RX = "last_rx_bytes"
    private const val KEY_LAST_TX = "last_tx_bytes"
    private const val KEY_LAST_UPTIME = "last_uptime_millis"
    private const val KEY_TODAY_RX = "today_rx_bytes"
    private const val KEY_TODAY_TX = "today_tx_bytes"
    private const val KEY_TOTAL_RX = "total_rx_bytes"
    private const val KEY_TOTAL_TX = "total_tx_bytes"
    private const val KEY_DATE = "local_date"

    private const val SAMPLE_INTERVAL_MS = 1_000L
    private const val PERSIST_INTERVAL_MS = 5_000L
    private val lock = Any()
    private var started = false
    private var appContext: Context? = null
    private var handler: Handler? = null
    private var initialized = false
    private var lastRxBytes = -1L
    private var lastTxBytes = -1L
    private var lastUptimeMillis = -1L
    private var todayRxBytes = 0L
    private var todayTxBytes = 0L
    private var totalRxBytes = 0L
    private var totalTxBytes = 0L
    private var localDate = ""
    private var lastPersistAtMillis = 0L

    private val sampler = object : Runnable {
        override fun run() {
            val context = appContext ?: return
            sample(context, forcePersist = false)
            handler?.postDelayed(this, SAMPLE_INTERVAL_MS)
        }
    }

    fun start(context: Context) {
        synchronized(lock) {
            appContext = context.applicationContext
            if (started) return
            started = true
            if (handler == null) handler = Handler(Looper.getMainLooper())
            sampleLocked(context.applicationContext, forcePersist = true)
            handler?.removeCallbacks(sampler)
            handler?.postDelayed(sampler, SAMPLE_INTERVAL_MS)
        }
    }

    fun snapshot(context: Context): Map<String, Any> {
        val app = context.applicationContext
        synchronized(lock) {
            sampleLocked(app, forcePersist = true)
            val supported = TrafficStats.getUidRxBytes(Process.myUid()) >= 0L &&
                TrafficStats.getUidTxBytes(Process.myUid()) >= 0L
            return mapOf(
                "supported" to supported,
                "todayRxBytes" to todayRxBytes,
                "todayTxBytes" to todayTxBytes,
                "totalRxBytes" to totalRxBytes,
                "totalTxBytes" to totalTxBytes,
                "date" to currentDateKey(),
                "scope" to "wifi_and_mobile",
                "updatedAtMillis" to System.currentTimeMillis(),
            )
        }
    }

    private fun sample(context: Context, forcePersist: Boolean) {
        synchronized(lock) { sampleLocked(context.applicationContext, forcePersist) }
    }

    private fun sampleLocked(context: Context, forcePersist: Boolean) {
        val uid = Process.myUid()
        val rx = TrafficStats.getUidRxBytes(uid)
        val tx = TrafficStats.getUidTxBytes(uid)
        // A negative result means this Android build does not expose UID counters.
        if (rx < 0L || tx < 0L) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!initialized) {
            lastRxBytes = prefs.getLong(KEY_LAST_RX, -1L)
            lastTxBytes = prefs.getLong(KEY_LAST_TX, -1L)
            lastUptimeMillis = prefs.getLong(KEY_LAST_UPTIME, -1L)
            todayRxBytes = prefs.getLong(KEY_TODAY_RX, 0L)
            todayTxBytes = prefs.getLong(KEY_TODAY_TX, 0L)
            totalRxBytes = prefs.getLong(KEY_TOTAL_RX, 0L)
            totalTxBytes = prefs.getLong(KEY_TOTAL_TX, 0L)
            localDate = prefs.getString(KEY_DATE, "").orEmpty()
            initialized = true
        }

        val dateNow = currentDateKey()
        if (localDate != dateNow) {
            todayRxBytes = 0L
            todayTxBytes = 0L
            localDate = dateNow
        }

        // Use elapsed realtime to detect a reboot reliably. A post-reboot UID
        // counter can already be larger than the old counter by the time MusikKu
        // starts again; comparing byte counters alone would then miss that traffic.
        // First read establishes a baseline; no traffic before the first sample is guessed.
        val uptimeNow = SystemClock.elapsedRealtime()
        val rebootDetected = lastUptimeMillis >= 0L && uptimeNow < lastUptimeMillis
        val deltaRx = when {
            lastRxBytes < 0L -> 0L
            rebootDetected -> rx
            rx >= lastRxBytes -> rx - lastRxBytes
            else -> rx
        }
        val deltaTx = when {
            lastTxBytes < 0L -> 0L
            rebootDetected -> tx
            tx >= lastTxBytes -> tx - lastTxBytes
            else -> tx
        }

        todayRxBytes += deltaRx
        todayTxBytes += deltaTx
        totalRxBytes += deltaRx
        totalTxBytes += deltaTx
        lastRxBytes = rx
        lastTxBytes = tx
        lastUptimeMillis = uptimeNow

        val now = System.currentTimeMillis()
        if (forcePersist || now - lastPersistAtMillis >= PERSIST_INTERVAL_MS) {
            prefs.edit()
                .putLong(KEY_LAST_RX, lastRxBytes)
                .putLong(KEY_LAST_TX, lastTxBytes)
                .putLong(KEY_LAST_UPTIME, lastUptimeMillis)
                .putLong(KEY_TODAY_RX, todayRxBytes)
                .putLong(KEY_TODAY_TX, todayTxBytes)
                .putLong(KEY_TOTAL_RX, totalRxBytes)
                .putLong(KEY_TOTAL_TX, totalTxBytes)
                .putString(KEY_DATE, localDate)
                .apply()
            lastPersistAtMillis = now
        }
    }

    private fun currentDateKey(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
}
