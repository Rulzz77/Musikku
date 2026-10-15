import 'youtube_search_result.dart';

class LocalSong {
  final String mediaId;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String uri;
  final String genre;

  const LocalSong({
    required this.mediaId,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.uri,
    this.genre = '',
  });

  double get durationSeconds => durationMs / 1000.0;

  YoutubeSearchResult toPlayable() {
    return YoutubeSearchResult(
      videoId: 'local:$mediaId',
      title: title,
      channelTitle: artist.isEmpty ? 'Artis tidak diketahui' : artist,
      thumbnailUrl: '',
      sourceType: 'local',
      mediaUri: uri,
      durationSeconds: durationSeconds,
      album: album,
      localMediaId: mediaId,
    );
  }
}
