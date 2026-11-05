part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Jarak minimum antar penyimpanan posisi saat lagu sedang diputar.
/// saveLastPlayed menulis beberapa key SharedPreferences sekaligus, jadi jangan
/// terlalu sering. Posisi terakhir tetap aman karena snapshot lifecycle
/// (background/keluar) mengambil posisi native terbaru.
const Duration _positionSaveInterval = Duration(seconds: 5);

/// Saat paused, simpan posisi di event pertama tetapi jangan menulis ulang
/// di setiap event berikutnya.
const Duration _pausedPositionSaveMinGap = Duration(seconds: 1);

/// Sinkronisasi state native, progres, statistik, snapshot, dan notifikasi media.
extension _HomeStateSync on _HomePageState {
  Future<void> _publishFloatingLyricsLine(NativeYoutubeState state) async {
    if (!FloatingLyricsBridge.enabled) return;
    final video = _currentVideo;
    if (video == null) return;
    final lyrics = _playerUiState.value.lyrics;
    LyricLine? activeLine;
    for (final line in lyrics) {
      if (line.time <= state.position) {
        activeLine = line;
      } else {
        break;
      }
    }
    final text = activeLine?.text ??
        (_playerUiState.value.lyricsSynced
            ? 'Lirik akan muncul saat lagu dimulai'
            : 'Lirik belum tersinkron untuk ${video.title}');
    await FloatingLyricsBridge.updateLine(text);
  }

  Future<void> _saveCurrentPlaybackSnapshot({
    bool queryNativePosition = false,
  }) {
    // Semua snapshot diproses berurutan supaya write yang lebih lama tidak
    // pernah selesai setelah write terbaru dan menimpa posisi yang benar.
    _snapshotSaveChain = _snapshotSaveChain.then((_) async {
      try {
        await _writePlaybackSnapshot(queryNativePosition: queryNativePosition);
      } finally {
        // Statistik dengar yang tertunda harus ikut ditulis walau tidak ada
        // lagu aktif atau sedang restore, supaya tidak hilang saat app di-kill.
        await _storage.flushPendingWrites();
      }
    }).catchError((Object error, StackTrace stackTrace) {
      // Rantai tidak boleh berhenti selamanya karena satu kegagalan.
      debugPrint('SNAPSHOT SAVE ERROR: $error');
    });

    return _snapshotSaveChain;
  }

  Future<void> _writePlaybackSnapshot({
    required bool queryNativePosition,
  }) async {
    if (_isRestoringLastPlayback) {
      return;
    }

    final video = _currentVideo;

    if (video == null) {
      return;
    }

    var positionSeconds = _pendingSavedPosition;

    // Lagu hasil restore belum di-load ke player native, jadi currentTime
    // pasti 0. Kalau dipakai, posisi tersimpan tertimpa 0 setiap app
    // dibuka lalu langsung ditutup tanpa menekan Play.
    if (queryNativePosition &&
        !_nativeState.isEnded &&
        !_restoredNeedsLoad) {
      try {
        final nativeSeconds = await _youtubeController.currentTime;

        if (nativeSeconds.isFinite && nativeSeconds >= 0) {
          positionSeconds = nativeSeconds;
          _pendingSavedPosition = nativeSeconds;
        }
      } catch (e) {
        debugPrint('CURRENT TIME SNAPSHOT ERROR: $e');
      }
    }

    if (_nativeState.isEnded) {
      positionSeconds = 0.0;
    }

    _lastPositionSaveAt = DateTime.now();

    await _storage.saveLastPlayed(
      video,
      positionSeconds: positionSeconds,
      durationSeconds: _nativeState.duration.inMilliseconds / 1000.0,
    );
  }

