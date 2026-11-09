import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/lyrics_service.dart';
import 'package:flutter_application_5/services/music_style_matcher.dart';
import 'package:flutter_application_5/services/original_track_resolver.dart';
import 'package:flutter_application_5/services/radio_service.dart';
import 'package:flutter_application_5/services/youtube_music_policy.dart';

YoutubeSearchResult _video({
  required String id,
  required String title,
  required String channel,
  String description = '',
  int? views,
  double? duration = 220,
}) {
  return YoutubeSearchResult(
    videoId: id,
    title: title,
    channelTitle: channel,
    description: description,
    thumbnailUrl: '',
    viewCount: views,
    durationSeconds: duration,
  );
}

void main() {
  group('Unicode song detection', () {
    test('Radio builds identities for Hangul and Japanese song titles', () {
      final korean = _video(
        id: 'korean-song',
        title: '사랑은 늘 도망가 - 임영웅',
        channel: '임영웅 - Topic',
      );
      final japanese = _video(
        id: 'japanese-song',
        title: '夜に駆ける - YOASOBI',
        channel: 'YOASOBI',
      );

      expect(RadioService.trackKeysFor(korean), isNotEmpty);
      expect(
        RadioService.trackKeysFor(korean).join(' '),
        contains('사랑은 늘 도망가'),
      );
      expect(RadioService.trackKeysFor(japanese), isNotEmpty);
      expect(
        RadioService.trackKeysFor(japanese).join(' '),
        contains('夜に駆ける'),
      );
    });

    test('query-aware catalogue matching preserves non-Latin artist tokens', () {
      final korean = _video(
        id: 'iu-night-letter',
        title: '밤편지 (Official Audio)',
        channel: '아이유 - Topic',
      );
      final japanese = _video(
        id: 'yonezu-lemon',
        title: 'Lemon (Official Music Video)',
        channel: '米津玄師 - Topic',
      );

      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          korean,
          query: '아이유 밤편지',
        ),
        isTrue,
      );
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          japanese,
          query: '米津玄師 Lemon',
        ),
        isTrue,
      );
    });

    test('original-track resolver can compare a Japanese title and artist', () {
      final original = _video(
        id: 'yoasobi-original',
        title: '夜に駆ける (Official Audio)',
        channel: 'YOASOBI - Topic',
        views: 1200000,
      );
      final match = OriginalTrackResolver.selectOriginalCandidate(
        [original],
        target: const OriginalTrackTarget(
          songTitle: '夜に駆ける',
          originalArtist: 'YOASOBI',
          query: 'YOASOBI 夜に駆ける',
        ),
        currentVideoId: 'cover-upload',
      );

      expect(match?.videoId, 'yoasobi-original');
    });

    test('style and lyrics normalization preserve non-Latin titles', () {
      expect(MusicStyleMatcher.normalize('아이유 밤편지'), '아이유 밤편지');
      expect(MusicStyleMatcher.normalize('夜に駆ける YOASOBI'), '夜に駆ける yoasobi');
      expect(
        LyricsService.metadataMatchScoreForTesting('夜に駆ける', '夜に駆ける'),
        100,
      );
    });
  });
}
