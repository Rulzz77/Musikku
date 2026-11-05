package com.musikku.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.util.Locale

/**
 * Keeps the MusikKu process at foreground-service priority while the Dart
 * download queue is actively transferring files. The transfer itself remains
 * owned by OfflineDownloadService; this service does not duplicate network IO.
 *
 * If Android kills the application process, partial files are retained by the
 * Dart downloader and are reconciled/resumed after MusikKu is opened again.
 */
class OfflineDownloadForegroundService : Service() {
    companion object {
        private const val CHANNEL_ID = "musikku_offline_downloads"
        private const val CHANNEL_NAME = "Unduhan MusikKu"
        private const val NOTIFICATION_ID = 2002
        private const val ACTION_UPDATE = "com.musikku.app.OFFLINE_DOWNLOAD_UPDATE"
        private const val ACTION_STOP = "com.musikku.app.OFFLINE_DOWNLOAD_STOP"

        @Volatile
        private var activeService: OfflineDownloadForegroundService? = null

        fun update(
            context: Context,
            title: String,
            artist: String,
            progress: Int,
            downloadedBytes: Long,
            totalBytes: Long,
            queueCount: Int,
            paused: Boolean,
        ): Boolean {
            val intent = Intent(context, OfflineDownloadForegroundService::class.java).apply {
                action = ACTION_UPDATE
                putExtra("title", title.take(120))
                putExtra("artist", artist.take(120))
                putExtra("progress", progress.coerceIn(0, 100))
                putExtra("downloadedBytes", downloadedBytes.coerceAtLeast(0L))
                putExtra("totalBytes", totalBytes.coerceAtLeast(0L))
                putExtra("queueCount", queueCount.coerceAtLeast(0))
                putExtra("paused", paused)
            }
            // Do not call startForegroundService for every progress tick. Once
            // running, update the existing notification directly; this avoids
            // repeated background service-start requests on Android 12+.
            val current = activeService
            return try {
                if (current != null) {
                    current.publishNotification(intent)
                } else {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        ContextCompat.startForegroundService(context, intent)
                    } else {
                        context.startService(intent)
                    }
                    true
                }
            } catch (error: RuntimeException) {
                MusikKuLogger.e("OfflineDownloadFGS", "Permintaan foreground service ditolak", error)
                false
            }
        }

        fun stop(context: Context) {
            val current = activeService
            if (current != null) {
                current.stopNow()
            } else {
                context.stopService(Intent(context, OfflineDownloadForegroundService::class.java))
            }
        }
    }

    private var foregroundStarted = false
    private var downloadWakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        activeService = this
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopNow()
            return START_NOT_STICKY
        }
        publishNotification(intent, startId)
        return START_NOT_STICKY
    }

    private fun publishNotification(intent: Intent?, startId: Int = 0): Boolean {
        val paused = intent?.getBooleanExtra("paused", false) ?: false
        updateDownloadWakeLock(keepAwake = !paused)
        val notification = buildNotification(intent)
        try {
            if (!foregroundStarted) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                foregroundStarted = true
            } else {
                notificationManager().notify(NOTIFICATION_ID, notification)
            }
            return true
        } catch (error: RuntimeException) {
            MusikKuLogger.e("OfflineDownloadFGS", "Tidak dapat memperbarui notifikasi unduhan", error)
            stopForegroundCompat()
            if (startId > 0) stopSelfResult(startId) else stopSelf()
            return false
        }
    }

    private fun stopNow() {
        stopForegroundCompat()
        stopSelf()
    }

    /** Keep the CPU awake only while an active transfer is running. */
    private fun updateDownloadWakeLock(keepAwake: Boolean) {
        if (!keepAwake) {
            releaseDownloadWakeLock()
            return
        }
        try {
            val lock = downloadWakeLock ?: run {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                powerManager.newWakeLock(
                    PowerManager.PARTIAL_WAKE_LOCK,
                    "$packageName:OfflineDownload",
                ).apply {
                    setReferenceCounted(false)
                }.also { downloadWakeLock = it }
            }
            if (!lock.isHeld) lock.acquire()
        } catch (error: RuntimeException) {
            MusikKuLogger.e("OfflineDownloadFGS", "Tidak dapat menjaga CPU saat unduhan", error)
        }
    }

    private fun releaseDownloadWakeLock() {
        val lock = downloadWakeLock ?: return
        try {
            if (lock.isHeld) lock.release()
        } catch (error: RuntimeException) {
            MusikKuLogger.w("OfflineDownloadFGS", "Melepas wake lock gagal", error)
        } finally {
            downloadWakeLock = null
        }
    }

    /** Android 15+ enforces a six-hour/24-hour limit for dataSync FGS. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        MusikKuLogger.w(
            "OfflineDownloadFGS",
            "Batas waktu foreground dataSync tercapai; menyimpan status parsial dan menghentikan service.",
        )
        stopForegroundCompat()
        stopSelf(startId)
    }

    private fun buildNotification(intent: Intent?): Notification {
        val title = intent?.getStringExtra("title")?.trim().orEmpty()
            .ifBlank { "Mengunduh musik" }
        val artist = intent?.getStringExtra("artist")?.trim().orEmpty()
        val progress = intent?.getIntExtra("progress", 0) ?: 0
        val downloaded = intent?.getLongExtra("downloadedBytes", 0L) ?: 0L
        val total = intent?.getLongExtra("totalBytes", 0L) ?: 0L
        val queueCount = intent?.getIntExtra("queueCount", 0) ?: 0
        val paused = intent?.getBooleanExtra("paused", false) ?: false

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                2002,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val status = when {
            paused -> "Dijeda"
            total > 0L -> "${formatBytes(downloaded)} / ${formatBytes(total)}"
            else -> "Menyiapkan koneksi unduhan"
        }
        val queueText = if (queueCount > 0) "$queueCount lagu dalam antrean" else "Unduhan aktif"
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_musikku)
            .setContentTitle(if (paused) "Unduhan dijeda" else title)
            .setContentText(listOf(artist, status, queueText).filter { it.isNotBlank() }.joinToString(" · "))
            .setStyle(NotificationCompat.BigTextStyle().bigText(
                listOf(title, artist, status, queueText).filter { it.isNotBlank() }.joinToString("\n"),
            ))
            .setContentIntent(contentIntent)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setOngoing(!paused)
            .setAutoCancel(false)

        if (paused) {
            builder.setProgress(0, 0, false)
        } else if (total > 0L) {
            builder.setProgress(100, progress, false)
        } else {
            builder.setProgress(100, 0, true)
        }
        return builder.build()
    }

    private fun formatBytes(value: Long): String {
        val mb = value.toDouble() / (1024.0 * 1024.0)
        return String.format(Locale.US, "%.1f MB", mb)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Menampilkan progres unduhan playlist MusikKu"
            setShowBadge(false)
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun stopForegroundCompat() {
        releaseDownloadWakeLock()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        foregroundStarted = false
    }

    override fun onDestroy() {
        if (activeService === this) activeService = null
        if (foregroundStarted) stopForegroundCompat()
        super.onDestroy()
    }
}