  void _applyNativeGaplessTrackTransition(
    YoutubeSearchResult video,
    NativeYoutubeState state,
  ) {
    final previous = _currentVideo;
    if (previous == null || previous.videoId == video.videoId) return;

    if (previous.videoId.isNotEmpty) {
      _playHistory.add(previous);
      if (_playHistory.length > 50) _playHistory.removeAt(0);
    }

    _radio.markPlayed(video);
    _crossfadeFadingVideoId = '';
    _historyTrackId = video.videoId;
    _historyListenedSeconds = 0.0;
    _historyRecordedForTrack = false;
    _pendingSavedPosition = 0.0;
    _lastGoodPositionSeconds = 0.0;
    _lastGoodPositionVideoId = video.videoId;
    _lastPositionSaveAt = DateTime.fromMillisecondsSinceEpoch(0);

    if (mounted) {
      setState(() {
        _currentVideo = video;
        if (_youtubeWatchVideo != null) _youtubeWatchVideo = video;
      });
    }

    _playerUiState.value = _playerUiState.value.copyWith(
      video: video,
      isFavorite: _isFavorite(video.videoId),
      isLiked: _likedIds.contains(video.videoId),
      isDisliked: _dislikedIds.contains(video.videoId),
      lyrics: const <LyricLine>[],
      lyricsLoading: true,
      lyricsSynced: false,
    );
    unawaited(_loadLyrics(video));

    // Restore per-track EQ without touching the native playlist or playback
    // position. The transition itself is owned by Media3.
    unawaited(() async {
      try {
        final preset = await _storage.loadEqualizerPresetForTrack(video.videoId);
        if (!mounted || _currentVideo?.videoId != video.videoId) return;
        _equalizerPreset = preset;
        await _youtubeController.setEqualizerPreset(preset);
        if (mounted) setState(() {});
      } catch (error) {
        debugPrint('GAPLESS TRACK EQ RESTORE ERROR: $error');
      }
    }());

    // _onYoutubeState publishes this event after the model is updated.
  }

  void _onYoutubeState(NativeYoutubeState state) {
    if (!mounted) {
      return;
    }

    // Event dari lagu lama (masih terkirim sesaat setelah pindah lagu)
    // diabaikan, supaya posisi lagu lama tidak tersimpan / tampil sebagai
    // posisi lagu baru.
    var activeId = _currentVideo?.videoId ?? '';

    if (state.videoId.isNotEmpty &&
        activeId.isNotEmpty &&
        state.videoId != activeId) {
      if (state.trackTransition) {
        YoutubeSearchResult? nextTrack;
        for (final candidate in _activeList) {
          if (candidate.videoId == state.videoId) {
            nextTrack = candidate;
            break;
          }
        }
        if (nextTrack == null) return;
        _applyNativeGaplessTrackTransition(nextTrack, state);
        activeId = nextTrack.videoId;
        if (!nextTrack.isLocal &&
            Platform.isAndroid &&
            _youtubeController.isUsingYoutubeAudio) {
          unawaited(_youtubeController.appendRemoteGaplessSuccessors(
            currentVideoId: nextTrack.videoId,
            candidates: _buildNativeYoutubeGaplessQueueFor(nextTrack),
          ));
        }
      } else {
        return;
      }
    }

    // Sebelum user menekan Play, player native belum memuat lagu hasil
    // restore. Event mentahnya (posisi 0 / unstarted) tidak boleh menimpa
    // posisi tersimpan. Kecuali native memang sudah memutar lagu yang sama.
    if (_restoredNeedsLoad) {
      if (state.isPlaying && state.videoId == activeId) {
        _restoredNeedsLoad = false;
      } else {
        return;
      }
    }

    final previousNativeState = _nativeStateNotifier.value;
    _nativeStateNotifier.value = state;
    unawaited(_publishFloatingLyricsLine(state));

    // Broadcast pause intent immediately and confirmed native state changes
    // as soon as they arrive. The periodic timer is only a recovery path; it
    // must not add up to two seconds of pause latency for other devices.
    if (_listenTogether.isHost) {
      final currentVideoId = _currentVideo?.videoId ?? '';
      final eventMatchesCurrentTrack = currentVideoId.isEmpty ||
          (state.videoId.isNotEmpty && state.videoId == currentVideoId);
      final pauseIntentChanged =
          previousNativeState.requestedPlaying != false &&
          state.requestedPlaying == false;
      final confirmedPlaybackStateChanged =
          previousNativeState.playbackState != state.playbackState &&
          state.requestedPlaying == null;
      final nativeTrackChanged = state.videoId.isNotEmpty &&
          state.videoId == currentVideoId &&
          previousNativeState.videoId != state.videoId;
      if (eventMatchesCurrentTrack &&
          (pauseIntentChanged || confirmedPlaybackStateChanged || nativeTrackChanged)) {
        _broadcastListenTogetherState();
      }
    }

    _syncBufferAlert(state);

    unawaited(_savePlaybackProgress(state));
    _recordListeningStats(state);

    if (state.isPlaying || state.isBuffering) {
      _playbackWatchdog?.cancel();
    }

    if (state.playbackState == NativePlaybackState.error &&
        _currentVideo?.isLocal == true) {
      // Native local-file failures are handled here. Remote audio failures
      // are resolved by the audio-service callback; don't restart or advance
      // a stale YouTube source in response to its old state event.
      unawaited(
        _handlePlaybackFailure(
          state.videoId.isNotEmpty ? state.videoId : activeId,
        ),
      );
    }

    // Saat task sedang ditutup, abaikan event transien yang sering datang
    // dengan posisi 0. Notification/service sudah punya snapshot posisi yang
    // benar dan akan dihentikan oleh Android saat task benar-benar dihapus.
    final transientClosingReset =
        _isAppExiting &&
        state.position.inMilliseconds + 500 <
            _pendingSavedPosition * 1000;

    if (!transientClosingReset) {
      final activeVideo = _currentVideo;
      // Before NewPipe has resolved and Media3 has accepted a URL, a remote
      // track is only a loading intent. Do not let notification sync start a
      // generic YouTube service over the previous, still-paused audio item.
      if (activeVideo == null || activeVideo.isLocal ||
          _youtubeController.isUsingYoutubeAudio) {
        _syncNotification(state);
      }
    }

    // Lagu diputar lagi (mis. Play setelah lagu terakhir selesai) →
    // "ended" berikutnya harus bisa diproses lagi.
    if (state.isPlaying) {
      _playbackSessionGuard.resetEndedEvent();
    }

    _maybeStartAutoCrossfade(state);
    // Auto-next now depends on the real Media3 STATE_ENDED event only. The
    // old near-end timer queried the old YouTube view and could skip songs
    // early or twice when that view was stale/hidden.

    if (!state.isEnded) {
      return;
    }

    final currentVideoId = _currentVideo?.videoId ?? '';

    final endedVideoId =
        state.videoId.isNotEmpty ? state.videoId : currentVideoId;

    // Tidak ada ID / sedang pindah lagu.
    if (endedVideoId.isEmpty || _playbackSessionGuard.isChangingTrack) {
      return;
    }

    // Event dari video lama.
    if (currentVideoId.isNotEmpty && endedVideoId != currentVideoId) {
      return;
    }

    // A previous Media3 item can report STATE_ENDED while a new YouTube
    // stream is still resolving. It must never advance the queue.
    final activeVideo = _currentVideo;
    if (activeVideo != null && !activeVideo.isLocal &&
        !_youtubeController.isUsingYoutubeAudio) {
      return;
    }

    // Event ended yang sama sudah diproses / masih diproses.
    // Claim before starting async work; duplicate native callbacks cannot
    // advance the queue more than once for the same end event.
    if (!_playbackSessionGuard.tryClaimEndedEvent(endedVideoId)) {
      return;
    }

    unawaited(_handleAutoNext(endedVideoId));
  }

