package com.musikku.app

import android.Manifest
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.content.ContentUris
import android.provider.MediaStore
import android.provider.Settings
import android.media.MediaMetadataRetriever
import android.os.Build
import android.annotation.TargetApi
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.content.Intent
import android.os.Bundle
import android.net.ConnectivityManager
import android.net.Uri
import android.net.NetworkCapabilities

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

import java.io.File
import java.util.Locale

import androidx.work.WorkManager
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat


private const val PIP_ACTION = "com.musikku.app.PIP_CONTROL"
private const val PIP_EXTRA_TYPE = "type"
private const val PIP_PREVIOUS = 1
private const val PIP_PLAY_PAUSE = 2
private const val PIP_NEXT = 3

/** Only direct YouTube media CDN URLs are accepted by the native audio player. */
private fun isTrustedYoutubeAudioUrl(raw: String): Boolean {
    if (raw.isBlank() || raw.length > 8192) return false
    val uri = runCatching { Uri.parse(raw) }.getOrNull() ?: return false
    val host = uri.host?.lowercase(Locale.ROOT).orEmpty()
    val trustedHost = host == "googlevideo.com" || host.endsWith(".googlevideo.com")
    return uri.scheme.equals("https", ignoreCase = true) &&
        trustedHost &&
        (uri.port == -1 || uri.port == 443) &&
        uri.encodedAuthority?.contains('@') != true &&
        uri.fragment.isNullOrEmpty()
}

private val allowedStreamHeaderNames = setOf("user-agent", "referer", "origin")
private fun sanitizeStreamHeaders(raw: Map<String, Any?>): Map<String, String> =
    raw.mapNotNull { (key, value) ->
        val normalizedKey = key.trim()
        val normalizedValue = value?.toString()?.trim().orEmpty()
        val lowerKey = normalizedKey.lowercase(Locale.ROOT)
        if (lowerKey !in allowedStreamHeaderNames || normalizedValue.isBlank() ||
            normalizedValue.length > 2048 || normalizedValue.any { it == '\r' || it == '\n' }) {
            null
        } else {
            normalizedKey to normalizedValue
        }
    }.toMap()

// ============================================================
// YOUTUBE PLATFORM VIEW FACTORY
// ============================================================

class YoutubePlatformViewFactory :
    PlatformViewFactory(
        StandardMessageCodec.INSTANCE
    ) {

    override fun create(
        context: android.content.Context,
        viewId: Int,
        args: Any?
    ): PlatformView {

        MusikKuLogger.d(
            "MusikKuNative",
            "===================================="
        )

        MusikKuLogger.d(
            "MusikKuNative",
            "PLATFORM VIEW CREATE"
        )

        MusikKuLogger.d(
            "MusikKuNative",
            "viewId = $viewId"
        )

        MusikKuLogger.d(
            "MusikKuNative",
            "===================================="
        )

        return YoutubePlatformView(context)
    }
}


// ============================================================
// MAIN ACTIVITY
// ============================================================

class MainActivity : AudioServiceActivity() {

    private val audioEffectsController = AudioEffectsController()
    private lateinit var healthMonitor: AppHealthMonitor

    private var pendingFileResult: MethodChannel.Result? = null
    private var backupJsonWaiting: String = ""
    private var pendingFileRequestCode: Int = 0
    private var pendingLocalPermissionResult: MethodChannel.Result? = null

    companion object {

        private const val TAG =
            "MusikKuNative"

        const val METHOD_CHANNEL =
            "musikku/youtube_player"

        const val EVENT_CHANNEL =
            "musikku/youtube_player/events"

        private const val REQUEST_EXPORT_BACKUP = 9901
        private const val REQUEST_IMPORT_BACKUP = 9902

        const val LOCAL_METHOD_CHANNEL =
            "musikku/local_media"

        private const val REQUEST_LOCAL_AUDIO_PERMISSION = 6001

        // ====================================================
        // CHANNEL UNTUK SERVICE -> FLUTTER
        // ====================================================

        var notificationMethodChannel: MethodChannel? = null
        private var uncaughtHandlerInstalled = false

    }

