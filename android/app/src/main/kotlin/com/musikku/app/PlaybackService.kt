package com.musikku.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.KeyEvent
import java.net.HttpURLConnection
import java.net.URL

import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.MediaBrowserServiceCompat
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat

import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory

import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat

class PlaybackService : MediaBrowserServiceCompat() {

    companion object {
        private const val TAG = "MusikKuNative"

        private const val CHANNEL_ID = "musikku_playback"
        private const val CHANNEL_NAME = "MusikKu Playback"
        private const val NOTIFICATION_ID = 1001

        var eventSink: io.flutter.plugin.common.EventChannel.EventSink? = null
        private var activeInstance: PlaybackService? = null

        fun isLocalActiveStatic(): Boolean = activeInstance?.isLocalActive() == true
        fun isAudioPlayerActiveStatic(): Boolean = activeInstance?.isAudioPlayerActive() == true
        fun playLocalStatic() { activeInstance?.playLocal() }
        fun pauseLocalStatic() { activeInstance?.pauseLocal() }
        fun seekLocalStatic(seconds: Double) { activeInstance?.seekLocal(seconds) }
        fun setLocalVolumeStatic(percent: Int) { activeInstance?.setLocalVolume(percent) }
        fun localCurrentTimeStatic(): Double = activeInstance?.localCurrentTime() ?: 0.0
        fun playAudioStatic() { activeInstance?.playAudio() }
        fun pauseAudioStatic() { activeInstance?.pauseAudio() }
        fun seekAudioStatic(seconds: Double) { activeInstance?.seekAudio(seconds) }
        fun setAudioVolumeStatic(percent: Int) { activeInstance?.setAudioVolume(percent) }
        fun audioCurrentTimeStatic(): Double = activeInstance?.audioCurrentTime() ?: 0.0
        fun stopLocalForYoutubeStatic() { activeInstance?.stopLocalForYoutube() }

        fun updateAudioMetadataStatic(
            videoId: String,
            title: String,
            artist: String,
            thumbnailUrl: String,
            durationSeconds: Double,
        ) {
            activeInstance?.updateAudioMetadata(videoId, title, artist, thumbnailUrl, durationSeconds)
        }

        const val ACTION_PLAY_PAUSE =
            "com.musikku.app.PLAY_PAUSE"
        const val ACTION_NEXT =
            "com.musikku.app.NEXT"
        const val ACTION_PREVIOUS =
            "com.musikku.app.PREVIOUS"
        const val ACTION_STOP =
            "com.musikku.app.STOP"

        fun start(
            context: Context,
            videoId: String,
            title: String,
            artist: String,
            thumbnailUrl: String,
            playing: Boolean,
            positionSeconds: Double,
            durationSeconds: Double,
            sourceType: String = "youtube",
            mediaUri: String = "",
            streamHeaders: Map<String, String> = emptyMap(),
        ) {
            val intent = Intent(context, PlaybackService::class.java).apply {
                putExtra("videoId", videoId)
                putExtra("title", title)
                putExtra("artist", artist)
                putExtra("thumbnailUrl", thumbnailUrl)
                putExtra("playing", playing)
                putExtra("positionSeconds", positionSeconds.coerceAtLeast(0.0))
                putExtra("durationSeconds", durationSeconds.coerceAtLeast(0.0))
                putExtra("sourceType", sourceType)
                putExtra("mediaUri", mediaUri)
                putExtra("streamHeaders", Bundle().apply {
                    streamHeaders.forEach { (key, value) -> putString(key, value) }
                })
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun currentMediaSnapshot(): MediaSnapshot? {
            val service = activeInstance ?: return null
            if (service.currentVideoId.isBlank()) return null
            return MediaSnapshot(
                videoId = service.currentVideoId,
                title = service.currentTitle,
                artist = service.currentArtist,
                thumbnailUrl = service.currentThumbnailUrl,
                sourceType = service.currentSourceType,
                mediaUri = service.currentMediaUri,
            )
        }
    }

    private lateinit var mediaSession: MediaSessionCompat

    // Beberapa headset kabel hanya mengirim KEYCODE_HEADSETHOOK untuk semua
    // klik. Tunda satu klik sebentar agar klik ganda bisa dibaca sebagai NEXT
    // dan klik tiga kali sebagai PREVIOUS, bukan dua/tiga kali toggle play.
    private val mediaButtonHandler = Handler(Looper.getMainLooper())
    private var headsetClickCount = 0
    private var pendingHeadsetClick: Runnable? = null
    private val headsetClickWindowMs = 380L

    private fun queueHeadsetButtonClick(
        onSingleClick: () -> Unit,
        onDoubleClick: () -> Unit,
        onTripleClick: () -> Unit,
    ) {
        headsetClickCount = (headsetClickCount + 1).coerceAtMost(3)
        pendingHeadsetClick?.let { mediaButtonHandler.removeCallbacks(it) }

        val action = Runnable {
            val clicks = headsetClickCount
            headsetClickCount = 0
            pendingHeadsetClick = null
            when (clicks) {
                1 -> onSingleClick()
                2 -> onDoubleClick()
                else -> onTripleClick()
            }
        }
        pendingHeadsetClick = action
        mediaButtonHandler.postDelayed(action, headsetClickWindowMs)
    }

    private fun cancelPendingHeadsetClick() {
        pendingHeadsetClick?.let { mediaButtonHandler.removeCallbacks(it) }
        pendingHeadsetClick = null
        headsetClickCount = 0
    }

    // ========================================================
    // HEADSET DICABUT / BLUETOOTH PUTUS
    //
    // Audio focus sengaja TIDAK diminta di sini. WebView (Chromium) yang
    // memutar YouTube sudah meminta dan menangani audio focus sendiri
    // (pause saat telepon / app lain, lanjut setelahnya). Kalau service
    // ikut meminta, keduanya saling merebut fokus dan musik ter-pause
    // sendiri tepat setelah mulai.
    // ========================================================

    private var lastNoisyEventAtMs = 0L

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AudioManager.ACTION_AUDIO_BECOMING_NOISY) return

            val now = SystemClock.elapsedRealtime()
            val backendActuallyPlaying = localPlayer?.isPlaying == true
            if (!currentPlaying && !backendActuallyPlaying) return
            // Some devices emit duplicate route-change broadcasts. Debounce them
            // so one unplug action produces one pause + one diagnostic event.
            if (lastNoisyEventAtMs > 0L && now - lastNoisyEventAtMs < 900L) return
            lastNoisyEventAtMs = now

            // Capture the position before switching state to paused.
            currentPositionMs = effectivePositionMs()
            MusikKuLogger.d(TAG, "AUDIO BECOMING NOISY -> pause and persist")
            AppHealthMonitor.get(applicationContext).record(
                "AudioRouteChange",
                "Output audio berubah atau headset terputus; pemutaran dijeda untuk mencegah audio keluar dari speaker.",
            )

            try {
                if (isAudioPlayerSource()) {
                    localPlayer?.pause()
                } else {
                    YoutubePlatformView.instance?.pause()
                }
            } catch (error: Exception) {
                AppHealthMonitor.get(applicationContext).record(
                    "AudioRoutePauseFailure",
                    "Gagal menjeda pemutaran setelah perubahan output audio.",
                    error,
                )
                MusikKuLogger.e(TAG, "AUDIO ROUTE PAUSE FAILED", error)
            }

            currentPlaying = false
            positionClockBaseElapsedMs = SystemClock.elapsedRealtime()
            persistPlaybackSnapshot()
            updateMediaSession()
            syncWakeLock()
            scheduleSnapshotPersistence()

            if (foregroundStarted) {
                val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                manager.notify(NOTIFICATION_ID, createNotification())
                notificationTitle = currentTitle
                notificationArtist = currentArtist
                notificationPlaying = currentPlaying
                notificationDurationMs = currentDurationMs
            }
        }
    }

    private var noisyReceiverRegistered = false

    private fun registerNoisyReceiver() {
        if (noisyReceiverRegistered) {
            return
        }

        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(noisyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(noisyReceiver, filter)
        }

        noisyReceiverRegistered = true
    }

    private fun unregisterNoisyReceiver() {
        if (!noisyReceiverRegistered) {
            return
        }

        try {
            unregisterReceiver(noisyReceiver)
        } catch (_: Exception) {
            // no-op
        }

        noisyReceiverRegistered = false
    }

    private var foregroundStarted = false

    private var currentVideoId = ""
    private var currentSourceType = "youtube"
    private var currentMediaUri = ""
    private var currentLocalMediaId = ""
    private var currentStreamHeaders: Map<String, String> = emptyMap()
    private var localPlayer: ExoPlayer? = null
    private val localStateHandler = android.os.Handler(Looper.getMainLooper())
    private var currentTitle = "MusikKu"
    private var currentArtist = ""
    private var currentThumbnailUrl = ""
    private var notificationArtwork: Bitmap? = null
    private var artworkGeneration = 0L
    private var currentPlaying = false
    private var currentPositionMs = 0L
    private var currentDurationMs = 0L
    private var positionClockBaseElapsedMs = 0L
    private var positionPersistedAtElapsedMs = 0L

    data class MediaSnapshot(
        val videoId: String,
        val title: String,
        val artist: String,
        val thumbnailUrl: String,
        val sourceType: String,
        val mediaUri: String,
    )


    private val snapshotHandler = android.os.Handler(Looper.getMainLooper())
    private val wakeLock: PowerManager.WakeLock by lazy {
        val powerManager =
            getSystemService(Context.POWER_SERVICE) as PowerManager
        powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "MusikKu:Playback",
        ).apply {
            setReferenceCounted(false)
        }
    }

    private val snapshotRunnable = object : Runnable {
        override fun run() {
            if (!foregroundStarted) {
                return
            }

            if (currentPlaying) {
                persistPlaybackSnapshot()
                updateMediaSession()
                snapshotHandler.postDelayed(this, 1000L)
            }
        }
    }

    private var notificationTitle = ""
    private var notificationArtist = ""
    private var notificationPlaying = false
    private var notificationDurationMs = 0L

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: android.os.Bundle?
    ): BrowserRoot? {
        return BrowserRoot("musikku_root", null)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<List<MediaBrowserCompat.MediaItem>>
    ) {
        val items = mutableListOf<MediaBrowserCompat.MediaItem>()
        if (parentId == "musikku_root" && currentVideoId.isNotBlank()) {
            val description = MediaDescriptionCompat.Builder()
                .setMediaId(currentVideoId)
                .setTitle(currentTitle)
                .setSubtitle(currentArtist)
                .setIconUri(
                    currentThumbnailUrl.takeIf { it.isNotBlank() }?.let(Uri::parse)
                )
                .build()
            items += MediaBrowserCompat.MediaItem(
                description,
                MediaBrowserCompat.MediaItem.FLAG_PLAYABLE,
            )
        }
        result.sendResult(items)
    }

    override fun onCreate() {
        super.onCreate()
        activeInstance = this
        // Keep data-usage sampling active while audio continues in background.
        DataUsageTracker.start(applicationContext)

        createNotificationChannel()

        mediaSession = MediaSessionCompat(this, "MusikKuMediaSession")
        mediaSession.setFlags(
            MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS or
                MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS,
        )
        mediaSession.setCallback(
            object : MediaSessionCompat.Callback() {
                // Map tombol media eksplisit agar tombol inline kabel (KEYCODE_HEADSETHOOK)
                // dan tombol play/pause/next/previous Bluetooth konsisten di Android lama
                // maupun baru. Key-up ditelan supaya satu klik hanya dijalankan sekali.
                @Suppress("DEPRECATION")
                override fun onMediaButtonEvent(mediaButtonIntent: Intent): Boolean {
                    val keyEvent = mediaButtonIntent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT)
                        ?: return super.onMediaButtonEvent(mediaButtonIntent)
                    if (keyEvent.action != KeyEvent.ACTION_DOWN || keyEvent.repeatCount > 0) return true

                    when (keyEvent.keyCode) {
                        KeyEvent.KEYCODE_MEDIA_PLAY -> {
                            cancelPendingHeadsetClick()
                            onPlay()
                        }
                        KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                            cancelPendingHeadsetClick()
                            onPause()
                        }
                        KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                            cancelPendingHeadsetClick()
                            if (currentPlaying) onPause() else onPlay()
                        }
                        KeyEvent.KEYCODE_HEADSETHOOK -> {
                            queueHeadsetButtonClick(
                                onSingleClick = { if (currentPlaying) onPause() else onPlay() },
                                onDoubleClick = { onSkipToNext() },
                                onTripleClick = { onSkipToPrevious() },
                            )
                        }
                        KeyEvent.KEYCODE_MEDIA_NEXT -> {
                            cancelPendingHeadsetClick()
                            onSkipToNext()
                        }
                        KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {
                            cancelPendingHeadsetClick()
                            onSkipToPrevious()
                        }
                        else -> return super.onMediaButtonEvent(mediaButtonIntent)
                    }
                    return true
                }

                // Tombol headset / earbuds: play hanya bila sedang pause,
                // pause hanya bila sedang play, supaya tidak salah toggle.
                override fun onPlay() {
                    if (isAudioPlayerSource()) {
                        localPlayer?.play()
                    } else if (!currentPlaying) {
                        sendCommandToFlutter("notificationPlayPause")
                    }
                }

                override fun onPause() {
                    if (isAudioPlayerSource()) {
                        localPlayer?.pause()
                    } else if (currentPlaying) {
                        sendCommandToFlutter("notificationPlayPause")
                    }
                }

                override fun onSkipToNext() {
                    sendCommandToFlutter("notificationNext")
                }

                override fun onSkipToPrevious() {
                    sendCommandToFlutter("notificationPrevious")
                }

                override fun onStop() {
                    sendCommandToFlutter("notificationStop")
                    stopSelf()
                }
            },
        )

        mediaSession.isActive = true
        sessionToken = mediaSession.sessionToken

        ensureLocalPlayer()
        registerNoisyReceiver()
    }


    private fun ensureLocalPlayer() {
        if (localPlayer != null) return

        localPlayer = ExoPlayer.Builder(this).build().also { player ->
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true,
            )
            player.addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    if (!isPlayerMediaCurrent(player)) return
                    currentPlaying = isPlaying
                    currentPositionMs = player.currentPosition.coerceAtLeast(0L)
                    currentDurationMs = player.duration.takeIf { it > 0L } ?: currentDurationMs
                    syncWakeLock()
                    emitLocalState(if (isPlaying) "playing" else "paused")
                    updateMediaSession()
                    if (foregroundStarted) {
                        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        manager.notify(NOTIFICATION_ID, createNotification())
                    }
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (!isPlayerMediaCurrent(player)) return
                    currentPositionMs = player.currentPosition.coerceAtLeast(0L)
                    currentDurationMs = player.duration.takeIf { it > 0L } ?: currentDurationMs
                    when (playbackState) {
                        Player.STATE_BUFFERING -> emitLocalState("buffering")
                        Player.STATE_READY -> emitLocalState(if (player.isPlaying) "playing" else "paused")
                        Player.STATE_ENDED -> {
                            currentPlaying = false
                            emitLocalState("ended")
                            updateMediaSession()
                            sendCommandToFlutter("notificationLocalEnded")
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    if (!isPlayerMediaCurrent(player)) return
                    val shouldResume = currentPlaying || player.playWhenReady
                    currentPlaying = false
                    currentPositionMs = player.currentPosition.coerceAtLeast(0L)
                    MusikKuLogger.e(TAG, "AUDIO PLAYER ERROR source=$currentSourceType id=$currentVideoId", error)
                    emitLocalState("error")
                    updateMediaSession()
                    if (currentSourceType == "youtube_audio") {
                        MainActivity.notificationMethodChannel?.invokeMethod(
                            "youtubeAudioPlaybackError",
                            mapOf(
                                "videoId" to currentVideoId,
                                "positionSeconds" to (currentPositionMs / 1000.0),
                                "shouldPlay" to shouldResume,
                                "message" to (error.message ?: "Audio stream gagal diputar"),
                            ),
                        )
                    }
                }
            })
        }
    }

    private fun isAudioPlayerSource(): Boolean =
        currentSourceType == "local" || currentSourceType == "youtube_audio"

    /**
     * ExoPlayer listeners are asynchronous. During a track change an `ended` or
     * `error` event from the previous MediaItem can arrive after currentVideoId
     * has already changed; compare the actual MediaItem URI before forwarding it.
     */
    private fun isPlayerMediaCurrent(player: Player): Boolean {
        if (!isAudioPlayerSource() || currentMediaUri.isBlank()) return false
        val playingUri = player.currentMediaItem?.localConfiguration?.uri?.toString() ?: return false
        return playingUri == currentMediaUri
    }

    private fun stopLocalForYoutube() {
        if (!isAudioPlayerSource()) return
        try {
            localPlayer?.pause()
            localPlayer?.clearMediaItems()
        } catch (_: Exception) {
            // no-op
        }
        currentPlaying = false
        currentSourceType = "youtube"
        currentMediaUri = ""
        currentLocalMediaId = ""
        currentStreamHeaders = emptyMap()
        snapshotHandler.removeCallbacks(snapshotRunnable)
        localStateHandler.removeCallbacksAndMessages(null)
        syncWakeLock()
    }

    private fun prepareLocalPlayback(
        uriString: String,
        positionMs: Long,
        playWhenReady: Boolean,
    ) {
        ensureLocalPlayer()
        val player = localPlayer ?: return
        // Drop old buffers before attaching a new source; listeners validate the URI above.
        player.pause()
        player.clearMediaItems()
        val mediaItem = MediaItem.fromUri(Uri.parse(uriString))

        if (currentSourceType == "youtube_audio") {
            val headers = if (currentStreamHeaders.isNotEmpty()) {
                currentStreamHeaders
            } else {
                mapOf(
                    "User-Agent" to "Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 Chrome/130.0.0.0 Mobile Safari/537.36",
                    "Referer" to "https://www.youtube.com/",
                )
            }
            val httpFactory = DefaultHttpDataSource.Factory()
                .setDefaultRequestProperties(headers)
                .setAllowCrossProtocolRedirects(true)
            val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
            val sourceFactory = DefaultMediaSourceFactory(dataSourceFactory)
            player.setMediaSource(
                sourceFactory.createMediaSource(mediaItem),
                positionMs.coerceAtLeast(0L),
            )
        } else {
            player.setMediaItem(mediaItem, positionMs.coerceAtLeast(0L))
        }

        player.prepare()
        player.playWhenReady = playWhenReady
        player.volume = player.volume.coerceIn(0f, 1f)
        scheduleLocalStateUpdates()
    }

    fun playLocal() {
        if (currentSourceType != "local") return
        playAudio()
    }

    fun pauseLocal() {
        if (currentSourceType != "local") return
        pauseAudio()
    }

    fun seekLocal(seconds: Double) {
        if (currentSourceType != "local") return
        seekAudio(seconds)
    }

    fun setLocalVolume(percent: Int) {
        if (currentSourceType != "local") return
        setAudioVolume(percent)
    }

    fun localCurrentTime(): Double {
        if (currentSourceType != "local") return 0.0
        return audioCurrentTime()
    }

    fun isLocalActive(): Boolean = currentSourceType == "local"
    fun isAudioPlayerActive(): Boolean = isAudioPlayerSource()

    fun playAudio() {
        if (isAudioPlayerSource()) {
            ensureLocalPlayer()
            localPlayer?.play()
        }
    }

    fun pauseAudio() {
        if (isAudioPlayerSource()) localPlayer?.pause()
    }

    fun seekAudio(seconds: Double) {
        if (!isAudioPlayerSource()) return
        val safe = if (seconds.isFinite() && seconds >= 0) seconds else 0.0
        localPlayer?.seekTo((safe * 1000.0).toLong())
    }

    fun setAudioVolume(percent: Int) {
        if (!isAudioPlayerSource()) return
        localPlayer?.volume = percent.coerceIn(0, 100) / 100f
    }

    fun audioCurrentTime(): Double {
        if (!isAudioPlayerSource()) return 0.0
        return (localPlayer?.currentPosition ?: 0L) / 1000.0
    }

    private fun updateAudioMetadata(
        videoId: String,
        title: String,
        artist: String,
        thumbnailUrl: String,
        durationSeconds: Double,
    ) {
        if (!isAudioPlayerSource() || currentVideoId != videoId) return
        val metadataChanged = currentTitle != title || currentArtist != artist || currentThumbnailUrl != thumbnailUrl
        currentTitle = title
        currentArtist = artist
        currentThumbnailUrl = thumbnailUrl
        if (currentDurationMs <= 0L && durationSeconds.isFinite() && durationSeconds > 0.0) {
            currentDurationMs = (durationSeconds * 1000.0).toLong()
        }
        if (metadataChanged) {
            notificationArtwork = null
            artworkGeneration += 1L
            loadNotificationArtworkIfNeeded()
        }
        updateMediaSession()
        if (foregroundStarted) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, createNotification())
        }
        persistPlaybackSnapshot()
    }

    private fun scheduleLocalStateUpdates() {
        localStateHandler.removeCallbacksAndMessages(null)
        localStateHandler.post(object : Runnable {
            override fun run() {
                if (!isAudioPlayerSource()) return
                val player = localPlayer ?: return
                currentPositionMs = player.currentPosition.coerceAtLeast(0L)
                currentDurationMs = player.duration.takeIf { it > 0L && it != C.TIME_UNSET } ?: currentDurationMs
                currentPlaying = player.isPlaying
                if (currentPlaying) {
                    persistPlaybackSnapshot()
                    updateMediaSession()
                }

                // Send updates while buffering/paused too; ExoPlayer's buffered
                // position can grow before playback resumes, and the UI should
                // show that gray buffer segment as it grows.
                if (player.playbackState != Player.STATE_ENDED) {
                    val uiState = when (player.playbackState) {
                        Player.STATE_BUFFERING -> "buffering"
                        Player.STATE_READY -> if (player.isPlaying) "playing" else "paused"
                        else -> if (player.playWhenReady) "buffering" else "paused"
                    }
                    emitLocalState(uiState)
                }
                localStateHandler.postDelayed(this, 500L)
            }
        })
    }

    private fun emitLocalState(state: String) {
        // ExoPlayer is the real audio source in audio-only mode. Export its
        // buffered position so Flutter can draw a real buffer bar rather than
        // treating the entire unplayed section as buffered.
        val player = localPlayer
        val reportedDurationMs = player?.duration
            ?.takeIf { it > 0L && it != C.TIME_UNSET }
            ?: currentDurationMs.coerceAtLeast(0L)
        val rawPositionMs = player?.currentPosition?.coerceAtLeast(0L)
            ?: currentPositionMs.coerceAtLeast(0L)
        val positionMs = if (reportedDurationMs > 0L) {
            rawPositionMs.coerceIn(0L, reportedDurationMs)
        } else {
            rawPositionMs
        }
        val rawBufferedPositionMs = player?.bufferedPosition?.coerceAtLeast(positionMs)
            ?: positionMs
        val bufferedPositionMs = if (reportedDurationMs > 0L) {
            rawBufferedPositionMs.coerceIn(positionMs, reportedDurationMs)
        } else {
            positionMs
        }
        val bufferedFraction = if (reportedDurationMs > 0L) {
            (bufferedPositionMs.toDouble() / reportedDurationMs.toDouble()).coerceIn(0.0, 1.0)
        } else {
            0.0
        }
        val bufferedAheadSeconds = (bufferedPositionMs - positionMs).coerceAtLeast(0L) / 1000.0

        val payload = mapOf<String, Any>(
            "state" to state,
            "videoId" to currentVideoId,
            "position" to (positionMs / 1000.0),
            "duration" to (reportedDurationMs / 1000.0),
            "bufferedFraction" to bufferedFraction,
            "bufferedAheadSeconds" to bufferedAheadSeconds,
        )
        eventSink?.success(payload)
    }

    private fun extractEmbeddedArtwork(uriString: String): Bitmap? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(this, Uri.parse(uriString))
            val bytes = retriever.embeddedPicture ?: return null
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        } catch (e: Exception) {
            MusikKuLogger.d(TAG, "LOCAL NOTIFICATION ARTWORK ERROR: ${e.message}")
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // no-op
            }
        }
    }

    private fun effectivePositionMs(): Long {
        if (isAudioPlayerSource()) {
            val position = localPlayer?.currentPosition ?: currentPositionMs
            return if (currentDurationMs > 0L) {
                position.coerceIn(0L, currentDurationMs)
            } else {
                position.coerceAtLeast(0L)
            }
        }

        if (!currentPlaying || positionClockBaseElapsedMs <= 0L) {
            return currentPositionMs
        }

        val elapsed =
            (SystemClock.elapsedRealtime() - positionClockBaseElapsedMs)
                .coerceAtLeast(0L)

        val calculated = currentPositionMs + elapsed

        return if (currentDurationMs > 0L) {
            calculated.coerceAtMost(currentDurationMs)
        } else {
            calculated
        }
    }

    private fun persistPlaybackSnapshot() {
        val position = effectivePositionMs()
        currentPositionMs = position
        positionClockBaseElapsedMs = SystemClock.elapsedRealtime()
        positionPersistedAtElapsedMs = positionClockBaseElapsedMs

        val prefs = getSharedPreferences("musikku_native_playback", Context.MODE_PRIVATE)
        prefs.edit()
            .putString("videoId", currentVideoId)
            .putString("title", currentTitle)
            .putString("artist", currentArtist)
            .putLong("positionMs", position)
            .putLong("durationMs", currentDurationMs)
            .putBoolean("playing", currentPlaying)
            .putLong("savedAtElapsedMs", positionPersistedAtElapsedMs)
            .apply()
    }

    fun clearPlaybackSnapshot() {
        getSharedPreferences("musikku_native_playback", Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        when (intent?.action) {
            ACTION_PLAY_PAUSE -> {
                // Play/Pause notifikasi harus tetap bekerja meskipun Flutter
                // Activity sudah ditutup. Untuk sumber audio native, kendalikan
                // ExoPlayer langsung dari service; sumber lain tetap memakai
                // callback Flutter selama engine masih aktif.
                if (isAudioPlayerSource()) {
                    if (localPlayer?.isPlaying == true || currentPlaying) {
                        pauseAudio()
                    } else {
                        playAudio()
                    }
                } else {
                    sendCommandToFlutter("notificationPlayPause")
                }
                return START_NOT_STICKY
            }

            ACTION_NEXT -> {
                sendCommandToFlutter("notificationNext")
                return START_NOT_STICKY
            }

            ACTION_PREVIOUS -> {
                sendCommandToFlutter("notificationPrevious")
                return START_NOT_STICKY
            }

            ACTION_STOP -> {
                sendCommandToFlutter("notificationStop")
                stopPlaybackService()
                return START_NOT_STICKY
            }
        }

        val previousVideoId = currentVideoId
        val previousTitle = currentTitle
        val previousArtist = currentArtist
        val previousPlaying = currentPlaying
        val previousDurationMs = currentDurationMs

        currentVideoId = intent?.getStringExtra("videoId") ?: ""
        currentTitle = intent?.getStringExtra("title") ?: "MusikKu"
        currentArtist = intent?.getStringExtra("artist") ?: ""
        currentThumbnailUrl = intent?.getStringExtra("thumbnailUrl")?.trim().orEmpty()
        currentPlaying = intent?.getBooleanExtra("playing", false) ?: false
        currentSourceType = intent?.getStringExtra("sourceType")?.trim().orEmpty().ifBlank {
            if (currentVideoId.startsWith("local:")) "local" else "youtube"
        }
        currentMediaUri = intent?.getStringExtra("mediaUri")?.trim().orEmpty()
        currentStreamHeaders = intent?.getBundleExtra("streamHeaders")?.let { bundle ->
            bundle.keySet().mapNotNull { key ->
                val value = bundle.getString(key)
                if (value.isNullOrBlank()) null else key to value
            }.toMap()
        }.orEmpty()
        currentLocalMediaId = if (currentVideoId.startsWith("local:")) {
            currentVideoId.removePrefix("local:")
        } else {
            ""
        }
        syncWakeLock()
        currentPositionMs = secondsToMillis(
            intent?.getDoubleExtra("positionSeconds", 0.0) ?: 0.0,
        )
        currentDurationMs = secondsToMillis(
            intent?.getDoubleExtra("durationSeconds", 0.0) ?: 0.0,
        )

        if (isAudioPlayerSource() && currentMediaUri.isNotBlank()) {
            prepareLocalPlayback(
                currentMediaUri,
                currentPositionMs,
                currentPlaying,
            )
        } else if (!isAudioPlayerSource()) {
            localPlayer?.pause()
            localPlayer?.clearMediaItems()
            localStateHandler.removeCallbacksAndMessages(null)
        }

        positionClockBaseElapsedMs =
            SystemClock.elapsedRealtime()

        val trackChanged = previousVideoId != currentVideoId ||
            previousTitle != currentTitle ||
            previousArtist != currentArtist ||
            notificationTitle != currentTitle

        if (trackChanged) {
            notificationArtwork = null
            artworkGeneration += 1L
        }

        persistPlaybackSnapshot()
        updateMediaSession()
        notifyChildrenChanged("musikku_root")
        scheduleSnapshotPersistence()

        val notificationVisualChanged =
            previousVideoId != currentVideoId ||
            previousTitle != currentTitle ||
            previousArtist != currentArtist ||
            previousPlaying != currentPlaying ||
            previousDurationMs != currentDurationMs

        if (!foregroundStarted) {
            val notification = createNotification()
            startForeground(NOTIFICATION_ID, notification)
            foregroundStarted = true
            notificationTitle = currentTitle
            notificationArtist = currentArtist
            notificationPlaying = currentPlaying
            notificationDurationMs = currentDurationMs
        } else if (notificationVisualChanged || !currentPlaying) {
            // MediaSession menggerakkan timeline saat sedang playing. Jangan
            // me-render ulang notification tiap detik karena itu membuat action
            // Play/Pause berkedip. Saat pause/track berubah, render ulang sekali.
            val notification = createNotification()
            val manager =
                getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, notification)
            notificationTitle = currentTitle
            notificationArtist = currentArtist
            notificationPlaying = currentPlaying
            notificationDurationMs = currentDurationMs
        }

        loadNotificationArtworkIfNeeded()

        return START_NOT_STICKY
    }

    private fun updateMediaSession() {
        val metadataBuilder = MediaMetadataCompat.Builder()
            .putString(
                MediaMetadataCompat.METADATA_KEY_TITLE,
                currentTitle,
            )
            .putString(
                MediaMetadataCompat.METADATA_KEY_ARTIST,
                currentArtist,
            )
            .putString(
                MediaMetadataCompat.METADATA_KEY_ALBUM,
                "MusikKu",
            )
            .putLong(
                MediaMetadataCompat.METADATA_KEY_DURATION,
                currentDurationMs,
            )

        notificationArtwork?.let { bitmap ->
            metadataBuilder.putBitmap(
                MediaMetadataCompat.METADATA_KEY_ART,
                bitmap,
            )
            metadataBuilder.putBitmap(
                MediaMetadataCompat.METADATA_KEY_ALBUM_ART,
                bitmap,
            )
        }

        mediaSession.setMetadata(metadataBuilder.build())

        val actions =
            PlaybackStateCompat.ACTION_PLAY or
                PlaybackStateCompat.ACTION_PAUSE or
                PlaybackStateCompat.ACTION_PLAY_PAUSE or
                PlaybackStateCompat.ACTION_SKIP_TO_NEXT or
                PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS or
                PlaybackStateCompat.ACTION_STOP or
                PlaybackStateCompat.ACTION_SEEK_TO

        val playbackState =
            if (currentPlaying) {
                PlaybackStateCompat.STATE_PLAYING
            } else {
                PlaybackStateCompat.STATE_PAUSED
            }

        val speed = if (currentPlaying) 1.0f else 0.0f

        val state = PlaybackStateCompat.Builder()
            .setActions(actions)
            .setState(
                playbackState,
                effectivePositionMs(),
                speed,
                SystemClock.elapsedRealtime(),
            )
            .build()

        mediaSession.setPlaybackState(state)
    }

    private fun scheduleSnapshotPersistence() {
        snapshotHandler.removeCallbacks(snapshotRunnable)
        if (currentPlaying) {
            snapshotHandler.postDelayed(snapshotRunnable, 1000L)
        }
    }

    private fun syncWakeLock() {
        if (currentPlaying) {
            if (!wakeLock.isHeld) {
                wakeLock.acquire()
            }
        } else {
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
        }
    }

    private fun sendCommandToFlutter(method: String) {
        MainActivity.notificationMethodChannel?.invokeMethod(method, null)
    }

    private fun createNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)

        val contentPendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                100,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val previousPendingIntent = pendingServiceIntent(101, ACTION_PREVIOUS)
        val playPausePendingIntent = pendingServiceIntent(102, ACTION_PLAY_PAUSE)
        val nextPendingIntent = pendingServiceIntent(103, ACTION_NEXT)
        val stopPendingIntent = pendingServiceIntent(104, ACTION_STOP)

        val playPauseIcon =
            if (currentPlaying) {
                android.R.drawable.ic_media_pause
            } else {
                android.R.drawable.ic_media_play
            }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(currentTitle)
            .setContentText(currentArtist)
            .setContentIntent(contentPendingIntent)
            // Jika sistem mengizinkan notifikasi ini di-dismiss, perlakukan sebagai Stop:
            // hentikan service supaya notifikasi tidak langsung muncul kembali.
            .setDeleteIntent(stopPendingIntent)
            .setOngoing(currentPlaying)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setColor(0xFF087F79.toInt())
            .setColorized(false)
            .setShowWhen(false)
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_previous,
                    "Previous",
                    previousPendingIntent,
                ),
            )
            .addAction(
                NotificationCompat.Action(
                    playPauseIcon,
                    if (currentPlaying) "Pause" else "Play",
                    playPausePendingIntent,
                ),
            )
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_media_next,
                    "Next",
                    nextPendingIntent,
                ),
            )
            .addAction(
                NotificationCompat.Action(
                    android.R.drawable.ic_menu_close_clear_cancel,
                    "Stop",
                    stopPendingIntent,
                ),
            )
            .setStyle(
                MediaStyle()
                    .setMediaSession(mediaSession.sessionToken)
                    .setShowActionsInCompactView(0, 1, 2),
            )

        notificationArtwork?.let { bitmap ->
            builder.setLargeIcon(bitmap)
        }

        if (currentDurationMs > 0L) {
            val max = currentDurationMs.coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            val progress = effectivePositionMs()
                .coerceIn(0L, currentDurationMs.coerceAtMost(Int.MAX_VALUE.toLong()))
                .toInt()

            builder
                .setProgress(max, progress, false)
                .setSubText(
                    "${formatTime(effectivePositionMs())} / ${formatTime(currentDurationMs)}",
                )
        } else {
            builder.setProgress(0, 0, true)
        }

        return builder.build()
    }

    private fun loadNotificationArtworkIfNeeded() {
        val videoId = currentVideoId.trim()
        if (videoId.isEmpty()) {
            return
        }

        if (notificationArtwork != null) {
            return
        }

        val generation = artworkGeneration

        Thread {
            val bitmap = if (currentSourceType == "local" && currentMediaUri.isNotBlank()) {
                extractEmbeddedArtwork(currentMediaUri)
            } else {
                val fallbackUrl = "https://i.ytimg.com/vi/$videoId/hqdefault.jpg"
                val url = currentThumbnailUrl.ifBlank { fallbackUrl }
                downloadBitmap(url)
            }

            snapshotHandler.post {
                if (bitmap == null ||
                    generation != artworkGeneration ||
                    videoId != currentVideoId
                ) {
                    return@post
                }

                notificationArtwork = bitmap
                updateMediaSession()

                if (foregroundStarted) {
                    val manager =
                        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(NOTIFICATION_ID, createNotification())
                }
            }
        }.start()
    }

    private fun downloadBitmap(url: String): Bitmap? {
        var connection: HttpURLConnection? = null

        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = 5000
                readTimeout = 8000
                requestMethod = "GET"
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", "Mozilla/5.0 MusikKu")
                connect()
            }

            if (connection.responseCode !in 200..299) {
                return null
            }

            connection.inputStream.use { input ->
                BitmapFactory.decodeStream(input)
            }
        } catch (e: Exception) {
            MusikKuLogger.d(TAG, "NOTIFICATION ARTWORK ERROR: ${e.message}")
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun pendingServiceIntent(
        requestCode: Int,
        action: String,
    ): PendingIntent {
        val intent = Intent(this, PlaybackService::class.java).apply {
            this.action = action
        }

        return PendingIntent.getService(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Kontrol pemutaran MusikKu"
        }

        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun secondsToMillis(seconds: Double): Long {
        if (!seconds.isFinite() || seconds <= 0.0) {
            return 0L
        }

        return (seconds * 1000.0).toLong().coerceAtLeast(0L)
    }

    private fun formatTime(milliseconds: Long): String {
        val totalSeconds = (milliseconds / 1000L).coerceAtLeast(0L)
        val hours = totalSeconds / 3600L
        val minutes = (totalSeconds % 3600L) / 60L
        val seconds = totalSeconds % 60L

        return if (hours > 0L) {
            "%d:%02d:%02d".format(hours, minutes, seconds)
        } else {
            "%02d:%02d".format(minutes, seconds)
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Perilaku yang diminta: menutup task dari Recent Apps menghentikan musik
        // dan menghapus notifikasi media. Saat pengguna memutar lagi di aplikasi,
        // startForeground akan memunculkan notifikasi baru.
        MusikKuLogger.d(TAG, "TASK REMOVED -> stop playback and remove notification")
        stopPlaybackService()
        super.onTaskRemoved(rootIntent)
    }

    private fun stopPlaybackService() {
        snapshotHandler.removeCallbacks(snapshotRunnable)
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Exception) {
            // no-op
        }

        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)

        foregroundStarted = false
        notificationArtwork = null
        currentThumbnailUrl = ""
        artworkGeneration += 1L
        mediaSession.isActive = false
        stopSelf()
    }


    override fun onDestroy() {
        cancelPendingHeadsetClick()
        mediaButtonHandler.removeCallbacksAndMessages(null)
        snapshotHandler.removeCallbacks(snapshotRunnable)
        localStateHandler.removeCallbacksAndMessages(null)
        if (activeInstance === this) {
            activeInstance = null
        }
        localStateHandler.removeCallbacksAndMessages(null)
        localPlayer?.release()
        localPlayer = null
        unregisterNoisyReceiver()
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            }
        } catch (_: Exception) {
            // no-op
        }

        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)

        foregroundStarted = false
        mediaSession.isActive = false
        mediaSession.release()
        super.onDestroy()
    }
}
