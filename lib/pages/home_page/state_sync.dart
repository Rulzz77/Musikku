part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Sinkronisasi state native, progres, statistik, snapshot, dan notifikasi media.
extension _HomeStateSync on _HomePageState {
  Future<void> _saveCurrentPlaybackSnapshot({
    bool queryNativePosition = false,
  }) {
    // Semua snapshot diproses berurutan supaya write yang lebih lama tidak
    // pernah selesai setelah write terbaru dan menimpa posisi yang benar.
    _snapshotSaveChain = _snapshotSaveChain.then((_) async {
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
        durationSeconds:
            _nativeState.duration.inMilliseconds / 1000.0,
      );
      await _storage.flushPendingWrites();
    });

    return _snapshotSaveChain;
  }

  void _onYoutubeState(NativeYoutubeState state) {
    if (!mounted) {
      return;
    }

    // Event dari lagu lama (masih terkirim sesaat setelah pindah lagu)
    // diabaikan, supaya posisi lagu lama tidak tersimpan / tampil sebagai
    // posisi lagu baru.
    final activeId = _currentVideo?.videoId ?? '';

    if (state.videoId.isNotEmpty &&
        activeId.isNotEmpty &&
        state.videoId != activeId) {
      return;
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

    _nativeStateNotifier.value = state;

    _savePlaybackProgress(state);
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
      _lastHandledEndedVideoId = '';
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
    if (endedVideoId.isEmpty || _isChangingTrack) {
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
    if (endedVideoId == _lastHandledEndedVideoId || _isAutoNextProcessing) {
      return;
    }

    // Tandai sebelum async.
    _lastHandledEndedVideoId = endedVideoId;

    unawaited(_handleAutoNext(endedVideoId));
  }

  void _recordListeningStats(NativeYoutubeState state) {
    final video = _currentVideo;
    if (video == null || video.videoId.isEmpty || state.videoId.isNotEmpty && state.videoId != video.videoId) {
      return;
    }

    if (!state.isPlaying && !state.isEnded) {
      return;
    }

    final position = state.position.inMilliseconds / 1000.0;
    final now = DateTime.now();

    // Recent-history uses actual playback progress, not the user's selection.
    // Count only small natural position deltas, so a seek does not fake ten
    // seconds of listening. A failed stream never reaches this threshold.
    if (state.isPlaying && state.videoId == video.videoId) {
      if (_historyTrackId != video.videoId) {
        _historyTrackId = video.videoId;
        _historyLastPositionSeconds = null;
        _historyListenedSeconds = 0.0;
        _historyRecordedForTrack = false;
      }
      final previousHistoryPosition = _historyLastPositionSeconds;
      if (previousHistoryPosition != null) {
        final historyDelta = position - previousHistoryPosition;
        if (historyDelta > 0 && historyDelta <= 3.0) {
          _historyListenedSeconds += historyDelta;
        }
      }
      _historyLastPositionSeconds = position;
      if (_historyListenedSeconds >= 10.0 && !_historyRecordedForTrack) {
        _historyRecordedForTrack = true;
        _rememberRecentlyPlayed(video);
      }
    }

    final isNewPlay = video.videoId != _statsLastVideoId || !_statsCountedCurrentPlay;

    var delta = 0.0;
    if (video.videoId == _statsLastVideoId && state.isPlaying && position >= _statsLastPositionSeconds) {
      delta = position - _statsLastPositionSeconds;
      delta = delta.clamp(0.0, 15.0);
    }

    if (isNewPlay || (delta >= 2.0 && now.difference(_statsLastRecordAt) >= const Duration(seconds: 4))) {
      _statsLastRecordAt = now;
      final existing = _listeningStatsById[video.videoId];
      _listeningStatsById[video.videoId] = ListeningStat(
        videoId: video.videoId,
        title: video.title,
        artist: video.channelTitle,
        thumbnailUrl: video.coverUrl,
        playCount: (existing?.playCount ?? 0) + (isNewPlay ? 1 : 0),
        skipCount: existing?.skipCount ?? 0,
        listenedSeconds: (existing?.listenedSeconds ?? 0) + delta,
        lastPlayedAt: now,
      );
      unawaited(_storage.recordListening(
        video: video,
        deltaSeconds: delta,
        newPlay: isNewPlay,
      ));
    }

    if (state.isPlaying) {
      _statsLastVideoId = video.videoId;
      _statsLastPositionSeconds = position;
      _statsCountedCurrentPlay = true;
    } else if (state.isEnded) {
      _statsLastVideoId = '';
      _statsLastPositionSeconds = 0.0;
      _statsCountedCurrentPlay = false;
    }
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

    _pendingSavedPosition =
        state.position.inMilliseconds / 1000.0;

    final now = DateTime.now();

    final shouldSave =
        now.difference(_lastPositionSaveAt) >= const Duration(seconds: 2) ||
        state.isEnded ||
        state.isPaused;

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
      positionSeconds: state.isEnded ? 0.0 : _pendingSavedPosition,
      durationSeconds: durationSeconds,
    );

    if (durationSeconds > 0.0) {
      final positionSeconds = state.isEnded
          ? durationSeconds
          : _pendingSavedPosition.clamp(0.0, durationSeconds);
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
}