    private fun currentNetworkTypeForApp(): String {
        return try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return "unknown"
            val network = manager.activeNetwork ?: return "offline"
            val capabilities = manager.getNetworkCapabilities(network) ?: return "offline"
            when {
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "mobile"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                else -> "other"
            }
        } catch (_: Exception) {
            "unknown"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Cancel subscription-monitor work scheduled by older versions.
        // Music playback/media controls are unaffected.
        runCatching {
            WorkManager.getInstance(applicationContext).cancelUniqueWork("musikku_subscription_watch")
            WorkManager.getInstance(applicationContext).cancelUniqueWork("musikku_subscription_watch_now")
        }.onFailure { error ->
            MusikKuLogger.w(TAG, "GAGAL MEMBATALKAN WORKER SUBSCRIPTION LAMA", error)
        }
        healthMonitor = AppHealthMonitor.get(this)
        healthMonitor.start()
        // Start sampling per-app network traffic early; the tracker keeps
        // recording while the app's foreground playback service is alive.
        DataUsageTracker.start(applicationContext)
        if (!uncaughtHandlerInstalled) {
            val previousHandler = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
                healthMonitor.record("Crash", "Uncaught exception on ${thread.name}", throwable)
                previousHandler?.uncaughtException(thread, throwable)
            }
            uncaughtHandlerInstalled = true
        }
    }


    // ========================================================
    // CONFIGURE FLUTTER ENGINE
    // ========================================================

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {

        super.configureFlutterEngine(
            flutterEngine
        )

        // Register search/audio stream resolver on the channel used by Dart.
        // Without this, resolveAudio returns MissingPluginException and every
        // online track falls back to the embedded video player.
        NewPipeExtractorBridge.register(flutterEngine.dartExecutor.binaryMessenger)
        DataUsageTracker.start(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "musikku/data_usage",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getStats", "refresh" -> {
                    try {
                        result.success(DataUsageTracker.snapshot(applicationContext))
                    } catch (error: Exception) {
                        MusikKuLogger.e(TAG, "Membaca konsumsi data gagal", error)
                        result.error("DATA_USAGE_FAILED", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // APK updater mandiri: izin instalasi dan FileProvider dibatasi pada
        // folder apk_updates privat di files/ (cache persisten) dan cache/
        // (untuk mendukung APK lama yang masih memakai lokasi sebelumnya).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "musikku/app_update",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSupportedAbis" -> {
                    // Android returns the device's preferred supported ABIs first.
                    result.success(Build.SUPPORTED_ABIS.toList())
                }

                "canInstallPackages" -> {
                    val allowed = Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        packageManager.canRequestPackageInstalls()
                    result.success(allowed)
                }

                "requestInstallPermission" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            !packageManager.canRequestPackageInstalls()
                        ) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName"),
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    } catch (error: Exception) {
                        MusikKuLogger.e(TAG, "Membuka pengaturan izin APK gagal", error)
                        result.error("INSTALL_PERMISSION_SETTINGS", error.message, null)
                    }
                }

                "installApk" -> {
                    try {
                        val rawPath = call.argument<String>("path")
                            ?: throw IllegalArgumentException("Path APK tidak tersedia")
                        val apkFile = File(rawPath).canonicalFile
                        // New updater cache lives in persistent app-private files so a
                        // verified APK can be reused after app restarts/updates. Keep the
                        // legacy cache path accepted for APKs downloaded by older builds.
                        val allowedDirs = listOf(
                            File(filesDir, "apk_updates").canonicalFile,
                            File(cacheDir, "apk_updates").canonicalFile,
                        )
                        val isInUpdaterDirectory = allowedDirs.any { directory ->
                            apkFile.path.startsWith(directory.path + File.separator)
                        }
                        if (!isInUpdaterDirectory || !apkFile.isFile || apkFile.length() < 4L) {
                            throw IllegalArgumentException("File APK tidak valid atau berada di luar folder updater")
                        }

                        val contentUri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apkFile,
                        )
                        val installIntent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(contentUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(installIntent)
                        result.success(true)
                    } catch (error: Exception) {
                        MusikKuLogger.e(TAG, "Membuka installer APK gagal", error)
                        result.error("APK_INSTALLER_FAILED", error.message, null)
                    }
                }

                "openReleasesPage" -> {
                    try {
                        startActivity(
                            Intent(
                                Intent.ACTION_VIEW,
                                Uri.parse("https://github.com/Rulzz77/flutter_application_5/releases"),
                            ),
                        )
                        result.success(true)
                    } catch (error: Exception) {
                        result.error("OPEN_RELEASES_FAILED", error.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }


        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "MUSIKKU NATIVE ENGINE AKTIF"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        // ====================================================
        // METHOD CHANNEL
        // ====================================================

        val methodChannel =
            MethodChannel(
                flutterEngine
                    .dartExecutor
                    .binaryMessenger,

                METHOD_CHANNEL
            )


        // ====================================================
        // SIMPAN CHANNEL
        // ====================================================

        notificationMethodChannel =
            methodChannel


        MusikKuLogger.d(
            TAG,
            "NOTIFICATION METHOD CHANNEL SIAP"
        )


        // ====================================================
        // METHOD CALL HANDLER
        // ====================================================

        methodChannel.setMethodCallHandler { call, result ->

            MusikKuLogger.d(
                TAG,
                "METHOD CHANNEL = ${call.method}"
            )


            when (call.method) {


                // ==================================================
                // LOAD VIDEO
                // ==================================================

                "setPlayerUiVisible" -> {
                    val visible = call.argument<Boolean>("visible") ?: true
                    YoutubePlatformView.instance?.setPlayerUiVisible(visible)
                    result.success(null)
                }

                "setPlaybackQuality" -> {
                    val quality = call.argument<String>("quality")?.trim().orEmpty()
                    if (quality.isBlank()) {
                        result.error("INVALID_QUALITY", "Kualitas video kosong", null)
                        return@setMethodCallHandler
                    }
                    if (!YoutubePlatformView.requestQuality(quality)) {
                        result.error("INVALID_QUALITY", "Level kualitas tidak dikenal: $quality", null)
                        return@setMethodCallHandler
                    }
                    result.success(null)
                }

                "setDataSaverLevel" -> {
                    val level = call.argument<Int>("level") ?: 0
                    YoutubePlatformView.requestDataSaverLevel(level)
                    result.success(null)
                }

                "setCaptionSettings" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val language = call.argument<String>("language")?.trim().orEmpty().ifBlank { "id" }
                    YoutubePlatformView.requestCaptionSettings(enabled, language)
                    result.success(null)
                }

                "setVideoCrop" -> {
                    val zoom = call.argument<Double>("zoom") ?: 1.0
                    YoutubePlatformView.requestCrop(zoom)
                    result.success(null)
                }

                "setLandscapeSystemUi" -> {
                    val immersive = call.argument<Boolean>("immersive") ?: false
                    setLandscapeSystemUi(immersive)
                    result.success(null)
                }

                "loadYoutubeAudio" -> {
                    val videoId = call.argument<String>("videoId")?.trim().orEmpty()
                    val title = call.argument<String>("title")?.trim().orEmpty().ifBlank { "Tanpa judul" }
                    val artist = call.argument<String>("artist")?.trim().orEmpty()
                    val thumbnailUrl = call.argument<String>("thumbnailUrl")?.trim().orEmpty()
                    val streamUrl = call.argument<String>("streamUrl")?.trim().orEmpty()
                    val startSeconds = call.argument<Double>("startSeconds") ?: 0.0
                    val durationSeconds = call.argument<Double>("durationSeconds") ?: 0.0
                    val playing = call.argument<Boolean>("playing") ?: true
                    val headersRaw = call.argument<Map<String, Any?>>("headers") ?: emptyMap()
                    val headers = sanitizeStreamHeaders(headersRaw)

                    if (!videoId.matches(Regex("[A-Za-z0-9_-]{11}")) ||
                        !isTrustedYoutubeAudioUrl(streamUrl)) {
                        result.error("INVALID_AUDIO_STREAM", "ID lagu atau URL audio tidak valid", null)
                        return@setMethodCallHandler
                    }

                    // Music-only mode: ensure the embedded YouTube view is not
                    // playing alongside the native audio-only stream.
                    YoutubePlatformView.instance?.deactivateForExternalPlayback()
                    val safeStartSeconds = if (startSeconds.isFinite()) startSeconds.coerceIn(0.0, 86400.0) else 0.0
                    val safeDurationSeconds = if (durationSeconds.isFinite()) durationSeconds.coerceIn(0.0, 86400.0) else 0.0
                    PlaybackService.start(
                        this,
                        videoId = videoId,
                        title = title.take(256),
                        artist = artist.take(128),
                        thumbnailUrl = thumbnailUrl.take(2048),
                        playing = playing,
                        positionSeconds = safeStartSeconds,
                        durationSeconds = safeDurationSeconds,
                        sourceType = "youtube_audio",
                        mediaUri = streamUrl,
                        streamHeaders = headers,
                    )

                    // startForegroundService() returns before onStartCommand is
                    // guaranteed to run. Don't tell Dart the new track is ready
                    // until the service snapshot belongs to it; otherwise the
                    // first volume/play command can accidentally target old audio.
                    var attempts = 0
                    val verifyServiceStarted = object : Runnable {
                        override fun run() {
                            val snapshot = PlaybackService.currentMediaSnapshot()
                            if (snapshot?.videoId == videoId &&
                                snapshot.sourceType == "youtube_audio") {
                                result.success(null)
                                return
                            }
                            attempts += 1
                            if (attempts >= 20) {
                                result.error(
                                    "AUDIO_SERVICE_START_FAILED",
                                    "Layanan pemutar audio belum siap untuk lagu ini",
                                    null,
                                )
                            } else {
                                Handler(Looper.getMainLooper()).postDelayed(this, 75L)
                            }
                        }
                    }
                    Handler(Looper.getMainLooper()).postDelayed(verifyServiceStarted, 50L)
                }

                "loadVideo" -> {

                    val videoId =
                        call.argument<String>(
                            "videoId"
                        )

                    val startSeconds =
                        call.argument<Double>(
                            "startSeconds"
                        ) ?: 0.0


                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "MAINACTIVITY: LOAD VIDEO"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "VIDEO ID = $videoId"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "PLAYER INSTANCE = ${YoutubePlatformView.instance}"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    if (
                        videoId.isNullOrBlank()
                    ) {

                        MusikKuLogger.e(
                            TAG,
                            "LOAD VIDEO GAGAL: videoId kosong"
                        )

                        result.error(
                            "INVALID_ID",
                            "videoId kosong",
                            null
                        )

                        return@setMethodCallHandler
                    }



                    PlaybackService.stopLocalForYoutubeStatic()

                    val player =
                        YoutubePlatformView.instance


                    if (player == null) {

                        MusikKuLogger.e(
                            TAG,
                            "LOAD VIDEO GAGAL: PLAYER BELUM READY"
                        )

                        result.error(
                            "PLAYER_NOT_READY",
                            "Youtube player belum siap",
                            null
                        )

                        return@setMethodCallHandler
                    }


                    MusikKuLogger.d(
                        TAG,
                        "MEMANGGIL player.loadVideo()"
                    )


                    player.loadVideo(
                        videoId,
                        startSeconds.toFloat()
                    )


                    MusikKuLogger.d(
                        TAG,
                        "player.loadVideo() SELESAI"
                    )


                    result.success(
                        null
                    )
                }


                // Pause the currently active source before resolving a different song.
                // This is intentionally not ID-gated: at this point the new stream URL
                // may not exist yet, but the old source must not continue underneath it.
                "pauseActiveAudio" -> {
                    PlaybackService.pauseAudioStatic()
                    YoutubePlatformView.instance?.pause()
                    result.success(null)
                }

                // ==================================================
                // PLAY
                // ==================================================

                "play" -> {

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "MAINACTIVITY: METHOD PLAY DITERIMA"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "PLAYER = ${YoutubePlatformView.instance}"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    val requestedVideoId = call.argument<String>("videoId")?.trim().orEmpty()
                    val serviceVideoId = PlaybackService.currentMediaSnapshot()?.videoId.orEmpty()
                    val serviceMatchesRequestedTrack = requestedVideoId.isNotBlank() &&
                        requestedVideoId == serviceVideoId &&
                        PlaybackService.isAudioPlayerActiveStatic()
                    if (serviceMatchesRequestedTrack) {
                        PlaybackService.playAudioStatic()
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val player = YoutubePlatformView.instance


                    if (player == null) {

                        MusikKuLogger.e(
                            TAG,
                            "PLAY GAGAL: PLAYER NULL"
                        )

                    } else {

                        MusikKuLogger.d(
                            TAG,
                            "MEMANGGIL NATIVE PLAYER PLAY"
                        )

                        player.play()

                        MusikKuLogger.d(
                            TAG,
                            "NATIVE PLAYER PLAY SELESAI"
                        )
                    }


                    result.success(
                        null
                    )
                }


                // ==================================================
                // PAUSE
                // ==================================================

                "pause" -> {

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "MAINACTIVITY: METHOD PAUSE DITERIMA"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "PLAYER = ${YoutubePlatformView.instance}"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    val requestedVideoId = call.argument<String>("videoId")?.trim().orEmpty()
                    val serviceVideoId = PlaybackService.currentMediaSnapshot()?.videoId.orEmpty()
                    val serviceMatchesRequestedTrack = requestedVideoId.isNotBlank() &&
                        requestedVideoId == serviceVideoId &&
                        PlaybackService.isAudioPlayerActiveStatic()
                    if (serviceMatchesRequestedTrack) {
                        PlaybackService.pauseAudioStatic()
                        result.success(null)
                        return@setMethodCallHandler
                    }

                    val player = YoutubePlatformView.instance


                    if (player == null) {

                        MusikKuLogger.e(
                            TAG,
                            "PAUSE GAGAL: PLAYER NULL"
                        )

                    } else {

                        MusikKuLogger.d(
                            TAG,
                            "MEMANGGIL NATIVE PLAYER PAUSE"
                        )

                        player.pause()

                        MusikKuLogger.d(
                            TAG,
                            "NATIVE PLAYER PAUSE SELESAI"
                        )
                    }


                    result.success(
                        null
                    )
                }


                // ==================================================
                // SEEK
                // ==================================================

                "seek" -> {

                    val seconds =
                        call.argument<Double>(
                            "seconds"
                        ) ?: 0.0


                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "MAINACTIVITY: SEEK"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "SECONDS = $seconds"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "PLAYER = ${YoutubePlatformView.instance}"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    val requestedVideoId = call.argument<String>("videoId")?.trim().orEmpty()
                    val serviceVideoId = PlaybackService.currentMediaSnapshot()?.videoId.orEmpty()
                    if (requestedVideoId.isNotBlank() && requestedVideoId == serviceVideoId &&
                        PlaybackService.isAudioPlayerActiveStatic()) {
                        PlaybackService.seekAudioStatic(seconds)
                    } else {
                        YoutubePlatformView.instance?.seek(seconds.toFloat())
                    }


                    result.success(
                        null
                    )
                }


                // ==================================================
                // PLAYER VOLUME
                // ==================================================

                "setVolume" -> {
                    val percent =
                        call.argument<Int>("percent")?.coerceIn(0, 100) ?: 100

                    val requestedVideoId = call.argument<String>("videoId")?.trim().orEmpty()
                    val serviceVideoId = PlaybackService.currentMediaSnapshot()?.videoId.orEmpty()
                    if (requestedVideoId.isNotBlank() && requestedVideoId == serviceVideoId &&
                        PlaybackService.isAudioPlayerActiveStatic()) {
                        PlaybackService.setAudioVolumeStatic(percent)
                    } else {
                        YoutubePlatformView.instance?.setVolume(percent)
                    }
                    result.success(null)
                }


                // ==================================================
                // LOCAL MUSIC PLAYER
                // ==================================================

                "loadLocal" -> {
                    val mediaId = call.argument<String>("mediaId")?.trim().orEmpty()
                    val title = call.argument<String>("title")?.trim().orEmpty()
                    val artist = call.argument<String>("artist")?.trim().orEmpty()
                    val uri = call.argument<String>("mediaUri")?.trim().orEmpty()
                    val startSeconds = call.argument<Double>("startSeconds") ?: 0.0
                    val durationSeconds = call.argument<Double>("durationSeconds") ?: 0.0

                    if (mediaId.isEmpty() || uri.isEmpty()) {
                        result.error("INVALID_LOCAL_MEDIA", "Data lagu lokal tidak lengkap", null)
                        return@setMethodCallHandler
                    }

                    YoutubePlatformView.instance?.deactivateForExternalPlayback()

                    PlaybackService.start(
                        this,
                        videoId = "local:$mediaId",
                        title = title.ifBlank { "Tanpa judul" },
                        artist = artist,
                        thumbnailUrl = "",
                        playing = true,
                        positionSeconds = startSeconds,
                        durationSeconds = durationSeconds,
                        sourceType = "local",
                        mediaUri = uri,
                    )
                    result.success(null)
                }


                // ==================================================
                // EQUALIZER PRESET
                // ==================================================

                "setEqualizerPreset" -> {
                    val preset = call.argument<String>("preset") ?: "Flat"
                    result.success(audioEffectsController.applyPreset(preset))
                }
                "setEqualizerBands" -> {
                    val rawBands = call.argument<List<Number>>("bandsDb") ?: emptyList()
                    result.success(audioEffectsController.applyManualBands(rawBands.map { it.toDouble() }))
                }


                "getNetworkType" -> {
                    result.success(currentNetworkTypeForApp())
                }


                // ==================================================
                // PLAYER DEBUG SNAPSHOT
                // ==================================================

                "getPlayerDebugSnapshot" -> {
                    val player = YoutubePlatformView.instance
                    if (player == null) {
                        result.success(
                            mapOf(
                                "ready" to false,
                                "error" to "player_not_ready",
                                "videoId" to "",
                                "state" to "unknown",
                                "preferredQuality" to YoutubePlatformView.preferredQuality,
                                "actualQuality" to "unknown",
                                "captionsRequested" to YoutubePlatformView.preferredCaptionsEnabled,
                                "captionPreference" to YoutubePlatformView.preferredCaptionLanguage,
                                "captionTracks" to 0,
                                "captionLanguages" to emptyList<String>(),
                                "captionSelected" to "",
                                "captionTranslation" to "",
                                "captionActive" to false,
                            ),
                        )
                    } else {
                        player.getPlayerDebugSnapshot { snapshot ->
                            result.success(snapshot)
                        }
                    }
                }


                // ==================================================
                // CURRENT TIME
                // ==================================================

                "currentTime" -> {

                    val requestedVideoId = call.argument<String>("videoId")?.trim().orEmpty()
                    val serviceVideoId = PlaybackService.currentMediaSnapshot()?.videoId.orEmpty()
                    val current = if (requestedVideoId.isNotBlank() &&
                        requestedVideoId == serviceVideoId &&
                        PlaybackService.isAudioPlayerActiveStatic()) {
                        PlaybackService.audioCurrentTimeStatic().toFloat()
                    } else {
                        YoutubePlatformView.instance?.currentTime() ?: 0.0f
                    }


                    MusikKuLogger.d(
                        TAG,
                        "CURRENT TIME = $current"
                    )


                    result.success(
                        current.toDouble()
                    )
                }


                // ==================================================
                // NATIVE PLAYBACK SNAPSHOT BACKUP
                // ==================================================

                "getNativePlaybackSnapshot" -> {
                    val prefs =
                        getSharedPreferences(
                            "musikku_native_playback",
                            android.content.Context.MODE_PRIVATE,
                        )

                    result.success(
                        mapOf(
                            "videoId" to (prefs.getString("videoId", "") ?: ""),
                            "title" to (prefs.getString("title", "") ?: ""),
                            "artist" to (prefs.getString("artist", "") ?: ""),
                            "positionSeconds" to
                                (prefs.getLong("positionMs", 0L).toDouble() / 1000.0),
                            "durationSeconds" to
                                (prefs.getLong("durationMs", 0L).toDouble() / 1000.0),
                            "playing" to prefs.getBoolean("playing", false),
                        ),
                    )
                }


                "getAudioOutputDevices" -> {
                    val audioManager = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val outputs = audioManager.getDevices(android.media.AudioManager.GET_DEVICES_OUTPUTS).map { device ->
                            val typeLabel = when (device.type) {
                                1 -> "Earpiece"
                                2 -> "Speaker bawaan"
                                3 -> "Headset kabel (mikrofon)"
                                4 -> "Headphone kabel"
                                5 -> "Line analog"
                                6 -> "Line digital"
                                7 -> "Bluetooth hands-free"
                                8 -> "Bluetooth audio"
                                9, 10, 29 -> "HDMI"
                                11, 12 -> "USB audio"
                                13, 28 -> "Dock audio"
                                14, 16 -> "FM audio"
                                17 -> "TV tuner"
                                18 -> "Telephony audio"
                                19 -> "Aux audio"
                                20 -> "IP audio"
                                21 -> "Bus audio"
                                22 -> "Headset USB"
                                23 -> "Alat bantu dengar"
                                24 -> "Speaker aman"
                                25 -> "Remote submix"
                                26 -> "Bluetooth LE headset"
                                27 -> "Bluetooth LE speaker"
                                30 -> "Bluetooth LE broadcast"
                                else -> "Output audio lain"
                            }
                            mapOf(
                                "id" to device.id,
                                "typeCode" to device.type,
                                "type" to typeLabel,
                                "productName" to device.productName?.toString().orEmpty(),
                            )
                        }
                        result.success(mapOf("supported" to true, "devices" to outputs))
                    } else {
                        result.success(mapOf("supported" to false, "devices" to emptyList<Map<String, Any>>()))
                    }
                }

                "getHealthEvents" -> {
                    result.success(healthMonitor.events())
                }

                "clearHealthEvents" -> {
                    healthMonitor.clear()
                    result.success(null)
                }

                // ==================================================
                // BACKUP / RESTORE
                // ==================================================

                "exportBackup" -> {
                    val raw = call.argument<String>("json") ?: ""
                    pendingFileResult = result
                    pendingFileRequestCode = REQUEST_EXPORT_BACKUP
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, "musikKu_backup.json")
                    }
                    try {
                        startActivityForResult(intent, REQUEST_EXPORT_BACKUP)
                    } catch (e: Exception) {
                        pendingFileResult = null
                        result.error("FILE_PICKER", e.message, null)
                    }

                    backupJsonWaiting = raw
                }

                "importBackup" -> {
                    pendingFileResult = result
                    pendingFileRequestCode = REQUEST_IMPORT_BACKUP
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                    }
                    try {
                        startActivityForResult(intent, REQUEST_IMPORT_BACKUP)
                    } catch (e: Exception) {
                        pendingFileResult = null
                        result.error("FILE_PICKER", e.message, null)
                    }
                }

                // ==================================================
                // START NOTIFICATION
                // ==================================================

                "startNotification" -> {

                    val videoId =
                        call.argument<String>(
                            "videoId"
                        ) ?: ""


                    val title =
                        call.argument<String>(
                            "title"
                        ) ?: "MusikKu"


                    val artist =
                        call.argument<String>(
                            "artist"
                        ) ?: ""


                    val thumbnailUrl =
                        call.argument<String>(
                            "thumbnailUrl"
                        ) ?: ""

                    val mediaUri =
                        call.argument<String>(
                            "mediaUri"
                        ) ?: ""


                    val playing =
                        call.argument<Boolean>(
                            "playing"
                        ) ?: false

                    val positionSeconds =
                        call.argument<Double>(
                            "positionSeconds"
                        ) ?: 0.0

                    val durationSeconds =
                        call.argument<Double>(
                            "durationSeconds"
                        ) ?: 0.0


                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "START NOTIFICATION"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "TITLE = $title"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "ARTIST = $artist"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "PLAYING = $playing"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    val activeSnapshot = PlaybackService.currentMediaSnapshot()
                    if (PlaybackService.isAudioPlayerActiveStatic() && activeSnapshot?.videoId == videoId) {
                        PlaybackService.updateAudioMetadataStatic(
                            videoId, title, artist, thumbnailUrl, durationSeconds,
                        )
                    } else {
                        PlaybackService.start(
                            this,
                            videoId,
                            title,
                            artist,
                            thumbnailUrl,
                            playing,
                            positionSeconds,
                            durationSeconds,
                            sourceType = if (videoId.startsWith("local:")) "local" else "youtube",
                            mediaUri = mediaUri,
                        )
                    }


                    result.success(
                        null
                    )
                }


                // ==================================================
                // UPDATE NOTIFICATION
                // ==================================================

                "updateNotification" -> {

                    val videoId =
                        call.argument<String>(
                            "videoId"
                        ) ?: ""


                    val title =
                        call.argument<String>(
                            "title"
                        ) ?: "MusikKu"


                    val artist =
                        call.argument<String>(
                            "artist"
                        ) ?: ""


                    val thumbnailUrl =
                        call.argument<String>(
                            "thumbnailUrl"
                        ) ?: ""

                    val mediaUri =
                        call.argument<String>(
                            "mediaUri"
                        ) ?: ""


                    val playing =
                        call.argument<Boolean>(
                            "playing"
                        ) ?: false

                    val positionSeconds =
                        call.argument<Double>(
                            "positionSeconds"
                        ) ?: 0.0

                    val durationSeconds =
                        call.argument<Double>(
                            "durationSeconds"
                        ) ?: 0.0


                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "UPDATE NOTIFICATION"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "TITLE = $title"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "ARTIST = $artist"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "PLAYING = $playing"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    val activeSnapshot = PlaybackService.currentMediaSnapshot()
                    if (PlaybackService.isAudioPlayerActiveStatic() && activeSnapshot?.videoId == videoId) {
                        PlaybackService.updateAudioMetadataStatic(
                            videoId, title, artist, thumbnailUrl, durationSeconds,
                        )
                    } else {
                        PlaybackService.start(
                            this,
                            videoId,
                            title,
                            artist,
                            thumbnailUrl,
                            playing,
                            positionSeconds,
                            durationSeconds,
                            sourceType = if (videoId.startsWith("local:")) "local" else "youtube",
                            mediaUri = mediaUri,
                        )
                    }


                    result.success(
                        null
                    )
                }


                // ==================================================
                // STOP NOTIFICATION
                // ==================================================

                "stopNotification" -> {

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "STOP NOTIFICATION"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    val serviceIntent =
                        android.content.Intent(
                            this,
                            PlaybackService::class.java
                        )


                    stopService(
                        serviceIntent
                    )


                    result.success(
                        null
                    )
                }


                // ==================================================
                // UNKNOWN METHOD
                // ==================================================

                else -> {

                    MusikKuLogger.w(
                        TAG,
                        "METHOD TIDAK DIKENAL = ${call.method}"
                    )


                    result.notImplemented()
                }
            }
        }


        // ========================================================
        // LOCAL MEDIA CHANNEL
        // ========================================================

        MusikKuLogger.d(TAG, "REGISTER LOCAL MEDIA METHOD CHANNEL")

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOCAL_METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasLocalMusicPermission" -> {
                    result.success(hasLocalMusicPermission())
                }

                "requestLocalMusicPermission" -> {
                    if (hasLocalMusicPermission()) {
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        Manifest.permission.READ_MEDIA_AUDIO
                    } else {
                        Manifest.permission.READ_EXTERNAL_STORAGE
                    }

                    pendingLocalPermissionResult = result
                    requestPermissions(arrayOf(permission), REQUEST_LOCAL_AUDIO_PERMISSION)
                }

                "scanLocalMusic" -> {
                    if (!hasLocalMusicPermission()) {
                        result.success(emptyList<Map<String, Any?>>())
                        return@setMethodCallHandler
                    }

                    result.success(scanLocalMusic())
                }

                "getLocalArtwork" -> {
                    val mediaId = call.argument<String>("mediaId")?.trim().orEmpty()
                    result.success(getLocalArtwork(mediaId))
                }

                else -> result.notImplemented()
            }
        }


        // ========================================================
        // EVENT CHANNEL
        // ========================================================

        MusikKuLogger.d(
            TAG,
            "REGISTER EVENT CHANNEL"
        )


        EventChannel(
            flutterEngine
                .dartExecutor
                .binaryMessenger,

            EVENT_CHANNEL

        ).setStreamHandler(

            object :
                EventChannel.StreamHandler {


                // ================================================
                // FLUTTER LISTEN
                // ================================================

                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?
                ) {

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "EVENT CHANNEL: FLUTTER MULAI LISTEN"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "EVENT SINK = $events"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    YoutubePlatformView
                        .eventSink = events
                    PlaybackService.eventSink = events
                }


                // ================================================
                // FLUTTER CANCEL LISTEN
                // ================================================

                override fun onCancel(
                    arguments: Any?
                ) {

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )

                    MusikKuLogger.d(
                        TAG,
                        "EVENT CHANNEL: FLUTTER STOP LISTEN"
                    )

                    MusikKuLogger.d(
                        TAG,
                        "===================================="
                    )


                    YoutubePlatformView
                        .eventSink = null
                    PlaybackService.eventSink = null
                }
            }
        )


        // ========================================================
        // REGISTER PLATFORM VIEW
        // ========================================================

        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "REGISTER YOUTUBE PLATFORM VIEW"
        )

        MusikKuLogger.d(
            TAG,
            "VIEW TYPE = musikku/youtube_player"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(

                "musikku/youtube_player",

                YoutubePlatformViewFactory()
            )


        MusikKuLogger.d(
            TAG,
            "YOUTUBE PLATFORM VIEW REGISTERED"
        )


        // ========================================================
        // NOTIFICATION PERMISSION
        // ========================================================

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.TIRAMISU
        ) {

            if (
                checkSelfPermission(
                    Manifest.permission
                        .POST_NOTIFICATIONS
                ) !=
                PackageManager.PERMISSION_GRANTED
            ) {

                MusikKuLogger.d(
                    TAG,
                    "REQUEST NOTIFICATION PERMISSION"
                )


                requestPermissions(

                    arrayOf(
                        Manifest.permission
                            .POST_NOTIFICATIONS
                    ),

                    5001
                )

            } else {

                MusikKuLogger.d(
                    TAG,
                    "NOTIFICATION PERMISSION SUDAH ADA"
                )
            }
        }
    }


    private fun hasLocalMusicPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun scanLocalMusic(): List<Map<String, Any?>> {
        val resolver = contentResolver
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.IS_MUSIC,
        )

        val result = mutableListOf<Map<String, Any?>>()

        val genreBySongId = mutableMapOf<Long, String>()
        run {
            val genreCollection = MediaStore.Audio.Genres.EXTERNAL_CONTENT_URI
            val genreProjection = arrayOf(
                MediaStore.Audio.Genres._ID,
                MediaStore.Audio.Genres.NAME,
            )
            resolver.query(genreCollection, genreProjection, null, null, null)?.use { genreCursor ->
                val gid = genreCursor.getColumnIndexOrThrow(MediaStore.Audio.Genres._ID)
                val gname = genreCursor.getColumnIndexOrThrow(MediaStore.Audio.Genres.NAME)
                while (genreCursor.moveToNext()) {
                    val genreId = genreCursor.getLong(gid)
                    val genreName = genreCursor.getString(gname)?.trim().orEmpty()
                    if (genreName.isEmpty()) continue
                    val members = MediaStore.Audio.Genres.Members.getContentUri("external", genreId)
                    val memberProjection = arrayOf(MediaStore.Audio.Genres.Members.AUDIO_ID)
                    resolver.query(members, memberProjection, null, null, null)?.use { memberCursor ->
                        val audioId = memberCursor.getColumnIndexOrThrow(MediaStore.Audio.Genres.Members.AUDIO_ID)
                        while (memberCursor.moveToNext()) {
                            genreBySongId.putIfAbsent(memberCursor.getLong(audioId), genreName)
                        }
                    }
                }
            }
        }

        resolver.query(
            collection,
            projection,
            "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} > 0",
            null,
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC",
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
            val titleIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
            val artistIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
            val albumIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationIndex = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)

            while (cursor.moveToNext()) {
                val id = cursor.getLong(idIndex)
                val uri = ContentUris.withAppendedId(collection, id).toString()
                result += mapOf(
                    "mediaId" to id.toString(),
                    "uri" to uri,
                    "title" to (cursor.getString(titleIndex) ?: "Tanpa judul"),
                    "artist" to (cursor.getString(artistIndex) ?: ""),
                    "album" to (cursor.getString(albumIndex) ?: ""),
                    "durationMs" to cursor.getLong(durationIndex),
                    "genre" to (genreBySongId[id] ?: ""),
                )
            }
        }

        return result
    }

    private fun getLocalArtwork(mediaId: String): ByteArray? {
        if (mediaId.isBlank()) return null

        val uri = ContentUris.withAppendedId(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            mediaId.toLongOrNull() ?: return null,
        )

        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, uri)
            retriever.embeddedPicture
        } catch (e: Exception) {
            MusikKuLogger.d(TAG, "LOCAL ARTWORK ERROR: ${e.message}")
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // no-op
            }
        }
    }


    private fun setLandscapeSystemUi(immersive: Boolean) {
        val controller = WindowCompat.getInsetsController(window, window.decorView)
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

        if (immersive) {
            controller.hide(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.show(WindowInsetsCompat.Type.systemBars())
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != REQUEST_LOCAL_AUDIO_PERMISSION) return

        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingLocalPermissionResult?.success(granted)
        pendingLocalPermissionResult = null
    }


    override fun onStart() {
        super.onStart()
        YoutubePlatformView.setAppBackground(false)
        registerQualityNetworkCallback()
        YoutubePlatformView.instance?.onAppForeground()
        refreshPipParamsForPlayerState(force = true)
    }

    override fun onStop() {
        super.onStop()
        // Layar mati / app ke background: video tidak terlihat, kualitas
        // diturunkan kalau mode hemat data aktif. Audio tidak terpengaruh.
        YoutubePlatformView.setAppBackground(true)
        unregisterQualityNetworkCallback()
    }

    private var qualityNetworkCallback: ConnectivityManager.NetworkCallback? = null
    private var lastNetworkNotMetered: Boolean? = null

    private fun registerQualityNetworkCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || qualityNetworkCallback != null) return
        try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(
                    network: android.net.Network,
                    capabilities: NetworkCapabilities
                ) {
                    val notMetered =
                        capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
                    if (lastNetworkNotMetered != notMetered) {
                        lastNetworkNotMetered = notMetered
                        YoutubePlatformView.instance?.reapplyQuality()
                    }
                }
            }
            manager.registerDefaultNetworkCallback(callback)
            qualityNetworkCallback = callback
        } catch (e: Exception) {
            MusikKuLogger.w(TAG, "Gagal mendaftarkan network callback", e)
        }
    }

    private fun unregisterQualityNetworkCallback() {
        val callback = qualityNetworkCallback ?: return
        qualityNetworkCallback = null
        try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            manager?.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        MusikKuLogger.d(TAG, "ACTIVITY CONFIG CHANGED orientation=${newConfig.orientation}")
    }

    // ========================================================
    // PIP: tombol Sebelumnya / Jeda-Putar / Berikutnya
    // ========================================================

    private val pipHandler = Handler(Looper.getMainLooper())
    private var pipReceiverRegistered = false
    private var lastPipPlaying: Boolean? = null
    private var systemPipEntryScheduled = false
    private var lastPipEligibility: Boolean? = null

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val method = when (intent?.getIntExtra(PIP_EXTRA_TYPE, -1)) {
                PIP_PREVIOUS -> "notificationPrevious"
                PIP_PLAY_PAUSE -> "notificationPlayPause"
                PIP_NEXT -> "notificationNext"
                else -> return
            }
            notificationMethodChannel?.invokeMethod(method, null)
            // Beri waktu player mengganti state, lalu perbarui ikon jeda/putar.
            pipHandler.postDelayed({ refreshPipActions() }, 500L)
        }
    }

    // Memeriksa state player tiap ~0,8 detik selama PiP supaya ikon
    // jeda/putar ikut berubah (mis. video selesai atau lanjut sendiri).
    private val pipPoller = object : Runnable {
        override fun run() {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            if (!isInPictureInPictureMode) return
            refreshPipActions()
            pipHandler.postDelayed(this, 800L)
        }
    }

    private fun isPipPlaying(): Boolean {
        val state = YoutubePlatformView.instance?.getCurrentPlaybackState() ?: return false
        return state == "playing" || state == "buffering"
    }

    private fun ensurePipReceiver() {
        if (pipReceiverRegistered) return
        val filter = IntentFilter(PIP_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pipReceiver, filter)
        }
        pipReceiverRegistered = true
    }

    private fun releasePipReceiver() {
        pipHandler.removeCallbacks(pipPoller)
        if (!pipReceiverRegistered) return
        try {
            unregisterReceiver(pipReceiver)
        } catch (_: Exception) {
        }
        pipReceiverRegistered = false
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun pipAction(
        iconRes: Int,
        title: String,
        type: Int
    ): RemoteAction {
        val intent = Intent(PIP_ACTION)
            .setPackage(packageName)
            .putExtra(PIP_EXTRA_TYPE, type)
        val pending = PendingIntent.getBroadcast(
            this,
            type,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        return RemoteAction(
            Icon.createWithResource(this, iconRes),
            title,
            title,
            pending
        )
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun buildPipParams(autoEnterEnabled: Boolean = false): PictureInPictureParams {
        val playing = isPipPlaying()
        lastPipPlaying = playing
        val actions = listOf(
            pipAction(android.R.drawable.ic_media_previous, "Sebelumnya", PIP_PREVIOUS),
            pipAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "Jeda" else "Putar",
                PIP_PLAY_PAUSE
            ),
            pipAction(android.R.drawable.ic_media_next, "Berikutnya", PIP_NEXT)
        )
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(actions)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnterEnabled)
        }
        return builder.build()
    }

    /**
     * Keeps Android 12+ auto-enter PiP parameters up to date while a YouTube
     * video is active. This is intentionally called from player state changes,
     * not only from onUserLeaveHint(), because Android 12+ can enter PiP before
     * onUserLeaveHint is delivered.
     */
    @TargetApi(Build.VERSION_CODES.O)
    fun refreshPipParamsForPlayerState(force: Boolean = false) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || isFinishing) return
        val eligible = YoutubePlatformView.instance?.shouldEnterPictureInPicture() == true
        val playing = isPipPlaying()
        if (!force && lastPipEligibility == eligible && lastPipPlaying == playing) return
        lastPipEligibility = eligible
        try {
            setPictureInPictureParams(
                buildPipParams(
                    autoEnterEnabled = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && eligible
                )
            )
        } catch (e: Exception) {
            MusikKuLogger.e(TAG, "GAGAL MENYIAPKAN AUTO-ENTER PIP", e)
        }
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun refreshPipActions() {
        if (isFinishing || !isInPictureInPictureMode) return
        if (isPipPlaying() == lastPipPlaying) return
        try {
            setPictureInPictureParams(buildPipParams())
        } catch (e: Exception) {
            MusikKuLogger.e(TAG, "GAGAL MEMPERBARUI TOMBOL PIP", e)
        }
    }

    @TargetApi(Build.VERSION_CODES.O)
    private fun enterSystemPipIfPossible(onStarted: (() -> Unit)? = null): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        if (isFinishing || isInPictureInPictureMode || systemPipEntryScheduled) return false

        val player = YoutubePlatformView.instance
        if (player?.shouldEnterPictureInPicture() != true) {
            return false
        }

        systemPipEntryScheduled = true
        MusikKuLogger.d(TAG, "MASUK ANDROID SYSTEM PIP LANGSUNG")
        notificationMethodChannel?.invokeMethod("youtubePipWillEnter", null)

        try {
            ensurePipReceiver()
            refreshPipParamsForPlayerState(force = true)
            // Use the parameterized API on all supported API levels.
            // The parameterless overload returns Unit on newer Kotlin stubs,
            // which caused the previous if-expression to infer Any and fail
            // compilation when used as a Boolean condition.
            val entered: Boolean = enterPictureInPictureMode(buildPipParams(false))
            MusikKuLogger.d(TAG, "ANDROID SYSTEM PIP ENTERED=$entered")
            if (entered) onStarted?.invoke()
            systemPipEntryScheduled = false
            return entered
        } catch (e: Exception) {
            systemPipEntryScheduled = false
            MusikKuLogger.e(TAG, "GAGAL MASUK ANDROID SYSTEM PIP", e)
            return false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ uses setAutoEnterEnabled(true). The system performs
            // the actual transition while leaving the app; do not call the
            // explicit enter API from this callback.
            refreshPipParamsForPlayerState(force = true)
            return
        }
        if (!enterSystemPipIfPossible()) {
            MusikKuLogger.d(TAG, "USER LEAVE HINT: system PiP tidak diperlukan")
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode)
        notificationMethodChannel?.invokeMethod("youtubePipChanged", isInPictureInPictureMode)
        MusikKuLogger.d(TAG, "YOUTUBE PIP = $isInPictureInPictureMode")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            pipHandler.removeCallbacks(pipPoller)
            if (isInPictureInPictureMode) {
                pipHandler.postDelayed(pipPoller, 800L)
            } else {
                releasePipReceiver()
                lastPipEligibility = null
            }
        }
    }

    // ========================================================
    // TEKANAN MEMORI (untuk diagnosa)
    // ========================================================

    override fun onTrimMemory(level: Int) {
        MusikKuLogger.w(TAG, "TRIM MEMORY level=$level")
        super.onTrimMemory(level)
    }

    // ========================================================
    // TOMBOL BACK DI HALAMAN UTAMA
    // ========================================================
    //
    // Player YouTube hidup di dalam Activity ini. Kalau Activity di-finish
    // (Back di halaman utama), player ikut mati dan musik berhenti walau
    // notifikasi ada. Jadi Back cukup memindahkan app ke background,
    // sama seperti tombol Home. Musik baru berhenti lewat tombol Stop di
    // notifikasi atau saat task di-swipe dari recent apps.

    override fun popSystemNavigator(): Boolean {
        if (enterSystemPipIfPossible()) {
            // Android System PiP sendiri yang menangani perpindahan task ke
            // jendela PiP; tidak perlu moveTaskToBack agar surface player tetap hidup.
            return true
        }

        moveTaskToBack(true)
        return true
    }

    // ========================================================
    // ACTIVITY DESTROY
    // ========================================================

    override fun onDestroy() {
        if (::healthMonitor.isInitialized) healthMonitor.stop()
        releasePipReceiver()
        audioEffectsController.release()

        MusikKuLogger.d(TAG, "MAIN ACTIVITY DESTROY (isFinishing=$isFinishing)")

        // Activity benar-benar ditutup (task di-swipe dari recent apps atau
        // Stop dari notifikasi): hentikan musik, lepas player, dan matikan service/notifikasi.
        // Kalau bukan finishing (mis. sistem membuat ulang Activity),
        // player dibiarkan supaya tidak putus.
        if (isFinishing) {

            YoutubePlatformView.instance?.release()

            stopService(
                android.content.Intent(
                    this,
                    PlaybackService::class.java
                )
            )

            notificationMethodChannel = null
        }

        YoutubePlatformView.eventSink = null

        super.onDestroy()
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val pending = pendingFileResult ?: return
        pendingFileResult = null

        if (resultCode != RESULT_OK || data?.data == null) {
            pending.success(null)
            return
        }

        try {
            val uri = data.data!!
            if (requestCode == REQUEST_EXPORT_BACKUP) {
                contentResolver.openOutputStream(uri)?.use { output ->
                    output.write(backupJsonWaiting.toByteArray(Charsets.UTF_8))
                    output.flush()
                } ?: throw IllegalStateException("Tidak bisa membuka file tujuan")
                backupJsonWaiting = ""
                pending.success(true)
            } else if (requestCode == REQUEST_IMPORT_BACKUP) {
                val raw = contentResolver.openInputStream(uri)?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }
                    ?: throw IllegalStateException("Tidak bisa membaca file backup")
                pending.success(raw)
            } else {
                pending.success(null)
            }
        } catch (e: Exception) {
            pending.error("FILE_IO", e.message, null)
        }
    }

}
