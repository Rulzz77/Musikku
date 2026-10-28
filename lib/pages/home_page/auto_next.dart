part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Auto-next berdasarkan event lagu selesai dari Media3.
extension _HomeAutoNext on _HomePageState {
  Future<void> _handleAutoNext(String endedVideoId) async {
    // Guest devices follow the host's song changes; their local ENDED event
    // must never pick an independent next song.
    if (_listenTogether.isGuest) return;

    if (_suppressAutoNextInPip) {
      return;
    }

    final currentVideo = _currentVideo;

    if (currentVideo == null || currentVideo.videoId != endedVideoId) {
      return;
    }

    if (!_playbackSessionGuard.tryBeginAutoNext()) {
      return;
    }

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

      // 2. QUEUE. Jangan menyela playlist tetap dengan item dari sumber lain.
      if (!_isFixedPlaybackList && _queueManager.isNotEmpty) {
        final nextItem = _takeQueueItemForCurrentMode(shuffle: isShuffle);

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
      // Kunci auto-next tidak boleh nyangkut selamanya (itu yang
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
      _playbackSessionGuard.finishAutoNext();
    }
  }
}