  void _recordListeningStats(NativeYoutubeState state) {
    final video = _currentVideo;
    if (video == null ||
        video.videoId.isEmpty ||
        (state.videoId.isNotEmpty && state.videoId != video.videoId)) {
      return;
    }

    final position = state.position.inMilliseconds / 1000.0;
    final now = DateTime.now();

    // Use one trusted measurement for both lifetime statistics and listening
    // history. This prevents seeking, buffering, paused time, and stale native
    // events from inflating either total.
    final sample = _listeningPlaybackTracker.update(
      videoId: video.videoId,
      positionSeconds: position,
      isPlaying: state.isEffectivelyPlaying,
      isEnded: state.isEnded,
      timestamp: now,
    );

    if (_historyTrackId != video.videoId || sample.newPlay) {
      _historyTrackId = video.videoId;
      _historyListenedSeconds = 0.0;
      _historyRecordedForTrack = false;
    }
    if (sample.listenedSeconds > 0) {
      _historyListenedSeconds += sample.listenedSeconds;
    }
    if (_historyListenedSeconds >= 10.0 && !_historyRecordedForTrack) {
      _historyRecordedForTrack = true;
      _rememberRecentlyPlayed(video);
    }

    if (!sample.newPlay && sample.listenedSeconds <= 0) return;

    final existing = _listeningStatsById[video.videoId];
    _listeningStatsById[video.videoId] = ListeningStat(
      videoId: video.videoId,
      title: video.title,
      artist: video.channelTitle,
      thumbnailUrl: video.coverUrl,
      playCount: (existing?.playCount ?? 0) + (sample.newPlay ? 1 : 0),
      skipCount: existing?.skipCount ?? 0,
      listenedSeconds:
          (existing?.listenedSeconds ?? 0) + sample.listenedSeconds,
      lastPlayedAt: now,
    );
    unawaited(_storage.recordListening(
      video: video,
      deltaSeconds: sample.listenedSeconds,
      newPlay: sample.newPlay,
    ));
  }

