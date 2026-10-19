part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Pemuatan data awal (storage) dan pemulihan lagu terakhir.
extension _HomeDataLoading on _HomePageState {
  void _onDataSaverChanged() {
    _searchService.setDataSaverMode(widget.settings.dataSaverLevel);
    unawaited(_youtubeController.setDataSaverLevel(widget.settings.dataSaverLevel));
  }

  Future<void> _loadSavedData() async {
    _searchService.setDataSaverMode(widget.settings.dataSaverLevel);

    final results = await Future.wait([
      _storage.loadFavorites(),
      _storage.loadQueue(),
      _storage.loadRecentlyPlayed(),
      _storage.loadLastPlayed(),
      _storage.loadLastPosition(),
      _storage.loadLastDuration(),
      _storage.loadPlaylists(),
      _storage.loadWatchProgress(),
      _storage.loadCrossfadeSeconds(),
      _storage.loadEqualizerPreset(),
      _storage.loadListeningStats(),
      _storage.loadWatchDurations(),
    ]);

    final favorites = results[0] as List<YoutubeSearchResult>;
    final savedQueue = results[1] as List<QueueItem>;
    final recentlyPlayed = results[2] as List<YoutubeSearchResult>;
    final lastPlayed = results[3] as YoutubeSearchResult?;
    var lastPosition = results[4] as double;
    var lastDuration = results[5] as double;
    final playlists = results[6] as List<Playlist>;
    final watchProgress = results[7] as Map<String, double>;
    final crossfadeSeconds = results[8] as int;
    final equalizerPreset = results[9] as String;
    final listeningStats = results[10] as List<ListeningStat>;
    final watchDurations = results[11] as Map<String, double>;
    _listeningStatsById = {
      for (final stat in listeningStats) stat.videoId: stat,
    };
    final feedback = await Future.wait([
      _storage.loadLikedIds(),
      _storage.loadDislikedIds(),
      _storage.loadBlockedChannelKeys(),
    ]);
    final likedIds = feedback[0];
    final dislikedIds = feedback[1];
    final blockedChannelKeys = feedback[2];
    try {
      final prefs = await SharedPreferences.getInstance();
      _playerVolumePercent = (prefs.getInt(_playerVolumePrefKey) ?? 100)
          .clamp(0, 100)
          .toInt();
    } catch (_) {
      _playerVolumePercent = 100;
    }

    // Native backup menjadi sumber pemulihan yang lebih kuat ketika lagu
    // yang sama masih tersimpan di service. Flutter bisa sempat menulis
    // snapshot lama/0 saat task ditutup; karena itu native dipakai bila
    // posisinya jelas lebih maju daripada snapshot Flutter.
    if (lastPlayed != null) {
      try {
        final nativeSnapshot =
            await _youtubeController.loadNativePlaybackSnapshot();
        final nativeVideoId =
            nativeSnapshot['videoId']?.toString() ?? '';
        final nativePosition =
            (nativeSnapshot['positionSeconds'] as num?)?.toDouble() ?? 0.0;
        final nativeDuration =
            (nativeSnapshot['durationSeconds'] as num?)?.toDouble() ?? 0.0;

        final nativeLooksLikeSameTrack =
            nativeVideoId == lastPlayed.videoId;

        if (nativeLooksLikeSameTrack && nativeDuration > 0) {
          lastDuration = nativeDuration;
        }
        final nativeLooksLikeNotEnded =
            nativePosition > 0.25 &&
            (nativeDuration <= 0.0 ||
                nativePosition < nativeDuration - 1.0);
        final nativeIsMeaningfullyNewer =
            nativePosition > lastPosition + 1.0;

        if (nativeLooksLikeSameTrack &&
            nativeLooksLikeNotEnded &&
            (lastPosition <= 0.25 || nativeIsMeaningfullyNewer)) {
          lastPosition = nativePosition;
        }
      } catch (e) {
        debugPrint('LOAD NATIVE SNAPSHOT ERROR: $e');
      }
    }

    _queueManager.restore(savedQueue);

    if (!mounted) {
      return;
    }

    setState(() {
      _favorites = favorites;
      _playlists = playlists;
      _recentlyPlayed = recentlyPlayed;
      _watchProgress = watchProgress;
      _watchDuration = watchDurations;
      _crossfadeSeconds = crossfadeSeconds.clamp(0, 6).toInt();
      _equalizerPreset = equalizerPreset;
      _likedIds = likedIds;
      _dislikedIds = dislikedIds;
      _blockedChannelKeys = blockedChannelKeys;
    });

    try {
      await _youtubeController.setEqualizerPreset(_equalizerPreset);
    } catch (e) {
      debugPrint('LOAD EQUALIZER PRESET ERROR: $e');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedShuffle = prefs.getBool(_shufflePrefKey) ?? false;
      final savedSmart = prefs.getBool(_smartShufflePrefKey) ?? false;
      final savedLoopIndex = prefs.getInt(_loopModePrefKey) ?? LoopModeCustom.off.index;
      final safeIndex = savedLoopIndex.clamp(0, LoopModeCustom.values.length - 1).toInt();
      final savedLoop = LoopModeCustom.values[safeIndex];
      _playerUiState.value = _playerUiState.value.copyWith(
        isShuffle: savedShuffle || savedSmart,
        isSmartShuffle: savedSmart,
        loopMode: savedLoop,
      );
    } catch (_) {}

    if (_playerUiState.value.isShuffle) {
      _prepareShufflePool(excludeCurrent: true);
    }

    _syncFavoriteFlag();
    _syncFeedbackFlags();

    // Pulihkan lagu terakhir hanya jika memang pernah ada.
    // Posisi terakhir dicari setelah video selesai dimuat oleh native player.
    if (lastPlayed != null) {
      unawaited(
        _restoreLastPlayed(
          lastPlayed,
          lastPosition,
          lastDuration,
        ),
      );
    }
  }

  Future<void> _restoreLastPlayed(
    YoutubeSearchResult video,
    double positionSeconds,
    double durationSeconds,
  ) async {
    _activeSource = _ListSource.none;
    _activeList = [];

    // Startup hanya memulihkan metadata + posisi. Jangan sentuh player native
    // dulu supaya tidak ada autoplay sekilas ketika aplikasi dibuka.
    _currentVideo = video;
    _pendingSavedPosition = positionSeconds.clamp(0.0, 86400.0).toDouble();
    _lastPositionSaveAt = DateTime.now();
    _restoredNeedsLoad = true;

    _nativeStateNotifier.value = NativeYoutubeState(
      playbackState: NativePlaybackState.paused,
      position: Duration(
        milliseconds: (_pendingSavedPosition * 1000).round(),
      ),
      duration: Duration(
        milliseconds: (durationSeconds.clamp(0.0, 86400.0) * 1000).round(),
      ),
      videoId: video.videoId,
    );

    _playerUiState.value = _playerUiState.value.copyWith(
      video: video,
      isFavorite: _isFavorite(video.videoId),
      isLiked: _likedIds.contains(video.videoId),
      isDisliked: _dislikedIds.contains(video.videoId),
      lyrics: const <LyricLine>[],
      lyricsLoading: true,
      lyricsSynced: false,
    );

    if (mounted) {
      setState(() {});
    }

    unawaited(_loadLyrics(video));
  }
}
