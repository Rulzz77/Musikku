import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/listening_stat.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/smart_playlist_service.dart';

YoutubeSearchResult song(String id, {String title = ''}) => YoutubeSearchResult(
      videoId: id,
      title: title.isEmpty ? 'Track $id' : title,
      channelTitle: 'Artist $id',
      thumbnailUrl: '',
    );

ListeningStat stat(
  String id, {
  int plays = 0,
  double listened = 0,
  DateTime? lastPlayed,
}) => ListeningStat(
      videoId: id,
      title: 'Track $id',
      artist: 'Artist $id',
      thumbnailUrl: '',
      playCount: plays,
      listenedSeconds: listened,
      lastPlayedAt: lastPlayed,
    );

void main() {
  group('SmartPlaylistService', () {
    test('builds dynamic favorites and recently played mixes without duplicates', () {
      final a = song('a');
      final b = song('b');
      final result = SmartPlaylistService.build(
        favorites: [a, b, a],
        recentlyPlayed: [b, a, b],
      );

      final byId = {for (final playlist in result) playlist.id: playlist};
      expect(byId['smart_favorites']!.songs.map((e) => e.videoId), ['a', 'b']);
      expect(byId['smart_recent']!.songs.map((e) => e.videoId), ['b', 'a']);
    });

    test('most played mix follows real play counts and listens', () {
      final a = song('a');
      final b = song('b');
      final result = SmartPlaylistService.build(
        favorites: const [],
        recentlyPlayed: [a, b],
        listeningStats: [
          stat('a', plays: 2, listened: 100),
          stat('b', plays: 7, listened: 300),
        ],
      );
      final mostPlayed = result.firstWhere((playlist) => playlist.id == 'smart_most_played');
      expect(mostPlayed.songs.map((e) => e.videoId).toList(), ['b', 'a']);
    });

    test('Mix Kamu only includes repeated songs and restores songs from old stats', () {
      final result = SmartPlaylistService.build(
        favorites: const [],
        recentlyPlayed: [song('recent')],
        catalog: [song('catalog')],
        listeningStats: [
          stat('once', plays: 1, listened: 900),
          stat('quick_skip', plays: 7, listened: 12),
          stat('old_repeat', plays: 8, listened: 1400),
          stat('catalog', plays: 3, listened: 420),
        ],
      );

      final mix = result.firstWhere((playlist) => playlist.id == 'smart_most_played');
      expect(mix.title, 'Mix Kamu');
      expect(mix.songs.map((entry) => entry.videoId).toList(), ['old_repeat', 'catalog']);
      expect(mix.songs.any((entry) => entry.videoId == 'once'), isFalse);
      expect(mix.songs.any((entry) => entry.videoId == 'quick_skip'), isFalse);
    });

    test('does not create Mix Kamu when no track has been replayed', () {
      final result = SmartPlaylistService.build(
        favorites: [song('favorite')],
        recentlyPlayed: [song('recent')],
        listeningStats: [stat('favorite', plays: 1)],
      );
      expect(result.any((playlist) => playlist.id == 'smart_most_played'), isFalse);
    });

    test('does not duplicate a tiny history as a rediscover playlist', () {
      final result = SmartPlaylistService.build(
        favorites: const [],
        recentlyPlayed: [song('one')],
      );
      expect(result.map((playlist) => playlist.id), ['smart_recent']);
    });

    test('rediscover does not mutate history and caps generated songs', () {
      final a = song('a');
      final b = song('b');
      final c = song('c');
      final history = [a, b, c];
      final result = SmartPlaylistService.build(
        favorites: const [],
        recentlyPlayed: history,
        maxSongs: 2,
      );
      expect(history.map((e) => e.videoId).toList(), ['a', 'b', 'c']);
      expect(result.firstWhere((playlist) => playlist.id == 'smart_recent').songs, hasLength(2));
    });
  });
}
