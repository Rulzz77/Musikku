part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Inti pemutaran: memutar lagu, watchdog, penanganan gagal putar, dan lirik.
extension _HomePlayback on _HomePageState {
  Future<void> _loadLyrics(YoutubeSearchResult video) async {
    final requestId = ++_lyricsRequestId;

    if (video.isLocal) {
      if (mounted && requestId == _lyricsRequestId) {
        _playerUiState.value = _playerUiState.value.copyWith(
          lyrics: const <LyricLine>[],
          lyricsLoading: false,
          lyricsSynced: false,
        );
      }
      return;
    }

    final result = await LyricsService.getLyrics(
      title: video.title,
      artist: video.channelTitle,
      albumName: video.album,
      durationSeconds: video.durationSeconds,
    );

    // Lagu sudah ganti selama menunggu → buang hasilnya.
    if (!mounted || requestId != _lyricsRequestId) {
      return;
    }

    _playerUiState.value = _playerUiState.value.copyWith(
      lyrics: result?.lines ?? const <LyricLine>[],
      lyricsLoading: false,
      lyricsSynced: result?.synced ?? false,
    );
  }

  /// Putar [video] dari [list]. Kalau sumber playlist berubah
  /// (misalnya dari pencarian ke favorit), playlist aktif diganti.
  Future<void> _playVideo(
    YoutubeSearchResult video, {
    bool recordHistory = true,
    double? restorePosition,
    double? restoreDurationSeconds,
    bool autoPlay = true,
  }) async {
    // A guest's track selection is a shared-room command, not a local playback
    // change. State snapshots from the host set _applyingListenTogetherState,
    // so this guard does not echo the host's state back as another command.
    if (_listenTogether.isGuest && !_applyingListenTogetherState) {
      if (video.isLocal) {
        if (mounted) _toast('File lokal hanya tersedia di perangkat masing-masing.');
        return;
      }
      try {
        await _listenTogether.requestTrackSelection(
          videoId: video.videoId,
          title: video.title,
          artist: video.channelTitle,
          thumbnailUrl: video.coverUrl,
          durationSeconds: video.durationSeconds,
        );
      } catch (error) {
        if (mounted) _toast('Tidak bisa memilih lagu untuk kamar: $error');
      }
      return;
    }

    final requestId = _playbackSessionGuard.beginTrackChange();

    _youtubeAudioRetryVideoId = video.videoId;
    _youtubeAudioRetryCount = 0;
    if (_youtubeEmbedErrorVideoId.isNotEmpty) {
      _youtubeEmbedErrorVideoId = '';
    }

    _radio.markPlayed(video);

    _playbackWatchdog?.cancel();

    _failureHandledFor = '';

    final previous = _currentVideo;

    final sameVideo = previous?.videoId == video.videoId;

    // Catat lagu sebelumnya untuk tombol Previous.
    if (recordHistory && previous != null && !sameVideo) {
      _playHistory.add(previous);

      if (_playHistory.length > 50) {
        _playHistory.removeAt(0);
      }
    }

    // Lagu yang sedang diputar keluar dari shuffle pool.
    if (_playerUiState.value.isShuffle) {
      _shufflePool.removeWhere((item) => item.videoId == video.videoId);
    }

    if (mounted) {
      setState(() {
        _currentVideo = video;
        // Halaman tonton (judul, deskripsi, komentar) harus ikut lagu baru saat
        // Next / Previous / auto-next. Kuncinya memakai videoId, jadi halaman
        // dibangun ulang dan memuat detail video yang baru.
        if (_youtubeWatchVideo != null) _youtubeWatchVideo = video;
      });
    }

    // Preset EQ mengikuti track yang sedang diputar. Bila belum pernah diatur
    // untuk track ini, pakai preset default dari Settings.
    try {
      final trackPreset = await _storage.loadEqualizerPresetForTrack(video.videoId);
      if (_playbackSessionGuard.isCurrentRequest(requestId)) {
        _equalizerPreset = trackPreset;
        await _youtubeController.setEqualizerPreset(trackPreset);
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('TRACK EQ RESTORE ERROR: $e');
    }

    if (!sameVideo) {
      _crossfadeFadingVideoId = '';
    }

    // Player native akan di-load sekarang, jadi lagu hasil restore tidak lagi
    // "menunggu load" — termasuk kalau user memilih lagu yang sama dengan
    // lagu terakhir. Kalau flag ini tertinggal, tombol Pause malah memuat ulang.
    _restoredNeedsLoad = false;

    if (!sameVideo) {
      // Start a fresh listening-history candidate. It will only be committed
      // once native playback proves that at least ten seconds were heard.
      _historyTrackId = video.videoId;
      _historyListenedSeconds = 0.0;
      _historyRecordedForTrack = false;

      // Lagu baru selalu dimulai dari posisi 0, kecuali ini adalah
      // pemulihan snapshot lagu terakhir saat aplikasi dibuka kembali.
      _pendingSavedPosition = restorePosition ?? 0.0;

      _lastPositionSaveAt =
          DateTime.fromMillisecondsSinceEpoch(0);
    }

    _nativeStateNotifier.value = NativeYoutubeState(
      playbackState: NativePlaybackState.unstarted,
      duration: Duration(
        milliseconds:
            ((restoreDurationSeconds ?? 0.0).clamp(0.0, 86400.0) * 1000)
                .round(),
      ),
      videoId: video.videoId,
    );

    final currentLyrics = _playerUiState.value.lyrics;
    final currentLyricsLoading = _playerUiState.value.lyricsLoading;
    final currentLyricsSynced = _playerUiState.value.lyricsSynced;

    _playerUiState.value = _playerUiState.value.copyWith(
      video: video,
      isFavorite: _isFavorite(video.videoId),
      isLiked: _likedIds.contains(video.videoId),
      isDisliked: _dislikedIds.contains(video.videoId),
      lyrics: sameVideo ? currentLyrics : const <LyricLine>[],
      lyricsLoading: sameVideo ? currentLyricsLoading : true,
      lyricsSynced: sameVideo ? currentLyricsSynced : false,
    );

    if (!sameVideo) {
      unawaited(_loadLyrics(video));
    }

    try {
      // Membatalkan fade lama sebelum menghitung transition baru. Tanpa ini,
      // fade-out lagu sebelumnya bisa selesai terlambat dan menurunkan volume
      // lagu yang baru saja dimulai.
      _cancelVolumeFade();

      final wasAutoFading = !sameVideo &&
          previous != null &&
          _crossfadeFadingVideoId == previous.videoId;

      final transitionPlaying = !sameVideo &&
          previous != null &&
          _crossfadeSeconds > 0 &&
          _nativeState.isEffectivelyPlaying &&
          restorePosition == null &&
          !wasAutoFading;

      if (transitionPlaying) {
        await _fadeVolume(
          from: _playerVolumePercent,
          to: 0,
          duration: Duration(milliseconds: _crossfadeSeconds * 500),
        );
      }

      final safeRestorePosition =
          restorePosition != null && restorePosition.isFinite
              ? restorePosition.clamp(0.0, 86400.0).toDouble()
              : 0.0;

      final safeRestoreDuration =
          restoreDurationSeconds != null && restoreDurationSeconds.isFinite
              ? restoreDurationSeconds.clamp(0.0, 86400.0).toDouble()
              : _nativeState.duration.inMilliseconds / 1000.0;

      final hasRestorePosition = safeRestorePosition > 0;

      // Unified playback: local tracks and YouTube audio-only streams both
      // use Media3. A failed remote stream remains an explicit error; never
      // mount a video player as a fallback.
      if (video.isLocal) {
        if (previous != null && !previous.isLocal) {
          try {
            await _youtubeController.pauseVideo();
          } catch (_) {}
        }
        await _youtubeController.loadLocalTrack(
          mediaId: video.localMediaId.isNotEmpty
              ? video.localMediaId
              : video.videoId.replaceFirst('local:', ''),
          title: video.title,
          artist: video.channelTitle,
          mediaUri: video.mediaUri,
          startSeconds: hasRestorePosition ? safeRestorePosition : 0.0,
          durationSeconds: safeRestoreDuration,
        );
      } else {
        try {
          // Musik utama diputar oleh ExoPlayer native, sehingga bisa tetap
          // hidup ketika layar mati tanpa bergantung pada iframe/WebView.
          await _youtubeController.loadYoutubeAudioTrack(
            videoId: video.videoId,
            title: video.title,
            artist: video.channelTitle,
            thumbnailUrl: video.coverUrl,
            startSeconds: hasRestorePosition ? safeRestorePosition : 0.0,
            durationSeconds: video.durationSeconds ?? safeRestoreDuration,
            playing: autoPlay,
          );
        } catch (audioError) {
          // MusikKu adalah pemutar audio saja. Jangan diam-diam membuka video
          // YouTube ketika direct audio stream gagal, karena itu membuat
          // sumber suara bercampur dan state player memicu auto-next palsu.
          debugPrint('YOUTUBE AUDIO RESOLVE FAILED: $audioError');
          if (_playbackSessionGuard.isCurrentRequest(requestId)) {
            _nativeStateNotifier.value = NativeYoutubeState(
              playbackState: NativePlaybackState.error,
              videoId: video.videoId,
              duration: Duration(
                milliseconds: ((video.durationSeconds ?? safeRestoreDuration) * 1000).round(),
              ),
            );
            unawaited(AppHealthMonitor.instance.record(
              kind: 'PlaybackLoadFailure',
              error: 'Audio source could not be resolved for playback.',
            ));
            _showPlaybackRecoverySnack(
              video,
              'Lagu ini gagal dimuat sebagai audio.',
              positionSeconds: safeRestorePosition,
              durationSeconds: safeRestoreDuration,
            );
          }
          return;
        }
      }

      if (transitionPlaying || wasAutoFading) {
        await _fadeVolume(
          from: 0,
          to: _playerVolumePercent,
          duration: Duration(milliseconds: _crossfadeSeconds * 500),
        );
      } else {
        await _setPlayerVolume(_playerVolumePercent);
      }
      _crossfadeFadingVideoId = '';

      if (!_playbackSessionGuard.isCurrentRequest(requestId)) {
        return;
      }

      if (autoPlay) {
        _armPlaybackWatchdog(video.videoId, requestId);
      }

      if (hasRestorePosition) {
        _pendingSavedPosition = safeRestorePosition;
        _lastPositionSaveAt = DateTime.now();
        await _storage.saveLastPlayed(
          video,
          positionSeconds: safeRestorePosition,
          durationSeconds: safeRestoreDuration,
        );

        if (!autoPlay) {
          // API native loadVideo memang autoplay. Hanya dipakai sebagai
          // safeguard bila caller meminta restore tanpa autoplay.
          await Future<void>.delayed(const Duration(milliseconds: 700));
          if (_playbackSessionGuard.isCurrentRequest(requestId)) {
            await _youtubeController.pauseVideo();
          }
        }

        if (mounted && safeRestorePosition >= 3) {
          _toast(
            'Melanjutkan dari ${_formatStoredPosition(safeRestorePosition)}',
            duration: const Duration(seconds: 2),
          );
        }
      } else if (!autoPlay) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (_playbackSessionGuard.isCurrentRequest(requestId)) {
          await _youtubeController.pauseVideo();
        }
      }
    } catch (e) {
      debugPrint('PLAY VIDEO ERROR: $e');
      if (_playbackSessionGuard.isCurrentRequest(requestId) && _currentVideo?.videoId == video.videoId) {
        unawaited(AppHealthMonitor.instance.record(
          kind: 'PlaybackLoadFailure',
          error: e,
        ));
        _showPlaybackRecoverySnack(
          video,
          'Pemutaran gagal. Periksa koneksi, lalu coba lagi.',
          positionSeconds: restorePosition ?? _nativeState.position.inMilliseconds / 1000.0,
          durationSeconds: restoreDurationSeconds ?? _nativeState.duration.inMilliseconds / 1000.0,
        );
      }
    } finally {
      _playbackSessionGuard.finishTrackChange(requestId);
    }
  }

