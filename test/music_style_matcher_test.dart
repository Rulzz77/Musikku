import 'package:flutter_test/flutter_test.dart';

import '../lib/models/youtube_search_result.dart';
import '../lib/services/music_style_matcher.dart';

YoutubeSearchResult track(String title, String channel) => YoutubeSearchResult(
      videoId: title,
      title: title,
      channelTitle: channel,
      thumbnailUrl: '',
    );

void main() {
  group('MusicStyleMatcher', () {
    test('keeps Jawa as the main style even for Pop Jawa', () {
      expect(MusicStyleMatcher.styleFromText('lagu Jawa'), 'jawa');
      expect(MusicStyleMatcher.styleFromText('Pop Jawa terbaru'), 'jawa');
    });

    test('recognizes common music styles', () {
      expect(MusicStyleMatcher.styleFromText('lagu pop Indonesia'), 'pop');
      expect(MusicStyleMatcher.styleFromText('DJ remix'), 'dj_remix');
      expect(MusicStyleMatcher.styleFromText('lagu dangdut koplo'), 'dangdut');
    });

    test('rejects explicitly different style but keeps untagged candidates', () {
      final jawa = track('Lagu Jawa - Denny Caknan', 'Denny Caknan');
      final pop = track('Lagu Pop Indonesia', 'Rossa');
      final unknown = track('Cinta Terakhir', 'Channel Musik');

      expect(
        MusicStyleMatcher.isCompatible(video: jawa, targetStyle: 'jawa'),
        isTrue,
      );
      expect(
        MusicStyleMatcher.isCompatible(video: pop, targetStyle: 'jawa'),
        isFalse,
      );
      expect(
        MusicStyleMatcher.isCompatible(video: unknown, targetStyle: 'jawa'),
        isTrue,
      );
    });

    test('prioritizes matching style before untagged tracks', () {
      final jawa = track('Lagu Jawa - Denny Caknan', 'Denny Caknan');
      final unknown = track('Cinta Terakhir', 'Channel Musik');
      final pop = track('Lagu Pop Indonesia', 'Rossa');

      final selected = MusicStyleMatcher.prioritizeStyle(
        [unknown, pop, jawa],
        'jawa',
      );

      expect(selected.map((video) => video.videoId), [jawa.videoId]);
    });
  });
}
