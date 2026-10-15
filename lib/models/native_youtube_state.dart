enum NativePlaybackState {
  unstarted,
  ended,
  playing,
  paused,
  buffering,
  cued,
  error,
  unknown,
}

class NativeYoutubeState {
  final NativePlaybackState playbackState;
  final Duration position;
  final Duration duration;
  final String videoId;
  final double bufferedFraction;
  final Duration bufferedAhead;
  final int networkRxBytes;
  final String networkType;

  /// UI intent sementara dari tombol Play/Pause. Null berarti gunakan state native mentah.
  final bool? requestedPlaying;

  /// Nilai buffer yang aman untuk dipakai UI (selalu 0..1 dan finite).
  double get safeBufferedFraction {
    if (!bufferedFraction.isFinite) return 0.0;
    return bufferedFraction.clamp(0.0, 1.0).toDouble();
  }

  const NativeYoutubeState({
    this.playbackState = NativePlaybackState.unstarted,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.videoId = '',
    this.bufferedFraction = 0.0,
    this.bufferedAhead = Duration.zero,
    this.networkRxBytes = 0,
    this.networkType = 'unknown',
    this.requestedPlaying,
  });

  bool get isPlaying =>
      playbackState == NativePlaybackState.playing;

  bool get isEnded =>
      playbackState == NativePlaybackState.ended;

  bool get isPaused =>
      playbackState == NativePlaybackState.paused;

  bool get isBuffering =>
      playbackState == NativePlaybackState.buffering;

  /// Untuk UI, buffering berarti playback masih berlangsung.
  /// Ini mencegah ikon Play/Pause berkedip Play saat transisi buffer -> playing.
  bool get isEffectivelyPlaying =>
      requestedPlaying ?? (isPlaying || isBuffering);
}