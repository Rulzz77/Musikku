package com.musikku.app

import android.content.Context
import android.graphics.Bitmap
import android.content.res.ColorStateList
import android.graphics.Color
import android.net.http.SslError
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.TrafficStats
import android.os.Process
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebSettings
import android.webkit.WebViewClient
import android.widget.FrameLayout

import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.PlayerConstants
import com.pierfrancescosoffritti.androidyoutubeplayer.core.customui.DefaultPlayerUiController
import com.pierfrancescosoffritti.androidyoutubeplayer.core.customui.views.YouTubePlayerSeekBar
import com.pierfrancescosoffritti.androidyoutubeplayer.core.customui.PlayerUiController
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.options.IFramePlayerOptions
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.YouTubePlayer
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.listeners.AbstractYouTubePlayerListener
import com.pierfrancescosoffritti.androidyoutubeplayer.core.player.views.YouTubePlayerView

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.platform.PlatformView


class YoutubePlatformView(
    private val context: Context
) : PlatformView {

    companion object {

        private const val TAG =
            "MusikKuNative"

        var instance:
            YoutubePlatformView? = null

        var eventSink:
            EventChannel.EventSink? = null

        var lastEvent:
            Map<String, Any>? = null

        // Kualitas pilihan pengguna. Ada di companion supaya TETAP sama saat
        // ganti video, rotasi, PiP, pemulihan WebView, bahkan view dibuat ulang.
        @Volatile
        var preferredQuality: String = "default"

        // Volume pilihan pengguna harus bertahan ketika YouTubePlayer/WebView
        // dibuat ulang atau slider digerakkan sebelum callback onReady.
        @Volatile
        var preferredVolumePercent: Int = 100

        // Mode hemat data (0 mati, 1 hemat, 2 super hemat) dan status app di
        // background. Dipakai untuk menurunkan kualitas otomatis.
        @Volatile
        var dataSaverLevel: Int = 0

        @Volatile
        var appInBackground: Boolean = false

        fun requestDataSaverLevel(level: Int) {
            dataSaverLevel = level.coerceIn(0, 2)
            instance?.reapplyQuality()
        }

        fun setAppBackground(background: Boolean) {
            if (appInBackground == background) return
            appInBackground = background
            instance?.reapplyQuality()
        }

        @Volatile
        var preferredCaptionsEnabled: Boolean = false

        @Volatile
        var preferredCaptionLanguage: String = "id"

        fun normalizeQuality(requested: String): String? =
            when (requested.trim().lowercase()) {
                "default", "auto" -> "default"
                "tiny", "144p" -> "tiny"
                "small", "240p" -> "small"
                "medium", "360p" -> "medium"
                "large", "480p" -> "large"
                "hd720", "720p" -> "hd720"
                "hd1080", "1080p" -> "hd1080"
                "highres", "1440p", "2160p" -> "highres"
                else -> null
            }

        @Volatile
        var preferredCrop: Double = 1.0

        /** Zoom 1.0..1.3; dipakai untuk memotong tepi iframe (judul/watermark). */
        fun requestCrop(zoom: Double) {
            preferredCrop = zoom.coerceIn(1.0, 1.3)
            instance?.setPlaybackQuality(preferredQuality)
        }

        private fun captionLangPref(mode: String): String =
            when (mode.trim().lowercase()) {
                "auto:en" -> "en"
                "auto:id", "original" -> "id"
                else -> mode.trim().ifBlank { "id" }
            }

        /** Dipakai MainActivity; aman dipanggil sebelum view native dibuat. */
        fun requestQuality(requested: String): Boolean {
            val quality = normalizeQuality(requested) ?: return false
            preferredQuality = quality
            instance?.setPlaybackQuality(quality)
            return true
        }

        fun requestCaptionSettings(enabled: Boolean, language: String): Boolean {
            preferredCaptionsEnabled = enabled
            preferredCaptionLanguage = language.trim().ifBlank { "id" }
            // Apply immediately to the existing player. Rebuilding the WebView
            // when the user toggles captions was the source of the lingering
            // caption state after switching OFF. The IFrame captions module can
            // be loaded/unloaded in-place, so playback no longer needs to restart.
            instance?.applyCaptionSettingsNow()
            return true
        }
    }


    // ============================================================
    // VIEW
    // ============================================================

    private val container:
        FrameLayout

    private lateinit var youtubePlayerView:
        YouTubePlayerView

    private var recoveringRenderer =
        false

    // Naik tiap kali player dibuat ulang; dipakai untuk mengabaikan
    // watchdog milik pemulihan yang sudah usang.
    private var recoveryGeneration =
        0

    // true kalau pemulihan di background gagal (player baru tidak mau
    // mulai). Saat app kembali ke depan, player dibuat ulang lagi.
    private var needsRebuildOnForeground =
        false


    // ============================================================
    // PLAYER
    // ============================================================

    private var youtubePlayer:
        YouTubePlayer? = null

    // android-youtube-player 13.x memisahkan UI ke modul custom-ui.
    // Controller ini dipakai untuk menampilkan UI normal dan menyembunyikannya
    // saat PiP supaya tombol pause tidak dobel.
    private var playerUiController:
        PlayerUiController? = null

    private var playerUiRequestedVisible = false


    // ============================================================
    // STATE
    // ============================================================

    private var isReady =
        false

    private var pendingVideoId:
        String? = null

    private var pendingStartSeconds =
        0f

    private var currentVideoId =
        ""

    private var currentState =
        "unstarted"

    private var currentPosition =
        0f

    private var videoDuration =
        0f

    // Fraksi buffer resmi dari IFrame Player API. Kita tidak mengontrol
    // berapa banyak YouTube melakukan buffering; kita hanya menampilkan
    // kondisi aktualnya seperti progress buffer di YouTube.
    private var bufferedFraction =
        0f

    private var dataBytesAtVideoStart =
        -1L

    private var endedSentForVideoId =
        ""

    // Saat musik lokal diputar, YouTube harus benar-benar diam agar tidak
    // mengirim event unstarted tiap detik ke EventChannel yang sama.
    private var externalPlaybackActive =
        false

    private var idleStateSent =
        false

    // loadVideo() dari Flutter adalah aksi autoplay. Jika WebView/player
    // membutuhkan satu siklus tambahan sebelum menerima perintah play(),
    // flag ini membuat kita mencoba play lagi tanpa mengandalkan callback UI.
    private var autoplayRequested =
        false

    // ============================================================
    // HANDLER
    // ============================================================

    private val handler =
        Handler(
            Looper.getMainLooper()
        )


    // Kualitas yang benar-benar dilaporkan player. Berbeda dari preferensi
    // pengguna: YouTube tetap dapat memilih kualitas adaptif.
    private var actualPlaybackQuality =
        "unknown"

    // Helper terpisah supaya aturan kualitas dan caption tidak menumpuk di
    // PlatformView utama.
    private var captionAppliedFor: String? = null

    private val qualityController by lazy {
        YoutubeQualityController(
            handler = handler,
            getWebView = {
                if (::youtubePlayerView.isInitialized) findWebView(youtubePlayerView) else null
            },
            getVideoId = { currentVideoId },
            getPreferredQuality = { effectiveQuality() },
            getCrop = { preferredCrop },
        )
    }

    private val captionController by lazy {
        YoutubeCaptionController(
            handler = handler,
            getWebView = {
                if (::youtubePlayerView.isInitialized) findWebView(youtubePlayerView) else null
            },
            getVideoId = { currentVideoId },
            isEnabled = { preferredCaptionsEnabled },
            getLanguage = { preferredCaptionLanguage },
        )
    }

    private val diagnosticsController by lazy {
        YoutubePlayerDiagnostics(
            handler = handler,
            getWebView = {
                if (::youtubePlayerView.isInitialized) findWebView(youtubePlayerView) else null
            },
            getVideoId = { currentVideoId },
            getState = { currentState },
            getPreferredQuality = { preferredQuality },
            getActualQuality = { actualPlaybackQuality },
            isCaptionEnabled = { preferredCaptionsEnabled },
            getCaptionLanguage = { preferredCaptionLanguage },
        )
    }


    // ============================================================
    // PROGRESS
    // ============================================================

    private val progressRunnable =
        object : Runnable {

            override fun run() {

                if (!isReady || externalPlaybackActive || currentVideoId.isBlank()) {
                    return
                }

                if (currentState == "ended") {

                    MusikKuLogger.d(
                        TAG,
                        "PROGRESS BERHENTI: VIDEO ENDED"
                    )

                    return
                }

                sendState(
                    currentState
                )

                handler.postDelayed(
                    this,
                    1000L
                )
            }
        }


    // ============================================================
    // DURATION RETRY
    // ============================================================

    private val durationRetryRunnable =
        object : Runnable {

            override fun run() {

                if (!isReady) {
                    return
                }

                if (videoDuration <= 0f) {

                    MusikKuLogger.d(
                        TAG,
                        "MENUNGGU CALLBACK DURATION..."
                    )

                    handler.postDelayed(
                        this,
                        1000L
                    )

                } else {

                    MusikKuLogger.d(
                        TAG,
                        "DURATION SUDAH TERSEDIA = $videoDuration"
                    )
                }
            }
        }


    // ============================================================
    // INIT
    // ============================================================

    init {

        instance =
            this


        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "YOUTUBE PLATFORM VIEW DIBUAT"
        )

        MusikKuLogger.d(
            TAG,
            "INSTANCE = $this"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        // ========================================================
        // CONTAINER
        // ========================================================

        container =
            FrameLayout(
                context
            )


        buildPlayerView()
    }

    // ============================================================
    // BUILD PLAYER VIEW
    // (dipisah dari init supaya bisa dibuat ulang kalau renderer WebView mati)
    // ============================================================

    private fun buildPlayerView() {

        // ========================================================
        // YOUTUBE PLAYER VIEW
        // ========================================================

        youtubePlayerView =
            YouTubePlayerView(
                context
            )

        // Inisialisasi manual diperlukan agar controls iframe bisa dimatikan
        // dan diganti custom UI dari library 13.x.
        youtubePlayerView.enableAutomaticInitialization = false


        // ========================================================
        // BACKGROUND PLAYBACK
        // ========================================================

        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "MENGAKTIFKAN BACKGROUND PLAYBACK"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        youtubePlayerView
            .enableBackgroundPlayback(
                true
            )


        // Jaga proses renderer WebView tetap berprioritas tinggi saat app
        // di background. Kalau renderer dimatikan Android (mis. memori habis
        // ketika buka aplikasi berat), musik ikut mati.
        keepRendererImportant(
            youtubePlayerView
        )


        // ========================================================
        // TAMBAHKAN YOUTUBE VIEW
        // ========================================================

        container.addView(

            youtubePlayerView,

            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )


        // ========================================================
        // YOUTUBE PLAYER LISTENER
        // ========================================================

        youtubePlayerView
            .addYouTubePlayerListener(

                object :
                    AbstractYouTubePlayerListener() {


                    // ==================================================
                    // READY
                    // ==================================================

                    override fun onReady(
                        player: YouTubePlayer
                    ) {

                        MusikKuLogger.d(
                            TAG,
                            "===================================="
                        )

                        MusikKuLogger.d(
                            TAG,
                            "YOUTUBE PLAYER READY"
                        )

                        MusikKuLogger.d(
                            TAG,
                            "===================================="
                        )


                        youtubePlayer =
                            player

                        val ui =
                            DefaultPlayerUiController(
                                youtubePlayerView,
                                player
                            )

                        // Default custom-ui seek bar punya hit-area vertikal besar.
                        // Tipiskan visualnya agar lebih ramping,
                        // tanpa mengubah area kontrol/seek yang bisa disentuh.
                        val seekBarContainer = ui.rootView.findViewById<YouTubePlayerSeekBar>(
                            com.pierfrancescosoffritti.androidyoutubeplayer.core.customui.R.id.youtube_player_seekbar
                        )
                        seekBarContainer?.seekBar?.apply {
                            scaleY = 0.62f
                            progressTintList = ColorStateList.valueOf(Color.rgb(108, 99, 255)) // aksen aplikasi (bukan merah YouTube)
                            progressBackgroundTintList = ColorStateList.valueOf(Color.argb(150, 255, 255, 255))
                            thumbTintList = ColorStateList.valueOf(Color.WHITE)
                        }

                        ui.showVideoTitle(false)
                        // Play/Pause bawaan custom-ui disembunyikan karena
                        // MusikKu menyediakan kontrol Play/Pause sendiri di
                        // Flutter. Ini mencegah tombol dobel di tengah video.
                        ui.showPlayPauseButton(false)
                        ui.showSeekBar(false)
                        ui.showCurrentTime(false)
                        ui.showDuration(false)
                        ui.showFullscreenButton(false)
                        ui.showYouTubeButton(false)
                        ui.showMenuButton(false)
                        // Biarkan indikator buffering milik player/web tetap tunggal; spinner Flutter
                        // tambahan tidak dipakai agar tidak muncul dobel.
                        ui.showBufferingProgress(false)
                        // YouTube/custom-ui controls TIDAK dipakai. Semua kontrol
                        // play/pause/next/previous/seek sekarang dirender Flutter.
                        // Ini mencegah tombol Pause bawaan muncul dobel dan mencegah
                        // panel native menangkap tap/drag pengguna.
                        ui.showUi(false)

                        playerUiController =
                            ui

                        youtubePlayerView.setCustomPlayerUi(
                            ui.rootView
                        )

                        applyPlaybackQuality(force = true)
                        enforceCaptionState()

                        isReady =
                            true

                        // Terapkan ulang volume terakhir setelah IFrame player siap.
                        player.setVolume(preferredVolumePercent.coerceIn(0, 100))

                        currentState =
                            "unstarted"

                        currentPosition =
                            pendingStartSeconds.coerceAtLeast(0f)

                        videoDuration =
                            0f

                        endedSentForVideoId =
                            ""


                        val videoId =
                            pendingVideoId

                        if (!externalPlaybackActive && !videoId.isNullOrBlank()) {
                            startProgressUpdates()
                        }


                        if (
                            !videoId.isNullOrBlank()
                        ) {

                            MusikKuLogger.d(
                                TAG,
                                "LOAD PENDING VIDEO = $videoId"
                            )

                            val startSeconds =
                                pendingStartSeconds.coerceAtLeast(0f)

                            currentVideoId =
                                videoId

                            currentPosition =
                                startSeconds

                            pendingVideoId =
                                null

                            player.loadVideo(
                                videoId,
                                startSeconds
                            )

                            if (autoplayRequested && !externalPlaybackActive) {
                                handler.postDelayed({
                                    if (autoplayRequested && !externalPlaybackActive && currentVideoId == videoId) {
                                        try {
                                            player.play()
                                        } catch (_: Exception) {
                                            // WebView mungkin belum selesai menyiapkan frame.
                                        }
                                    }
                                }, 350L)
                            }

                            startDurationRetry()
                        }


                        sendState(
                            currentState
                        )
                    }


                    // ==================================================
                    // VIDEO ID
                    // ==================================================

                    override fun onVideoId(
                        player: YouTubePlayer,
                        videoId: String
                    ) {

                        MusikKuLogger.d(
                            TAG,
                            "===================================="
                        )

                        MusikKuLogger.d(
                            TAG,
                            "VIDEO ID CALLBACK"
                        )

                        MusikKuLogger.d(
                            TAG,
                            "VIDEO ID = $videoId"
                        )

                        MusikKuLogger.d(
                            TAG,
                            "===================================="
                        )


                        currentVideoId =
                            videoId

                        currentPosition =
                            pendingStartSeconds.coerceAtLeast(0f)

                        pendingStartSeconds =
                            0f

                        videoDuration =
                            0f

                        currentState =
                            "unstarted"

                        endedSentForVideoId =
                            ""


                        sendState(
                            currentState
                        )

                        if (autoplayRequested && !externalPlaybackActive) {
                            val id = currentVideoId
                            handler.postDelayed({
                                if (autoplayRequested && !externalPlaybackActive && currentVideoId == id) {
                                    try {
                                        youtubePlayer?.play()
                                    } catch (_: Exception) {}
                                }
                            }, 350L)
                        }

                        startDurationRetry()
                    }


                    // ==================================================
                    // DURATION
                    // ==================================================

                    override fun onVideoDuration(
                        player: YouTubePlayer,
                        duration: Float
                    ) {

                        MusikKuLogger.d(
                            TAG,
                            "VIDEO DURATION CALLBACK"
                        )

                        MusikKuLogger.d(
                            TAG,
                            "DURATION = $duration"
                        )


                        if (
                            duration > 0f
                        ) {

                            videoDuration =
                                duration


                            handler.removeCallbacks(
                                durationRetryRunnable
                            )


                            sendState(
                                currentState
                            )
                        }
                    }


                    // ==================================================
                    // CURRENT SECOND
                    // ==================================================

                    override fun onVideoLoadedFraction(
                        player: YouTubePlayer,
                        loadedFraction: Float
                    ) {
                        bufferedFraction = loadedFraction.coerceIn(0f, 1f)
                        sendState(currentState)
                    }


                    // ==================================================
                    // CURRENT SECOND
                    // ==================================================

                    override fun onCurrentSecond(
                        player: YouTubePlayer,
                        second: Float
                    ) {

                        currentPosition =
                            second


                        sendState(
                            currentState
                        )
                    }

                    // Kualitas aktual datang dari callback player. Ini dipakai
                    // diagnostik supaya Settings menampilkan kondisi nyata,
                    // bukan sekadar nilai yang diminta UI.
                    override fun onPlaybackQualityChange(
                        player: YouTubePlayer,
                        playbackQuality: PlayerConstants.PlaybackQuality
                    ) {
                        actualPlaybackQuality = playbackQuality.name.lowercase()
                        MusikKuLogger.d(
                            TAG,
                            "PLAYBACK QUALITY AKTUAL = $actualPlaybackQuality"
                        )
                        sendState(currentState)
                    }


                    // ==================================================
                    // STATE CHANGE
                    // ==================================================

                    override fun onStateChange(
                        player: YouTubePlayer,
                        state:
                            PlayerConstants.PlayerState
                    ) {

                        val newState =
                            convertState(
                                state
                            )


                        currentState =
                            newState

                        // Player YouTube memilih kualitas berdasarkan ukuran
                        // elemen. Tahan ukurannya + kirim hint tiap video baru.
                        if (newState == "playing" || newState == "buffering") {
                            applyPlaybackQuality(force = false)
                        }
                        // Subtitle: coba lagi tepat saat video mulai jalan, karena
                        // daftar track baru tersedia di titik ini.
                        // Hanya sekali per video: tiap pause->play tidak perlu
                        // menjalankan ulang JS caption (bikin subtitle berkedip).
                        if (newState == "playing" && preferredCaptionsEnabled &&
                            captionAppliedFor != currentVideoId
                        ) {
                            captionAppliedFor = currentVideoId
                            handler.postDelayed({ applyCaptionSettingsNow() }, 600L)
                        }

                        // Satu sumber indikator buffering. DefaultPlayerUiController
                        // sendiri memiliki spinner buffering; saat buffering sembunyikan
                        // seluruh custom UI agar WebView tidak menampilkan dua spinner
                        // bertumpuk. Kembalikan kontrol ketika state stabil.
                        try {
                            playerUiController?.showUi(
                                playerUiRequestedVisible && newState != "buffering"
                            )
                        } catch (_: Exception) {
                        }


                        MusikKuLogger.d(
                            TAG,
                            "===================================="
                        )

                        MusikKuLogger.d(
                            TAG,
                            "PLAYER STATE = $currentState"
                        )

                        MusikKuLogger.d(
                            TAG,
                            "POSITION = $currentPosition"
                        )

                        MusikKuLogger.d(
                            TAG,
                            "DURATION = $videoDuration"
                        )

                        MusikKuLogger.d(
                            TAG,
                            "VIDEO = $currentVideoId"
                        )

                        MusikKuLogger.d(
                            TAG,
                            "===================================="
                        )


                        // ==================================================
                        // ENDED
                        // ==================================================

                        if (
                            newState == "ended"
                        ) {

                            handler.removeCallbacks(
                                progressRunnable
                            )


                            if (
                                videoDuration > 0f
                            ) {

                                currentPosition =
                                    videoDuration
                            }


                            if (
                                endedSentForVideoId !=
                                    currentVideoId
                            ) {

                                endedSentForVideoId =
                                    currentVideoId


                                MusikKuLogger.d(
                                    TAG,
                                    "===================================="
                                )

                                MusikKuLogger.d(
                                    TAG,
                                    "VIDEO ENDED"
                                )

                                MusikKuLogger.d(
                                    TAG,
                                    "ENDED VIDEO ID = $currentVideoId"
                                )

                                MusikKuLogger.d(
                                    TAG,
                                    "MENGIRIM EVENT ENDED KE FLUTTER"
                                )

                                MusikKuLogger.d(
                                    TAG,
                                    "===================================="
                                )


                                sendState(
                                    "ended"
                                )

                            } else {

                                MusikKuLogger.d(
                                    TAG,
                                    "ENDED SUDAH PERNAH DIKIRIM"
                                )
                            }


                            return
                        }


                        // ==================================================
                        // STATE NORMAL
                        // ==================================================

                        sendState(
                            currentState
                        )


                        if (
                            currentState == "playing" ||
                            currentState == "buffering"
                        ) {

                            startDurationRetry()
                        }


                        if (
                            currentState == "playing"
                        ) {

                            startProgressUpdates()
                        }
                    }


                    // ==================================================
                    // ERROR
                    // ==================================================

                    override fun onError(
                        player: YouTubePlayer,
                        error:
                            PlayerConstants.PlayerError
                    ) {

                        MusikKuLogger.e(
                            TAG,
                            "===================================="
                        )

                        MusikKuLogger.e(
                            TAG,
                            "YOUTUBE ERROR"
                        )

                        MusikKuLogger.e(
                            TAG,
                            "ERROR = ${error.name}"
                        )

                        MusikKuLogger.e(
                            TAG,
                            "VIDEO ID = $currentVideoId"
                        )

                        MusikKuLogger.e(
                            TAG,
                            "===================================="
                        )


                        sendEvent(

                            mapOf(

                                "event" to
                                    "error",

                                "error" to
                                    error.name,

                                "videoId" to
                                    currentVideoId
                            )
                        )
                    }
                }
            )


        // Core 13.x: web controls dimatikan karena kontrol normal sekarang
        // berasal dari custom-ui. PiP dapat menyembunyikannya lewat showUi(false).
        val playerOptions =
            IFramePlayerOptions.Builder(context)
                .controls(0)
                .fullscreen(0)
                .rel(0)
                .ivLoadPolicy(3) // sembunyikan anotasi/kartu bawaan YouTube
                .ccLoadPolicy(0)
                .langPref(captionLangPref(preferredCaptionLanguage))
                .build()

        youtubePlayerView.initialize(
            object : AbstractYouTubePlayerListener() {},
            playerOptions
        )
    }


    // ============================================================
    // CONVERT STATE
    // ============================================================

    private fun convertState(
        state:
            PlayerConstants.PlayerState
    ): String {

        return when (state) {

            PlayerConstants.PlayerState.UNSTARTED ->
                "unstarted"

            PlayerConstants.PlayerState.ENDED ->
                "ended"

            PlayerConstants.PlayerState.PLAYING ->
                "playing"

            PlayerConstants.PlayerState.PAUSED ->
                "paused"

            PlayerConstants.PlayerState.BUFFERING ->
                "buffering"

            PlayerConstants.PlayerState.VIDEO_CUED ->
                "cued"

            PlayerConstants.PlayerState.UNKNOWN ->
                "unknown"
        }
    }


    // ============================================================
    // START PROGRESS
    // ============================================================

    private fun startProgressUpdates() {

        handler.removeCallbacks(
            progressRunnable
        )

        if (externalPlaybackActive || currentVideoId.isBlank()) {
            return
        }

        handler.post(
            progressRunnable
        )
    }


    // ============================================================
    // START DURATION
    // ============================================================

    private fun startDurationRetry() {

        handler.removeCallbacks(
            durationRetryRunnable
        )

        handler.post(
            durationRetryRunnable
        )
    }


    // ============================================================
    // GET VIEW
    // ============================================================

    override fun getView(): View {

        return container
    }


    // ============================================================
    // LOAD VIDEO
    // ============================================================

    fun loadVideo(
        videoId: String,
        startSeconds: Float = 0f,
    ) {

        if (
            videoId.isBlank()
        ) {

            MusikKuLogger.w(
                TAG,
                "LOAD VIDEO: VIDEO ID KOSONG"
            )

            return
        }


        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "LOAD VIDEO"
        )

        MusikKuLogger.d(
            TAG,
            "VIDEO ID = $videoId"
        )

        MusikKuLogger.d(
            TAG,
            "IS READY = $isReady"
        )

        MusikKuLogger.d(
            TAG,
            "PLAYER = $youtubePlayer"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        val safeStartSeconds =
            startSeconds.coerceAtLeast(0f)

        externalPlaybackActive =
            false
        idleStateSent =
            false
        autoplayRequested =
            true

        currentVideoId =
            videoId

        currentPosition =
            safeStartSeconds

        pendingStartSeconds =
            safeStartSeconds

        videoDuration =
            0f

        bufferedFraction =
            0f
        dataBytesAtVideoStart =
            TrafficStats.getUidRxBytes(Process.myUid())

        currentState =
            "unstarted"

        actualPlaybackQuality =
            "unknown"
        qualityController.invalidateVideo()

        endedSentForVideoId =
            ""


        handler.removeCallbacks(
            progressRunnable
        )


        if (
            !isReady ||
            youtubePlayer == null
        ) {

            pendingVideoId =
                videoId


            sendState(
                "unstarted"
            )

            return
        }


        youtubePlayer?.loadVideo(
            videoId,
            safeStartSeconds
        )

        // Tegaskan lagi state caption setelah video baru dimuat. Ini penting
        // saat YouTube/WebView mencoba memulihkan preferensi caption sendiri.
        handler.postDelayed({ enforceCaptionState() }, 500L)
        handler.postDelayed({ enforceCaptionState() }, 1400L)

        if (autoplayRequested && !externalPlaybackActive) {
            val id = videoId
            handler.postDelayed({
                if (autoplayRequested && !externalPlaybackActive && currentVideoId == id) {
                    try {
                        youtubePlayer?.play()
                    } catch (_: Exception) {}
                }
            }, 350L)
        }

        startDurationRetry()


        sendState(
            "unstarted"
        )
    }


    // ============================================================
    // DEACTIVATE FOR EXTERNAL/LOCAL PLAYBACK
    // ============================================================

    fun deactivateForExternalPlayback() {

        externalPlaybackActive = true

        handler.removeCallbacks(progressRunnable)
        handler.removeCallbacks(durationRetryRunnable)

        try {
            youtubePlayer?.pause()
        } catch (_: Exception) {
            // Player mungkin sudah dilepas oleh WebView.
        }

        pendingVideoId = null
        pendingStartSeconds = 0f
        autoplayRequested = false
        currentVideoId = ""
        currentState = "unstarted"
        currentPosition = 0f
        videoDuration = 0f
        bufferedFraction = 0f
        dataBytesAtVideoStart = -1L
        endedSentForVideoId = ""
    }


    private fun findWebView(root: View): WebView? {
        if (root is WebView) return root
        if (root is ViewGroup) {
            for (index in 0 until root.childCount) {
                val found = findWebView(root.getChildAt(index))
                if (found != null) return found
            }
        }
        return null
    }

    /** Terapkan preferensi kualitas sebagai hint/layout, bukan jaminan resolusi. */
    private fun applyPlaybackQuality(force: Boolean) {
        qualityController.apply(force)
    }

    /** Pertahankan helper lama untuk kompatibilitas internal. */
    private fun enforceCaptionState() {
        applyCaptionSettingsNow()
    }

    /** Terapkan ON/OFF + mode bahasa caption tanpa reload video. */
    fun applyCaptionSettingsNow() {
        captionController.applyNow()
    }

    private val qualityOrder =
        listOf("tiny", "small", "medium", "large", "hd720", "hd1080", "highres")

    private fun isNetworkMetered(): Boolean =
        try {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            manager?.isActiveNetworkMetered ?: true
        } catch (_: Exception) {
            true
        }

    /**
     * Kualitas yang benar-benar diminta ke player: pilihan pengguna, dibatasi
     * mode hemat data. Di background video tidak terlihat, jadi diturunkan ke
     * 144p. Di paket data (jaringan metered): Hemat maks 360p, Super hemat 144p.
     */
    private fun effectiveQuality(): String {
        val preferred = preferredQuality
        val level = dataSaverLevel
        if (level <= 0) return preferred
        val cap: String? = when {
            appInBackground -> "tiny"
            level >= 2 -> if (isNetworkMetered()) "tiny" else "medium"
            else -> if (isNetworkMetered()) "medium" else null
        }
        if (cap == null) return preferred
        val capRank = qualityOrder.indexOf(cap)
        val preferredRank =
            if (preferred == "default") qualityOrder.indexOf("hd720")
            else qualityOrder.indexOf(preferred)
        return if (preferredRank in 0..capRank) preferred else cap
    }

    fun reapplyQuality() {
        handler.post { applyPlaybackQuality(force = true) }
    }

    fun setPlaybackQuality(requestedQuality: String) {
        val quality = normalizeQuality(requestedQuality)
        if (quality == null) {
            MusikKuLogger.w(TAG, "SET QUALITY: level tidak dikenal = $requestedQuality")
            return
        }

        preferredQuality = quality
        MusikKuLogger.d(TAG, "SET QUALITY PREFERENCE = $quality")
        handler.post { applyPlaybackQuality(force = true) }
    }

    // ============================================================
    // PLAY
    // ============================================================

    fun play() {

        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "NATIVE PLAY"
        )

        MusikKuLogger.d(
            TAG,
            "IS READY = $isReady"
        )

        MusikKuLogger.d(
            TAG,
            "PLAYER = $youtubePlayer"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        if (
            !isReady
        ) {

            MusikKuLogger.w(
                TAG,
                "PLAY: PLAYER BELUM READY"
            )

            return
        }


        autoplayRequested = true
        youtubePlayer?.play()

        // Jangan kirim state "playing" secara optimistis dari sini.
        // Flutter memakai requestedPlaying untuk menahan ikon Play/Pause
        // selama callback native yang sebenarnya masih tertunda. Kalau kita
        // mengirim "playing" palsu di sini, intent langsung dianggap
        // terkonfirmasi lalu event "paused" lama dari YouTube bisa
        // menimpa UI sebelum callback "playing" yang sebenarnya tiba.
        // State resmi tetap hanya berasal dari onStateChange().

    }


    // ============================================================
    // PAUSE
    // ============================================================

    fun shouldEnterPictureInPicture(): Boolean {
        return !externalPlaybackActive &&
            currentVideoId.isNotBlank() &&
            currentState != "unstarted" &&
            currentState != "ended" &&
            currentState != "error"
    }

    fun getCurrentVideoId(): String = currentVideoId

    fun getCurrentPlaybackState(): String = currentState

    fun setPlayerUiVisible(visible: Boolean) {
        // Method ini dipertahankan untuk compatibility dengan Flutter lama,
        // tetapi custom-ui YouTube sengaja selalu tersembunyi. Semua kontrol
        // pengguna dikelola Flutter agar tap tidak direbut WebView.
        playerUiRequestedVisible = false
        try {
            playerUiController?.showUi(false)
        } catch (e: Exception) {
            MusikKuLogger.w(TAG, "GAGAL MENYEMBUNYIKAN UI PLAYER", e)
        }
    }

    @Suppress("unused")
    private fun rebuildForCaptionSettings() {
        // Dipertahankan hanya agar source lama tetap kompatibel; toggle caption
        // sekarang tidak perlu reload player.
        applyCaptionSettingsNow()
    }

    fun pause() {

        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "NATIVE PAUSE"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        if (
            !isReady
        ) {

            MusikKuLogger.w(
                TAG,
                "PAUSE: PLAYER BELUM READY"
            )

            return
        }


        autoplayRequested = false
        youtubePlayer?.pause()

        // Sama seperti play(): jangan membuat callback state sintetis.
        // Callback onStateChange(PAUSED) adalah satu-satunya konfirmasi resmi;
        // ini mencegah event playback lama mengalahkan intent pause terbaru.
        handler.removeCallbacks(
            progressRunnable
        )

    }


    // ============================================================
    // SEEK
    // ============================================================

    fun seek(
        seconds: Float
    ) {

        if (
            !isReady
        ) {
            return
        }


        youtubePlayer?.seekTo(
            seconds
        )


        currentPosition =
            seconds


        if (
            seconds < videoDuration
        ) {

            endedSentForVideoId =
                ""
        }


        sendState(
            currentState
        )
    }


    // ============================================================
    // VOLUME
    // ============================================================

    fun setVolume(percent: Int) {
        val safe = percent.coerceIn(0, 100)
        preferredVolumePercent = safe

        // Simpan meski player belum siap. Nilai ini akan diterapkan di onReady,
        // jadi geser slider saat lagu baru mulai tidak hilang begitu saja.
        handler.post {
            if (isReady) {
                youtubePlayer?.setVolume(safe)
            }
        }
    }


    // ============================================================
    // CURRENT TIME
    // ============================================================

    fun currentTime():
        Float {

        return currentPosition
    }

    fun getActualPlaybackQuality(): String = actualPlaybackQuality

    fun getPlayerDebugSnapshot(callback: (Map<String, Any?>) -> Unit) {
        handler.post {
            diagnosticsController.snapshot(callback)
        }
    }


    private fun currentNetworkType(): String {
        return try {
            val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
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


    // ============================================================
    // SEND STATE
    // ============================================================

    private fun sendState(
        state: String
    ) {

        // Jangan mengirim heartbeat YouTube saat musik lokal aktif. Kedua
        // sumber berbagi satu EventChannel; event idle YouTube bisa menimpa
        // state player lokal dan memenuhi log/UI.
        if (externalPlaybackActive) {
            return
        }

        if (currentVideoId.isBlank()) {
            if (idleStateSent) {
                return
            }
            idleStateSent = true
        } else {
            idleStateSent = false
        }

        val rxBytes =
            TrafficStats.getUidRxBytes(Process.myUid()).let {
                if (it < 0L || dataBytesAtVideoStart < 0L) 0L
                else (it - dataBytesAtVideoStart).coerceAtLeast(0L)
            }

        val bufferedAheadSeconds =
            if (videoDuration > 0f && bufferedFraction > 0f) {
                (bufferedFraction * videoDuration - currentPosition)
                    .coerceIn(0f, (videoDuration - currentPosition).coerceAtLeast(0f))
            } else {
                0f
            }

        val networkType = currentNetworkType()

        val data =
            mapOf<String, Any>(

                "state" to
                    state,

                "position" to
                    currentPosition,

                "duration" to
                    videoDuration,

                "videoId" to
                    currentVideoId,

                "preferredQuality" to
                    preferredQuality,

                "actualQuality" to
                    actualPlaybackQuality,

                "bufferedFraction" to
                    bufferedFraction,

                "bufferedAheadSeconds" to
                    bufferedAheadSeconds,

                "networkRxBytes" to
                    rxBytes,

                "networkType" to
                    networkType,
            )


        lastEvent =
            data


        MusikKuLogger.d(
            TAG,
            "SEND STATE:"
                + " state=$state"
                + " | position=$currentPosition"
                + " | duration=$videoDuration"
                + " | video=$currentVideoId"
                + " | sink=${eventSink != null}"
        )


        sendEvent(
            data
        )

        // Keep Android 12+ auto-enter PiP parameters current as soon as the
        // player has a real video/state. This prevents Home/gesture navigation
        // from depending on the timing of onUserLeaveHint().
        (context as? MainActivity)?.refreshPipParamsForPlayerState()
    }


    // ============================================================
    // SEND EVENT
    // ============================================================

    private fun sendEvent(
        data:
            Map<String, Any>
    ) {

        val sink =
            eventSink


        if (
            sink == null
        ) {

            MusikKuLogger.w(
                TAG,
                "EVENT SINK = NULL"
            )

            return
        }


        try {

            sink.success(
                data
            )


            MusikKuLogger.d(
                TAG,
                "EVENT BERHASIL DIKIRIM KE FLUTTER"
            )

        } catch (
            e: Exception
        ) {

            MusikKuLogger.e(
                TAG,
                "GAGAL KIRIM EVENT KE FLUTTER",
                e
            )
        }
    }


    // ============================================================
    // RENDERER PRIORITY
    // ============================================================

    private fun keepRendererImportant(
        root: View
    ) {
        val webView = findWebView(root)
        if (webView == null) {
            MusikKuLogger.w(TAG, "WEBVIEW TIDAK DITEMUKAN; PENGATURAN KEAMANAN TIDAK DITERAPKAN")
            return
        }

        try {
            // The remote YouTube player needs JavaScript and DOM storage, but
            // it does not need local-file/content URI access or mixed HTTP content.
            webView.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                allowFileAccess = false
                allowContentAccess = false
                allowFileAccessFromFileURLs = false
                allowUniversalAccessFromFileURLs = false
                mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
                setSupportMultipleWindows(false)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    safeBrowsingEnabled = true
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                webView.setRendererPriorityPolicy(
                    WebView.RENDERER_PRIORITY_IMPORTANT,
                    false
                )
                MusikKuLogger.d(TAG, "RENDERER PRIORITY = IMPORTANT")
            }

            // Preserve player navigation callbacks while adding crash recovery
            // and a strict SSL-error handler.
            webView.webViewClient = GuardedWebViewClient(webView.webViewClient)
        } catch (e: Exception) {
            MusikKuLogger.e(TAG, "PENGATURAN WEBVIEW GAGAL", e)
        }
    }

    // ============================================================
    // RENDERER MATI (OOM) -> PULIHKAN
    // ============================================================

    private inner class GuardedWebViewClient(
        private val delegate: WebViewClient
    ) : WebViewClient() {

        override fun onRenderProcessGone(
            view: WebView?,
            detail: RenderProcessGoneDetail?
        ): Boolean {

            MusikKuLogger.e(
                TAG,
                "RENDERER WEBVIEW MATI (crash=${detail?.didCrash()}), PLAYER DIBUAT ULANG"
            )

            handler.post {
                recoverFromRendererGone()
            }

            // true = sudah ditangani, app TIDAK ikut dimatikan.
            return true
        }

        override fun shouldOverrideUrlLoading(
            view: WebView?,
            request: WebResourceRequest?
        ): Boolean =
            delegate.shouldOverrideUrlLoading(view, request)

        override fun shouldInterceptRequest(
            view: WebView?,
            request: WebResourceRequest?
        ): WebResourceResponse? =
            delegate.shouldInterceptRequest(view, request)

        override fun onPageStarted(
            view: WebView?,
            url: String?,
            favicon: Bitmap?
        ) {
            delegate.onPageStarted(view, url, favicon)
        }

        override fun onPageFinished(
            view: WebView?,
            url: String?
        ) {
            delegate.onPageFinished(view, url)
        }

        override fun onLoadResource(
            view: WebView?,
            url: String?
        ) {
            delegate.onLoadResource(view, url)
        }

        override fun onReceivedError(
            view: WebView?,
            request: WebResourceRequest?,
            error: WebResourceError?
        ) {
            delegate.onReceivedError(view, request, error)
        }

        override fun onReceivedSslError(
            view: WebView?,
            handler: SslErrorHandler?,
            error: SslError?
        ) {
            // Never allow a WebView certificate error to be bypassed by a
            // library callback; cancel the request and keep TLS strict.
            handler?.cancel()
            MusikKuLogger.w(TAG, "KONEKSI WEBVIEW DIBATALKAN KARENA ERROR SERTIFIKAT SSL")
        }
    }

    private fun forceWebViewVisible() {

        val webView =
            findWebView(
                youtubePlayerView
            )
            ?: return

        try {

            webView.onResume()

            webView.resumeTimers()

            youtubePlayerView.dispatchWindowVisibilityChanged(
                View.VISIBLE
            )

            MusikKuLogger.d(
                TAG,
                "WEBVIEW BARU DIPAKSA TERLIHAT"
            )

        } catch (
            e: Exception
        ) {

            MusikKuLogger.e(
                TAG,
                "GAGAL MEMAKSA WEBVIEW TERLIHAT",
                e
            )
        }
    }

    private fun onRecoveryFailed() {

        MusikKuLogger.w(
            TAG,
            "PEMULIHAN PLAYER GAGAL DI BACKGROUND, MENUNGGU APP KEMBALI KE DEPAN"
        )

        needsRebuildOnForeground =
            true

        handler.removeCallbacks(
            progressRunnable
        )

        handler.removeCallbacks(
            durationRetryRunnable
        )

        currentState =
            "paused"

        sendState(
            "paused"
        )
    }

    /**
     * Dipanggil MainActivity.onStart(). Kalau pemulihan di background gagal,
     * bangun ulang player sekarang saat window terlihat.
     */
    fun onAppForeground() {

        if (
            needsRebuildOnForeground
        ) {

            MusikKuLogger.d(
                TAG,
                "APP KEMBALI KE DEPAN, MEMBANGUN ULANG PLAYER"
            )

            recoverFromRendererGone()
        }
    }

    private fun recoverFromRendererGone() {

        if (
            recoveringRenderer
        ) {
            return
        }

        recoveringRenderer =
            true

        try {

            val videoId =
                currentVideoId

            val resumeAt =
                currentPosition

            handler.removeCallbacks(
                progressRunnable
            )

            handler.removeCallbacks(
                durationRetryRunnable
            )

            isReady =
                false

            youtubePlayer =
                null

            try {

                container.removeView(
                    youtubePlayerView
                )

                youtubePlayerView.release()

            } catch (
                e: Exception
            ) {

                MusikKuLogger.e(
                    TAG,
                    "GAGAL MEMBUANG PLAYER LAMA",
                    e
                )
            }

            pendingVideoId =
                if (videoId.isBlank()) null else videoId

            pendingStartSeconds =
                resumeAt

            currentState =
                "buffering"

            buildPlayerView()

            // Beri tahu Flutter bahwa lagu sedang dipulihkan (bukan berhenti).
            sendState(
                "buffering"
            )

            needsRebuildOnForeground =
                false

            recoveryGeneration++

            val generation =
                recoveryGeneration

            // WebView yang dibuat saat app di background dianggap "tidak
            // terlihat" oleh Chromium sehingga video tidak mau mulai.
            // Paksa dia menganggap window-nya terlihat.
            handler.postDelayed(
                {
                    if (generation == recoveryGeneration) {
                        forceWebViewVisible()
                    }
                },
                300L
            )

            handler.postDelayed(
                {
                    if (generation == recoveryGeneration) {
                        forceWebViewVisible()
                    }
                },
                1500L
            )

            // Watchdog: kalau 8 detik kemudian durasi belum diketahui,
            // player baru gagal jalan. Jangan nyangkut di "unstarted";
            // tandai paused dan coba lagi saat app kembali ke depan.
            handler.postDelayed(
                {
                    if (
                        generation == recoveryGeneration &&
                        videoDuration <= 0f
                    ) {
                        onRecoveryFailed()
                    }
                },
                8000L
            )

        } catch (
            e: Exception
        ) {

            MusikKuLogger.e(
                TAG,
                "GAGAL MEMULIHKAN PLAYER",
                e
            )

        } finally {

            recoveringRenderer =
                false
        }
    }


    // ============================================================
    // DISPOSE
    // ============================================================

    override fun dispose() {

        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "YOUTUBE PLATFORM VIEW DISPOSE"
        )

        MusikKuLogger.d(
            TAG,
            "PLAYER TIDAK DI-RELEASE"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        // ========================================================
        // PENTING
        // ========================================================
        //
        // Jangan panggil release() di sini.
        //
        // Kita sedang menguji background playback.
        //
        // Jika dispose() terjadi hanya karena Flutter/Activity
        // kehilangan surface ketika masuk background, release()
        // akan menghancurkan YouTubePlayerView.
        //
        // release() tetap tersedia dan hanya dipanggil ketika
        // player benar-benar ingin dihentikan/dihancurkan.
        //
    }


    // ============================================================
    // RELEASE
    // ============================================================

    fun release() {

        MusikKuLogger.d(
            TAG,
            "===================================="
        )

        MusikKuLogger.d(
            TAG,
            "YOUTUBE PLATFORM VIEW RELEASE"
        )

        MusikKuLogger.d(
            TAG,
            "===================================="
        )


        isReady =
            false
        externalPlaybackActive =
            false
        idleStateSent =
            false

        handler.removeCallbacks(
            progressRunnable
        )

        handler.removeCallbacks(
            durationRetryRunnable
        )


        youtubePlayer =
            null

        pendingVideoId =
            null

        pendingStartSeconds =
            0f

        currentVideoId =
            ""

        currentState =
            "unstarted"

        currentPosition =
            0f

        videoDuration =
            0f

        endedSentForVideoId =
            ""


        try {

            youtubePlayerView.release()

        } catch (
            e: Exception
        ) {

            MusikKuLogger.e(
                TAG,
                "GAGAL RELEASE YOUTUBE VIEW",
                e
            )
        }


        if (
            instance === this
        ) {

            instance =
                null
        }
    }
}