  /// Called if ExoPlayer starts but YouTube rejects/expires the direct stream
  /// URL after resolution. Fall back to the embedded YouTube player once.
  Future<void> _fallbackFromYoutubeAudioError({
    String? videoId,
    double? positionSeconds,
    required bool shouldPlay,
  }) async {
    final video = _currentVideo;
    if (!mounted || video == null || video.isLocal ||
        !_youtubeController.isUsingYoutubeAudio) {
      return;
    }
    // An error from the previous track must not replace the track the user
    // has already selected.
    if (videoId != null && videoId.isNotEmpty && videoId != video.videoId) {
      return;
    }

    final fallbackPosition = positionSeconds != null && positionSeconds.isFinite
        ? positionSeconds
        : _nativeState.position.inMilliseconds / 1000.0;
    final safePosition = fallbackPosition.clamp(0.0, 86400.0).toDouble();

    if (_youtubeAudioRetryVideoId != video.videoId) {
      _youtubeAudioRetryVideoId = video.videoId;
      _youtubeAudioRetryCount = 0;
    }

    // Direct stream URLs can expire or be rejected. Re-resolve a fresh URL
    // once, then leave an actionable error instead of starting video playback.
    if (_youtubeAudioRetryCount < 1) {
      _youtubeAudioRetryCount++;
      try {
        await _youtubeController.loadYoutubeAudioTrack(
          videoId: video.videoId,
          title: video.title,
          artist: video.channelTitle,
          thumbnailUrl: video.coverUrl,
          startSeconds: safePosition,
          durationSeconds: video.durationSeconds ??
              _nativeState.duration.inMilliseconds / 1000.0,
          // Never start the hidden Media3 player over the visible YouTube
          // player. It resumes only when Android has actually backgrounded us.
          playing: shouldPlay,
        );
        await _setPlayerVolume(_playerVolumePercent);
        if (mounted) {
          _toast(shouldPlay
              ? 'Link audio diperbarui; pemutaran background dicoba lagi.'
              : 'Sumber audio diperbarui. Lagu siap diputar.');
        }
        return;
      } catch (retryError) {
        debugPrint('YOUTUBE AUDIO RETRY FAILED: $retryError');
      }
    }

    if (!shouldPlay) {
      if (mounted) {
        _toast('Sumber audio tidak tersedia untuk lagu ini. Coba lagu lain.');
      }
      return;
    }

    try {
      // In background, don't try to restart an embedded video as a fallback:
      // the official iframe isn't a reliable screen-off audio source.
      await _youtubeController.pauseVideo();
      if (mounted) {
        _toast('Sumber audio gagal diperbarui. Tekan putar ulang untuk mencoba lagi.');
      }
    } catch (e) {
      debugPrint('BACKGROUND AUDIO RETRY FAILED: $e');
      if (mounted) _toast('Sumber audio gagal. Coba lagu lain atau ulangi nanti.');
    }
  }

