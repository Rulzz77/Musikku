part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Crossfade, volume fade, pengaturan audio, dan sleep timer.
extension _HomeAudioEffects on _HomePageState {
  void _maybeStartAutoCrossfade(NativeYoutubeState state) {
    if (_crossfadeSeconds <= 0 ||
        !state.isPlaying ||
        state.duration <= Duration.zero ||
        state.videoId.isEmpty ||
        _crossfadeFadingVideoId == state.videoId) {
      return;
    }

    final remaining = state.duration - state.position;
    final lead = Duration(milliseconds: _crossfadeSeconds * 500);

    if (remaining <= lead && remaining > Duration.zero) {
      _crossfadeFadingVideoId = state.videoId;
      unawaited(
        _fadeVolume(
          from: 100,
          to: 0,
          duration: remaining < lead ? remaining : lead,
        ),
      );
    }
  }

  void _cancelVolumeFade() {
    _volumeFadeGeneration++;
  }

  Future<void> _setPlayerVolume(int percent) async {
    _cancelVolumeFade();
    final safe = percent.clamp(0, 100).toInt();
    _playerVolumePercent = safe;
    await _youtubeController.setVolume(safe);
  }

  Future<void> _fadeVolume({
    required int from,
    required int to,
    required Duration duration,
  }) async {
    final generation = ++_volumeFadeGeneration;

    if (duration <= Duration.zero) {
      if (generation != _volumeFadeGeneration) {
        return;
      }
      _playerVolumePercent = to.clamp(0, 100).toInt();
      await _youtubeController.setVolume(_playerVolumePercent);
      return;
    }

    final steps = (duration.inMilliseconds / 90).round().clamp(5, 24);
    for (var i = 1; i <= steps; i++) {
      if (generation != _volumeFadeGeneration) {
        return;
      }

      final value = (from + ((to - from) * i / steps).round())
          .clamp(0, 100)
          .toInt();
      try {
        _playerVolumePercent = value;
        await _youtubeController.setVolume(value);
      } catch (e) {
        debugPrint('FADE VOLUME ERROR: $e');
        return;
      }

      if (i != steps) {
        await Future<void>.delayed(
          Duration(milliseconds: (duration.inMilliseconds / steps).round()),
        );
      }
    }
  }

  void _clearSleepTimer() {
    _sleepTimer?.cancel();

    _sleepTimer = null;

    _stopAfterCurrent = false;

    _sleepActive.value = false;
  }
}
