package com.musikku.app

import android.app.Notification
import android.database.ContentObserver
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.provider.MediaStore
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
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
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.media.app.NotificationCompat.MediaStyle
import androidx.media.MediaBrowserServiceCompat
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaDescriptionCompat

import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
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
        private const val BROWSE_ROOT_ID = "musikku_root"
        private const val BROWSE_SONGS_ID = "local_songs"
        private const val BROWSE_RECENT_ID = "local_recent"
        private const val BROWSE_ARTISTS_ID = "local_artists"
        private const val BROWSE_ALBUMS_ID = "local_albums"
        private const val BROWSE_PLAYLISTS_ID = "musikku_playlists"
        private const val MEDIA_ID_SEPARATOR = "|"
        private const val ANDROID_AUTO_PREFETCH_REMAINING = 8

        var eventSink: io.flutter.plugin.common.EventChannel.EventSink? = null
        private var activeInstance: PlaybackService? = null

        fun setPreferredAudioOutputStatic(context: Context, deviceId: Int): Map<String, Any?> {
            val prefs = context.getSharedPreferences("musikku_playback_settings", Context.MODE_PRIVATE)
            val editor = prefs.edit().putInt("preferredAudioOutputId", deviceId)
            if (deviceId < 0) {
                editor.remove("preferredAudioOutputType").remove("preferredAudioOutputName")
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val selected = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                    .firstOrNull { it.id == deviceId && it.isSink }
                if (selected != null) {
                    editor.putInt("preferredAudioOutputType", selected.type)
                    editor.putString("preferredAudioOutputName", selected.productName?.toString().orEmpty())
                }
            }
            editor.apply()
            val service = activeInstance
            val applied = service?.applyPreferredAudioOutput(deviceId) == true
            val nativeActive = service?.isAudioPlayerSource() == true
            return mapOf<String, Any?>(
                "saved" to true,
                "applied" to applied,
                "nativePlayerActive" to nativeActive,
                "message" to if (nativeActive && applied) {
                    "Output audio diterapkan ke pemutar native."
                } else {
                    "Pilihan disimpan dan akan diterapkan saat lagu lokal atau audio native diputar. Fallback iframe memakai rute sistem Android."
                },
            )
        }

        fun setPcmVisualizationEnabledStatic(enabled: Boolean) {
            MusikKuAudioVisualizationEvents.enabled = enabled
        }

        fun setLoudnessNormalizationStatic(context: Context, enabled: Boolean) {
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit().putBoolean("flutter.audio_loudness_normalization_v1", enabled).apply()
            activeInstance?.pcmAudioProcessor?.normalizationEnabled = enabled
        }

        /**
         * Saves and applies MusikKu's mono-safe PCM soundstage profile.
         * This processor only touches audio decoded by this service's Media3
         * ExoPlayer; it cannot process the embedded WebView/iframe fallback.
         */
        fun setSpeakerSoundstageStatic(
            context: Context,
            enabled: Boolean,
            strength: Int,
        ): Map<String, Any?> {
            val safeStrength = strength.coerceIn(0, 100)
            context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("flutter.speaker_soundstage_enabled_v1", enabled)
                .putInt("flutter.speaker_soundstage_strength_v1", safeStrength)
                .apply()

            val service = activeInstance
            service?.speakerSoundstageRequestedEnabled = enabled
            service?.pcmAudioProcessor?.soundStageStrength = safeStrength
            service?.refreshSoundstageOutputProfile()
            if (enabled) service?.pcmAudioProcessor?.resetForNewTrack()
            val media3Active = service?.localPlayer?.isPlaying == true
            val pcmDiagnostics = service?.pcmAudioProcessor?.diagnostics().orEmpty()
            MusikKuLogger.d(
                TAG,
                "Soundstage enabled=$enabled strength=$safeStrength media3Playing=$media3Active " +
                    "pcmConfigured=${pcmDiagnostics["pcmConfigured"]} " +
                    "pcmBuffers=${pcmDiagnostics["pcmBuffersProcessed"]} " +
                    "source=${service?.currentSourceType ?: "idle"}",
            )
            return mapOf(
                "saved" to true,
                "enabled" to enabled,
                "strength" to safeStrength,
                "processorReady" to (service != null),
                "media3Active" to media3Active,
                "sourceType" to (service?.currentSourceType ?: "idle"),
                "playerIsPlaying" to media3Active,
                "playerReady" to (service?.localPlayer != null),
                "soundStageRequestedEnabled" to (service?.speakerSoundstageRequestedEnabled ?: enabled),
                "soundStageApplied" to (service?.pcmAudioProcessor?.soundStageEnabled == true),
                "outputProfile" to (service?.soundstageOutputProfile ?: "unknown"),
                "outputDeviceName" to (service?.soundstageOutputDeviceName ?: "Belum terdeteksi"),
                "outputDeviceType" to (service?.soundstageOutputDeviceType ?: -1),
                "routeDetectionReason" to (service?.soundstageRouteDetectionReason ?: "Layanan audio belum aktif"),
                "message" to when (service?.soundstageOutputProfile) {
                    "speaker_internal" -> if (media3Active && service?.pcmAudioProcessor?.soundStageEnabled == true) {
                        "Speaker internal terdeteksi. MusikKu Soundstage diterapkan pada audio Media3."
                    } else {
                        "Speaker internal terdeteksi. Soundstage akan memproses saat audio Media3 diputar."
                    }
                    "external_output" -> "Headset/perangkat eksternal terdeteksi. DSP MusikKu bypass agar efek audio sistem seperti Dolby tidak bertumpuk."
                    else -> "Profil disimpan. Rute audio belum dapat dipastikan; DSP dinonaktifkan sementara demi keamanan audio."
                },
            ) + pcmDiagnostics
        }

        fun getSpeakerSoundstageStatusStatic(): Map<String, Any?> {
            val service = activeInstance
                ?: return mapOf(
                    "serviceAttached" to false,
                    "sourceType" to "idle",
                    "playerIsPlaying" to false,
                    "pcmConfigured" to false,
                    "pcmBuffersProcessed" to 0L,
                    "soundStageBuffersProcessed" to 0L,
                    "configuredFormat" to "Belum ada layanan Media3",
                    "unsupportedFormatReason" to "PlaybackService belum aktif",
                    "soundStageRequestedEnabled" to false,
                    "soundStageApplied" to false,
                    "outputProfile" to "unknown",
                    "outputDeviceName" to "Belum terdeteksi",
                    "outputDeviceType" to -1,
                    "routeDetectionReason" to "Layanan audio belum aktif",
                    "autoOutputSwitching" to true,
                )
            val status = service.pcmAudioProcessor.diagnostics().toMutableMap()
            status["serviceAttached"] = true
            status["sourceType"] = service.currentSourceType
            status["playerReady"] = service.localPlayer != null
            status["playerIsPlaying"] = service.localPlayer?.isPlaying == true
            status["currentVideoId"] = service.currentVideoId
            status["soundStageRequestedEnabled"] = service.speakerSoundstageRequestedEnabled
            status["soundStageApplied"] = service.pcmAudioProcessor.soundStageEnabled
            status["outputProfile"] = service.soundstageOutputProfile
            status["outputDeviceName"] = service.soundstageOutputDeviceName
            status["outputDeviceType"] = service.soundstageOutputDeviceType
            status["routeDetectionReason"] = service.soundstageRouteDetectionReason
            status["autoOutputSwitching"] = true
            return status
        }

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
        fun clearNativeGaplessQueueStatic(): Boolean =
            activeInstance?.clearNativeGaplessQueue() == true

        fun appendYoutubeGaplessQueueStatic(
            currentVideoId: String,
            tracks: List<Map<String, Any?>>,
        ): Map<String, Any?> = activeInstance?.appendYoutubeGaplessQueue(currentVideoId, tracks)
            ?: mapOf("appended" to 0, "reason" to "service_not_active")

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
            gaplessQueue: List<Map<String, String>> = emptyList(),
            fromAndroidAuto: Boolean = false,
            androidAutoBrowseParentId: String = "",
            androidAutoBrowseSearchQuery: String = "",
            androidAutoNextBrowsePosition: Int = -1,
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
                putExtra("androidAutoBrowseQueue", fromAndroidAuto)
                putExtra("androidAutoBrowseParentId", androidAutoBrowseParentId)
                putExtra("androidAutoBrowseSearchQuery", androidAutoBrowseSearchQuery)
                putExtra("androidAutoNextBrowsePosition", androidAutoNextBrowsePosition)
                putExtra("streamHeaders", Bundle().apply {
                    streamHeaders.forEach { (key, value) -> putString(key, value) }
                })
                val queueBundles = ArrayList<Bundle>()
                gaplessQueue.take(60).forEach { track ->
                    queueBundles += Bundle().apply {
                        putString("videoId", track["videoId"].orEmpty())
                        putString("title", track["title"].orEmpty())
                        putString("artist", track["artist"].orEmpty())
                        putString("mediaUri", track["mediaUri"].orEmpty())
                    }
                }
                putParcelableArrayListExtra("gaplessQueue", queueBundles)
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
    private val pcmAudioProcessor = MusikKuPcmAudioProcessor()

    // The user's Soundstage preference is global, but the DSP is only applied
    // to the built-in speaker route. External outputs are deliberately kept
    // dry so Samsung/OEM headphone effects (including Dolby, when supported)
    // are not stacked with MusikKu's PCM processing.
    @Volatile private var speakerSoundstageRequestedEnabled = false
    @Volatile private var soundstageOutputProfile = "unknown"
    @Volatile private var soundstageOutputDeviceName = "Belum terdeteksi"
    @Volatile private var soundstageOutputDeviceType = -1
    @Volatile private var soundstageRouteDetectionReason = "Menunggu deteksi output Android"
    private val soundstageRouteHandler = Handler(Looper.getMainLooper())
    private val soundstageRouteRefreshRunnable = Runnable { refreshSoundstageOutputProfile() }

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

    // Auto-resume hanya boleh aktif bila Bluetooth output terputus ketika
    // musik sedang berjalan, lalu perangkat Bluetooth tersambung kembali.
    private var audioDeviceCallback: AudioDeviceCallback? = null
    private var pendingBluetoothReconnect = false
    private var pendingBluetoothTrackId = ""
    private var pendingBluetoothSinceMs = 0L
    private var recentlyNoisyPauseAtMs = 0L
    private var recentlyNoisyWasPlaying = false
    private val bluetoothResumeHandler = Handler(Looper.getMainLooper())
    private val clearBluetoothResumeRunnable = Runnable {
        clearPendingBluetoothResume()
    }

    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AudioManager.ACTION_AUDIO_BECOMING_NOISY) return

            val now = SystemClock.elapsedRealtime()
            val backendActuallyPlaying = localPlayer?.isPlaying == true
            val wasPlayingBeforeRouteLoss = currentPlaying || backendActuallyPlaying
            if (!wasPlayingBeforeRouteLoss) return
            recentlyNoisyPauseAtMs = now
            recentlyNoisyWasPlaying = true
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

    private fun isBluetoothOutput(device: AudioDeviceInfo): Boolean {
        if (!device.isSink) return false
        return when (device.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
            AudioDeviceInfo.TYPE_BLE_BROADCAST -> true
            else -> false
        }
    }

    private fun isBluetoothAutoResumeEnabled(): Boolean {
        return try {
            // shared_preferences Flutter menggunakan nama file ini dan prefix
            // "flutter." untuk key default. Tidak ada data yang dikirim keluar.
            getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                .getBoolean("flutter.bluetooth_auto_resume_v1", false)
        } catch (_: Exception) {
            false
        }
    }

    private fun armBluetoothAutoResume() {
        if (!isBluetoothAutoResumeEnabled()) return
        if (currentVideoId.isBlank()) return

        pendingBluetoothReconnect = true
        pendingBluetoothTrackId = currentVideoId
        pendingBluetoothSinceMs = SystemClock.elapsedRealtime()
        bluetoothResumeHandler.removeCallbacks(clearBluetoothResumeRunnable)
        bluetoothResumeHandler.postDelayed(clearBluetoothResumeRunnable, 60_000L)
        MusikKuLogger.d(TAG, "BLUETOOTH DISCONNECTED DURING PLAYBACK -> waiting for reconnect")
    }

    private fun clearPendingBluetoothResume() {
        pendingBluetoothReconnect = false
        pendingBluetoothTrackId = ""
        pendingBluetoothSinceMs = 0L
        bluetoothResumeHandler.removeCallbacks(clearBluetoothResumeRunnable)
    }

    private fun resumeAfterBluetoothReconnect() {
        if (!pendingBluetoothReconnect) return
        if (!isBluetoothAutoResumeEnabled()) {
            clearPendingBluetoothResume()
            return
        }
        if (pendingBluetoothTrackId != currentVideoId || currentVideoId.isBlank()) {
            clearPendingBluetoothResume()
            return
        }
        if (currentPlaying || localPlayer?.isPlaying == true) {
            clearPendingBluetoothResume()
            return
        }
        if (SystemClock.elapsedRealtime() - pendingBluetoothSinceMs > 60_000L) {
            clearPendingBluetoothResume()
            return
        }

        clearPendingBluetoothResume()
        MusikKuLogger.d(TAG, "BLUETOOTH RECONNECTED -> resuming current track")
        if (isAudioPlayerSource()) {
            ensureLocalPlayer()
            localPlayer?.play()
        } else {
            val youtubeView = YoutubePlatformView.instance
            if (youtubeView != null) {
                youtubeView.play()
            } else {
                sendCommandToFlutter("notificationPlayPause")
            }
        }
    }

    private fun isBuiltInSpeaker(device: AudioDeviceInfo): Boolean {
        if (!device.isSink) return false
        return device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE)
    }

    private fun externalOutputPriority(device: AudioDeviceInfo): Int = when (device.type) {
        AudioDeviceInfo.TYPE_WIRED_HEADSET,
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
        AudioDeviceInfo.TYPE_USB_HEADSET -> 0
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> 1
        AudioDeviceInfo.TYPE_BLE_HEADSET -> 1
        AudioDeviceInfo.TYPE_USB_DEVICE,
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> 2
        AudioDeviceInfo.TYPE_HDMI,
        AudioDeviceInfo.TYPE_HDMI_ARC,
        AudioDeviceInfo.TYPE_HDMI_EARC,
        AudioDeviceInfo.TYPE_LINE_ANALOG,
        AudioDeviceInfo.TYPE_LINE_DIGITAL,
        AudioDeviceInfo.TYPE_DOCK,
        AudioDeviceInfo.TYPE_AUX_LINE,
        AudioDeviceInfo.TYPE_BUS,
        AudioDeviceInfo.TYPE_HEARING_AID -> 3
        AudioDeviceInfo.TYPE_BLE_SPEAKER,
        AudioDeviceInfo.TYPE_BLE_BROADCAST -> 4
        else -> 5
    }

    private data class SoundstageOutputRoute(
        val profile: String,
        val name: String,
        val type: Int,
        val reason: String,
    )

    /**
     * Resolves an output profile from an explicit user route, when configured,
     * otherwise from Android's currently connected output-device topology.
     * Android's public AudioDeviceCallback reports connection changes, not a
     * universal active-media-route getter; when the route is ambiguous this
     * method fails safe and bypasses Soundstage rather than double-processing
     * a headset/external output.
     */
    private fun resolveSoundstageOutputRoute(): SoundstageOutputRoute {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return SoundstageOutputRoute(
                "unknown", "Output Android tidak tersedia", -1,
                "Deteksi output otomatis membutuhkan Android 6.0 atau lebih baru.",
            )
        }

        return try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .filter { it.isSink }
            val preferences = getSharedPreferences("musikku_playback_settings", Context.MODE_PRIVATE)
            val preferredId = preferences.getInt("preferredAudioOutputId", -1)
            val preferredType = preferences.getInt("preferredAudioOutputType", -1)
            val preferredName = preferences.getString("preferredAudioOutputName", "").orEmpty()

            val explicitlySelected = if (preferredId >= 0) {
                outputs.firstOrNull { it.id == preferredId }
                    ?: outputs.firstOrNull {
                        it.type == preferredType &&
                            (preferredName.isBlank() || it.productName?.toString().orEmpty() == preferredName)
                    }
            } else {
                null
            }

            val selected = explicitlySelected ?: outputs
                .filterNot {
                    isBuiltInSpeaker(it) || it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE
                }
                .sortedWith(compareBy<AudioDeviceInfo> { externalOutputPriority(it) }.thenBy { it.id })
                .firstOrNull()
                ?: outputs.firstOrNull(::isBuiltInSpeaker)
                ?: outputs.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE }

            if (selected == null) {
                SoundstageOutputRoute(
                    "unknown", "Output tidak diketahui", -1,
                    "Android belum melaporkan speaker internal atau perangkat output yang dapat dikenali.",
                )
            } else if (isBuiltInSpeaker(selected)) {
                SoundstageOutputRoute(
                    "speaker_internal",
                    selected.productName?.toString()?.ifBlank { "Speaker bawaan HP" } ?: "Speaker bawaan HP",
                    selected.type,
                    if (explicitlySelected != null) "Speaker internal dipilih secara manual." else
                        "Tidak ada output eksternal yang terdeteksi; memakai speaker internal Android.",
                )
            } else {
                SoundstageOutputRoute(
                    "external_output",
                    selected.productName?.toString()?.ifBlank { "Headset / perangkat eksternal" }
                        ?: "Headset / perangkat eksternal",
                    selected.type,
                    if (explicitlySelected != null) "Output eksternal dipilih secara manual; DSP MusikKu dibypass." else
                        "Output eksternal tersedia. DSP MusikKu dibypass untuk menghindari penumpukan efek OEM.",
                )
            }
        } catch (error: Exception) {
            SoundstageOutputRoute(
                "unknown", "Output tidak diketahui", -1,
                error.message ?: "Gagal mendeteksi rute output Android.",
            )
        }
    }

    private fun refreshSoundstageOutputProfile() {
        val route = resolveSoundstageOutputRoute()
        soundstageOutputProfile = route.profile
        soundstageOutputDeviceName = route.name
        soundstageOutputDeviceType = route.type
        soundstageRouteDetectionReason = route.reason

        val shouldApplySoundstage = speakerSoundstageRequestedEnabled && route.profile == "speaker_internal"
        val wasApplied = pcmAudioProcessor.soundStageEnabled
        pcmAudioProcessor.soundStageEnabled = shouldApplySoundstage
        if (wasApplied != shouldApplySoundstage) {
            pcmAudioProcessor.resetForNewTrack()
        }

        MusikKuLogger.d(
            TAG,
            "AUTO AUDIO PROFILE requested=$speakerSoundstageRequestedEnabled profile=${route.profile} " +
                "device=${route.name} type=${route.type} soundstageApplied=$shouldApplySoundstage reason=${route.reason}",
        )
    }

    private fun scheduleSoundstageOutputRefresh(delayMs: Long = 300L) {
        soundstageRouteHandler.removeCallbacks(soundstageRouteRefreshRunnable)
        soundstageRouteHandler.postDelayed(soundstageRouteRefreshRunnable, delayMs)
    }

    private fun registerAudioDeviceCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M || audioDeviceCallback != null) {
            return
        }

        val callback = object : AudioDeviceCallback() {
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                scheduleSoundstageOutputRefresh()
                val removedIds = removedDevices.map { it.id }.toSet()
                val preferredId = getSharedPreferences(
                    "musikku_playback_settings", Context.MODE_PRIVATE,
                ).getInt("preferredAudioOutputId", -1)
                if (preferredId >= 0 && preferredId in removedIds && isAudioPlayerSource()) {
                    // Let Android select its default route while the preferred
                    // device is absent. Keep the saved preference so it can be
                    // restored when the same device reconnects.
                    applyPreferredAudioOutput(-1)
                }

                val bluetoothRemoved = removedDevices.any(::isBluetoothOutput)
                if (!bluetoothRemoved) return

                val now = SystemClock.elapsedRealtime()
                val playbackWasActive = currentPlaying || localPlayer?.isPlaying == true
                val pausedByRecentRouteChange = recentlyNoisyWasPlaying &&
                    now - recentlyNoisyPauseAtMs <= 3_000L
                if (playbackWasActive || pausedByRecentRouteChange) {
                    armBluetoothAutoResume()
                }
            }

            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>) {
                scheduleSoundstageOutputRefresh()
                val preferredId = getSharedPreferences(
                    "musikku_playback_settings", Context.MODE_PRIVATE,
                ).getInt("preferredAudioOutputId", -1)
                if (preferredId >= 0 && isAudioPlayerSource()) {
                    bluetoothResumeHandler.postDelayed({ applyPreferredAudioOutput(preferredId) }, 250L)
                }
                if (!pendingBluetoothReconnect || !addedDevices.any(::isBluetoothOutput)) return

                // Tunggu sebentar agar Android menyelesaikan perpindahan route
                // sebelum playback dimulai kembali.
                bluetoothResumeHandler.postDelayed({
                    resumeAfterBluetoothReconnect()
                }, 650L)
            }
        }

        audioDeviceCallback = callback
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.registerAudioDeviceCallback(callback, Handler(Looper.getMainLooper()))
        scheduleSoundstageOutputRefresh(150L)
    }

    private fun unregisterAudioDeviceCallback() {
        val callback = audioDeviceCallback ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager.unregisterAudioDeviceCallback(callback)
            } catch (_: Exception) {
                // Service shutdown can race with audio framework teardown.
            }
        }
        audioDeviceCallback = null
        clearPendingBluetoothResume()
    }

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
    private var androidAutoBrowseQueue = false
    private var androidAutoBrowseParentId = ""
    private var androidAutoBrowseSearchQuery = ""
    private var androidAutoNextBrowsePosition = -1
    private var androidAutoBrowseQueueLoading = false
    private var androidAutoBrowseGeneration = 0L
    private var currentMediaUri = ""
    private var currentLocalMediaId = ""
    private var currentStreamHeaders: Map<String, String> = emptyMap()
    private data class GaplessLocalTrack(
        val videoId: String, val title: String, val artist: String, val mediaUri: String,
    )
    private data class GaplessRemoteTrack(
        val videoId: String,
        val title: String,
        val artist: String,
        val thumbnailUrl: String,
        val streamUrl: String,
        val headers: Map<String, String>,
        val durationMs: Long,
    )
    private var pendingGaplessQueue: List<GaplessLocalTrack> = emptyList()
    private val gaplessRemoteTracks = linkedMapOf<String, GaplessRemoteTrack>()
    private var nativeGaplessQueueIds: Set<String> = emptySet()
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

    private val androidAutoBrowseExecutor = Executors.newSingleThreadExecutor()
    // Stream extraction can involve slow network work; keep it off the same
    // executor that serves Android Auto's catalogue pages and search results.
    private val androidAutoResolveExecutor = Executors.newSingleThreadExecutor()
    private val androidAutoMainHandler = Handler(Looper.getMainLooper())
    private val audioLibraryObserver = object : ContentObserver(androidAutoMainHandler) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            notifyChildrenChanged(BROWSE_ROOT_ID)
            notifyChildrenChanged(BROWSE_SONGS_ID)
            notifyChildrenChanged(BROWSE_RECENT_ID)
            notifyChildrenChanged(BROWSE_ARTISTS_ID)
            notifyChildrenChanged(BROWSE_ALBUMS_ID)
        }
    }
    private var audioLibraryObserverRegistered = false
    private var savedPlaylistPreferences: android.content.SharedPreferences? = null
    private var savedPlaylistPreferenceListener: android.content.SharedPreferences.OnSharedPreferenceChangeListener? = null

    private var notificationTitle = ""
    private var notificationArtist = ""
    private var notificationPlaying = false
    private var notificationDurationMs = 0L
    private var lastWidgetUpdateAtMs = 0L
    private var lastWidgetStateKey = ""

    private fun registerAudioLibraryObserver() {
        if (audioLibraryObserverRegistered) return
        runCatching {
            contentResolver.registerContentObserver(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                true,
                audioLibraryObserver,
            )
            audioLibraryObserverRegistered = true
        }.onFailure { MusikKuLogger.w(TAG, "MediaStore observer registration failed", it) }
    }

    private fun unregisterAudioLibraryObserver() {
        if (!audioLibraryObserverRegistered) return
        runCatching { contentResolver.unregisterContentObserver(audioLibraryObserver) }
        audioLibraryObserverRegistered = false
    }

    private fun registerSavedPlaylistObserver() {
        if (savedPlaylistPreferenceListener != null) return
        val preferences = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val listener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "flutter.playlists_v1") {
                androidAutoMainHandler.post {
                    notifyChildrenChanged(BROWSE_ROOT_ID)
                    notifyChildrenChanged(BROWSE_PLAYLISTS_ID)
                    readSavedPlaylists().forEach { playlist ->
                        val id = playlist.optString("id")
                        if (id.isNotBlank()) notifyChildrenChanged("app_playlist:${Uri.encode(id)}")
                    }
                }
            }
        }
        savedPlaylistPreferences = preferences
        savedPlaylistPreferenceListener = listener
        preferences.registerOnSharedPreferenceChangeListener(listener)
    }

    private fun unregisterSavedPlaylistObserver() {
        val preferences = savedPlaylistPreferences
        val listener = savedPlaylistPreferenceListener
        if (preferences != null && listener != null) {
            runCatching { preferences.unregisterOnSharedPreferenceChangeListener(listener) }
        }
        savedPlaylistPreferences = null
        savedPlaylistPreferenceListener = null
    }

    private data class SavedPlaylistTrack(
        val videoId: String,
        val title: String,
        val artist: String,
        val thumbnailUrl: String,
        val sourceType: String,
        val mediaUri: String,
        val offlinePath: String,
        val durationMs: Long,
        val position: Int,
    )

    private data class ResolvedPlaylistTrack(
        val mediaId: String,
        val videoId: String,
        val title: String,
        val artist: String,
        val thumbnailUrl: String,
        val mediaUri: String,
        val durationMs: Long,
        val isRemote: Boolean,
        val headers: Map<String, String>,
    )

    private val androidAutoPlaylistMediaTracks = linkedMapOf<String, ResolvedPlaylistTrack>()
    private var androidAutoCustomPlaylistId = ""

    private data class BrowseAudioTrack(
        val id: Long,
        val title: String,
        val artist: String,
        val album: String,
        val durationMs: Long,
        val albumId: Long,
    ) {
        val mediaUri: Uri get() = ContentUris.withAppendedId(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            id,
        )

        val artworkUri: Uri get() = ContentUris.withAppendedId(
            Uri.parse("content://media/external/audio/albumart"),
            albumId,
        )
    }

    private fun hasAudioLibraryPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 33) {
            android.Manifest.permission.READ_MEDIA_AUDIO
        } else {
            android.Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return ContextCompat.checkSelfPermission(this, permission) == android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    override fun onGetRoot(
        clientPackageName: String,
        clientUid: Int,
        rootHints: Bundle?,
    ): BrowserRoot? {
        return BrowserRoot(BROWSE_ROOT_ID, null)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<List<MediaBrowserCompat.MediaItem>>,
    ) {
        onLoadChildren(parentId, result, Bundle.EMPTY)
    }

    override fun onLoadChildren(
        parentId: String,
        result: Result<List<MediaBrowserCompat.MediaItem>>,
        options: Bundle,
    ) {
        // MediaStore queries must not block the Android Auto browser's UI thread.
        // Support the standard MediaBrowser page options so large libraries are
        // browsable without returning an unbounded list in one binder response.
        val page = options.getInt(MediaBrowserCompat.EXTRA_PAGE, 0).coerceAtLeast(0)
        val pageSize = options.getInt(MediaBrowserCompat.EXTRA_PAGE_SIZE, 50).coerceIn(1, 100)
        result.detach()
        androidAutoBrowseExecutor.execute {
            val items = runCatching { loadBrowseChildren(parentId, page, pageSize) }
                .onFailure { MusikKuLogger.w(TAG, "Android Auto browse failed for $parentId", it) }
                .getOrDefault(emptyList())
            androidAutoMainHandler.post {
                runCatching { result.sendResult(items) }
                    .onFailure { MusikKuLogger.w(TAG, "Android Auto result delivery failed for $parentId", it) }
            }
        }
    }

    private fun browseOffset(page: Int, pageSize: Int): Int =
        (page.toLong().coerceAtLeast(0L) * pageSize.coerceIn(1, 100).toLong())
            .coerceAtMost(Int.MAX_VALUE.toLong())
            .toInt()

    private fun loadBrowseChildren(
        parentId: String,
        page: Int,
        pageSize: Int,
    ): List<MediaBrowserCompat.MediaItem> {
        if (parentId == BROWSE_ROOT_ID) {
            val items = mutableListOf<MediaBrowserCompat.MediaItem>()
            if (currentVideoId.isNotBlank()) {
                items += playableBrowseItem(
                    mediaId = "now_playing",
                    title = "Sedang diputar",
                    artist = currentTitle,
                    album = currentArtist,
                    durationMs = currentDurationMs,
                    artworkUri = currentThumbnailUrl.takeIf { it.startsWith("https://") }?.let(Uri::parse),
                )
            }
            val librarySubtitle = if (hasAudioLibraryPermission()) {
                "Koleksi audio perangkat"
            } else {
                "Buka MusikKu dan izinkan akses musik"
            }
            items += browsableItem(BROWSE_SONGS_ID, "Semua lagu", librarySubtitle)
            items += browsableItem(
                BROWSE_RECENT_ID,
                "Baru ditambahkan",
                if (hasAudioLibraryPermission()) "Lagu yang terakhir masuk ke perangkat" else librarySubtitle,
            )
            items += browsableItem(BROWSE_ARTISTS_ID, "Artis", librarySubtitle)
            items += browsableItem(BROWSE_ALBUMS_ID, "Album", librarySubtitle)
            items += browsableItem(BROWSE_PLAYLISTS_ID, "Playlist MusikKu", "Playlist yang dibuat di aplikasi")
            return items
        }

        if (!hasAudioLibraryPermission() &&
            parentId != BROWSE_PLAYLISTS_ID &&
            !parentId.startsWith("app_playlist:")
        ) return emptyList()

        return when {
            parentId == BROWSE_SONGS_ID -> {
                val offset = browseOffset(page, pageSize)
                queryBrowseTracks(parentId, limit = pageSize, offset = offset)
                    .mapIndexed { index, track -> trackBrowseItem(track, parentId, offset + index) }
            }
            parentId == BROWSE_RECENT_ID -> {
                val offset = browseOffset(page, pageSize)
                queryBrowseTracks(parentId, limit = pageSize, offset = offset, recentFirst = true)
                    .mapIndexed { index, track -> trackBrowseItem(track, parentId, offset + index) }
            }
            parentId == BROWSE_ARTISTS_ID -> queryArtists(page, pageSize)
            parentId == BROWSE_ALBUMS_ID -> queryAlbums(page, pageSize)
            parentId.startsWith("artist:") || parentId.startsWith("album:") -> {
                val offset = browseOffset(page, pageSize)
                queryBrowseTracks(parentId, limit = pageSize, offset = offset)
                    .mapIndexed { index, track -> trackBrowseItem(track, parentId, offset + index) }
            }
            parentId == BROWSE_PLAYLISTS_ID -> loadSavedPlaylistFolders(page, pageSize)
            parentId.startsWith("app_playlist:") -> loadSavedPlaylistSongs(
                Uri.decode(parentId.removePrefix("app_playlist:")), page, pageSize,
            )
            else -> emptyList()
        }
    }

    private fun readSavedPlaylists(): List<org.json.JSONObject> {
        val raw = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.playlists_v1", null) ?: return emptyList()
        return runCatching {
            val array = org.json.JSONArray(raw)
            buildList {
                for (index in 0 until array.length()) {
                    val item = array.optJSONObject(index) ?: continue
                    if (item.optString("id").isNotBlank()) add(item)
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun savedPlaylistTracks(playlistId: String): List<SavedPlaylistTrack> {
        val playlist = readSavedPlaylists().firstOrNull { it.optString("id") == playlistId }
            ?: return emptyList()
        val songs = playlist.optJSONArray("songs") ?: return emptyList()
        return buildList {
            for (index in 0 until songs.length()) {
                val song = songs.optJSONObject(index) ?: continue
                val videoId = song.optString("videoId").trim()
                if (videoId.isBlank()) continue
                val durationSeconds = song.optDouble("durationSeconds", 0.0)
                val durationMs = if (durationSeconds.isFinite() && durationSeconds > 0.0) {
                    (durationSeconds.coerceAtMost(86400.0) * 1000.0).toLong()
                } else 0L
                add(
                    SavedPlaylistTrack(
                        videoId = videoId,
                        title = song.optString("title", "Tanpa judul").take(256),
                        artist = song.optString("channelTitle", "Artis tidak diketahui").take(160),
                        thumbnailUrl = song.optString("thumbnailUrl").take(2048),
                        sourceType = song.optString("sourceType", "youtube"),
                        mediaUri = song.optString("mediaUri").take(4096),
                        offlinePath = song.optString("offlinePath").take(4096),
                        durationMs = durationMs,
                        position = index,
                    ),
                )
            }
        }
    }

    private fun loadSavedPlaylistFolders(page: Int, pageSize: Int): List<MediaBrowserCompat.MediaItem> {
        val playlists = readSavedPlaylists()
        val offset = browseOffset(page, pageSize)
        return playlists.drop(offset).take(pageSize).map { playlist ->
            val id = playlist.optString("id")
            val name = playlist.optString("name", "Playlist").ifBlank { "Playlist" }
            val count = playlist.optJSONArray("songs")?.length() ?: 0
            browsableItem("app_playlist:${Uri.encode(id)}", name.take(120), "$count lagu")
        }
    }

    private fun loadSavedPlaylistSongs(
        playlistId: String,
        page: Int,
        pageSize: Int,
    ): List<MediaBrowserCompat.MediaItem> {
        val tracks = savedPlaylistTracks(playlistId)
        val offset = browseOffset(page, pageSize)
        return tracks.filter { it.position >= offset }.take(pageSize).map { track ->
            playableBrowseItem(
                mediaId = "app_track|${Uri.encode(playlistId)}|${track.position}|${Uri.encode(track.videoId)}",
                title = track.title,
                artist = track.artist,
                album = "Playlist MusikKu",
                durationMs = track.durationMs,
                artworkUri = track.thumbnailUrl.takeIf { it.startsWith("https://") }?.let(Uri::parse),
            )
        }
    }

    private fun resolveSavedPlaylistTrack(track: SavedPlaylistTrack): ResolvedPlaylistTrack? {
        val mediaId = "${track.videoId}@${track.position}"
        val appData = File(applicationInfo.dataDir).canonicalFile
        val offlineFile = track.offlinePath.takeIf { it.isNotBlank() }?.let { raw ->
            runCatching { File(raw).canonicalFile }.getOrNull()?.takeIf { file ->
                val parent = file.parentFile
                file.isFile && parent?.name == "Offline" &&
                    parent.parentFile?.name == "MusikKu" &&
                    file.path.startsWith(appData.path + File.separator)
            }
        }
        if (offlineFile != null) {
            return ResolvedPlaylistTrack(
                mediaId, track.videoId, track.title, track.artist, track.thumbnailUrl,
                Uri.fromFile(offlineFile).toString(), track.durationMs, false, emptyMap(),
            )
        }

        if (track.sourceType == "local" || track.videoId.startsWith("local:")) {
            val parsed = runCatching { Uri.parse(track.mediaUri) }.getOrNull() ?: return null
            if (parsed.scheme !in setOf("content", "file")) return null
            return ResolvedPlaylistTrack(
                mediaId, track.videoId, track.title, track.artist, track.thumbnailUrl,
                parsed.toString(), track.durationMs, false, emptyMap(),
            )
        }

        if (!track.videoId.matches(Regex("[A-Za-z0-9_-]{11}"))) return null
        val resolved = NewPipeExtractorBridge.resolveAudioForPlayback(track.videoId)
        val streamUrl = resolved["streamUrl"]?.toString()?.trim().orEmpty()
        val uri = runCatching { Uri.parse(streamUrl) }.getOrNull() ?: return null
        val host = uri.host?.lowercase().orEmpty()
        if (uri.scheme != "https" ||
            (host != "googlevideo.com" && !host.endsWith(".googlevideo.com")) ||
            (uri.port != -1 && uri.port != 443) || uri.encodedAuthority?.contains('@') == true || !uri.fragment.isNullOrEmpty()) {
            return null
        }
        val rawHeaders = resolved["headers"] as? Map<*, *> ?: emptyMap<Any, Any>()
        val headers = rawHeaders.mapNotNull { (key, value) ->
            val name = key?.toString()?.trim().orEmpty()
            val content = value?.toString()?.trim().orEmpty()
            if (name.lowercase() !in setOf("user-agent", "referer", "origin") ||
                content.isBlank() || content.length > 2048 || content.any { it == '\r' || it == '\n' }) {
                null
            } else name to content
        }.toMap()
        return ResolvedPlaylistTrack(
            mediaId, track.videoId, track.title, track.artist, track.thumbnailUrl,
            streamUrl, track.durationMs, true, headers,
        )
    }

    private fun createSavedPlaylistMediaSource(track: ResolvedPlaylistTrack): androidx.media3.exoplayer.source.MediaSource {
        val item = MediaItem.Builder()
            .setMediaId(track.mediaId)
            .setUri(Uri.parse(track.mediaUri))
            .setMediaMetadata(
                MediaMetadata.Builder().setTitle(track.title).setArtist(track.artist).build(),
            )
            .build()
        val factory = if (track.isRemote) {
            val http = DefaultHttpDataSource.Factory()
                .setDefaultRequestProperties(track.headers)
                .setAllowCrossProtocolRedirects(false)
            DefaultMediaSourceFactory(DefaultDataSource.Factory(this, http))
        } else {
            DefaultMediaSourceFactory(this)
        }
        return factory.createMediaSource(item)
    }

    private fun playFromSavedPlaylist(playlistId: String, position: Int, expectedVideoId: String) {
        if (position < 0) return
        val generation = ++androidAutoBrowseGeneration
        androidAutoBrowseQueueLoading = true
        androidAutoResolveExecutor.execute {
            val tracks = savedPlaylistTracks(playlistId)
            val selected = tracks.firstOrNull { it.position == position }
            if (selected == null || selected.videoId != expectedVideoId) {
                androidAutoMainHandler.post { androidAutoBrowseQueueLoading = false }
                return@execute
            }
            val resolvedTracks = mutableListOf<ResolvedPlaylistTrack>()
            var nextPosition = position
            for (track in tracks.filter { it.position >= position }.take(12)) {
                nextPosition = track.position + 1
                val resolved = runCatching { resolveSavedPlaylistTrack(track) }
                    .onFailure { MusikKuLogger.w(TAG, "Android Auto playlist track resolve failed: ${track.videoId}", it) }
                    .getOrNull()
                if (resolved != null) resolvedTracks += resolved
                // Do not block a head unit for too long; build a rolling batch.
                if (resolvedTracks.size >= 6) break
            }
            androidAutoMainHandler.post {
                if (generation != androidAutoBrowseGeneration) return@post
                androidAutoBrowseQueueLoading = false
                val first = resolvedTracks.firstOrNull()?.takeIf { it.videoId == selected.videoId }
                    ?: return@post
                val player = localPlayer ?: return@post
                androidAutoPlaylistMediaTracks.clear()
                gaplessRemoteTracks.clear()
                resolvedTracks.forEach { track ->
                    androidAutoPlaylistMediaTracks[track.mediaId] = track
                    if (track.isRemote) {
                        gaplessRemoteTracks[track.mediaId] = GaplessRemoteTrack(
                            videoId = track.videoId,
                            title = track.title,
                            artist = track.artist,
                            thumbnailUrl = track.thumbnailUrl,
                            streamUrl = track.mediaUri,
                            headers = track.headers,
                            durationMs = track.durationMs,
                        )
                    }
                }
                nativeGaplessQueueIds = resolvedTracks.map { it.mediaId }.toSet()
                androidAutoBrowseQueue = true
                androidAutoBrowseParentId = "app_playlist:${Uri.encode(playlistId)}"
                androidAutoCustomPlaylistId = playlistId
                androidAutoBrowseSearchQuery = ""
                androidAutoNextBrowsePosition = if (nextPosition < tracks.size) nextPosition else -1

                val previousId = currentVideoId
                currentVideoId = first.videoId
                currentTitle = first.title
                currentArtist = first.artist
                currentThumbnailUrl = first.thumbnailUrl
                currentSourceType = if (first.isRemote) "youtube_audio" else "local"
                currentMediaUri = first.mediaUri
                currentStreamHeaders = first.headers
                currentLocalMediaId = if (first.videoId.startsWith("local:")) {
                    first.videoId.removePrefix("local:")
                } else ""
                currentPositionMs = 0L
                currentDurationMs = first.durationMs
                currentPlaying = true
                notificationArtwork = null
                artworkGeneration += 1L
                syncWakeLock()

                runCatching {
                    player.pause()
                    player.clearMediaItems()
                    val sources = resolvedTracks.map(::createSavedPlaylistMediaSource)
                    player.setMediaSources(sources, 0, 0L)
                    player.prepare()
                    player.playWhenReady = true
                }.onFailure {
                    MusikKuLogger.e(TAG, "Gagal menyiapkan playlist MusikKu di Android Auto", it)
                    androidAutoBrowseQueue = false
                    nativeGaplessQueueIds = emptySet()
                    androidAutoPlaylistMediaTracks.clear()
                    gaplessRemoteTracks.clear()
                    return@post
                }
                persistPlaybackSnapshot()
                updateMediaSession()
                notifyChildrenChanged(BROWSE_ROOT_ID)
                loadNotificationArtworkIfNeeded()
                if (!foregroundStarted) {
                    startForeground(NOTIFICATION_ID, createNotification())
                    foregroundStarted = true
                } else {
                    val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    manager.notify(NOTIFICATION_ID, createNotification())
                }
                notificationTitle = currentTitle
                notificationArtist = currentArtist
                notificationPlaying = currentPlaying
                notificationDurationMs = currentDurationMs
                scheduleSnapshotPersistence()
                MusikKuLogger.i(TAG, "Android Auto opened playlist $playlistId at $position (was $previousId)")
            }
        }
    }

    private fun browsableItem(id: String, title: String, subtitle: String): MediaBrowserCompat.MediaItem {
        val description = MediaDescriptionCompat.Builder()
            .setMediaId(id)
            .setTitle(title)
            .setSubtitle(subtitle)
            .build()
        return MediaBrowserCompat.MediaItem(description, MediaBrowserCompat.MediaItem.FLAG_BROWSABLE)
    }

    private fun playableBrowseItem(
        mediaId: String,
        title: String,
        artist: String,
        album: String,
        durationMs: Long,
        artworkUri: Uri?,
    ): MediaBrowserCompat.MediaItem {
        val description = MediaDescriptionCompat.Builder()
            .setMediaId(mediaId)
            .setTitle(title.ifBlank { "Tanpa judul" })
            .setSubtitle(artist)
            .setDescription(album)
            .setIconUri(artworkUri)
            .setExtras(Bundle().apply {
                putLong(MediaMetadataCompat.METADATA_KEY_DURATION, durationMs.coerceAtLeast(0L))
            })
            .build()
        return MediaBrowserCompat.MediaItem(description, MediaBrowserCompat.MediaItem.FLAG_PLAYABLE)
    }

    private fun trackBrowseItem(
        track: BrowseAudioTrack,
        parentId: String,
        positionInParent: Int,
    ): MediaBrowserCompat.MediaItem {
        return playableBrowseItem(
            mediaId = "track$MEDIA_ID_SEPARATOR$parentId$MEDIA_ID_SEPARATOR$positionInParent$MEDIA_ID_SEPARATOR${track.id}",
            title = track.title,
            artist = track.artist,
            album = track.album,
            durationMs = track.durationMs,
            artworkUri = track.artworkUri,
        )
    }

    // Each item remembers its browsed parent so Play from Android Auto
    // rebuilds the same song order (all songs, recently added, artist, album).

    private fun queryBrowseTracks(
        parentId: String,
        limit: Int,
        offset: Int = 0,
        recentFirst: Boolean = false,
        searchQuery: String? = null,
    ): List<BrowseAudioTrack> {
        val resolver = contentResolver
        val collection = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.ALBUM_ID,
        )
        val clauses = mutableListOf("${MediaStore.Audio.Media.IS_MUSIC} != 0")
        val args = mutableListOf<String>()
        when {
            parentId.startsWith("artist:") -> {
                clauses += "${MediaStore.Audio.Media.ARTIST_ID} = ?"
                args += parentId.substringAfter(':')
            }
            parentId.startsWith("album:") -> {
                clauses += "${MediaStore.Audio.Media.ALBUM_ID} = ?"
                args += parentId.substringAfter(':')
            }
        }
        if (!searchQuery.isNullOrBlank()) {
            clauses += "(${MediaStore.Audio.Media.TITLE} LIKE ? ESCAPE '\\' OR ${MediaStore.Audio.Media.ARTIST} LIKE ? ESCAPE '\\')"
            val escaped = searchQuery.trim().replace("%", "\\%").replace("_", "\\_")
            args += "%$escaped%"
            args += "%$escaped%"
        }
        val order = if (recentFirst || parentId == BROWSE_RECENT_ID) {
            "${MediaStore.Audio.Media.DATE_ADDED} DESC, ${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC, ${MediaStore.Audio.Media._ID} ASC"
        } else {
            "${MediaStore.Audio.Media.TITLE} COLLATE NOCASE ASC, ${MediaStore.Audio.Media._ID} ASC"
        }
        val cursor = resolver.query(
            collection,
            projection,
            clauses.joinToString(" AND "),
            args.toTypedArray(),
            "$order LIMIT ${limit.coerceIn(1, 100)} OFFSET ${offset.coerceAtLeast(0)}",
        ) ?: return emptyList()
        cursor.use { c ->
            val idIndex = c.getColumnIndex(MediaStore.Audio.Media._ID)
            val titleIndex = c.getColumnIndex(MediaStore.Audio.Media.TITLE)
            val artistIndex = c.getColumnIndex(MediaStore.Audio.Media.ARTIST)
            val albumIndex = c.getColumnIndex(MediaStore.Audio.Media.ALBUM)
            val durationIndex = c.getColumnIndex(MediaStore.Audio.Media.DURATION)
            val albumIdIndex = c.getColumnIndex(MediaStore.Audio.Media.ALBUM_ID)
            val tracks = ArrayList<BrowseAudioTrack>(c.count.coerceAtMost(limit))
            while (c.moveToNext()) {
                val id = c.getLong(idIndex)
                val title = c.getString(titleIndex)?.trim().orEmpty().ifBlank { "Tanpa judul" }
                tracks += BrowseAudioTrack(
                    id = id,
                    title = title,
                    artist = c.getString(artistIndex)?.trim().orEmpty().ifBlank { "Artis tidak diketahui" },
                    album = c.getString(albumIndex)?.trim().orEmpty(),
                    durationMs = c.getLong(durationIndex).coerceAtLeast(0L),
                    albumId = c.getLong(albumIdIndex),
                )
            }
            return tracks
        }
    }

    private fun queryArtists(page: Int, pageSize: Int): List<MediaBrowserCompat.MediaItem> {
        val projection = arrayOf(
            MediaStore.Audio.Artists._ID,
            MediaStore.Audio.Artists.ARTIST,
            MediaStore.Audio.Artists.NUMBER_OF_TRACKS,
        )
        val cursor = contentResolver.query(
            MediaStore.Audio.Artists.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Artists.NUMBER_OF_TRACKS} > 0",
            null,
            "${MediaStore.Audio.Artists.ARTIST} COLLATE NOCASE ASC, ${MediaStore.Audio.Artists._ID} ASC LIMIT ${pageSize.coerceIn(1, 100)} OFFSET ${browseOffset(page, pageSize)}",
        ) ?: return emptyList()
        cursor.use { c ->
            val idIndex = c.getColumnIndex(MediaStore.Audio.Artists._ID)
            val nameIndex = c.getColumnIndex(MediaStore.Audio.Artists.ARTIST)
            val countIndex = c.getColumnIndex(MediaStore.Audio.Artists.NUMBER_OF_TRACKS)
            val items = mutableListOf<MediaBrowserCompat.MediaItem>()
            while (c.moveToNext()) {
                val id = c.getLong(idIndex)
                val title = c.getString(nameIndex)?.trim().orEmpty().ifBlank { "Artis tidak diketahui" }
                val count = c.getInt(countIndex)
                items += browsableItem("artist:$id", title, "$count lagu")
            }
            return items
        }
    }

    private fun queryAlbums(page: Int, pageSize: Int): List<MediaBrowserCompat.MediaItem> {
        val projection = arrayOf(
            MediaStore.Audio.Albums._ID,
            MediaStore.Audio.Albums.ALBUM,
            MediaStore.Audio.Albums.ARTIST,
            MediaStore.Audio.Albums.NUMBER_OF_SONGS,
        )
        val cursor = contentResolver.query(
            MediaStore.Audio.Albums.EXTERNAL_CONTENT_URI,
            projection,
            "${MediaStore.Audio.Albums.NUMBER_OF_SONGS} > 0",
            null,
            "${MediaStore.Audio.Albums.ALBUM} COLLATE NOCASE ASC, ${MediaStore.Audio.Albums._ID} ASC LIMIT ${pageSize.coerceIn(1, 100)} OFFSET ${browseOffset(page, pageSize)}",
        ) ?: return emptyList()
        cursor.use { c ->
            val idIndex = c.getColumnIndex(MediaStore.Audio.Albums._ID)
            val albumIndex = c.getColumnIndex(MediaStore.Audio.Albums.ALBUM)
            val artistIndex = c.getColumnIndex(MediaStore.Audio.Albums.ARTIST)
            val countIndex = c.getColumnIndex(MediaStore.Audio.Albums.NUMBER_OF_SONGS)
            val items = mutableListOf<MediaBrowserCompat.MediaItem>()
            while (c.moveToNext()) {
                val id = c.getLong(idIndex)
                val title = c.getString(albumIndex)?.trim().orEmpty().ifBlank { "Album tanpa judul" }
                val artist = c.getString(artistIndex)?.trim().orEmpty()
                val count = c.getInt(countIndex)
                items += browsableItem("album:$id", title, listOf(artist, "$count lagu").filter { it.isNotBlank() }.joinToString(" · "))
            }
            return items
        }
    }

    private fun playFromBrowseMediaId(mediaId: String) {
        if (mediaId.startsWith("app_track|")) {
            val parts = mediaId.split("|", limit = 4)
            if (parts.size == 4) {
                val playlistId = Uri.decode(parts[1])
                val position = parts[2].toIntOrNull() ?: return
                val videoId = Uri.decode(parts[3])
                playFromSavedPlaylist(playlistId, position, videoId)
            }
            return
        }
        if (mediaId == "now_playing") {
            if (isAudioPlayerSource()) playAudio() else if (!currentPlaying) sendCommandToFlutter("notificationPlayPause")
            return
        }
        val parts = mediaId.split(MEDIA_ID_SEPARATOR, limit = 4)
        if (parts.size != 4 || parts[0] != "track") return
        val parentId = parts[1]
        val selectedPosition = parts[2].toIntOrNull()?.takeIf { it >= 0 } ?: return
        val selectedId = parts[3].toLongOrNull() ?: return
        if (!hasAudioLibraryPermission()) return
        val tracks = queryBrowseTracks(
            parentId,
            limit = 62,
            offset = selectedPosition,
            recentFirst = parentId == BROWSE_RECENT_ID,
        )
        val selected = tracks.firstOrNull()?.takeIf { it.id == selectedId } ?: return
        val successors = tracks.drop(1).take(60).map { track ->
            mapOf(
                "videoId" to "local:${track.id}",
                "title" to track.title,
                "artist" to track.artist,
                "mediaUri" to track.mediaUri.toString(),
            )
        }
        start(
            context = this,
            videoId = "local:${selected.id}",
            title = selected.title,
            artist = selected.artist,
            thumbnailUrl = selected.artworkUri.toString(),
            playing = true,
            positionSeconds = 0.0,
            durationSeconds = selected.durationMs / 1000.0,
            sourceType = "local",
            mediaUri = selected.mediaUri.toString(),
            gaplessQueue = successors,
            fromAndroidAuto = true,
            androidAutoBrowseParentId = parentId,
            androidAutoNextBrowsePosition = if (tracks.size > 61) selectedPosition + 61 else -1,
        )
    }

    private fun playFromBrowseSearch(query: String?) {
        if (!hasAudioLibraryPermission()) return
        val safeQuery = query?.trim().orEmpty()
        val tracks = queryBrowseTracks(BROWSE_SONGS_ID, limit = 62, searchQuery = safeQuery)
        if (tracks.isEmpty()) return
        val selected = tracks.first()
        val successors = tracks.drop(1).take(60).map { track ->
            mapOf(
                "videoId" to "local:${track.id}",
                "title" to track.title,
                "artist" to track.artist,
                "mediaUri" to track.mediaUri.toString(),
            )
        }
        start(
            context = this,
            videoId = "local:${selected.id}",
            title = selected.title,
            artist = selected.artist,
            thumbnailUrl = selected.artworkUri.toString(),
            playing = true,
            positionSeconds = 0.0,
            durationSeconds = selected.durationMs / 1000.0,
            sourceType = "local",
            mediaUri = selected.mediaUri.toString(),
            gaplessQueue = successors,
            fromAndroidAuto = true,
            androidAutoBrowseParentId = BROWSE_SONGS_ID,
            androidAutoBrowseSearchQuery = safeQuery,
            androidAutoNextBrowsePosition = if (tracks.size > 61) 61 else -1,
        )
    }

    /**
     * Use the native playlist when it is authoritative (Android Auto browse or
     * the app's already-preloaded local gapless queue). Otherwise delegate to
     * Flutter so manual queue, Radio, Shuffle and online-source rules remain
     * the single source of truth.
     */
    private fun maybeAppendAndroidAutoBrowseQueue(player: ExoPlayer) {
        if (!androidAutoBrowseQueue || androidAutoBrowseParentId.isBlank() ||
            androidAutoNextBrowsePosition < 0 || androidAutoBrowseQueueLoading) {
            return
        }
        val remaining = player.mediaItemCount - player.currentMediaItemIndex - 1
        if (remaining > ANDROID_AUTO_PREFETCH_REMAINING) return

        val generation = androidAutoBrowseGeneration
        val parentId = androidAutoBrowseParentId
        val searchQuery = androidAutoBrowseSearchQuery
        val offset = androidAutoNextBrowsePosition
        val recentFirst = parentId == BROWSE_RECENT_ID
        val customPlaylistId = androidAutoCustomPlaylistId
        androidAutoBrowseQueueLoading = true
        androidAutoResolveExecutor.execute {
            if (customPlaylistId.isNotBlank()) {
                val allTracks = savedPlaylistTracks(customPlaylistId)
                val resolved = mutableListOf<ResolvedPlaylistTrack>()
                var nextCustomPosition = offset
                for (track in allTracks.filter { it.position >= offset }.take(12)) {
                    nextCustomPosition = track.position + 1
                    val item = runCatching { resolveSavedPlaylistTrack(track) }
                        .onFailure { MusikKuLogger.w(TAG, "Android Auto playlist prefetch failed: ${track.videoId}", it) }
                        .getOrNull()
                    if (item != null) resolved += item
                    if (resolved.size >= 6) break
                }
                androidAutoMainHandler.post {
                    if (generation != androidAutoBrowseGeneration || player !== localPlayer ||
                        !androidAutoBrowseQueue || androidAutoCustomPlaylistId != customPlaylistId) {
                        return@post
                    }
                    val fresh = resolved.filter { it.mediaId !in nativeGaplessQueueIds }
                    if (fresh.isNotEmpty()) {
                        runCatching {
                            player.addMediaSources(player.mediaItemCount, fresh.map(::createSavedPlaylistMediaSource))
                            fresh.forEach { track ->
                                androidAutoPlaylistMediaTracks[track.mediaId] = track
                                nativeGaplessQueueIds = nativeGaplessQueueIds + track.mediaId
                                if (track.isRemote) {
                                    gaplessRemoteTracks[track.mediaId] = GaplessRemoteTrack(
                                        track.videoId, track.title, track.artist, track.thumbnailUrl,
                                        track.mediaUri, track.headers, track.durationMs,
                                    )
                                }
                            }
                            androidAutoNextBrowsePosition = if (nextCustomPosition < allTracks.size) nextCustomPosition else -1
                        }.onFailure { MusikKuLogger.e(TAG, "Android Auto playlist append failed", it) }
                    } else {
                        androidAutoNextBrowsePosition = if (nextCustomPosition > offset &&
                            allTracks.any { it.position >= nextCustomPosition }) nextCustomPosition else -1
                    }
                    androidAutoBrowseQueueLoading = false
                    if (fresh.isEmpty() && androidAutoNextBrowsePosition >= 0 &&
                        player.currentMediaItem != null && player.mediaItemCount == player.currentMediaItemIndex + 1) {
                        androidAutoMainHandler.postDelayed({ maybeAppendAndroidAutoBrowseQueue(player) }, 180L)
                    }
                }
                return@execute
            }

            val nextTracks = runCatching {
                queryBrowseTracks(
                    parentId,
                    limit = 61,
                    offset = offset,
                    recentFirst = recentFirst,
                    searchQuery = searchQuery.takeIf { it.isNotBlank() },
                )
            }.onFailure {
                MusikKuLogger.w(TAG, "Android Auto queue prefetch failed at $offset", it)
            }.getOrDefault(emptyList())

            androidAutoMainHandler.post {
                if (generation != androidAutoBrowseGeneration || player !== localPlayer ||
                    !androidAutoBrowseQueue || currentSourceType != "local") {
                    return@post
                }
                val appendTracks = nextTracks.take(60)
                if (appendTracks.isNotEmpty()) {
                    val mediaItems = appendTracks.map { track ->
                        createLocalMediaItem(
                            "local:${track.id}",
                            track.title,
                            track.artist,
                            track.mediaUri.toString(),
                        )
                    }
                    player.addMediaItems(player.mediaItemCount, mediaItems)
                    nativeGaplessQueueIds = nativeGaplessQueueIds + appendTracks.map { "local:${it.id}" }
                    androidAutoNextBrowsePosition = if (nextTracks.size > 60) offset + 60 else -1
                } else {
                    androidAutoNextBrowsePosition = -1
                }
                androidAutoBrowseQueueLoading = false
            }
        }
    }

    private fun skipToNextPlayback() {
        val player = localPlayer
        if (androidAutoBrowseQueue) {
            if (player?.hasNextMediaItem() == true) player.seekToNextMediaItem()
            return
        }
        // The app's local gapless queue is authoritative only while a native
        // successor is still loaded. At its end, let Flutter resolve the next
        // item so a mixed playlist can continue with its online track.
        if ((currentSourceType == "local" || currentSourceType == "youtube_audio") &&
            nativeGaplessQueueIds.isNotEmpty() && player?.hasNextMediaItem() == true) {
            player.seekToNextMediaItem()
            return
        }
        sendCommandToFlutter("notificationNext")
    }

    private fun skipToPreviousPlayback() {
        val player = localPlayer
        if (androidAutoBrowseQueue) {
            if (player != null) {
                if (player.currentPosition > 3_000L) {
                    player.seekTo(0L)
                } else if (player.hasPreviousMediaItem()) {
                    player.seekToPreviousMediaItem()
                } else if (androidAutoCustomPlaylistId.isNotBlank()) {
                    // The native queue starts at the selected playlist row, so
                    // the item before that row is not loaded. Resolve it on the
                    // browse worker and rebuild the forward queue from there.
                    val playlistId = androidAutoCustomPlaylistId
                    val currentMediaId = player.currentMediaItem?.mediaId.orEmpty()
                    val currentPosition = currentMediaId.substringAfterLast('@').toIntOrNull()
                    if (currentPosition != null && currentPosition > 0 &&
                        !androidAutoBrowseQueueLoading) {
                        val generation = ++androidAutoBrowseGeneration
                        androidAutoBrowseQueueLoading = true
                        androidAutoBrowseExecutor.execute {
                            val previous = savedPlaylistTracks(playlistId)
                                .firstOrNull { it.position == currentPosition - 1 }
                            androidAutoMainHandler.post {
                                if (generation != androidAutoBrowseGeneration ||
                                    androidAutoCustomPlaylistId != playlistId) return@post
                                androidAutoBrowseQueueLoading = false
                                if (previous != null) {
                                    playFromSavedPlaylist(
                                        playlistId,
                                        previous.position,
                                        previous.videoId,
                                    )
                                }
                            }
                        }
                    }
                }
            }
            return
        }
        // Previous is kept in Flutter for normal app playback because the
        // native gapless playlist contains future tracks, not the full history.
        sendCommandToFlutter("notificationPrevious")
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

                override fun onPlayFromMediaId(mediaId: String?, extras: Bundle?) {
                    if (!mediaId.isNullOrBlank()) playFromBrowseMediaId(mediaId)
                }

                override fun onPlayFromSearch(query: String?, extras: Bundle?) {
                    playFromBrowseSearch(query)
                }

                // Tombol headset / earbuds: play hanya bila sedang pause,
                // pause hanya bila sedang play, supaya tidak salah toggle.
                override fun onPlay() {
                    clearPendingBluetoothResume()
                    if (isAudioPlayerSource()) {
                        localPlayer?.play()
                    } else if (!currentPlaying) {
                        sendCommandToFlutter("notificationPlayPause")
                    }
                }

                override fun onPause() {
                    clearPendingBluetoothResume()
                    recentlyNoisyWasPlaying = false
                    if (isAudioPlayerSource()) {
                        localPlayer?.pause()
                    } else if (currentPlaying) {
                        sendCommandToFlutter("notificationPlayPause")
                    }
                }

                override fun onSkipToNext() {
                    skipToNextPlayback()
                }

                override fun onSkipToPrevious() {
                    skipToPreviousPlayback()
                }

                override fun onSeekTo(pos: Long) {
                    if (isAudioPlayerSource()) seekAudio(pos / 1000.0)
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
        registerAudioDeviceCallback()
        registerAudioLibraryObserver()
        registerSavedPlaylistObserver()
    }


    @OptIn(UnstableApi::class)
    private fun ensureLocalPlayer() {
        if (localPlayer != null) return

        val audioPreferences = getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE,
        )
        pcmAudioProcessor.normalizationEnabled = audioPreferences.getBoolean(
            "flutter.audio_loudness_normalization_v1", false,
        )
        speakerSoundstageRequestedEnabled = audioPreferences.getBoolean(
            "flutter.speaker_soundstage_enabled_v1", false,
        )
        pcmAudioProcessor.soundStageEnabled = false
        pcmAudioProcessor.soundStageStrength = audioPreferences.getInt(
            "flutter.speaker_soundstage_strength_v1", 85,
        ).coerceIn(0, 100)
        val renderersFactory = object : DefaultRenderersFactory(this) {
            @OptIn(UnstableApi::class)
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioOutputPlaybackParameters: Boolean,
            ): AudioSink {
                return DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(false)
                    .setEnableAudioTrackPlaybackParams(enableAudioOutputPlaybackParameters)
                    .setAudioProcessors(arrayOf(pcmAudioProcessor))
                    .build()
            }
        }
        val trackSelector = DefaultTrackSelector(this).apply {
            // Let Media3 select multichannel audio only when Android reports
            // that the current output route can actually spatialize it.
            parameters = buildUponParameters()
                .setConstrainAudioChannelCountToDeviceCapabilities(true)
                .build()
        }

        localPlayer = ExoPlayer.Builder(this, renderersFactory)
            .setTrackSelector(trackSelector)
            .build().also { player ->
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .setSpatializationBehavior(C.SPATIALIZATION_BEHAVIOR_AUTO)
                    .build(),
                true,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val savedOutputId = getSharedPreferences(
                    "musikku_playback_settings", Context.MODE_PRIVATE,
                ).getInt("preferredAudioOutputId", -1)
                applyPreferredAudioOutputToPlayer(player, savedOutputId)
            }
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

                override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                    if (mediaItem == null) return
                    pcmAudioProcessor.resetForNewTrack()
                    val nextId = mediaItem.mediaId
                    if (nextId == currentVideoId || nextId !in nativeGaplessQueueIds) return
                    val appPlaylistTrack = androidAutoPlaylistMediaTracks[nextId]
                    val remoteTrack = gaplessRemoteTracks[nextId]
                    val isRemoteTransition = appPlaylistTrack?.isRemote == true || remoteTrack != null
                    val isLocalTransition = appPlaylistTrack?.isRemote == false ||
                        (appPlaylistTrack == null && currentSourceType == "local" && nextId.startsWith("local:"))
                    if (!isLocalTransition && !isRemoteTransition) return

                    val nextUri = appPlaylistTrack?.mediaUri
                        ?: mediaItem.localConfiguration?.uri?.toString().orEmpty()
                    if (nextUri.isBlank()) return

                    currentVideoId = appPlaylistTrack?.videoId ?: remoteTrack?.videoId ?: nextId
                    currentSourceType = if (isRemoteTransition) "youtube_audio" else "local"
                    currentTitle = appPlaylistTrack?.title
                        ?: mediaItem.mediaMetadata.title?.toString().orEmpty().ifBlank { "Tanpa judul" }
                    currentArtist = appPlaylistTrack?.artist
                        ?: mediaItem.mediaMetadata.artist?.toString().orEmpty()
                    currentThumbnailUrl = appPlaylistTrack?.thumbnailUrl ?: remoteTrack?.thumbnailUrl.orEmpty()
                    currentMediaUri = nextUri
                    currentStreamHeaders = appPlaylistTrack?.headers ?: remoteTrack?.headers ?: emptyMap()
                    currentLocalMediaId = if (isLocalTransition && currentVideoId.startsWith("local:")) {
                        currentVideoId.removePrefix("local:")
                    } else ""
                    currentPositionMs = 0L
                    currentDurationMs = remoteTrack?.durationMs?.takeIf { it > 0L }
                        ?: player.duration.takeIf { it > 0L && it != C.TIME_UNSET }
                        ?: currentDurationMs
                    currentPlaying = player.isPlaying
                    syncWakeLock()
                    notificationArtwork = null
                    artworkGeneration += 1L
                    persistPlaybackSnapshot()
                    updateMediaSession()
                    notifyChildrenChanged("musikku_root")
                    loadNotificationArtworkIfNeeded()
                    emitLocalState(
                        if (player.isPlaying) "playing" else "buffering",
                        trackTransition = true,
                    )
                    if (androidAutoBrowseQueue) maybeAppendAndroidAutoBrowseQueue(player)
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
                            // Android Auto browse queues are authoritative and
                            // must stop at their own playlist boundary. Never
                            // hand their end event to Flutter Radio/auto-next.
                            if (!androidAutoBrowseQueue) {
                                sendCommandToFlutter("notificationLocalEnded")
                            }
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
        refreshSoundstageOutputProfile()
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

    private fun createLocalMediaItem(
        videoId: String,
        title: String,
        artist: String,
        uriString: String,
    ): MediaItem {
        val metadata = MediaMetadata.Builder()
            .setTitle(title.ifBlank { "Tanpa judul" })
            .setArtist(artist)
            .build()
        return MediaItem.Builder()
            .setMediaId(videoId)
            .setUri(Uri.parse(uriString))
            .setMediaMetadata(metadata)
            .build()
    }

    private fun appendYoutubeGaplessQueue(
        expectedCurrentVideoId: String,
        rawTracks: List<Map<String, Any?>>,
    ): Map<String, Any?> {
        val player = localPlayer
            ?: return mapOf("appended" to 0, "reason" to "player_not_ready")
        if (currentSourceType != "youtube_audio" || currentVideoId != expectedCurrentVideoId) {
            return mapOf("appended" to 0, "reason" to "track_changed")
        }

        val seen = (nativeGaplessQueueIds + currentVideoId).toMutableSet()
        val tracks = rawTracks.mapNotNull { raw ->
            val id = raw["videoId"]?.toString()?.trim().orEmpty()
            val url = raw["streamUrl"]?.toString()?.trim().orEmpty()
            val uri = runCatching { Uri.parse(url) }.getOrNull()
            val host = uri?.host?.lowercase().orEmpty()
            val trusted = uri != null && uri.scheme == "https" &&
                (host == "googlevideo.com" || host.endsWith(".googlevideo.com")) &&
                (uri.port == -1 || uri.port == 443) &&
                uri.encodedAuthority?.contains('@') != true &&
                uri.fragment.isNullOrEmpty()
            if (!id.matches(Regex("[A-Za-z0-9_-]{11}")) || !trusted || !seen.add(id)) {
                return@mapNotNull null
            }
            val rawHeaders = raw["headers"] as? Map<*, *> ?: emptyMap<Any, Any>()
            val headers = rawHeaders.mapNotNull { (key, value) ->
                val name = key?.toString()?.trim().orEmpty()
                val data = value?.toString()?.trim().orEmpty()
                if (name.lowercase() !in setOf("user-agent", "referer", "origin") ||
                    data.isBlank() || data.length > 2048 || data.any { it == '\r' || it == '\n' }) {
                    null
                } else name to data
            }.toMap()
            val durationSeconds = (raw["durationSeconds"] as? Number)?.toDouble() ?: 0.0
            GaplessRemoteTrack(
                videoId = id,
                title = raw["title"]?.toString().orEmpty().take(256).ifBlank { "Tanpa judul" },
                artist = raw["artist"]?.toString().orEmpty().take(128),
                thumbnailUrl = raw["thumbnailUrl"]?.toString().orEmpty().take(2048),
                streamUrl = url,
                headers = headers,
                durationMs = if (durationSeconds.isFinite()) (durationSeconds.coerceIn(0.0, 86400.0) * 1000.0).toLong() else 0L,
            )
        }.take(8)

        if (tracks.isEmpty()) return mapOf("appended" to 0, "reason" to "no_valid_tracks")
        return try {
            val sources = tracks.map { track ->
                val metadata = MediaMetadata.Builder()
                    .setTitle(track.title)
                    .setArtist(track.artist)
                    .build()
                val mediaItem = MediaItem.Builder()
                    .setMediaId(track.videoId)
                    .setUri(Uri.parse(track.streamUrl))
                    .setMediaMetadata(metadata)
                    .build()
                val httpFactory = DefaultHttpDataSource.Factory()
                    .setDefaultRequestProperties(track.headers)
                    .setAllowCrossProtocolRedirects(false)
                val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
                DefaultMediaSourceFactory(dataSourceFactory).createMediaSource(mediaItem)
            }
            // Re-check after building sources: a new track selection can race
            // this async extraction while source construction is in progress.
            if (currentSourceType != "youtube_audio" || currentVideoId != expectedCurrentVideoId) {
                return mapOf("appended" to 0, "reason" to "track_changed")
            }
            player.addMediaSources(player.mediaItemCount, sources)
            tracks.forEach { gaplessRemoteTracks[it.videoId] = it }
            nativeGaplessQueueIds = nativeGaplessQueueIds + tracks.map { it.videoId }
            mapOf("appended" to tracks.size, "reason" to "ok")
        } catch (error: Exception) {
            MusikKuLogger.e(TAG, "Gagal menyiapkan native YouTube queue", error)
            mapOf("appended" to 0, "reason" to "prepare_failed")
        }
    }

    private fun clearNativeGaplessQueue(): Boolean {
        val player = localPlayer ?: return false
        if (currentSourceType != "local" && currentSourceType != "youtube_audio") return false
        val firstFutureIndex = (player.currentMediaItemIndex + 1).coerceAtLeast(0)
        val count = player.mediaItemCount
        if (firstFutureIndex < count) {
            val removed = runCatching {
                player.removeMediaItems(firstFutureIndex, count)
                true
            }.getOrElse { error ->
                MusikKuLogger.e(TAG, "Gagal menghapus antrean gapless", error)
                false
            }
            if (!removed) return false
        }
        nativeGaplessQueueIds = emptySet()
        pendingGaplessQueue = emptyList()
        gaplessRemoteTracks.clear()
        androidAutoPlaylistMediaTracks.clear()
        androidAutoCustomPlaylistId = ""
        androidAutoBrowseQueue = false
        androidAutoBrowseParentId = ""
        androidAutoNextBrowsePosition = -1
        return true
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
            if (currentSourceType == "local" && pendingGaplessQueue.isNotEmpty()) {
                val playlist = mutableListOf(
                    createLocalMediaItem(currentVideoId, currentTitle, currentArtist, uriString),
                )
                pendingGaplessQueue.forEach { track ->
                    playlist += createLocalMediaItem(
                        track.videoId, track.title, track.artist, track.mediaUri,
                    )
                }
                nativeGaplessQueueIds = pendingGaplessQueue.map { it.videoId }.toSet()
                player.setMediaItems(playlist, 0, positionMs.coerceAtLeast(0L))
            } else {
                nativeGaplessQueueIds = emptySet()
                player.setMediaItem(mediaItem, positionMs.coerceAtLeast(0L))
            }
            pendingGaplessQueue = emptyList()
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
        clearPendingBluetoothResume()
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

    @OptIn(UnstableApi::class)
    private fun applyPreferredAudioOutput(deviceId: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val player = localPlayer ?: return false
        return applyPreferredAudioOutputToPlayer(player, deviceId)
    }

    @OptIn(UnstableApi::class)
    private fun applyPreferredAudioOutputToPlayer(player: ExoPlayer, deviceId: Int): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val target = if (deviceId < 0) {
            null
        } else {
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .filter { it.isSink }
            val prefs = getSharedPreferences("musikku_playback_settings", Context.MODE_PRIVATE)
            val preferredType = prefs.getInt("preferredAudioOutputType", -1)
            val preferredName = prefs.getString("preferredAudioOutputName", "").orEmpty()
            devices.firstOrNull { it.id == deviceId }
                ?: devices.firstOrNull {
                    it.type == preferredType &&
                        (preferredName.isBlank() || it.productName?.toString().orEmpty() == preferredName)
                }
                ?: return false
        }
        return runCatching {
            player.setPreferredAudioDevice(target)
            scheduleSoundstageOutputRefresh(180L)
            true
        }.getOrDefault(false)
    }

    fun setPcmVisualizationEnabled(enabled: Boolean) {
        MusikKuAudioVisualizationEvents.enabled = enabled
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

    private fun emitLocalState(state: String, trackTransition: Boolean = false) {
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
            "trackTransition" to trackTransition,
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
                clearPendingBluetoothResume()
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
                skipToNextPlayback()
                return START_NOT_STICKY
            }

            ACTION_PREVIOUS -> {
                skipToPreviousPlayback()
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

        gaplessRemoteTracks.clear()
        androidAutoPlaylistMediaTracks.clear()
        androidAutoCustomPlaylistId = ""
        currentVideoId = intent?.getStringExtra("videoId") ?: ""
        currentTitle = intent?.getStringExtra("title") ?: "MusikKu"
        currentArtist = intent?.getStringExtra("artist") ?: ""
        currentThumbnailUrl = intent?.getStringExtra("thumbnailUrl")?.trim().orEmpty()
        currentPlaying = intent?.getBooleanExtra("playing", false) ?: false
        currentSourceType = intent?.getStringExtra("sourceType")?.trim().orEmpty().ifBlank {
            if (currentVideoId.startsWith("local:")) "local" else "youtube"
        }
        androidAutoBrowseQueue = intent?.getBooleanExtra("androidAutoBrowseQueue", false) ?: false
        androidAutoBrowseGeneration += 1L
        androidAutoBrowseParentId = if (androidAutoBrowseQueue) {
            intent?.getStringExtra("androidAutoBrowseParentId")?.trim().orEmpty()
        } else ""
        androidAutoBrowseSearchQuery = if (androidAutoBrowseQueue) {
            intent?.getStringExtra("androidAutoBrowseSearchQuery")?.trim().orEmpty()
        } else ""
        androidAutoNextBrowsePosition = if (androidAutoBrowseQueue) {
            intent?.getIntExtra("androidAutoNextBrowsePosition", -1) ?: -1
        } else -1
        androidAutoBrowseQueueLoading = false
        currentMediaUri = intent?.getStringExtra("mediaUri")?.trim().orEmpty()
        currentStreamHeaders = intent?.getBundleExtra("streamHeaders")?.let { bundle ->
            bundle.keySet().mapNotNull { key ->
                val value = bundle.getString(key)
                if (value.isNullOrBlank()) null else key to value
            }.toMap()
        }.orEmpty()
        @Suppress("DEPRECATION")
        val rawGaplessQueue = intent?.getParcelableArrayListExtra<Bundle>("gaplessQueue")
        pendingGaplessQueue = if (currentSourceType == "local") {
            rawGaplessQueue.orEmpty().mapNotNull { bundle ->
                val id = bundle.getString("videoId").orEmpty()
                val uri = bundle.getString("mediaUri").orEmpty()
                val parsedUri = runCatching { Uri.parse(uri) }.getOrNull()
                if (!id.startsWith("local:") ||
                    parsedUri?.scheme !in setOf("content", "file") ||
                    id == currentVideoId) {
                    null
                } else {
                    GaplessLocalTrack(
                        videoId = id,
                        title = bundle.getString("title").orEmpty(),
                        artist = bundle.getString("artist").orEmpty(),
                        mediaUri = uri,
                    )
                }
            }.distinctBy { it.videoId }.take(60)
        } else {
            emptyList()
        }
        nativeGaplessQueueIds = pendingGaplessQueue.map { it.videoId }.toSet()
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

        if (trackChanged || currentPlaying) {
            clearPendingBluetoothResume()
        }

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
                PlaybackStateCompat.ACTION_SEEK_TO or
                PlaybackStateCompat.ACTION_PLAY_FROM_MEDIA_ID or
                PlaybackStateCompat.ACTION_PLAY_FROM_SEARCH

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

        // Widget hanya menampilkan metadata dan status transport, bukan progress.
        // Karena snapshot player diperbarui tiap detik, batasi refresh agar tidak
        // membebani launcher/battery. Perubahan lagu atau play/pause tetap instan.
        val widgetStateKey = "$currentTitle|$currentArtist|$currentPlaying"
        val now = SystemClock.elapsedRealtime()
        if (widgetStateKey != lastWidgetStateKey || now - lastWidgetUpdateAtMs >= 10_000L) {
            lastWidgetStateKey = widgetStateKey
            lastWidgetUpdateAtMs = now
            MusikKuHomeWidgetProvider.updateAll(
                applicationContext,
                currentTitle,
                currentArtist,
                currentPlaying,
            )
        }
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
        unregisterAudioLibraryObserver()
        unregisterSavedPlaylistObserver()
        androidAutoBrowseExecutor.shutdownNow()
        androidAutoResolveExecutor.shutdownNow()
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
        soundstageRouteHandler.removeCallbacks(soundstageRouteRefreshRunnable)
        unregisterAudioDeviceCallback()
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