  //
  // Video bisa dihapus, diblokir embed, atau dibatasi umur. Dua jalur
  // deteksi: (1) native mengirim state 'error', (2) watchdog: 15 detik
  // setelah load tapi player tidak pernah playing / buffering.
  //

  void _armPlaybackWatchdog(String videoId, int requestId) {
    _playbackWatchdog?.cancel();

    _playbackWatchdog = Timer(const Duration(seconds: 15), () {
      if (!mounted || !_playbackSessionGuard.isCurrentRequest(requestId)) {
        return;
      }

      if (_currentVideo?.videoId != videoId) {
        return;
      }

      final playback = _nativeState.playbackState;

      final stuck = playback == NativePlaybackState.unstarted ||
          playback == NativePlaybackState.unknown ||
          playback == NativePlaybackState.cued ||
          playback == NativePlaybackState.error;

      if (stuck) {
        unawaited(_handlePlaybackFailure(videoId));
      }
    });
  }

  Future<void> _handlePlaybackFailure(String videoId) async {
    final video = _currentVideo;
    if (video == null || video.videoId != videoId || !mounted) return;

    // Jangan auto-skip saat audio resolver/player error. Dulu error dari player
    // video tersembunyi memanggil _next(), sehingga lagu dapat berpindah sendiri
    // walaupun audio lagu aktif sebenarnya belum habis.
    if (_failureHandledFor == videoId) return;
    _failureHandledFor = videoId;
    _playbackWatchdog?.cancel();

    try {
      await _youtubeController.pauseVideo();
    } catch (_) {}

    unawaited(AppHealthMonitor.instance.record(
      kind: 'PlaybackFailure',
      error: 'Playback watchdog timed out; state=${_nativeState.playbackState.name}.',
    ));
    _showPlaybackRecoverySnack(
      video,
      'Lagu gagal diputar. Coba lagi atau pilih lagu berikutnya.',
      positionSeconds: _nativeState.position.inMilliseconds / 1000.0,
      durationSeconds: _nativeState.duration.inMilliseconds / 1000.0,
    );
  }