  Future<void> _savePlaybackProgress(NativeYoutubeState state) async {
    if (_isRestoringLastPlayback) {
      // Posisi native saat load/seek belum stabil. Jangan menyimpan 0 atau
      // posisi sementara karena itu dapat menimpa snapshot terakhir.
      return;
    }

    final video = _currentVideo;

    if (video == null) {
      return;
    }

    // Saat app di background, musik tetap jalan. Dulu semua penyimpanan
    // dimatikan di fase ini, sehingga kalau app ditutup dari recent apps
    // posisinya kembali ke saat app pertama kali di-minimize.
    // Sekarang hanya kemajuan nyata (sedang playing, posisi tidak mundur)
    // yang boleh disimpan; event transien paused/0 tetap ditolak.
    if (_isAppExiting) {
      final progressed = state.isPlaying &&
          state.videoId == video.videoId &&
          state.position.inMilliseconds >=
              (_pendingSavedPosition * 1000).round() - 500;

      if (!progressed) {
        return;
      }
    }

    if (state.isEnded) {
      _lastGoodPositionSeconds = 0.0;
      _lastGoodPositionVideoId = video.videoId;
    } else if (state.videoId == video.videoId &&
        (state.isPlaying || state.isBuffering || state.isPaused) &&
        state.position.inMilliseconds > 1000) {
      _lastGoodPositionSeconds = state.position.inMilliseconds / 1000.0;
      _lastGoodPositionVideoId = video.videoId;
    }

    _pendingSavedPosition =
        state.position.inMilliseconds / 1000.0;

    // Salin sekarang: setelah await di bawah, _pendingSavedPosition bisa saja
    // sudah milik lagu berikutnya.
    final savedPosition = _pendingSavedPosition;

    final now = DateTime.now();
    final sinceLastSave = now.difference(_lastPositionSaveAt);

    // Saat paused, jangan melewati batas waktu sama sekali: event paused bisa
    // datang berulang dan tiap penyimpanan menulis beberapa key sekaligus.
    final shouldSave = sinceLastSave >= _positionSaveInterval ||
        state.isEnded ||
        (state.isPaused && sinceLastSave >= _pausedPositionSaveMinGap);

    if (!shouldSave) {
      return;
    }

    // Jangan query native lagi di setiap event posisi. Event native sudah
    // membawa posisi terbaru; query tambahan hanya dilakukan saat lifecycle
    // aplikasi berubah (background/keluar).
    _lastPositionSaveAt = now;

    final durationSeconds = state.duration.inMilliseconds / 1000.0;

    await _storage.saveLastPlayed(
      video,
      positionSeconds: state.isEnded ? 0.0 : savedPosition,
      durationSeconds: durationSeconds,
    );

    if (durationSeconds > 0.0) {
      final positionSeconds = state.isEnded
          ? durationSeconds
          : savedPosition.clamp(0.0, durationSeconds).toDouble();
      var progress = (positionSeconds / durationSeconds).clamp(0.0, 1.0).toDouble();
      if (state.isEnded || positionSeconds >= durationSeconds - 2.0) {
        progress = 1.0;
      }

      final progressUiDue =
          now.difference(_lastWatchProgressUiAt) >= const Duration(seconds: 4) ||
          state.isEnded;
      if (mounted && progressUiDue && _watchProgress[video.videoId] != progress) {
        _lastWatchProgressUiAt = now;
        setState(() {
          _watchProgress[video.videoId] = progress;
          _watchDuration[video.videoId] = durationSeconds;
        });
      }

      final progressDue =
          now.difference(_lastWatchProgressSaveAt) >= const Duration(seconds: 5) ||
          state.isEnded;
      if (progressDue) {
        _lastWatchProgressSaveAt = now;
        unawaited(
          _storage.saveWatchProgress(
            video.videoId,
            positionSeconds: positionSeconds,
            durationSeconds: durationSeconds,
          ),
        );
      }
    }
  }

  void _rememberRecentlyPlayed(YoutubeSearchResult video) {
    _recentlyPlayed.removeWhere(
      (item) => item.videoId == video.videoId,
    );

    _recentlyPlayed.insert(0, video);

    if (_recentlyPlayed.length > StorageService.maxRecentlyPlayed) {
      _recentlyPlayed.removeRange(
        StorageService.maxRecentlyPlayed,
        _recentlyPlayed.length,
      );
    }

    unawaited(_storage.saveRecentlyPlayed(_recentlyPlayed));

    if (mounted) {
      setState(() {});
    }
  }

  //
  // Dipanggil hanya kalau lagu / status play berubah (bukan tiap
  // event posisi) supaya native tidak dibanjiri update.
  //

