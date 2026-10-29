import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/loop_mode.dart';
import '../models/listening_stat.dart';
import '../models/lyric.dart';
import '../models/native_youtube_state.dart';
import '../models/playlist.dart';
import '../models/player_ui_state.dart';
import '../models/queue_item.dart';
import '../models/youtube_search_result.dart';
import '../services/lyrics_service.dart';
import '../services/listening_playback_tracker.dart';
import '../services/listening_together_service.dart';
import '../services/music_style_matcher.dart';
import '../services/original_track_resolver.dart';
import '../services/app_settings.dart';
import '../services/app_health_monitor.dart';
import '../services/app_update_service.dart';
import '../services/channel_block_filter.dart';
import '../services/queue_manager.dart';
import '../services/playback_source_policy.dart';
import '../services/playback_session_guard.dart';
import '../services/radio_service.dart';
import '../services/storage_service.dart';
import '../services/smart_queue_scorer.dart';
import '../services/youtube_controller.dart';
import '../services/youtube_search_service.dart';
import '../widgets/youtube_hub.dart';
import '../widgets/music_player_page.dart';
import '../widgets/mini_music_player.dart';
import '../widgets/app_update_sheet.dart';
import '../widgets/playlist_widgets.dart';
import '../widgets/video_menu_sheet.dart';
import 'artist_page.dart';
import 'custom_playlists_page.dart';

part 'home_page/state_sync.dart';
part 'home_page/audio_effects.dart';
part 'home_page/data_loading.dart';
part 'home_page/search.dart';
part 'home_page/favorites.dart';
part 'home_page/playlists.dart';
part 'home_page/radio.dart';
part 'home_page/auto_next.dart';
part 'home_page/listening_together.dart';
part 'home_page/playback.dart';
part 'home_page/controls.dart';
part 'home_page/queue.dart';
part 'home_page/navigation.dart';
part 'home_page/ui_layout.dart';

/// Kunci penyimpanan mode pemutaran musik (dipakai extension di part files).
const String _shufflePrefKey = 'playback_shuffle_v1';
const String _smartShufflePrefKey = 'playback_smart_shuffle_v1';
const String _loopModePrefKey = 'playback_loop_mode_v1';
const String _playerVolumePrefKey = 'player_volume_percent_v1';

