import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/pages/youtube_search_page.dart';

YoutubeSearchResult _song({
  required String id,
  String title = 'Song',
  String description = '',
  String channel = 'Artist',
  double? duration,
  int? views,
  DateTime? published,
}) {
  return YoutubeSearchResult(
    videoId: id,
    title: title,
    description: description,
    channelTitle: channel,
    thumbnailUrl: '',
    durationSeconds: duration,
    viewCount: views,
    publishedAt: published,
  );
}

void main() {
  group('YoutubeSearchFilters', () {
    final songs = <YoutubeSearchResult>[
      _song(id: 'short', duration: 180, views: 100, published: DateTime(2024)),
      _song(id: 'medium', duration: 600, views: 900, published: DateTime(2025)),
      _song(id: 'long', duration: 1500, views: 500, published: DateTime(2023)),
    ];

    test('filters tracks under four minutes', () {
      final result = const YoutubeSearchFilters(
        duration: SearchDurationFilter.underFourMinutes,
      ).apply(songs);
      expect(result.map((song) => song.videoId), ['short']);
    });

    test('filters official audio using channel topic signal', () {
      final input = <YoutubeSearchResult>[
        _song(id: 'topic', channel: 'Artist - Topic'),
        _song(id: 'unofficial', channel: 'Fan Channel'),
      ];
      final result = const YoutubeSearchFilters(
        content: SearchContentFilter.officialAudio,
      ).apply(input);
      expect(result.map((song) => song.videoId), ['topic']);
    });

    test('sorts by most viewed', () {
      final result = const YoutubeSearchFilters(
        sort: SearchSortOrder.mostViewed,
      ).apply(songs);
      expect(result.map((song) => song.videoId), ['medium', 'long', 'short']);
    });

    test('adds content and language hints to the query', () {
      const filters = YoutubeSearchFilters(
        content: SearchContentFilter.musicVideo,
        language: SearchLanguageFilter.english,
      );
      expect(
        filters.buildQuery('Billie Eilish'),
        'Billie Eilish official music video English',
      );
    });

    test('default filters preserve original order', () {
      final result = const YoutubeSearchFilters().apply(songs);
      expect(result.map((song) => song.videoId), ['short', 'medium', 'long']);
    });
  });
}
