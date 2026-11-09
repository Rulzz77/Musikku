/// Measures listening time from continuous playback events rather than raw
/// position jumps. Large seeks, backward seeks, pauses, buffering and stale
/// event gaps are not counted as listening time.
class ListeningPlaybackSample {
  const ListeningPlaybackSample({
    required this.listenedSeconds,
    required this.newPlay,
  });

  final double listenedSeconds;
  final bool newPlay;
}

class ListeningPlaybackTracker {
  static const double _maxEventGapSeconds = 10.0;
  static const double _positionDriftToleranceSeconds = 1.25;

  String _videoId = '';
  double _lastPositionSeconds = 0.0;
  DateTime? _lastEventAt;
  bool _lastWasPlaying = false;
  bool _countedCurrentPlay = false;

  ListeningPlaybackSample update({
    required String videoId,
    required double positionSeconds,
    required bool isPlaying,
    required bool isEnded,
    required DateTime timestamp,
  }) {
    final id = videoId.trim();
    final position = positionSeconds.isFinite && positionSeconds >= 0
        ? positionSeconds
        : 0.0;

    if (id.isEmpty) {
      return const ListeningPlaybackSample(listenedSeconds: 0, newPlay: false);
    }

    final trackChanged = id != _videoId;
    if (trackChanged) {
      _videoId = id;
      _lastPositionSeconds = position;
      _lastEventAt = timestamp;
      _lastWasPlaying = isPlaying && !isEnded;
      _countedCurrentPlay = isPlaying && !isEnded;
      return ListeningPlaybackSample(
        listenedSeconds: 0,
        newPlay: isPlaying && !isEnded,
      );
    }

    final newPlay = isPlaying && !_countedCurrentPlay;
    var listenedSeconds = 0.0;
    final previousAt = _lastEventAt;

    if (_lastWasPlaying && (isPlaying || isEnded) && previousAt != null) {
      final elapsed = timestamp.difference(previousAt).inMicroseconds / 1000000.0;
      final positionDelta = position - _lastPositionSeconds;
      final allowedDrift = _positionDriftToleranceSeconds + elapsed * 0.15;

      // A real playback tick advances media position at roughly the same rate
      // as wall time. A large positive jump is a forward seek; a negative jump
      // is a backward seek. Neither should inflate listening time.
      if (elapsed > 0 &&
          elapsed <= _maxEventGapSeconds &&
          positionDelta > 0 &&
          positionDelta <= _maxEventGapSeconds &&
          (positionDelta - elapsed).abs() <= allowedDrift) {
        listenedSeconds = elapsed;
      }
    }

    if (isEnded) {
      _countedCurrentPlay = false;
      _lastWasPlaying = false;
    } else {
      if (isPlaying) _countedCurrentPlay = true;
      _lastWasPlaying = isPlaying;
    }

    _lastPositionSeconds = position;
    _lastEventAt = timestamp;

    return ListeningPlaybackSample(
      listenedSeconds: listenedSeconds,
      newPlay: newPlay,
    );
  }

  void reset() {
    _videoId = '';
    _lastPositionSeconds = 0.0;
    _lastEventAt = null;
    _lastWasPlaying = false;
    _countedCurrentPlay = false;
  }
}