/// Daftar lagu yang sedang menjadi "playlist" untuk next / previous / shuffle.
enum _ListSource { none, search, favorites, radio, playlist, local, collection }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.settings,
  });

  final AppSettingsController settings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver {
  // Only one HomePage state may run the automatic launch check at a time.
  // This closes a small race where two nearly simultaneous States could both
  // read the same SharedPreferences flag before either write completed.
  static bool _launchUpdateCheckInProgress = false;

  // ============================================================
  // SERVICES
  // ============================================================

  final NativeYoutubeController _youtubeController = NativeYoutubeController();
  final YoutubeHubController _hubController = YoutubeHubController();

  final YoutubeSearchService _searchService = YoutubeSearchService();
  late final OriginalTrackResolver _originalTrackResolver =
      OriginalTrackResolver(_searchService);

  final QueueManager _queueManager = QueueManager();

  /// Coordinates stale playback requests and duplicate native ended events.
  final PlaybackSessionGuard _playbackSessionGuard = PlaybackSessionGuard();

  final StorageService _storage = StorageService();

  // Listen Together menggunakan Supabase Realtime lintas jaringan. Tidak ada
  // fallback LAN/IP: build harus menyertakan URL dan publishable key Supabase.
  final ListeningTogetherService _listenTogether = ListeningTogetherService();
  StreamSubscription<Map<String, dynamic>>? _listenTogetherMessagesSubscription;
  Timer? _listenTogetherSyncTimer;
  bool _applyingListenTogetherState = false;
  Map<String, dynamic>? _pendingListenTogetherState;
  int _listenTogetherStateSequence = 0;
  int _lastAppliedListenTogetherSequence = 0;
  // Incremented whenever a newer pause/resume intent arrives. An older async
  // seek must not resume playback after a newer pause command has arrived.
  int _listenTogetherPlaybackCommandRevision = 0;
  String _listenTogetherUrgentPlaybackVideoId = '';
  bool? _listenTogetherUrgentPlaybackTarget;
  // Guests optimistically update their own already-loaded player while the
  // command is travelling to the host, avoiding one full network round trip.
  String _listenTogetherOptimisticVideoId = '';
  bool? _listenTogetherOptimisticPlaying;
  int _listenTogetherOptimisticSinceMs = 0;
  bool _wasFollowingListenTogether = false;
  String _lastRoomUnsupportedTrackId = '';
  String _lastListenTogetherLoadFailureVideoId = '';
  DateTime? _lastListenTogetherLoadFailureAt;
  // Cooldown untuk seek koreksi drift di sisi guest.
  DateTime? _lastListenTogetherSeekAt;
  // Waktu terakhir event native diterima. Posisi native hanya diperbarui sekitar
  // tiap detik, jadi dipakai untuk memperkirakan posisi sebenarnya saat ini.
  DateTime _nativeStateStampedAt = DateTime.fromMillisecondsSinceEpoch(0);
  // Seek koreksi sengaja melompat sedikit ke depan untuk mengimbangi buffering.
  /// Lead seek adaptif: dasar 300 ms, naik mengikuti lama seekTo di perangkat
  /// ini (EMA) supaya HP lambat tidak selalu tertinggal setelah koreksi.
  int _listenTogetherSeekLeadMs = 300;

  final Random _random = Random();

  // ============================================================
  // SEARCH
  // ============================================================

  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocusNode = FocusNode();

  bool _searchTextEmpty = true;


  // ============================================================
  // PLAYER STATE
  // ============================================================

  final ValueNotifier<PlayerUiState> _playerUiState =
      ValueNotifier(const PlayerUiState());

  /// State native dipisah ke ValueNotifier supaya event posisi (tiap detik)
  /// hanya membangun ulang bagian yang butuh state native, bukan seluruh HomePage + daftar lagu.
  final ValueNotifier<NativeYoutubeState> _nativeStateNotifier =
      ValueNotifier(const NativeYoutubeState());

  NativeYoutubeState get _nativeState => _nativeStateNotifier.value;

  StreamSubscription<NativeYoutubeState>? _videoStateSubscription;

  YoutubeSearchResult? _currentVideo;

  // An expired/rejected direct stream gets one fresh resolution attempt per
  // explicit track play, avoiding an endless retry loop.
  String _youtubeAudioRetryVideoId = '';
  int _youtubeAudioRetryCount = 0;
  String _youtubeEmbedErrorVideoId = '';

  // ============================================================
  // DAFTAR LAGU
  // ============================================================

  /// Hasil pencarian terakhir (yang tampil di layar).
  List<YoutubeSearchResult> _searchResults = [];

  /// Lagu favorit (disimpan permanen).
  List<YoutubeSearchResult> _favorites = [];

  /// Feedback rekomendasi: like/dislike membantu menyaring radio dan shuffle.
  Set<String> _likedIds = <String>{};

  Set<String> _dislikedIds = <String>{};

  /// Channel yang dikecualikan dari rekomendasi Radio.
  Set<String> _blockedChannelKeys = <String>{};

  /// Riwayat lagu yang benar-benar diputar, terpisah dari riwayat pencarian.
  List<YoutubeSearchResult> _recentlyPlayed = [];

  /// Track only enters listening history after real playback progress has
  /// accumulated. This prevents failed/queued selections from polluting history.
  String _historyTrackId = '';
  double _historyListenedSeconds = 0.0;
  bool _historyRecordedForTrack = false;

  /// Progress dengar per lagu, ditampilkan sebagai garis di thumbnail.
  Map<String, double> _watchProgress = <String, double>{};
  Map<String, double> _watchDuration = <String, double>{};

  DateTime _lastWatchProgressSaveAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _lastWatchProgressUiAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  final ListeningPlaybackTracker _listeningPlaybackTracker =
      ListeningPlaybackTracker();

  /// Playlist yang dipakai next / previous / shuffle.
  List<YoutubeSearchResult> _activeList = [];

  _ListSource _activeSource = _ListSource.none;

  /// Menahan dua aksi Next yang terlalu berdekatan agar tidak memilih track dobel.
  bool _nextActionInProgress = false;
  // Lagu yang menjadi asal konteks Radio saat ini, dan lagu yang dipilih Radio
  // sendiri. Lagu di luar keduanya berarti konteks Radio sudah basi.
  String _radioOriginVideoId = '';
  final Set<String> _radioPickedIds = <String>{};

  /// Lagu yang BELUM diputar dalam siklus shuffle saat ini.
  List<YoutubeSearchResult> _shufflePool = [];

  /// Statistik dengar yang dipakai Shuffle Pintar.
  Map<String, ListeningStat> _listeningStatsById = <String, ListeningStat>{};

  /// Riwayat lagu yang sudah diputar, dipakai tombol Previous.
  final List<YoutubeSearchResult> _playHistory = [];

  bool _showFavorites = false;

  YoutubeSearchResult? _youtubeWatchVideo;

  bool _youtubeSystemPipMode = false;
  YoutubeSearchResult? _systemPipReturnVideo;

  /// Legacy PiP state retained temporarily for compatibility with old saved state.
  bool _suppressAutoNextInPip = false;

  /// Legacy setting from the former video player; not shown in audio-only UI.
  /// Disimpan permanen dan dikirim ulang ke player native.

  /// Playlist buatan pengguna.
  List<Playlist> _playlists = [];

  /// true = layar playlist sedang tampil.
  bool _showPlaylists = false;

  /// Playlist yang sedang dibuka di layar (null = tampil daftar playlist).
  String? _openPlaylistId;

  /// Playlist yang sedang menjadi sumber putar (untuk sinkron saat diedit).
  String? _activePlaylistId;

  bool _isLoading = false;

  String _errorMessage = '';

  // ============================================================
  // AUTO NEXT PROTECTION
  // ============================================================


  // ============================================================
  // AUTOPLAY / RADIO (lagu berikutnya untuk lagu dari pencarian)
  // ============================================================

  /// Kata kunci pencarian terakhir yang berhasil dimulai dari YouTube Hub.
  /// Dipakai radio/autoplay sebagai fallback konteks pencarian.
  String _lastSearchQuery = '';

  /// Autoplay: lagu terbaru yang masih sesuai konteks untuk lagu dari pencarian.
  late final RadioService _radio = RadioService(
    _searchService,
    currentVideoId: () => _currentVideo?.videoId,
    blockedIds: () => _dislikedIds,
    blockedChannelKeys: () => _blockedChannelKeys,
    onError: (message) {
      if (mounted) {
        _toast(message);
      }
    },
  );

  // ============================================================
  // LAGU GAGAL DIPUTAR
  // ============================================================

  String _failureHandledFor = '';

  Timer? _playbackWatchdog;

  int _lyricsRequestId = 0;

  DateTime _lastPositionSaveAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  double _pendingSavedPosition = 0;

  /// Menandai bahwa aplikasi sedang meninggalkan task/foreground.
  /// Selama fase ini event player transien tidak boleh menimpa snapshot
  /// terakhir dengan posisi 0.
  bool _isAppExiting = false;

  /// Mencegah beberapa callback lifecycle memicu snapshot penutupan
  /// yang saling balapan.
  bool _lifecycleSnapshotInProgress = false;

  /// Menyimpan snapshot penutupan terakhir yang sudah selesai.
  bool _lifecycleSnapshotSaved = false;

  /// Menjaga penulisan snapshot tetap berurutan.
  Future<void> _snapshotSaveChain = Future<void>.value();

  /// Menahan auto-save sementara lagu terakhir sedang dipulihkan.
  /// Event native dari loadVideo biasanya sempat membawa posisi 0 sebelum
  /// seek selesai; event itu tidak boleh menimpa snapshot posisi terakhir.
  bool _isRestoringLastPlayback = false;

  /// True setelah startup memulihkan metadata lagu terakhir, tetapi player
  /// native belum di-load. Load + seek + play baru dilakukan saat user
  /// menekan tombol Play.
  bool _restoredNeedsLoad = false;

  // ============================================================
  // NOTIFICATION
  // ============================================================

  bool _notificationStarted = false;

  String _lastNotificationKey = '';

  DateTime _lastNotificationProgressAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  int _lastNotificationPositionMs = 0;

  Duration _lastNotificationDuration = Duration.zero;

  bool _playPauseBusy = false;

  // ============================================================
  // SLEEP TIMER
  // ============================================================

  Timer? _sleepTimer;

  bool _stopAfterCurrent = false;

  final ValueNotifier<bool> _sleepActive = ValueNotifier(false);

  // ============================================================
  // AUDIO SETTINGS
  // ============================================================

  int _crossfadeSeconds = 0;

  String _equalizerPreset = 'Flat';


  String _crossfadeFadingVideoId = '';

  // Setiap fade mendapat generation sendiri. Fade lama dibatalkan secara
  // kooperatif agar tidak bisa menimpa volume fade yang lebih baru.
  int _volumeFadeGeneration = 0;

  int _playerVolumePercent = 100;

  // Peringatan jika buffering bertahan melebihi ambang yang dipilih.
  Timer? _bufferAlertTimer;
  String _bufferAlertVideoId = '';
  DateTime? _bufferingStartedAt;
  bool _bufferAlertShown = false;

  // ============================================================
  // HELPERS
  // ============================================================

  Future<void> _checkForAppUpdateOnLaunch() async {
    // Hormati opt-out: jika dimatikan, jangan menghubungi GitHub saat startup.
    if (!widget.settings.autoUpdateEnabled.value) return;

    // Jangan menutupi pemutaran pertama. Cek setelah UI utama stabil dan diam-diam
    // abaikan error jaringan atau repository yang belum punya Release.
    await Future<void>.delayed(const Duration(seconds: 5));
    if (!widget.settings.autoUpdateEnabled.value) return;
    if (_launchUpdateCheckInProgress) return;
    _launchUpdateCheckInProgress = true;

    try {
      final backgroundDownloadEnabled =
          widget.settings.backgroundDownloadUpdates.value;
      if (!mounted ||
          (!backgroundDownloadEnabled &&
              ModalRoute.of(context)?.isCurrent != true) ||
          _youtubeSystemPipMode) {
        return;
      }
      // Normal update prompts should never cover the player. When the user
      // explicitly enables background downloads, however, allow the silent
      // verified download to run while audio-only playback is open or another
      // settings route is on top of HomePage.
      if (_youtubeWatchVideo != null && !backgroundDownloadEnabled) {
        return;
      }

      if (!widget.settings.autoUpdateEnabled.value) return;
      final result = await AppUpdateService.instance.checkForUpdate();
      final release = result.release;
      final backgroundDownloadStillEnabled =
          widget.settings.backgroundDownloadUpdates.value;
      if (!mounted ||
          (!backgroundDownloadStillEnabled &&
              ModalRoute.of(context)?.isCurrent != true) ||
          !widget.settings.autoUpdateEnabled.value ||
          !result.updateAvailable ||
          release == null) {
        return;
      }

      final preferences = await SharedPreferences.getInstance();
      final autoInstall = widget.settings.autoInstallUpdates.value;

      // Optional silent background download. It deliberately does not open a
      // modal or the Android installer, so music playback is not interrupted.
      // Android still requires the user to confirm installation later. The
      // service validates the release asset SHA-256 before caching it.
      if (widget.settings.backgroundDownloadUpdates.value && !autoInstall) {
        const readyVersionKey = 'musikku_background_update_ready_version_v1';
        final alreadyNotified =
            preferences.getString(readyVersionKey) == release.version;
        try {
          await AppUpdateService.instance.downloadAndVerify(
            release,
            onProgress: (_, _) {},
          );
          if (!mounted) return;
          await preferences.setString(readyVersionKey, release.version);
          if (!alreadyNotified) {
            _toast(
              'Pembaruan MusikKu ${release.version} sudah diunduh. Buka Pengaturan → Periksa pembaruan untuk memasangnya.',
              duration: const Duration(seconds: 6),
            );
          }
        } catch (error) {
          // Keep the launch and current playback quiet if a background download
          // fails; the Settings update screen can retry with visible progress.
          debugPrint('BACKGROUND UPDATE DOWNLOAD: $error');
        }
        return;
      }

      // Keep normal and auto-install prompt tracking separate: enabling the
      // opt-in auto-install mode should not be blocked by an older normal prompt.
      final promptKey = autoInstall
          ? 'musikku_auto_install_prompted_${release.version}'
          : 'musikku_update_prompted_${release.version}';
      if (preferences.getBool(promptKey) == true) return;
      await preferences.setBool(promptKey, true);
      if (!mounted) return;
      // A dialog/sheet could have opened while the GitHub request was running.
      // Do not stack the update prompt on another route; allow the next launch
      // to prompt again if this automatic presentation was deferred.
      if (ModalRoute.of(context)?.isCurrent != true ||
          _youtubeWatchVideo != null) {
        // If music playback began while the update check was in flight, defer
        // the prompt/installer instead of covering Player. Background-download
        // mode has already returned above and never opens a modal.
        await preferences.remove(promptKey);
        return;
      }

      await AppUpdateSheet.show(
        context,
        initialResult: result,
        automaticPrompt: true,
        automaticInstall: widget.settings.autoInstallUpdates.value,
      );
    } catch (error) {
      // Auto-check tidak boleh mengganggu pengguna saat jaringan/API bermasalah.
      debugPrint('AUTO UPDATE CHECK: $error');
    } finally {
      _launchUpdateCheckInProgress = false;
    }
  }

  void _toast(
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        content: Text(message),
      ),
    );
  }

  String _formatStoredPosition(double seconds) {
    final total = seconds.floor().clamp(0, 86400).toInt();
    final minutes = total ~/ 60;
    final remainder = total % 60;

    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;

      return '$hours:${mins.toString().padLeft(2, '0')}:'
          '${remainder.toString().padLeft(2, '0')}';
    }

    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  // Refresh UI from part-file extensions without calling the protected
  // State.setState member outside the State subclass declaration.
  void _refreshListeningTogetherUi() {
    if (!mounted) return;
    setState(() {});
  }

  // ============================================================
  // LIFECYCLE & BUILD (override harus tetap di kelas State)
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);


    _searchController.addListener(_onSearchTextChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    widget.settings.dataSaver.addListener(_onDataSaverChanged);
    widget.settings.dataSaverMode.addListener(_onDataSaverChanged);
    widget.settings.cropVideoBranding.addListener(_applyVideoCrop);
    widget.settings.bufferAlertSeconds.addListener(_onBufferAlertThresholdChanged);
    unawaited(_youtubeController.setVideoCrop(_videoCropZoom));
    unawaited(_youtubeController.setDataSaverLevel(widget.settings.dataSaverLevel));

    _listenTogetherMessagesSubscription = _listenTogether.messages.listen(
      _onListenTogetherMessage,
      onError: (Object error) => debugPrint('LISTEN TOGETHER ERROR: $error'),
    );
    _listenTogether.status.addListener(_onListenTogetherStatusChanged);
    _nativeStateNotifier.addListener(_stampNativeStateTime);

    _videoStateSubscription = _youtubeController.stateStream.listen(
      _onYoutubeState,
      onError: (error) {
        debugPrint('NATIVE STATE ERROR: $error');
      },
    );

    _youtubeController.setNotificationCallbacks(
      onNext: () => _routeListenTogetherAction('next', () => _next()),
      onPrevious: () => _routeListenTogetherAction('previous', _previous),
      onPlayPause: () => _routeListenTogetherAction('play_pause', _togglePlayPause),
      onStop: () => _routeListenTogetherAction('stop', _stopPlayback),
      onYoutubeAudioPlaybackError: (videoId, positionSeconds, shouldPlay) =>
          _fallbackFromYoutubeAudioError(
        videoId: videoId,
        positionSeconds: positionSeconds,
        shouldPlay: shouldPlay,
      ),
      onYoutubeEmbedError: (videoId, error) {
        if (!mounted || _currentVideo?.videoId != videoId) return;
        setState(() => _youtubeEmbedErrorVideoId = videoId);
        _toast('Video ini tidak bisa ditampilkan di pemutar tertanam YouTube. Audio dapat tetap diputar.');
      },
      onPipWillEnter: () {
        if (mounted) {
          _systemPipReturnVideo = _youtubeWatchVideo ?? _currentVideo;
          unawaited(_youtubeController.setPlayerUiVisible(false));
          setState(() {
            // Ini adalah Android System PiP, bukan floating PiP di dalam app.
            // PENTING: jangan kosongkan _youtubeWatchVideo di sini. Kalau
            // widget watch dilepas saat Activity masuk PiP, saat keluar dari
            // PiP Flutter bisa kembali dalam frame yang berbeda dari callback
            // Android dan halaman video terlihat "hilang". Biarkan video tetap
            // terpasang; yang berubah hanya mode/render surface-nya.
            _youtubeSystemPipMode = true;
            _youtubeWatchVideo = _youtubeWatchVideo ?? _currentVideo;
            _suppressAutoNextInPip = true;
          });
        }
      },
      onPipChanged: (enabled) {
        if (mounted) {
          if (enabled) {
            setState(() {
              _youtubeSystemPipMode = true;
              _youtubeWatchVideo = _youtubeWatchVideo ?? _currentVideo;
              _suppressAutoNextInPip = true;
            });
            unawaited(_youtubeController.setPlayerUiVisible(false));
          } else {
            // Android bisa memberi callback PiP selesai sedikit sebelum /
            // sesudah Flutter menerima resumed. Simpan referensi video dan
            // restore UI setelah frame aktif supaya AndroidView tidak sempat
            // dibuang atau ditampilkan dengan state setengah jadi.
            final restoreVideo =
                _systemPipReturnVideo ?? _youtubeWatchVideo ?? _currentVideo;
            _systemPipReturnVideo = null;
            final canRestore = restoreVideo != null &&
                _currentVideo?.videoId == restoreVideo.videoId;
            setState(() {
              _youtubeSystemPipMode = false;
              _suppressAutoNextInPip = false;
              _youtubeWatchVideo = canRestore ? restoreVideo : null;
            });
            if (canRestore) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                unawaited(_youtubeController.setPlayerUiVisible(true));
              });
            } else {
              unawaited(_youtubeController.setPlayerUiVisible(false));
            }
          }
        }
      },
    );

    unawaited(_loadSavedData());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForAppUpdateOnLaunch());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Ambil SATU snapshot final dari player. Setelah flag ini aktif,
        // event paused/transient dari native tidak boleh menulis posisi 0
        // dan menimpa posisi yang baru saja kita simpan.
        _isAppExiting = true;

        if (!_lifecycleSnapshotInProgress && !_lifecycleSnapshotSaved) {
          _lifecycleSnapshotInProgress = true;
          unawaited(
            _saveCurrentPlaybackSnapshot(queryNativePosition: true).whenComplete(() {
              _lifecycleSnapshotInProgress = false;
              _lifecycleSnapshotSaved = true;
            }),
          );
        }
        break;

      case AppLifecycleState.resumed:
        // Aplikasi benar-benar kembali aktif. Snapshot baru boleh berjalan
        // lagi dan posisi player terbaru dapat mengambil alih.
        _isAppExiting = false;
        _lifecycleSnapshotSaved = false;
        break;
    }
  }

  @override
  void dispose() {
    // Jangan melakukan write snapshot kedua dengan nilai _pendingSavedPosition
    // yang mungkin stale. Itu adalah sumber utama posisi kembali ke 0.
    // Jika dispose terjadi tanpa callback lifecycle, ambil posisi native sekali.
    if (!_lifecycleSnapshotSaved && !_lifecycleSnapshotInProgress) {
      _isAppExiting = true;
      unawaited(_saveCurrentPlaybackSnapshot(queryNativePosition: true));
    }

    unawaited(_storage.saveQueue(_queueManager.items));

    WidgetsBinding.instance.removeObserver(this);

    _sleepTimer?.cancel();
    _bufferAlertTimer?.cancel();

    _radio.dispose();

    _playbackWatchdog?.cancel();

    _videoStateSubscription?.cancel();
    _listenTogetherSyncTimer?.cancel();
    _listenTogetherMessagesSubscription?.cancel();
    _listenTogether.status.removeListener(_onListenTogetherStatusChanged);
    unawaited(_listenTogether.dispose());

    _youtubeController.dispose();

    _searchController.removeListener(_onSearchTextChanged);
    _searchFocusNode.removeListener(_onSearchFocusChanged);

    widget.settings.dataSaver.removeListener(_onDataSaverChanged);
    widget.settings.cropVideoBranding.removeListener(_applyVideoCrop);
    widget.settings.bufferAlertSeconds.removeListener(_onBufferAlertThresholdChanged);
    widget.settings.dataSaverMode.removeListener(_onDataSaverChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();

    _playerUiState.dispose();
    _nativeStateNotifier.removeListener(_stampNativeStateTime);
    _nativeStateNotifier.dispose();
    _sleepActive.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        if (!_handleBack()) {
          // Di layar depan: pindahkan app ke background (musik tetap jalan).
          SystemNavigator.pop();
        }
      },
      child: _buildScaffold(context),
    );
  }
}