import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/listening_playback_tracker.dart';

void main() {
  group('ListeningPlaybackTracker', () {
    late ListeningPlaybackTracker tracker;
    final base = DateTime(2026, 10, 19, 12, 0, 0);

    ListeningPlaybackSample tick({
      String videoId = 'track-a',
      required double position,
      required int seconds,
      bool playing = true,
      bool ended = false,
    }) {
      return tracker.update(
        videoId: videoId,
        positionSeconds: position,
        isPlaying: playing,
        isEnded: ended,
        timestamp: base.add(Duration(seconds: seconds)),
      );
    }

    setUp(() => tracker = ListeningPlaybackTracker());

    test('counts a play once and counts continuous listening time', () {
      final start = tick(position: 0, seconds: 0);
      final next = tick(position: 1, seconds: 1);
      final nextAgain = tick(position: 2, seconds: 2);

      expect(start.newPlay, isTrue);
      expect(start.listenedSeconds, 0);
      expect(next.newPlay, isFalse);
      expect(next.listenedSeconds, closeTo(1, 0.01));
      expect(nextAgain.listenedSeconds, closeTo(1, 0.01));
    });

    test('does not count a large forward seek as listening time', () {
      tick(position: 10, seconds: 0);
      final seek = tick(position: 70, seconds: 1);
      final resumedProgress = tick(position: 71, seconds: 2);

      expect(seek.listenedSeconds, 0);
      expect(resumedProgress.listenedSeconds, closeTo(1, 0.01));
    });

    test('does not count a backward seek as negative or extra listening time', () {
      tick(position: 30, seconds: 0);
      final seek = tick(position: 5, seconds: 1);
      final progress = tick(position: 6, seconds: 2);

      expect(seek.listenedSeconds, 0);
      expect(progress.listenedSeconds, closeTo(1, 0.01));
    });

    test('does not count paused time or count resume as a new play', () {
      tick(position: 0, seconds: 0);
      final pause = tick(position: 1, seconds: 1, playing: false);
      final resume = tick(position: 1, seconds: 20);
      final progress = tick(position: 2, seconds: 21);

      expect(pause.listenedSeconds, 0);
      expect(resume.listenedSeconds, 0);
      expect(resume.newPlay, isFalse);
      expect(progress.listenedSeconds, closeTo(1, 0.01));
    });

    test('counts a new track as a new play', () {
      tick(position: 0, seconds: 0);
      final newTrack = tick(videoId: 'track-b', position: 0, seconds: 1);

      expect(newTrack.newPlay, isTrue);
      expect(newTrack.listenedSeconds, 0);
    });

    test('counts replay of the same track after the ended event', () {
      tick(position: 0, seconds: 0);
      final end = tick(position: 1, seconds: 1, ended: true, playing: false);
      final replay = tick(position: 0, seconds: 2, playing: true);

      expect(end.newPlay, isFalse);
      expect(replay.newPlay, isTrue);
      expect(replay.listenedSeconds, 0);
    });

    test('ignores stale gaps longer than ten seconds', () {
      tick(position: 0, seconds: 0);
      final stale = tick(position: 25, seconds: 25);

      expect(stale.listenedSeconds, 0);
    });
  });
}