  void _syncNotification(NativeYoutubeState state) {
    final video = _currentVideo;

    if (video == null) {
      return;
    }

    if (state.videoId.isNotEmpty && state.videoId != video.videoId) {
      return;
    }

    if (state.playbackState == NativePlaybackState.unknown ||
        state.playbackState == NativePlaybackState.unstarted ||
        state.playbackState == NativePlaybackState.cued) {
      return;
    }

    final playing = state.isPlaying || state.isBuffering;
    final now = DateTime.now();
    final playbackKey = '${video.videoId}|$playing';
    final sinceLast = now.difference(_lastNotificationProgressAt);

    // MediaSession + service native memperkirakan posisi sendiri antar
    // update, jadi tidak perlu dikirim tiap detik (tiap kirim = intent
    // startForegroundService). Kirim hanya kalau:
    //  - play/pause atau lagu berubah,
    //  - durasi baru diketahui,
    //  - posisi melompat (seek) dibanding perkiraan,
    //  - sudah 10 detik (sinkronisasi ulang).
    final expectedMs = _lastNotificationPositionMs +
        (playing ? sinceLast.inMilliseconds : 0);

    final jumped =
        (state.position.inMilliseconds - expectedMs).abs() > 2000;

    final durationChanged = state.duration != _lastNotificationDuration;

    final refreshDue = sinceLast >= const Duration(seconds: 10);

    if (playbackKey == _lastNotificationKey &&
        !refreshDue &&
        !jumped &&
        !durationChanged) {
      return;
    }

    _lastNotificationKey = playbackKey;
    _lastNotificationProgressAt = now;
    _lastNotificationPositionMs = state.position.inMilliseconds;
    _lastNotificationDuration = state.duration;

    unawaited(_pushNotification(
      video,
      playing,
      position: state.position,
      duration: state.duration,
    ));
  }

  Future<void> _pushNotification(
    YoutubeSearchResult video,
    bool playing, {
    required Duration position,
    required Duration duration,
  }) async {
    try {
      if (_notificationStarted) {
        await _youtubeController.updateNotification(
          videoId: video.videoId,
          title: video.title,
          artist: video.channelTitle,
          thumbnailUrl: video.coverUrl,
          mediaUri: video.mediaUri,
          playing: playing,
          position: position,
          duration: duration,
        );
      } else {
        await _youtubeController.startNotification(
          videoId: video.videoId,
          title: video.title,
          artist: video.channelTitle,
          thumbnailUrl: video.coverUrl,
          mediaUri: video.mediaUri,
          playing: playing,
          position: position,
          duration: duration,
        );

        _notificationStarted = true;
      }
    } catch (e) {
      debugPrint('NOTIFICATION ERROR: $e');
    }
  }


  void _onBufferAlertThresholdChanged() {
    if (_nativeState.isBuffering) _scheduleBufferAlert();
  }

  void _syncBufferAlert(NativeYoutubeState state) {
    final activeId = state.videoId.isNotEmpty
        ? state.videoId
        : (_currentVideo?.videoId ?? '');

    if (state.isBuffering && activeId.isNotEmpty) {
      if (_bufferAlertVideoId != activeId || _bufferingStartedAt == null) {
        _bufferAlertTimer?.cancel();
        _bufferAlertTimer = null;
        _bufferAlertVideoId = activeId;
        _bufferingStartedAt = DateTime.now();
        _bufferAlertShown = false;
      }
      if (!_bufferAlertShown && _bufferAlertTimer == null) {
        _scheduleBufferAlert();
      }
      return;
    }

    _bufferAlertTimer?.cancel();
    _bufferAlertTimer = null;
    _bufferingStartedAt = null;
    _bufferAlertShown = false;
    if (activeId.isNotEmpty) _bufferAlertVideoId = activeId;
  }

  void _scheduleBufferAlert() {
    _bufferAlertTimer?.cancel();
    _bufferAlertTimer = null;
    final startedAt = _bufferingStartedAt;
    final videoId = _bufferAlertVideoId;
    if (startedAt == null || videoId.isEmpty || _bufferAlertShown) return;

    final threshold = Duration(seconds: widget.settings.bufferAlertSeconds.value);
    final elapsed = DateTime.now().difference(startedAt);
    final remaining = threshold - elapsed;
    _bufferAlertTimer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
      _bufferAlertTimer = null;
      if (!mounted || !_nativeState.isBuffering ||
          _currentVideo?.videoId != videoId || _bufferAlertShown) {
        return;
      }
      _bufferAlertShown = true;
      _toast(
        'Masih buffering setelah ${widget.settings.bufferAlertSeconds.value} detik. Periksa koneksi internet.',
        duration: const Duration(seconds: 4),
      );
    });
  }

}