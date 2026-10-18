part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Kontrol pemutar: play/pause, previous, next, stop, shuffle, repeat.
extension _HomeControls on _HomePageState {
  Future<void> _persistPlaybackModes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_shufflePrefKey, _playerUiState.value.isShuffle);
      await prefs.setBool(_smartShufflePrefKey, _playerUiState.value.isSmartShuffle);
      await prefs.setInt(_loopModePrefKey, _playerUiState.value.loopMode.index);
    } catch (_) {}
  }

  void _toggleShuffle() {
    final next = !_playerUiState.value.isShuffle;
    final smart = next && _playerUiState.value.isSmartShuffle;

    _playerUiState.value = _playerUiState.value.copyWith(
      isShuffle: next,
      isSmartShuffle: smart,
    );

    if (next) {
      _prepareShufflePool(excludeCurrent: true);
    } else {
      _shufflePool = [];
    }

    unawaited(_persistPlaybackModes());
    _toast(next ? 'Shuffle aktif · sumber musik tetap terpisah' : 'Shuffle dimatikan');
    if (mounted) setState(() {});
  }

  void _toggleSmartShuffle() {
    final next = !_playerUiState.value.isSmartShuffle;
    final shuffle = next || _playerUiState.value.isShuffle;

    _playerUiState.value = _playerUiState.value.copyWith(
      isShuffle: shuffle,
      isSmartShuffle: next,
    );

    if (shuffle) {
      _prepareShufflePool(excludeCurrent: true);
    }

    unawaited(_persistPlaybackModes());
    _toast(next ? 'Smart Shuffle aktif · sumber musik tetap terpisah' : 'Smart Shuffle dimatikan');
    if (mounted) setState(() {});
  }

  void _cycleLoopMode() {
    final current = _playerUiState.value.loopMode;
    final next = switch (current) {
      LoopModeCustom.off => LoopModeCustom.all,
      LoopModeCustom.all => LoopModeCustom.one,
      LoopModeCustom.one => LoopModeCustom.off,
    };

    _playerUiState.value = _playerUiState.value.copyWith(loopMode: next);
    unawaited(_persistPlaybackModes());

    final label = switch (next) {
      LoopModeCustom.off => 'Repeat dimatikan',
      LoopModeCustom.all => 'Repeat semua aktif',
      LoopModeCustom.one => 'Repeat satu aktif',
    };
    _toast(label);
    if (mounted) setState(() {});
  }

  Future<void> _recordManualSkipIfNeeded() async {
    final video = _currentVideo;
    if (video == null || _nativeState.isEnded) return;

    final seconds = _nativeState.position.inMilliseconds / 1000.0;
    if (seconds > 20.0) return;

    final existing = _listeningStatsById[video.videoId];
    _listeningStatsById[video.videoId] = ListeningStat(
      videoId: video.videoId,
      title: video.title,
      artist: video.channelTitle,
      thumbnailUrl: video.coverUrl,
      playCount: existing?.playCount ?? 0,
      skipCount: (existing?.skipCount ?? 0) + 1,
      listenedSeconds: existing?.listenedSeconds ?? 0.0,
      lastPlayedAt: existing?.lastPlayedAt ?? DateTime.now(),
    );
    await _storage.recordSkip(video);
  }

  Future<void> _togglePlayPause() async {
    if (_playPauseBusy) {
      return;
    }

    final video = _currentVideo;

    if (video == null) {
      return;
    }

    _playPauseBusy = true;

    try {
      // Setelah startup, player native sengaja belum di-load. Tombol Play
      // menjadi titik pertama yang benar-benar memuat lagu dan melanjutkan
      // dari posisi terakhir.
      if (_restoredNeedsLoad) {
        _restoredNeedsLoad = false;
        _isRestoringLastPlayback = true;

        try {
          await _playVideo(
            video,
            recordHistory: false,
            restorePosition: _pendingSavedPosition,
            restoreDurationSeconds:
                _nativeState.duration.inMilliseconds / 1000.0,
            autoPlay: true,
          );

          // Beri waktu event native yang tertunda agar tidak menimpa snapshot
          // hasil seek yang baru saja dipasang.
          await Future<void>.delayed(const Duration(milliseconds: 500));
        } finally {
          _isRestoringLastPlayback = false;
        }

        return;
      }

      final stateBelongsToTrack = _nativeState.videoId.isEmpty ||
          _nativeState.videoId == video.videoId;
      final remoteAudioUnavailable = !video.isLocal &&
          (!_youtubeController.isUsingYoutubeAudio ||
              !stateBelongsToTrack ||
              _nativeState.playbackState == NativePlaybackState.error);

      // A failed resolver can leave the previous Media3 item paused in the
      // service. Never call native Play against that stale item; reload the
      // selected song and resolve a fresh URL instead.
      if (remoteAudioUnavailable || _nativeState.playbackState == NativePlaybackState.error) {
        await _playVideo(video, recordHistory: false);
        return;
      }

      final shouldPause = _nativeState.isEffectivelyPlaying;
      if (shouldPause) {
        await _youtubeController.pauseVideo();
      } else {
        await _setPlayerVolume(_playerVolumePercent);
        _crossfadeFadingVideoId = '';
        await _youtubeController.playVideo();
      }
    } catch (e) {
      debugPrint('PLAY/PAUSE ERROR: $e');
    } finally {
      _playPauseBusy = false;
    }
  }

  Future<void> _previous() async {
    final current = _currentVideo;

    if (current == null) {
      return;
    }

    // Lagu hasil restore belum di-load ke native: seek tidak ada efeknya.
    // Cukup reset posisi tersimpan ke awal.
    if (_restoredNeedsLoad) {
      _pendingSavedPosition = 0.0;
      _nativeStateNotifier.value = NativeYoutubeState(
        playbackState: NativePlaybackState.paused,
        videoId: current.videoId,
      );
      unawaited(_saveCurrentPlaybackSnapshot());

      return;
    }

    // Sudah lewat 3 detik → ulang lagu ini dari awal.
    if (_nativeState.position > const Duration(seconds: 3)) {
      try {
        await _youtubeController.seekTo(seconds: 0);
      } catch (e) {
        debugPrint('PREVIOUS SEEK ERROR: $e');
      }

      return;
    }

    // Dalam sesi Shuffle, Previous juga harus menghormati batas sumber.
    // Abaikan entri history dari sesi sumber lain agar file lokal tidak meloncat
    // ke YouTube (atau sebaliknya) hanya karena riwayat pemutaran lama.
    if (_playerUiState.value.isShuffle) {
      while (_playHistory.isNotEmpty &&
          _playHistory.last.isLocal != current.isLocal) {
        _playHistory.removeLast();
      }
    }

    // Kembali ke lagu yang tadi diputar (berlaku juga untuk shuffle).
    if (_playHistory.isNotEmpty) {
      final previous = _playHistory.removeLast();

      await _playVideo(previous, recordHistory: false);

      return;
    }

    // Belum ada riwayat: mundur satu lagu di playlist.
    if (!_playerUiState.value.isShuffle && _activeList.isNotEmpty) {
      final index = _activeList.indexWhere(
        (video) => video.videoId == current.videoId,
      );

      if (index > 0) {
        await _playVideo(_activeList[index - 1], recordHistory: false);

        return;
      }

      if (index == 0 && _playerUiState.value.loopMode == LoopModeCustom.all) {
        await _playVideo(_activeList.last, recordHistory: false);

        return;
      }
    }

    // Tidak ada lagu sebelumnya → ulang dari awal.
    try {
      await _youtubeController.seekTo(seconds: 0);
    } catch (e) {
      debugPrint('PREVIOUS SEEK ERROR: $e');
    }
  }

  Future<void> _next({bool fromAutoNext = false}) async {
    final current = _currentVideo;

    if (current == null) {
      return;
    }

    if (!fromAutoNext) {
      unawaited(_recordManualSkipIfNeeded());
      _lastHandledEndedVideoId = '';
    }

    final isShuffle = _playerUiState.value.isShuffle;

    final loopMode = _playerUiState.value.loopMode;

    // Tombol Next manual juga mengambil dari antrean dulu
    // (auto-next sudah menangani antrean sendiri).
    if (!fromAutoNext && _queueManager.isNotEmpty) {
      final nextItem = _takeQueueItemForCurrentMode(shuffle: isShuffle);

      if (nextItem != null) {
        unawaited(_storage.saveQueue(_queueManager.items));
        await _playVideo(nextItem.video);

        if (mounted) {
          setState(() {});
        }

        return;
      }
    }

    // Lagu dari pencarian: lanjut ke upload terbaru yang masih sesuai konteks
    // pencarian (DJ -> DJ, pop -> pop, jadul -> jadul). Bukan urutan populer.
    // Favorit & "Terakhir diputar" tetap playlist.
    if (!current.isLocal &&
        (_activeSource == _ListSource.search ||
            _activeSource == _ListSource.radio) &&
        _radio.hasSeed) {
      await _nextFromRadio(fromAutoNext: fromAutoNext);

      return;
    }

    if (_activeList.isEmpty) {
      // Belum ada playlist (mis. baru buka app dan menekan Next):
      // lanjut ke lagu serupa dari lagu yang sedang dipilih.
      await _continueWithRadio(current, fromAutoNext: fromAutoNext);

      return;
    }

    // ==========================================================
    // SHUFFLE
    // ==========================================================

    if (isShuffle) {
      if (_shufflePool.isEmpty) {
        if (loopMode != LoopModeCustom.all) {
          if (_activeSource == _ListSource.local) {
            await _stopPlayback();
            _toast('Daftar musik lokal selesai.');
          } else {
            await _continueWithRadio(current, fromAutoNext: fromAutoNext);
          }
          return;
        }

        // Repeat all: mulai siklus shuffle baru.
        _prepareShufflePool(excludeCurrent: true);

        // Playlist cuma satu lagu → putar ulang lagu itu.
        if (_shufflePool.isEmpty) {
          await _playVideo(current);

          return;
        }
      }

      final randomVideo = _takeShuffleVideo();

      if (randomVideo != null) {
        await _playVideo(randomVideo);
      }

      return;
    }

    // ==========================================================
    // NORMAL
    // ==========================================================

    final index = _activeList.indexWhere(
      (video) => video.videoId == current.videoId,
    );

    // Lagu aktif bukan bagian dari playlist ini (misalnya dari antrean
    // atau pencarian lama) → mulai dari lagu pertama.
    if (index < 0) {
      await _playVideo(_activeList.first);

      return;
    }

    if (index < _activeList.length - 1) {
      await _playVideo(_activeList[index + 1]);

      return;
    }

    // Sudah di lagu terakhir.
    if (loopMode == LoopModeCustom.all) {
      await _playVideo(_activeList.first);

      return;
    }

    if (_activeSource == _ListSource.local) {
      await _stopPlayback();
      _toast('Daftar musik lokal selesai.');
      return;
    }

    await _continueWithRadio(current, fromAutoNext: fromAutoNext);
  }

  Future<void> _stopPlayback() async {
    try {
      await _youtubeController.pauseVideo();
    } catch (e) {
      debugPrint('STOP ERROR: $e');
    }

    try {
      _notificationStarted = false;
      _lastNotificationKey = '';
      _lastNotificationProgressAt =
          DateTime.fromMillisecondsSinceEpoch(0);

      await _youtubeController.stopNotification();
    } catch (e) {
      debugPrint('STOP NOTIFICATION ERROR: $e');
    }
  }
}
