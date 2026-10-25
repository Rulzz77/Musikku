import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/original_track_resolver.dart';

YoutubeSearchResult _video({
  required String id,
  required String title,
  required String channel,
  String description = '',
}) => YoutubeSearchResult(
      videoId: id,
      title: title,
      channelTitle: channel,
      description: description,
      thumbnailUrl: '',
    );

void main() {
  group('OriginalTrackResolver', () {
    test('extracts the song title and original artist from a cover attribution', () {
      final cover = _video(
        id: 'cover-kangen',
        title: 'Nella Kharisma - Kangen (Dewa 19 Cover)',
        channel: 'Nella Kharisma',
      );

      final target = OriginalTrackResolver.targetFor(cover);
      expect(target, isNotNull);
      expect(target!.songTitle, 'Kangen');
      expect(target.originalArtist, 'Dewa 19');
      expect(target.query.toLowerCase(), contains('dewa 19 kangen'));
    });

    test('does not mistake the cover performer for the original artist', () {
      final cover = _video(
        id: 'cover-no-credit',
        title: 'Nella Kharisma - Kangen (Cover)',
        channel: 'Nella Kharisma',
      );

      final target = OriginalTrackResolver.targetFor(cover);
      expect(target, isNotNull);
      expect(target!.songTitle, 'Kangen');
      expect(target.originalArtist, isEmpty);
    });

    test('recognizes verb-form cover titles and extracts the song title', () {
      final cover = _video(
        id: 'cover-verb-form',
        title: 'Nella Kharisma covers Kangen',
        channel: 'Nella Kharisma',
      );

      final target = OriginalTrackResolver.targetFor(cover);
      expect(target, isNotNull);
      expect(target!.songTitle, 'Kangen');
      expect(target.originalArtist, isEmpty);
    });

    test('chooses a matching official original over a cover or unrelated result', () {
      final target = const OriginalTrackTarget(
        songTitle: 'Kangen',
        originalArtist: 'Dewa 19',
        query: 'Dewa 19 Kangen original official audio',
      );
      final selected = OriginalTrackResolver.selectOriginalCandidate(
        [
          _video(
            id: 'another-cover',
            title: 'Nella Kharisma - Kangen (Cover by Nella)',
            channel: 'Nella Kharisma',
          ),
          _video(
            id: 'unrelated',
            title: 'Risalah Hati (Official Video)',
            channel: 'Dewa 19 Official',
          ),
          _video(
            id: 'original',
            title: 'Dewa 19 - Kangen (Official Music Video)',
            channel: 'Dewa 19 - Topic',
          ),
        ],
        target: target,
        currentVideoId: 'another-cover',
      );
      expect(selected?.videoId, 'original');
    });

    test('keeps the selected result when no confident original is available', () {
      final target = const OriginalTrackTarget(
        songTitle: 'Kangen',
        originalArtist: '',
        query: 'Kangen original song official audio',
      );
      final selected = OriginalTrackResolver.selectOriginalCandidate(
        [
          _video(
            id: 'cover',
            title: 'Kangen (Cover by Nella)',
            channel: 'Nella Kharisma',
          ),
          _video(id: 'unknown', title: 'Kangen', channel: 'Random Upload'),
        ],
        target: target,
        currentVideoId: 'cover',
      );
      expect(selected, isNull);
    });
  });
}
