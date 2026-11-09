import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/playlist.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';

void main() {
  YoutubeSearchResult localSong(String id) => YoutubeSearchResult(
        videoId: 'local:$id',
        title: 'Local $id',
        channelTitle: 'Artist',
        thumbnailUrl: '',
        sourceType: 'local',
        mediaUri: 'content://media/external/audio/media/$id',
        localMediaId: id,
      );

  YoutubeSearchResult remoteSong(String id) => YoutubeSearchResult(
        videoId: id,
        title: 'Remote $id',
        channelTitle: 'Artist',
        thumbnailUrl: '',
      );

  test('offline count includes local files but not remote-only tracks', () {
    final playlist = Playlist(
      id: 'p1',
      name: 'Mixed',
      songs: [localSong('1'), remoteSong('yt1'), localSong('2')],
    );

    expect(playlist.offlineSongCount, 2);
    expect(playlist.isFullyOffline, isFalse);
  });

  test('playlist is fully offline when all entries are local', () {
    final playlist = Playlist(
      id: 'p2',
      name: 'Offline',
      songs: [localSong('1'), localSong('2')],
    );

    expect(playlist.offlineSongCount, 2);
    expect(playlist.isFullyOffline, isTrue);
  });


  test('online playlist entry becomes offline when it has a saved file path', () {
    final downloaded = remoteSong('abcdefghijk').copyWith(
      offlinePath: '/app/MusikKu/Offline/abcdefghijk.m4a',
    );
    final playlist = Playlist(
      id: 'p5',
      name: 'Downloaded',
      songs: [remoteSong('lmnopqrstuv'), downloaded],
    );

    expect(downloaded.isOfflineDownloaded, isTrue);
    expect(downloaded.isLocal, isFalse);
    expect(playlist.offlineSongCount, 1);
    expect(playlist.isFullyOffline, isFalse);
  });

  test('downloaded path survives playlist JSON round trip', () {
    final song = remoteSong('abcdefghijk').copyWith(
      offlinePath: '/app/MusikKu/Offline/abcdefghijk.m4a',
    );
    final playlist = Playlist(id: 'p6', name: 'Saved', songs: [song]);
    final restored = Playlist.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(playlist.toJson())) as Map),
    );

    expect(restored.songs.single.offlinePath, song.offlinePath);
    expect(restored.offlineSongCount, 1);
  });


  test('playlist of downloaded online tracks is fully offline', () {
    final playlist = Playlist(
      id: 'p7',
      name: 'All Downloaded',
      songs: [
        remoteSong('abcdefghijk').copyWith(offlinePath: '/offline/a.m4a'),
        remoteSong('lmnopqrstuv').copyWith(offlinePath: '/offline/b.m4a'),
      ],
    );

    expect(playlist.offlineSongCount, 2);
    expect(playlist.isFullyOffline, isTrue);
  });

  test('empty playlist is not marked fully offline', () {
    final playlist = Playlist(id: 'p3', name: 'Empty');
    expect(playlist.offlineSongCount, 0);
    expect(playlist.isFullyOffline, isFalse);
  });

  test('local source URI survives playlist JSON storage round trip', () {
    final playlist = Playlist(
      id: 'p4',
      name: 'On Device',
      songs: [localSong('42')],
    );
    final restored = Playlist.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(playlist.toJson())) as Map),
    );

    expect(restored.isFullyOffline, isTrue);
    expect(restored.songs.single.mediaUri, 'content://media/external/audio/media/42');
    expect(restored.songs.single.localMediaId, '42');
  });
}
