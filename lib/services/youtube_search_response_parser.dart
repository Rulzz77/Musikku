import '../models/youtube_search_result.dart';

/// Stateless decoding of YouTube API payloads into app models.
class YoutubeSearchResponseParser {
  static List<YoutubeSearchResult> resultsFromJson(Object? raw) {
    if (raw is! List) {
      return <YoutubeSearchResult>[];
    }

    final list = raw
        .whereType<Map>()
        .map((item) => YoutubeSearchResult.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((video) => video.videoId.isNotEmpty)
        .toList();

    // Cache lama (sebelum ada channelId) bikin foto channel tidak pernah
    // muncul. Anggap cache seperti itu kedaluwarsa supaya diambil ulang.
    if (list.any((v) => !v.isLocal && v.channelId.isEmpty)) {
      return <YoutubeSearchResult>[];
    }
    return list;
  }

  static List<YoutubeSearchResult> parseVideoResources(List items) {
    final out = <YoutubeSearchResult>[];
    for (final item in items) {
      if (item is! Map) continue;
      final video = YoutubeSearchResult.fromVideoResource(
        Map<String, dynamic>.from(item),
        pickThumbnail: pickThumbnail,
        decode: decodeHtml,
      );
      if (video == null) continue;
      final seconds = video.durationSeconds;
      if (!video.isLive && !video.isUpcoming && seconds != null && seconds <= 60) {
        continue;
      }
      out.add(video);
    }
    return out;
  }

  static List<YoutubeSearchResult> parseSearchItems(List items) {
    final results = <YoutubeSearchResult>[];

    for (final item in items) {
      if (item is! Map) {
        continue;
      }

      final id = item['id'];
      final snippet = item['snippet'];

      if (id is! Map || snippet is! Map) {
        continue;
      }

      final videoId = id['videoId']?.toString() ?? '';

      if (videoId.isEmpty) {
        continue;
      }

      results.add(
        YoutubeSearchResult(
          videoId: videoId,
          title: decodeHtml(snippet['title']?.toString() ?? 'Tanpa judul'),
          description: decodeHtml(snippet['description']?.toString() ?? ''),
          channelTitle: decodeHtml(
            snippet['channelTitle']?.toString() ?? 'Unknown',
          ),
          thumbnailUrl: pickThumbnail(snippet['thumbnails']),
          publishedAt: DateTime.tryParse(snippet['publishedAt']?.toString() ?? ''),
          channelId: snippet['channelId']?.toString() ?? '',
        ),
      );
    }

    return results;
  }

  static String pickThumbnail(dynamic thumbnails) {
    if (thumbnails is! Map) {
      return '';
    }

    for (final size in const ['high', 'medium', 'default']) {
      final image = thumbnails[size];

      if (image is Map) {
        final url = image['url']?.toString() ?? '';

        if (url.isNotEmpty) {
          return url;
        }
      }
    }

    return '';
  }

  static String decodeHtml(String input) {
    var text = input.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) {
        final code = int.tryParse(match.group(1)!);

        if (code == null || code > 0x10FFFF) {
          return match.group(0)!;
        }

        return String.fromCharCode(code);
      },
    );

    text = text.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (match) {
        final code = int.tryParse(match.group(1)!, radix: 16);

        if (code == null || code > 0x10FFFF) {
          return match.group(0)!;
        }

        return String.fromCharCode(code);
      },
    );

    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}
