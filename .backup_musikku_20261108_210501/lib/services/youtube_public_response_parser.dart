import '../models/youtube_search_result.dart';
import 'youtube_music_metadata_parser.dart';

/// Converts public YouTube API payloads into the app's track model.
class YoutubePublicResponseParser {
  static List<YoutubeSearchResult> playlistItemsToTracks(Map<String, dynamic> data) {
    final items = data['items'];
    if (items is! List) return const [];
    return items.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
      final content = Map<String, dynamic>.from(map['contentDetails'] as Map? ?? const {});
      final videoId = content['videoId']?.toString() ?? '';
      final title = snippet['title']?.toString() ?? 'Tanpa judul';
      final description = snippet['description']?.toString() ?? '';
      final releaseMetadata = YoutubeMusicMetadataParser.parse(
        title: title,
        description: description,
      );
      return YoutubeSearchResult(
        videoId: videoId,
        title: title,
        description: description,
        channelTitle: snippet['videoOwnerChannelTitle']?.toString() ??
            snippet['channelTitle']?.toString() ??
            'Channel',
        artistName: releaseMetadata.artistName,
        album: releaseMetadata.album,
        thumbnailUrl: thumbnail(snippet['thumbnails']),
        publishedAt: DateTime.tryParse(snippet['publishedAt']?.toString() ?? ''),
        channelId: snippet['videoOwnerChannelId']?.toString() ?? '',
      );
    }).where((item) => item.videoId.isNotEmpty).toList(growable: false);
  }

  static String thumbnail(dynamic raw) {
    if (raw is! Map) return '';
    for (final key in const ['maxres', 'high', 'standard', 'medium', 'default']) {
      final item = raw[key];
      if (item is Map) {
        final url = item['url']?.toString() ?? '';
        if (url.isNotEmpty) return url;
      }
    }
    return '';
  }
}
