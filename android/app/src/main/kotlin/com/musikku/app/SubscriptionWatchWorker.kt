package com.musikku.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * Mengecek channel yang di-subscribe secara berkala (walau aplikasi ditutup)
 * lalu mengirim notifikasi Android biasa:
 *  - "🔴 {channel} sedang live"
 *  - "{channel} mengunggah video baru"
 *
 * Hanya memakai data publik (API key), jadi tidak butuh token login Google.
 * Daftar channel dikirim dari Flutter lewat [configure].
 */
class SubscriptionWatchWorker(
    private val appContext: Context,
    params: WorkerParameters
) : Worker(appContext, params) {

    companion object {
        private const val TAG = "MusikKuWatch"

        private const val WORK_PERIODIC = "musikku_subscription_watch"
        private const val WORK_NOW = "musikku_subscription_watch_now"

        /** Interval minimum WorkManager 15 menit. 20 menit ~ 1500 unit kuota/hari. */
        private const val INTERVAL_MINUTES = 20L

        private const val PREFS = "musikku_watch"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_CONFIG = "config"
        private const val KEY_SEEN_VIDEOS = "seen_videos"
        private const val KEY_SEEN_LIVE = "seen_live"
        private const val KEY_KNOWN_CHANNELS = "known_channels"
        private const val KEY_SEEDED = "seeded"

        const val CHANNEL_LIVE = "youtube_live"
        const val CHANNEL_VIDEOS = "youtube_subscriptions"

        const val EXTRA_VIDEO_ID = "open_video_id"
        const val EXTRA_VIDEO_TITLE = "open_video_title"
        const val EXTRA_VIDEO_CHANNEL = "open_video_channel"

        private const val MAX_CHANNELS = 25
        private const val MAX_NOTIFICATIONS_PER_RUN = 5
        private const val MAX_VIDEO_AGE_MS = 2L * 24 * 60 * 60 * 1000
        private const val SEEN_LIMIT = 400

        private fun prefs(context: Context) =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        /** Simpan konfigurasi dari Flutter dan jadwalkan / batalkan worker. */
        fun configure(
            context: Context,
            enabled: Boolean,
            apiKey: String,
            channels: List<Map<String, String>>
        ) {
            val p = prefs(context)
            val workManager = WorkManager.getInstance(context)

            if (!enabled || apiKey.isBlank() || channels.isEmpty()) {
                workManager.cancelUniqueWork(WORK_PERIODIC)
                workManager.cancelUniqueWork(WORK_NOW)
                p.edit().clear().apply()
                MusikKuLogger.d(TAG, "WATCH DIMATIKAN")
                return
            }

            val array = JSONArray()
            for (channel in channels.take(MAX_CHANNELS)) {
                array.put(
                    JSONObject()
                        .put("id", channel["id"] ?: "")
                        .put("title", channel["title"] ?: "")
                        .put("uploads", channel["uploads"] ?: "")
                )
            }
            val config = JSONObject().put("apiKey", apiKey).put("channels", array)

            val configText = config.toString()
            val changed = p.getString(KEY_CONFIG, null) != configText ||
                !p.getBoolean(KEY_SEEDED, false)

            p.edit()
                .putBoolean(KEY_ENABLED, true)
                .putString(KEY_CONFIG, configText)
                .apply()

            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val periodic = PeriodicWorkRequestBuilder<SubscriptionWatchWorker>(
                INTERVAL_MINUTES, TimeUnit.MINUTES
            ).setConstraints(constraints).build()
            workManager.enqueueUniquePeriodicWork(
                WORK_PERIODIC,
                ExistingPeriodicWorkPolicy.UPDATE,
                periodic
            )

            // Pengecekan langsung hanya kalau daftar channel baru / berubah, supaya
            // data awal (tanpa notifikasi) siap dan kuota tidak terbuang tiap
            // aplikasi dibuka.
            if (changed) {
                val now = OneTimeWorkRequestBuilder<SubscriptionWatchWorker>()
                    .setConstraints(constraints)
                    .build()
                workManager.enqueueUniqueWork(WORK_NOW, ExistingWorkPolicy.KEEP, now)
            }
            MusikKuLogger.d(TAG, "WATCH AKTIF: ${array.length()} channel")
        }
    }

    private class Upload(
        val videoId: String,
        val title: String,
        val channelId: String,
        val channelTitle: String
    )

    override fun doWork(): Result {
        val p = prefs(appContext)
        if (!p.getBoolean(KEY_ENABLED, false)) return Result.success()

        val config = try {
            JSONObject(p.getString(KEY_CONFIG, "") ?: "")
        } catch (_: Exception) {
            return Result.success()
        }
        val apiKey = config.optString("apiKey")
        val channels = config.optJSONArray("channels") ?: return Result.success()
        if (apiKey.isBlank() || channels.length() == 0) return Result.success()

        val seenVideos = p.getStringSet(KEY_SEEN_VIDEOS, emptySet())!!.toMutableSet()
        val seenLive = p.getStringSet(KEY_SEEN_LIVE, emptySet())!!.toMutableSet()
        val knownChannels = p.getStringSet(KEY_KNOWN_CHANNELS, emptySet())!!.toMutableSet()
        val seeded = p.getBoolean(KEY_SEEDED, false)

        // 1) Upload terbaru tiap channel (1 unit kuota per channel).
        val uploads = LinkedHashMap<String, Upload>()
        try {
            for (i in 0 until channels.length()) {
                val channel = channels.getJSONObject(i)
                val playlistId = channel.optString("uploads")
                if (playlistId.isBlank()) continue
                val channelId = channel.optString("id")
                val channelTitle = channel.optString("title")
                val json = httpGetJson(
                    "https://www.googleapis.com/youtube/v3/playlistItems" +
                        "?part=snippet,contentDetails&maxResults=3" +
                        "&playlistId=${enc(playlistId)}&key=${enc(apiKey)}"
                ) ?: continue
                val items = json.optJSONArray("items") ?: continue
                for (j in 0 until items.length()) {
                    val item = items.getJSONObject(j)
                    val videoId = item.optJSONObject("contentDetails")?.optString("videoId").orEmpty()
                    if (videoId.isEmpty()) continue
                    val snippet = item.optJSONObject("snippet")
                    uploads[videoId] = Upload(
                        videoId = videoId,
                        title = snippet?.optString("title").orEmpty(),
                        channelId = channelId,
                        channelTitle = snippet?.optString("videoOwnerChannelTitle")
                            ?.takeIf { it.isNotBlank() } ?: channelTitle
                    )
                }
            }
        } catch (e: QuotaExceededException) {
            // Kuota harian habis: berhenti diam-diam, coba lagi di jadwal berikutnya.
            MusikKuLogger.w(TAG, "KUOTA HABIS, lewati pengecekan ini")
            return Result.success()
        }
        if (uploads.isEmpty()) return Result.success()

        // 2) Status live + waktu terbit (1 unit kuota per 50 video).
        val liveIds = HashSet<String>()
        val musicVideoIds = HashSet<String>()
        val publishedAt = HashMap<String, Long>()
        try {
            uploads.keys.chunked(50).forEach { chunk ->
                val json = httpGetJson(
                    "https://www.googleapis.com/youtube/v3/videos" +
                        "?part=snippet&id=${enc(chunk.joinToString(","))}&key=${enc(apiKey)}"
                ) ?: return@forEach
                val items = json.optJSONArray("items") ?: return@forEach
                for (i in 0 until items.length()) {
                    val item = items.getJSONObject(i)
                    val id = item.optString("id")
                    val snippet = item.optJSONObject("snippet") ?: continue
                    // Keep Android background notifications music-only too.
                    if (snippet.optString("categoryId") != "10") continue
                    musicVideoIds.add(id)
                    if (snippet.optString("liveBroadcastContent") == "live") liveIds.add(id)
                    parseIsoMillis(snippet.optString("publishedAt"))?.let { publishedAt[id] = it }
                }
            }
        } catch (e: QuotaExceededException) {
            MusikKuLogger.w(TAG, "KUOTA HABIS saat cek status live")
            return Result.success()
        }

        // 3) Tentukan yang baru. Channel yang baru ditambahkan / pengecekan
        //    pertama hanya dicatat (tanpa notifikasi) agar tidak membanjiri.
        val toNotifyLive = ArrayList<Upload>()
        val toNotifyVideo = ArrayList<Upload>()
        val nowMs = System.currentTimeMillis()

        for (upload in uploads.values) {
            // Unknown/non-music category is intentionally not notified.
            if (upload.videoId !in musicVideoIds) continue
            val isSeedChannel = !seeded || !knownChannels.contains(upload.channelId)
            if (upload.videoId in liveIds) {
                if (seenLive.add(upload.videoId)) {
                    seenVideos.add(upload.videoId)
                    if (!isSeedChannel) toNotifyLive.add(upload)
                }
                continue
            }
            if (seenVideos.add(upload.videoId) && !isSeedChannel) {
                val age = publishedAt[upload.videoId]?.let { nowMs - it } ?: 0L
                if (age <= MAX_VIDEO_AGE_MS) toNotifyVideo.add(upload)
            }
        }

        for (i in 0 until channels.length()) {
            knownChannels.add(channels.getJSONObject(i).optString("id"))
        }

        // 4) Simpan lebih dulu supaya tidak dobel kalau worker diulang.
        p.edit()
            .putStringSet(KEY_SEEN_VIDEOS, seenVideos.trimmed(uploads.keys))
            .putStringSet(KEY_SEEN_LIVE, seenLive.trimmed(uploads.keys))
            .putStringSet(KEY_KNOWN_CHANNELS, knownChannels)
            .putBoolean(KEY_SEEDED, true)
            .apply()

        // 5) Kirim notifikasi (live dulu).
        var sent = 0
        for (upload in toNotifyLive) {
            if (sent >= MAX_NOTIFICATIONS_PER_RUN) break
            if (postNotification(upload, live = true)) sent++
        }
        for (upload in toNotifyVideo) {
            if (sent >= MAX_NOTIFICATIONS_PER_RUN) break
            if (postNotification(upload, live = false)) sent++
        }
        MusikKuLogger.d(TAG, "CEK SELESAI: live=${toNotifyLive.size} video=${toNotifyVideo.size} terkirim=$sent")
        return Result.success()
    }

    // ============================================================
    // NOTIFIKASI
    // ============================================================

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_LIVE, "Siaran langsung", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Channel yang kamu subscribe sedang live."
            }
        )
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_VIDEOS, "Musik dari subscription", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Musik baru dari channel yang kamu subscribe."
            }
        )
    }

    private fun postNotification(upload: Upload, live: Boolean): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(appContext, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        if (!NotificationManagerCompat.from(appContext).areNotificationsEnabled()) return false

        ensureChannels()

        val open = Intent(appContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_VIDEO_ID, upload.videoId)
            putExtra(EXTRA_VIDEO_TITLE, upload.title)
            putExtra(EXTRA_VIDEO_CHANNEL, upload.channelTitle)
        }
        val notificationId = ((if (live) "live:" else "video:") + upload.videoId).hashCode() and 0x7fffffff
        val pending = PendingIntent.getActivity(
            appContext,
            notificationId,
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val thumbnail = downloadBitmap("https://i.ytimg.com/vi/${upload.videoId}/mqdefault.jpg")

        val builder = NotificationCompat.Builder(appContext, if (live) CHANNEL_LIVE else CHANNEL_VIDEOS)
            // Ikon kecil status bar harus monokrom (siluet putih); PNG berwarna
            // app_icon akan tampil sebagai kotak putih.
            .setSmallIcon(R.drawable.ic_stat_musikku)
            .setColor(0xFF5A52E8.toInt())
            .setContentTitle(
                if (live) "🔴 ${upload.channelTitle} sedang live"
                else "${upload.channelTitle} mengunggah musik baru"
            )
            .setContentText(upload.title)
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_SOCIAL)
            .setPriority(if (live) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)

        if (thumbnail != null) {
            builder.setLargeIcon(thumbnail)
            builder.setStyle(
                NotificationCompat.BigPictureStyle()
                    .bigPicture(thumbnail)
                    .setSummaryText(upload.title)
            )
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(upload.title))
        }

        return try {
            NotificationManagerCompat.from(appContext).notify(notificationId, builder.build())
            true
        } catch (e: SecurityException) {
            MusikKuLogger.w(TAG, "NOTIFIKASI DITOLAK", e)
            false
        }
    }

    // ============================================================
    // JARINGAN
    // ============================================================

    private class QuotaExceededException : Exception()

    private fun enc(value: String): String = URLEncoder.encode(value, "UTF-8")

    private fun httpGetJson(url: String): JSONObject? {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 15_000
                requestMethod = "GET"
            }
            val code = connection.responseCode
            if (code == 403 || code == 429) {
                val body = connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
                if (body.contains("quotaExceeded") || body.contains("rateLimitExceeded") ||
                    body.contains("dailyLimitExceeded")
                ) {
                    throw QuotaExceededException()
                }
                return null
            }
            if (code !in 200..299) return null
            JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
        } catch (e: QuotaExceededException) {
            throw e
        } catch (e: Exception) {
            MusikKuLogger.w(TAG, "HTTP GAGAL: ${e.message}")
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun downloadBitmap(url: String): Bitmap? {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5_000
                readTimeout = 5_000
            }
            if (connection.responseCode !in 200..299) return null
            connection.inputStream.use { BitmapFactory.decodeStream(it) }
        } catch (_: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun parseIsoMillis(value: String): Long? {
        if (value.isBlank()) return null
        return try {
            java.time.Instant.parse(value).toEpochMilli()
        } catch (_: Exception) {
            null
        }
    }

    /** Batasi ukuran, tapi id yang masih ada di upload terbaru selalu dipertahankan. */
    private fun MutableSet<String>.trimmed(protect: Set<String>): MutableSet<String> {
        if (size <= SEEN_LIMIT) return this
        val result = LinkedHashSet<String>(protect.filter { it in this })
        for (id in this) {
            if (result.size >= SEEN_LIMIT) break
            result.add(id)
        }
        return result
    }
}
