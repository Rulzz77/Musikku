import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/playback_session_guard.dart';

void main() {
  group('PlaybackSessionGuard', () {
    test('a newer track request makes older async results stale', () {
      final guard = PlaybackSessionGuard();
      final first = guard.beginTrackChange();
      final second = guard.beginTrackChange();

      expect(guard.isCurrentRequest(first), isFalse);
      expect(guard.isCurrentRequest(second), isTrue);
      expect(guard.finishTrackChange(first), isFalse);
      expect(guard.isChangingTrack, isTrue,
          reason: 'an old request must not clear the newer transition');
      expect(guard.finishTrackChange(second), isTrue);
      expect(guard.isChangingTrack, isFalse);
    });

    test('an ended event is claimed once until reset', () {
      final guard = PlaybackSessionGuard();

      expect(guard.tryClaimEndedEvent('video-1'), isTrue);
      expect(guard.tryClaimEndedEvent('video-1'), isFalse);
      expect(guard.tryClaimEndedEvent('video-2'), isTrue);
      guard.resetEndedEvent();
      expect(guard.tryClaimEndedEvent('video-1'), isTrue);
    });

    test('ended events are ignored while changing track or auto-next is busy', () {
      final guard = PlaybackSessionGuard();
      final request = guard.beginTrackChange();

      expect(guard.tryClaimEndedEvent('video-1'), isFalse);
      expect(guard.finishTrackChange(request), isTrue);

      expect(guard.tryBeginAutoNext(), isTrue);
      expect(guard.tryBeginAutoNext(), isFalse);
      expect(guard.tryClaimEndedEvent('video-2'), isFalse);
      guard.finishAutoNext();
      expect(guard.tryBeginAutoNext(), isTrue);
      guard.finishAutoNext();
    });

    test('starting a new track resets the prior ended-video claim', () {
      final guard = PlaybackSessionGuard();
      final first = guard.beginTrackChange();
      expect(guard.finishTrackChange(first), isTrue);
      expect(guard.tryClaimEndedEvent('video-1'), isTrue);
      final second = guard.beginTrackChange();

      expect(guard.isCurrentRequest(second), isTrue);
      expect(guard.lastHandledEndedVideoId, isEmpty);
    });
  });
}
