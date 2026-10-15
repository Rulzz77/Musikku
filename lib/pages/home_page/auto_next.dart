part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Auto-next saat lagu selesai, beserta retry jika macet.
extension _HomeAutoNext on _HomePageState {
  /// Fallback terakhir kalau callback native `ended` tidak sampai ke Flutter.
  /// Kita tunggu sedikit setelah durasi habis supaya tidak memotong lagu lebih awal.
  void _armCompletionAutoNext(NativeYoutubeState state) {
    if (_suppressAutoNextInPip) {
      _nearEndAutoNextTimer?.cancel();
      _nearEndAutoNextTimer = null;
      _nearEndArmedVideoId = '';
      return;
    }

    // Selesai lagu kadang tidak dikirim sebagai `ended` (WebView background),
    // tapi sebagai `paused` tepat di ujung durasi. Anggap itu selesai juga.
    final atEnd = state.duration.inMilliseconds > 5000 &&
        state.position.inMilliseconds >= state.duration.inMilliseconds - 1500;

    if (!(state.isPlaying || (state.isPaused && atEnd)) ||
        state.duration.inMilliseconds <= 5000 ||
        state.videoId.isEmpty ||
        state.position.inMilliseconds <= 0) {
      return;
    }

    final remaining =
        state.duration.inMilliseconds - state.position.inMilliseconds;

    if (remaining > 2000) {
      if (_nearEndArmedVideoId == state.videoId) {
        _nearEndAutoNextTimer?.cancel();
        _nearEndAutoNextTimer = null;
        _nearEndArmedVideoId = '';
      }
      return;
    }

    if (_nearEndArmedVideoId == state.videoId || _isAutoNextProcessing) {
      return;
    }

    _nearEndArmedVideoId = state.videoId;
    _nearEndAutoNextTimer?.cancel();
    _nearEndAutoNextTimer = Timer(const Duration(milliseconds: 2500), () async {
      final latest = _nativeState;
      final id = _currentVideo?.videoId ?? '';

      if (id.isEmpty ||
          id != state.videoId ||
          (latest.videoId.isNotEmpty && latest.videoId != id) ||
          latest.isEnded ||
          _isChangingTrack ||
          !(latest.isPlaying || latest.isPaused) ||
          latest.duration.inMilliseconds <= 5000) {
        return;
      }

      var positionSeconds = latest.position.inMilliseconds / 1000.0;
      try {
        positionSeconds = await _youtubeController.currentTime;
      } catch (_) {
        // Pakai posisi event terakhir.
      }

      final durationSeconds = latest.duration.inMilliseconds / 1000.0;
      if (durationSeconds <= 5.0 ||
          positionSeconds < durationSeconds - 1.25) {
        return;
      }

      if (_lastHandledEndedVideoId == id || _isAutoNextProcessing) {
        return;
      }

      _lastHandledEndedVideoId = id;
      await _handleAutoNext(id);
    });
  }

  /// Kalau setelah auto-next lagu yang sama masih jadi lagu aktif (tidak ada
  /// kandidat / jaringan gagal), coba lagi beberapa kali, bukan menyerah.
  void _scheduleAutoNextRetryIfStuck(String endedVideoId) {
    if (!mounted || _currentVideo?.videoId != endedVideoId) {
      return;
    }

    if (_autoNextRetries >= 4) {
      return;
    }

    _autoNextRetries++;

    _autoNextRetryTimer?.cancel();
    _autoNextRetryTimer = Timer(
      Duration(seconds: 2 * _autoNextRetries),
      () {
        if (!mounted ||
            _currentVideo?.videoId != endedVideoId ||
            _isAutoNextProcessing ||
            _isChangingTrack) {
          return;
        }

        final st = _nativeState;

        // Lagu masih benar-benar diputar ulang / user sudah menekan Play lagi.
        if (st.isPlaying && !st.isEnded) {
          return;
        }

        _lastHandledEndedVideoId = '';
        unawaited(_handleAutoNext(endedVideoId));
      },
    );
  }

  Future<void> _handleAutoNext(String endedVideoId) async {
    if (_suppressAutoNextInPip) {
      return;
    }

    if (_isAutoNextProcessing) {
      return;
    }

    final currentVideo = _currentVideo;

    if (currentVideo == null || currentVideo.videoId != endedVideoId) {
      return;
    }

    _isAutoNextProcessing = true;

    try {
      // 0. TIMER TIDUR "SETELAH LAGU INI"
      if (_stopAfterCurrent) {
        _clearSleepTimer();

        await _stopPlayback();

        return;
      }

      final loopMode = _playerUiState.value.loopMode;
      final isShuffle = _playerUiState.value.isShuffle;

      // 1. REPEAT ONE (paling awal, mengalahkan queue & shuffle)
      if (loopMode == LoopModeCustom.one) {
        await _playVideo(currentVideo);

        return;
      }

      // 2. QUEUE (prioritas di atas hasil pencarian / shuffle)
      if (_queueManager.isNotEmpty) {
        final nextItem = !isShuffle
            ? _queueManager.takeFirst()
            : _playerUiState.value.isSmartShuffle
                ? _queueManager.takeSmart(
                    score: (video) => _smartShuffleScore(
                      video,
                      currentArtist: _currentVideo?.channelTitle,
                    ),
                  )
                : _queueManager.takeRandom();

        if (nextItem != null) {
          unawaited(_storage.flushPendingWrites());
          unawaited(_storage.saveQueue(_queueManager.items));
          await _playVideo(nextItem.video);

          if (mounted) {
            setState(() {});
          }

          return;
        }
      }

      // 3. PLAYLIST AKTIF / SHUFFLE
      // Timeout: kalau request jaringan menggantung, flag
      // _isAutoNextProcessing tidak boleh nyangkut selamanya (itu yang
      // membuat auto-next mati total sampai app di-restart).
      await _next(fromAutoNext: true).timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          debugPrint('AUTO NEXT TIMEOUT');
        },
      );

      // Do not auto-retry/skip the same track if the next stream fails to
      // resolve. Failure is surfaced to the user instead of changing songs
      // repeatedly on its own.
    } catch (e, stackTrace) {
      debugPrint('AUTO NEXT ERROR: $e');
      debugPrint('$stackTrace');
    } finally {
      _isAutoNextProcessing = false;
    }
  }
}
