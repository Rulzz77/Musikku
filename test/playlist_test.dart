import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/playlist.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';

YoutubeSearchResult song(String id) => YoutubeSearchResult(
      videoId: id,
      title: 'Track $id',
      channelTitle: 'Artist',
      thumbnailUrl: '',
    );

void main() {
  group('Playlist', () {
    test('moveSong uses final destination indexes and preserves all songs', () {
      final playlist = Playlist(id: 'p', name: 'Test', songs: [song('a'), song('b'), song('c')]);
      expect(playlist.moveSong(0, 2), isTrue);
      expect(playlist.songs.map((item) => item.videoId).toList(), ['b', 'c', 'a']);
      expect(playlist.moveSong(2, 0), isTrue);
      expect(playlist.songs.map((item) => item.videoId).toList(), ['a', 'b', 'c']);
      expect(playlist.songs, hasLength(3));
    });

    test('invalid moves do not change playlist contents', () {
      final playlist = Playlist(id: 'p', name: 'Test', songs: [song('a'), song('b')]);
      expect(playlist.moveSong(-1, 1), isFalse);
      expect(playlist.moveSong(0, 0), isFalse);
      expect(playlist.moveSong(0, 3), isFalse);
      expect(playlist.moveSong(0, 5), isFalse);
      expect(playlist.songs.map((item) => item.videoId).toList(), ['a', 'b']);
    });

    test('JSON round trip preserves manually ordered songs', () {
      final playlist = Playlist(id: 'p', name: 'Test', songs: [song('a'), song('b')]);
      playlist.moveSong(0, 1);
      final restored = Playlist.fromJson(playlist.toJson());
      expect(restored.songs.map((item) => item.videoId).toList(), ['b', 'a']);
    });
  });
}
