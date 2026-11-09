/// Coordinates overlapping playback requests and duplicate end-of-track events.
///
/// This class deliberately contains no Flutter dependencies so its concurrency
/// guards can be regression-tested independently from the UI and native player.
class PlaybackSessionGuard {
  int _requestGeneration = 0;
  bool _changingTrack = false;
  bool _autoNextProcessing = false;
  String _lastHandledEndedVideoId = '';

  bool get isChangingTrack => _changingTrack;
  bool get isAutoNextProcessing => _autoNextProcessing;
  String get lastHandledEndedVideoId => _lastHandledEndedVideoId;

  /// Starts a new track request and makes all older async results stale.
  int beginTrackChange() {
    _changingTrack = true;
    _lastHandledEndedVideoId = '';
    return ++_requestGeneration;
  }

  /// Whether an async result still belongs to the newest playback request.
  bool isCurrentRequest(int requestId) => requestId == _requestGeneration;

  /// Finishes the changing-track guard only for the current request.
  /// A stale request must never clear the guard owned by a newer request.
  bool finishTrackChange(int requestId) {
    if (!isCurrentRequest(requestId)) return false;
    _changingTrack = false;
    return true;
  }

  /// Allows the same video to emit a fresh ended event after playback resumes.
  void resetEndedEvent() {
    _lastHandledEndedVideoId = '';
  }

  /// Claims an ended event exactly once, while no track transition/auto-next
  /// operation is in progress. The caller must perform identity/source checks
  /// before calling this method.
  bool tryClaimEndedEvent(String videoId) {
    if (videoId.isEmpty ||
        _changingTrack ||
        _autoNextProcessing ||
        videoId == _lastHandledEndedVideoId) {
      return false;
    }
    _lastHandledEndedVideoId = videoId;
    return true;
  }

  /// Acquires the auto-next lock before any asynchronous work starts.
  bool tryBeginAutoNext() {
    if (_autoNextProcessing) return false;
    _autoNextProcessing = true;
    return true;
  }

  /// Releases the auto-next lock in the caller's finally block.
  void finishAutoNext() {
    _autoNextProcessing = false;
  }
}
