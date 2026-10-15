import 'youtube_search_result.dart';

/// Playlist buatan pengguna (disimpan lokal di HP).
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<YoutubeSearchResult>? songs,
  }) : songs = songs ?? <YoutubeSearchResult>[];

  final String id;
  String name;
  final List<YoutubeSearchResult> songs;

  bool contains(String videoId) =>
      songs.any((song) => song.videoId == videoId);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songs': songs.map((song) => song.toJson()).toList(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final rawSongs = json['songs'];
    final songs = <YoutubeSearchResult>[];

    if (rawSongs is List) {
      for (final item in rawSongs) {
        if (item is! Map) {
          continue;
        }

        final song = YoutubeSearchResult.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (song.videoId.isNotEmpty) {
          songs.add(song);
        }
      }
    }

    return Playlist(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Playlist',
      songs: songs,
    );
  }
}
