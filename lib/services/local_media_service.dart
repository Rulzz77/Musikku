import 'package:flutter/services.dart';

import '../models/local_song.dart';

class LocalMediaService {
  static const MethodChannel _channel =
      MethodChannel('musikku/local_media');

  Future<List<LocalSong>> scanSongs() async {
    final value = await _channel.invokeMethod<dynamic>('scanLocalMusic');
    if (value is! List) {
      return const <LocalSong>[];
    }

    final songs = <LocalSong>[];
    for (final raw in value) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final mediaId = map['mediaId']?.toString() ?? '';
      final uri = map['uri']?.toString() ?? '';
      if (mediaId.isEmpty || uri.isEmpty) continue;

      final rawTitle = map['title']?.toString() ?? '';
      songs.add(
        LocalSong(
          mediaId: mediaId,
          title: rawTitle.trim().isNotEmpty ? rawTitle.trim() : 'Tanpa judul',
          artist: map['artist']?.toString() ?? '',
          album: map['album']?.toString() ?? '',
          durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
          genre: map['genre']?.toString() ?? '',
          uri: uri,
        ),
      );
    }

    songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return songs;
  }

  Future<bool> requestPermission() async {
    final value = await _channel.invokeMethod<dynamic>('requestLocalMusicPermission');
    return value == true;
  }

  Future<bool> hasPermission() async {
    final value = await _channel.invokeMethod<dynamic>('hasLocalMusicPermission');
    return value == true;
  }

  Future<List<LocalSong>> requestAndScan() async {
    final granted = await requestPermission();
    if (!granted) {
      return const <LocalSong>[];
    }
    return scanSongs();
  }

  Future<Uint8List?> getArtwork(String mediaId) async {
    if (mediaId.trim().isEmpty) return null;

    final value = await _channel.invokeMethod<dynamic>(
      'getLocalArtwork',
      {'mediaId': mediaId},
    );

    if (value is Uint8List) {
      return value;
    }

    if (value is List<int>) {
      return Uint8List.fromList(value);
    }

    return null;
  }
}