  void _showPlaybackRecoverySnack(
    YoutubeSearchResult video,
    String message, {
    double? positionSeconds,
    double? durationSeconds,
  }) {
    if (!mounted || _currentVideo?.videoId != video.videoId) return;

    final rawPosition = positionSeconds ?? 0.0;
    final rawDuration = durationSeconds ?? 0.0;
    final safePosition = rawPosition.isFinite
        ? rawPosition.clamp(0.0, 86400.0).toDouble()
        : 0.0;
    final safeDuration = rawDuration.isFinite
        ? rawDuration.clamp(0.0, 86400.0).toDouble()
        : 0.0;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'COBA LAGI',
          onPressed: () {
            if (!mounted || _currentVideo?.videoId != video.videoId) return;
            unawaited(_retryFailedPlayback(
              video,
              positionSeconds: safePosition,
              durationSeconds: safeDuration,
            ));
          },
        ),
      ),
    );
  }

  Future<void> _retryFailedPlayback(
    YoutubeSearchResult video, {
    required double positionSeconds,
    required double durationSeconds,
  }) async {
    if (!mounted || _currentVideo?.videoId != video.videoId) return;
    _failureHandledFor = '';
    await _playVideo(
      video,
      recordHistory: false,
      restorePosition: positionSeconds,
      restoreDurationSeconds: durationSeconds,
      autoPlay: true,
    );
  }
}
