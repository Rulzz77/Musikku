import '../models/youtube_search_result.dart';

/// Converts YouTube account API payloads into the app's track model.
class YoutubeAccountResponseParser {
  static List<YoutubeSearchResult> playlistItemsToTracks(Map<String, dynamic> data) {
    final items = data['items'];
    if (items is! List) return const [];
    return items.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
      final content = Map<String, dynamic>.from(map['contentDetails'] as Map? ?? const {});
      final videoId = content['videoId']?.toString() ?? '';
      return YoutubeSearchResult(
        videoId: videoId,
        title: snippet['title']?.toString() ?? 'Tanpa judul',
        channelTitle: snippet['videoOwnerChannelTitle']?.toString() ??
            snippet['channelTitle']?.toString() ??
            'Channel',
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
