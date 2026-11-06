import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/playback_source_policy.dart';

YoutubeSearchResult _video({
  required String id,
  required String title,
  double? duration = 220,
  String artist = 'Artist',
  String sourceType = 'youtube',
}) {
  return YoutubeSearchResult(
    videoId: id,
    title: title,
    channelTitle: artist,
    thumbnailUrl: '',
    durationSeconds: duration,
    sourceType: sourceType,
    mediaUri: sourceType == 'local' ? 'file:///music/$id.mp3' : '',
  );
}

void main() {
  group('automatic next source policy', () {
    final first = _video(id: 'first_track', title: 'Official Audio - Song One');
    final album = _video(
      id: 'album_track',
      title: 'Full Album - 20 Best Songs',
      duration: 2400,
    );
    final karaoke = _video(
      id: 'karaoke_track',
      title: 'Song Three Karaoke Version',
    );
    final cover = _video(
      id: 'cover_track',
      title: 'Song Four - Acoustic Cover by Someone',
    );
    final ai = _video(
      id: 'ai_track',
      title: 'AI Cover - Song Five',
    );
    final second = _video(id: 'second_track', title: 'Official Audio - Song Two');

    test('skips album, karaoke, cover, and AI in original playlist order', () {
      final source = <YoutubeSearchResult>[
        first,
        album,
        second,
        karaoke,
        cover,
        ai,
      ];

      expect(
        PlaybackSourcePolicy.nextAllowedInOrder(
          source,
          currentVideoId: first.videoId,
          repeatAll: false,
        )?.videoId,
        second.videoId,
      );
      // The stored/user-authored sequence is never rewritten by Next.
      expect(source.map((item) => item.videoId).toList(), [
        first.videoId,
        album.videoId,
        second.videoId,
        karaoke.videoId,
        cover.videoId,
        ai.videoId,
      ]);
    });

    test('repeat all wraps to first allowed item without changing order', () {
      final source = <YoutubeSearchResult>[first, album, second];
      expect(
        PlaybackSourcePolicy.nextAllowedInOrder(
          source,
          currentVideoId: second.videoId,
          repeatAll: true,
        )?.videoId,
        first.videoId,
      );
    });

    test('repeat all stops when no allowed successor exists and repeat is off', () {
      final source = <YoutubeSearchResult>[first, album, karaoke];
      expect(
        PlaybackSourcePolicy.nextAllowedInOrder(
          source,
          currentVideoId: first.videoId,
          repeatAll: false,
        ),
        isNull,
      );
    });

    test('local media remains eligible and is not run through YouTube heuristics', () {
      final local = _video(
        id: 'local:1',
        title: 'My Personal Recording',
        duration: 3600,
        sourceType: 'local',
      );
      expect(PlaybackSourcePolicy.isAllowedForAutomaticNext(local), isTrue);
    });

    test('explicit playlist serialization keeps every selected entry and its order', () {
      final source = <YoutubeSearchResult>[first, album, second];
      final saved = PlaybackSourcePolicy.explicitPlaylistItems(source);
      expect(saved.map((item) => item.videoId).toList(), [
        first.videoId,
        album.videoId,
        second.videoId,
      ]);
      // The automatic-next helper is separate from this serialization path,
      // so the item remains available for a direct manual selection.
      expect(saved[1], same(album));
    });
  });
}
