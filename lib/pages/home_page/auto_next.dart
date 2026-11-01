part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Auto-next berdasarkan event lagu selesai dari Media3.
extension _HomeAutoNext on _HomePageState {
  /// Jeda antar percobaan ulang bila auto-next gagal menemukan lagu
  /// (jaringan putus sesaat, pool Radio kosong, dll).
  static const List<Duration> _autoNextRetryDelays = <Duration>[
    Duration(seconds: 3),
    Duration(seconds: 8),
    Duration(seconds: 20),
  ];

  Future<void> _handleAutoNext(String endedVideoId, {int attempt = 0}) async {
    // Guest devices follow the host's song changes; their local ENDED event
    // must never pick an independent next song.
    if (_listenTogether.isGuest) return;

    if (_suppressAutoNextInPip) {
      // Jangan "menghabiskan" event ended: begitu PiP selesai, event ended
      // berikutnya harus bisa diklaim lagi. Tanpa ini lagu berhenti selamanya.
      _playbackSessionGuard.resetEndedEvent();
      return;
    }

    final currentVideo = _currentVideo;

    if (currentVideo == null || currentVideo.videoId != endedVideoId) {
      return;
    }

    if (!_playbackSessionGuard.tryBeginAutoNext()) {
      return;
    }

    var retryAfter = false;

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
          // Lagu dari queue adalah pilihan eksplisit: Radio harus mengikuti
          // lagu ini, bukan konteks lama.
          _prepareRadioForTrack(nextItem.video);

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

      // Kalau _next() selesai tapi lagu aktif masih lagu yang sama dan tidak
      // ada yang diputar, berarti tidak ada kandidat / request gagal / timeout.
      // Daftar tetap (playlist/favorit/lokal) memang berhenti di akhir, jadi
      // dikecualikan. Hanya Radio/pencarian yang boleh dicoba ulang.
      final now = _currentVideo;
      retryAfter = mounted &&
          now != null &&
          now.videoId == endedVideoId &&
          !now.isLocal &&
          !_isFixedPlaybackList &&
          !_nativeState.isPlaying &&
          !_nativeState.isBuffering;
    } catch (e, stackTrace) {
      debugPrint('AUTO NEXT ERROR: $e');
      debugPrint('$stackTrace');
      retryAfter = mounted &&
          _currentVideo?.videoId == endedVideoId &&
          _currentVideo?.isLocal != true &&
          !_isFixedPlaybackList;
    } finally {
      _playbackSessionGuard.finishAutoNext();
    }

    if (retryAfter && attempt < _autoNextRetryDelays.length) {
      final delay = _autoNextRetryDelays[attempt];
      debugPrint('AUTO NEXT RETRY #${attempt + 1} in ${delay.inSeconds}s');
      Timer(delay, () {
        if (!mounted) return;
        final current = _currentVideo;
        // Pengguna sudah pindah lagu / menekan Play lagi → batalkan retry.
        if (current == null || current.videoId != endedVideoId) return;
        if (_nativeState.isPlaying || _nativeState.isBuffering) return;
        unawaited(_handleAutoNext(endedVideoId, attempt: attempt + 1));
      });
    } else if (retryAfter && mounted) {
      // Semua percobaan habis: bebaskan klaim supaya Play/Next manual
      // dan event ended berikutnya tidak tertahan.
      _playbackSessionGuard.resetEndedEvent();
      _toast('Lagu berikutnya belum ketemu. Tekan Next untuk coba lagi.');
    }
  }
}
