import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/listening_stat.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/smart_queue_scorer.dart';

YoutubeSearchResult _track({
  required String id,
  required String title,
  String artist = 'Test Artist',
  double duration = 240,
  int views = 1000,
}) {
  return YoutubeSearchResult(
    videoId: id,
    title: title,
    channelTitle: artist,
    thumbnailUrl: '',
    durationSeconds: duration,
    viewCount: views,
  );
}

ListeningStat _stat({
  int plays = 0,
  int skips = 0,
  double listenedSeconds = 0,
  DateTime? lastPlayedAt,
}) {
  return ListeningStat(
    videoId: 'candidate',
    title: 'Candidate Song',
    artist: 'Test Artist',
    thumbnailUrl: '',
    playCount: plays,
    skipCount: skips,
    listenedSeconds: listenedSeconds,
    lastPlayedAt: lastPlayedAt,
  );
}

void main() {
  group('Smart Queue 2.0 scoring', () {
    final now = DateTime(2026, 11, 4, 12);

    test('disliked tracks are rejected with a hard negative score', () {
      final track = _track(id: 'candidate', title: 'Original Song');
      expect(
        SmartQueueScorer.score(video: track, isDisliked: true, now: now),
        SmartQueueScorer.dislikedScore,
      );
    });

    test('a high skip ratio lowers a track below a positively listened track', () {
      final track = _track(id: 'candidate', title: 'Original Song');
      final accepted = SmartQueueScorer.score(
        video: track,
        stat: _stat(plays: 3, listenedSeconds: 690),
        now: now,
      );
      final skipped = SmartQueueScorer.score(
        video: track,
        stat: _stat(plays: 1, skips: 4, listenedSeconds: 25),
        now: now,
      );
      expect(accepted, greaterThan(skipped));
    });

    test('recently played tracks receive a cooldown penalty', () {
      final track = _track(id: 'candidate', title: 'Original Song');
      final recent = SmartQueueScorer.score(
        video: track,
        stat: _stat(plays: 2, listenedSeconds: 300, lastPlayedAt: now.subtract(const Duration(hours: 2))),
        now: now,
      );
      final older = SmartQueueScorer.score(
        video: track,
        stat: _stat(plays: 2, listenedSeconds: 300, lastPlayedAt: now.subtract(const Duration(days: 10))),
        now: now,
      );
      expect(older, greaterThan(recent));
    });

    test('recent artist repetition lowers the candidate score', () {
      final track = _track(id: 'candidate', title: 'Original Song', artist: 'Billie Eilish - Topic');
      final normal = SmartQueueScorer.score(
        video: track,
        candidateArtist: 'Billie Eilish',
        now: now,
      );
      final repeated = SmartQueueScorer.score(
        video: track,
        candidateArtist: 'Billie Eilish',
        recentArtistKeys: const ['Billie Eilish', 'Billie Eilish'],
        now: now,
      );
      expect(normal, greaterThan(repeated));
    });

    test('mood hints come from the track title, not channel branding', () {
      final titleHint = _track(
        id: 'sad-title',
        title: 'Official Audio - Lagu Sedih Patah Hati',
        artist: 'Neutral Official Channel',
      );
      final channelOnlyHint = _track(
        id: 'neutral-title',
        title: 'Official Audio - Original Track',
        artist: 'Sad Music Official Channel',
      );
      expect(SmartQueueScorer.moodFor(titleHint), 'sad');
      expect(SmartQueueScorer.moodFor(channelOnlyHint), isNull);
    });

    test('an explicit like outweighs a large view-count difference', () {
      final modest = _track(id: 'modest', title: 'Original Song', views: 10);
      final viral = _track(id: 'viral', title: 'Original Song', views: 1000000000);
      final likedScore = SmartQueueScorer.score(
        video: modest,
        isLiked: true,
        now: now,
      );
      final unlikedScore = SmartQueueScorer.score(
        video: viral,
        now: now,
      );
      expect(likedScore, greaterThan(unlikedScore));
    });

    test('matching emotional context is preferred over a conflicting mood', () {
      final current = _track(
        id: 'current',
        title: 'Lagu Sedih Patah Hati',
        artist: 'Current Artist',
      );
      final sad = _track(
        id: 'sad',
        title: 'Sad Song Broken Heart',
        artist: 'Another Artist',
      );
      final energetic = _track(
        id: 'energetic',
        title: 'Party Anthem Upbeat',
        artist: 'Different Artist',
      );
      expect(
        SmartQueueScorer.moodAffinity(current: current, candidate: sad),
        greaterThan(SmartQueueScorer.moodAffinity(current: current, candidate: energetic)),
      );
    });

    test('musical similarity influences ranking more than tiny view differences', () {
      final lowViews = _track(id: 'candidate', title: 'Original Song', views: 100);
      final highViews = _track(id: 'candidate', title: 'Original Song', views: 900000000);
      final lowSimilarity = SmartQueueScorer.score(
        video: highViews,
        musicalSimilarity: 15,
        now: now,
      );
      final goodSimilarity = SmartQueueScorer.score(
        video: lowViews,
        musicalSimilarity: 50,
        now: now,
      );
      expect(goodSimilarity, greaterThan(lowSimilarity));
    });
  });
}
