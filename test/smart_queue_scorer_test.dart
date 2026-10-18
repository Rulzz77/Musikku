import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/listening_stat.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/smart_queue_scorer.dart';

YoutubeSearchResult song({
  String id = 'song-a',
  String artist = 'Artist A',
  int? views,
  DateTime? publishedAt,
}) =>
    YoutubeSearchResult(
      videoId: id,
      title: 'Song $id',
      channelTitle: artist,
      thumbnailUrl: '',
      viewCount: views,
      publishedAt: publishedAt,
    );

ListeningStat stat({
  String id = 'song-a',
  int plays = 0,
  int skips = 0,
  double listenedSeconds = 0,
  DateTime? lastPlayedAt,
  String artist = 'Artist A',
}) =>
    ListeningStat(
      videoId: id,
      title: 'Song $id',
      artist: artist,
      thumbnailUrl: '',
      playCount: plays,
      skipCount: skips,
      listenedSeconds: listenedSeconds,
      lastPlayedAt: lastPlayedAt,
    );

void main() {
  group('SmartQueueScorer', () {
    final now = DateTime.utc(2026, 10, 18, 12);

    test('explicit like outweighs an otherwise identical candidate', () {
      final candidate = song();
      final neutral = SmartQueueScorer.score(video: candidate, now: now);
      final liked = SmartQueueScorer.score(
        video: candidate,
        isLiked: true,
        now: now,
      );

      expect(liked, greaterThan(neutral));
      expect(liked - neutral, 15);
    });

    test('explicit dislike strongly lowers a candidate score', () {
      final candidate = song();
      final neutral = SmartQueueScorer.score(video: candidate, now: now);
      final disliked = SmartQueueScorer.score(
        video: candidate,
        isDisliked: true,
        now: now,
      );

      expect(disliked, lessThan(neutral));
      expect(neutral - disliked, 120);
    });

    test('repeated skips reduce a song score', () {
      final candidate = song();
      final noSkips = SmartQueueScorer.score(
        video: candidate,
        stat: stat(skips: 0),
        now: now,
      );
      final skippedOften = SmartQueueScorer.score(
        video: candidate,
        stat: stat(skips: 4),
        now: now,
      );

      expect(skippedOften, lessThan(noSkips));
      expect(noSkips - skippedOften, 22);
    });

    test('recently played tracks receive a cooldown penalty', () {
      final candidate = song();
      final recent = SmartQueueScorer.score(
        video: candidate,
        stat: stat(lastPlayedAt: now.subtract(const Duration(hours: 1))),
        now: now,
      );
      final older = SmartQueueScorer.score(
        video: candidate,
        stat: stat(lastPlayedAt: now.subtract(const Duration(days: 4))),
        now: now,
      );

      expect(recent, lessThan(older));
      expect(older - recent, closeTo(11.8333333333, 0.001));
    });

    test('artist matching ignores common channel suffixes', () {
      final candidate = song(artist: 'Mawar Official Topic');
      final sameArtist = SmartQueueScorer.score(
        video: candidate,
        currentArtist: 'Mawar - Official',
        now: now,
      );
      final differentArtist = SmartQueueScorer.score(
        video: candidate,
        currentArtist: 'Senja Music Channel',
        now: now,
      );

      expect(sameArtist, lessThan(differentArtist));
      expect(differentArtist - sameArtist, 11);
    });

    test('artist history can add affinity or reduce repeated recommendations', () {
      final candidate = song();
      final neutral = SmartQueueScorer.score(video: candidate, now: now);
      final knownFavorite = SmartQueueScorer.score(
        video: candidate,
        artistPlayCount: 10,
        artistHasLikedTrack: true,
        now: now,
      );
      final oftenSkippedArtist = SmartQueueScorer.score(
        video: candidate,
        artistSkipCount: 4,
        now: now,
      );

      expect(knownFavorite, greaterThan(neutral));
      expect(oftenSkippedArtist, lessThan(neutral));
    });

    test('popularity and fresh uploads are tie-breakers, not mandatory signals', () {
      final baseline = SmartQueueScorer.score(video: song(), now: now);
      final popularFresh = SmartQueueScorer.score(
        video: song(
          id: 'new',
          views: 1000000,
          publishedAt: now.subtract(const Duration(days: 2)),
        ),
        now: now,
      );

      expect(popularFresh, greaterThan(baseline));
    });
  });
}
