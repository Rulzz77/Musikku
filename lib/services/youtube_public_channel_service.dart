import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

import '../models/youtube_search_result.dart';
import '../models/youtube_channel_models.dart';
import 'disk_cache.dart';
import 'youtube_api_request_guard.dart';
import 'youtube_public_response_parser.dart';
import 'youtube_search_service.dart';

/// Reads publicly available channel uploads and video metadata.
/// This service intentionally has no Google Sign-In, OAuth tokens, or write methods.
class YoutubePublicChannelService {
  static final YoutubePublicChannelService instance = YoutubePublicChannelService._();
  YoutubePublicChannelService._();

  static const String _base = 'https://www.googleapis.com/youtube/v3';
  static const String _apiKey = String.fromEnvironment('YOUTUBE_API_KEY');

  static const DiskCache _uploadPageCache = DiskCache(
    namespace: 'yt_public_upload_pages_v1',
    maxEntries: 250,
    ttl: Duration(hours: 2),
  );
  static const DiskCache _enrichedVideoCache = DiskCache(
    namespace: 'yt_public_enriched_video_batches_v1',
    maxEntries: 80,
    ttl: Duration(hours: 6),
  );
  static const DiskCache _channelPlaylistCache = DiskCache(
    namespace: 'yt_public_channel_playlists_v1',
    maxEntries: 80,
    ttl: Duration(hours: 12),
  );

  Future<Map<String, dynamic>> _get(String path, Map<String, String> params) async {
    if (_apiKey.trim().isEmpty) {
      throw StateError('Kunci YouTube API belum dikonfigurasi.');
    }
    final uri = Uri.parse('$_base/$path').replace(
      queryParameters: <String, String>{...params, 'key': _apiKey},
    );
    await YoutubeApiRequestGuard.beforeRequest('data');
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    YoutubeApiRequestGuard.observeResponse(
      scope: 'data',
      statusCode: response.statusCode,
      body: response.body,
      headers: response.headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('YouTube API ${response.statusCode}: ${response.body}');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
  }

  /// Public playlists owned by a channel (often used by artists for albums
  /// and singles). Results are cached to avoid repeating API calls when the
  /// user reopens the artist page.
  Future<({List<YoutubePublicPlaylist> items, String? nextPageToken})>
      channelPlaylistsPage(
    String channelId, {
    String? pageToken,
    int maxResults = 50,
    bool forceRefresh = false,
  }) async {
    if (channelId.trim().isEmpty) {
      return (items: const <YoutubePublicPlaylist>[], nextPageToken: null);
    }

    final safeMax = maxResults.clamp(1, 50).toInt();
    final cacheKey = 'channel-playlists:$channelId:${pageToken ?? 'first'}:$safeMax';
    if (!forceRefresh) {
      final cached = await _channelPlaylistCache.get(
        cacheKey,
        maxAge: const Duration(hours: 12),
      );
      if (cached is Map && cached['items'] is List) {
        final items = (cached['items'] as List)
            .whereType<Map>()
            .map((item) => YoutubePublicPlaylist.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .where((item) => item.id.isNotEmpty)
            .toList(growable: false);
        final rawToken = cached['nextPageToken']?.toString();
        return (
          items: items,
          nextPageToken: rawToken == null || rawToken.isEmpty ? null : rawToken,
        );
      }
    }

    final data = await _get(
      'playlists',
      <String, String>{
        'part': 'snippet,contentDetails',
        'channelId': channelId,
        'maxResults': '$safeMax',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      },
    );
    final rawItems = data['items'];
    final items = <YoutubePublicPlaylist>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final snippet = Map<String, dynamic>.from(
          item['snippet'] as Map? ?? const {},
        );
        final content = Map<String, dynamic>.from(
          item['contentDetails'] as Map? ?? const {},
        );
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        items.add(YoutubePublicPlaylist(
          id: id,
          title: snippet['title']?.toString() ?? 'Playlist',
          description: snippet['description']?.toString() ?? '',
          thumbnailUrl: YoutubePublicResponseParser.thumbnail(snippet['thumbnails']),
          itemCount: int.tryParse(content['itemCount']?.toString() ?? '') ?? 0,
          publishedAt: DateTime.tryParse(snippet['publishedAt']?.toString() ?? ''),
        ));
      }
    }

    final token = data['nextPageToken']?.toString();
    final next = token == null || token.isEmpty ? null : token;
    await _channelPlaylistCache.put(cacheKey, <String, dynamic>{
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'nextPageToken': next,
    });
    return (items: items, nextPageToken: next);
  }

  Future<({List<YoutubeSearchResult> items, String? nextPageToken})> playlistItemsPage(
    String playlistId, {
    String? pageToken,
    int maxResults = 50,
    bool forceRefresh = false,
  }) async {
    const cacheScope = 'public';
    final rawCacheKey = '$cacheScope|$playlistId|${pageToken ?? 'first'}|$maxResults';
    final cacheKey = 'upload:${crypto.sha256.convert(utf8.encode(rawCacheKey))}';
    if (!forceRefresh) {
      final cached = await _uploadPageCache.get(
        cacheKey,
        maxAge: const Duration(hours: 2),
      );
      if (cached is Map && cached['items'] is List) {
        final rawItems = cached['items'] as List;
        final items = rawItems
            .whereType<Map>()
            .map((item) => YoutubeSearchResult.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.videoId.isNotEmpty)
            .toList(growable: false);
        final rawToken = cached['nextPageToken']?.toString();
        return (
          items: items,
          nextPageToken: (rawToken == null || rawToken.isEmpty) ? null : rawToken,
        );
      }
    }

    final data = await _get(
      'playlistItems',
      <String, String>{
        'part': 'snippet,contentDetails',
        'playlistId': playlistId,
        'maxResults': '$maxResults',
        if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
      },
    );
    final token = data['nextPageToken']?.toString();
    final result = (
      items: YoutubePublicResponseParser.playlistItemsToTracks(data),
      nextPageToken: (token == null || token.isEmpty) ? null : token,
    );
    await _uploadPageCache.put(cacheKey, <String, dynamic>{
      'items': result.items.map((item) => item.toJson()).toList(growable: false),
      'nextPageToken': result.nextPageToken,
    });
    return result;
  }


  /// Adds view/duration/live details using cached batches of up to 50 videos.
  Future<List<YoutubeSearchResult>> withViewCounts(
    List<YoutubeSearchResult> source,
  ) async {
    final out = <YoutubeSearchResult>[];
    for (var i = 0; i < source.length; i += 50) {
      final end = (i + 50 < source.length) ? i + 50 : source.length;
      out.addAll(await _enrichViewCounts(source.sublist(i, end)));
    }
    return out;
  }


  Future<List<YoutubeSearchResult>> _enrichViewCounts(
    List<YoutubeSearchResult> source,
  ) async {
    if (source.isEmpty) return source;

    final detailsById = <String, YoutubeSearchResult>{};
    // videos.list accepts up to 50 IDs per call. Cache each batch in one local
    // write instead of performing hundreds of small SharedPreferences writes.
    for (var i = 0; i < source.length; i += 50) {
      final end = (i + 50 < source.length) ? i + 50 : source.length;
      final chunk = source.sublist(i, end);
      final sortedIds = chunk.map((e) => e.videoId).toList()..sort();
      final batchKey = 'ids:${crypto.sha256.convert(utf8.encode(sortedIds.join(',')))}';
      final cached = await _enrichedVideoCache.get(
        batchKey,
        maxAge: const Duration(hours: 6),
      );
      if (cached is List) {
        for (final item in cached) {
          if (item is! Map) continue;
          try {
            final detail = YoutubeSearchResult.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (detail.videoId.isNotEmpty) detailsById[detail.videoId] = detail;
          } catch (_) {}
        }
        if (cached.isNotEmpty || chunk.isEmpty) continue;
      }

      final data = await _get(
        'videos',
        <String, String>{
          'part': 'snippet,statistics,contentDetails,liveStreamingDetails',
          'id': chunk.map((e) => e.videoId).join(','),
        },
      );
      final items = data['items'];
      if (items is! List) continue;
      final batchDetails = <YoutubeSearchResult>[];
      for (final item in items) {
        if (item is! Map) continue;
        final detail = YoutubeSearchResult.fromVideoResource(
          Map<String, dynamic>.from(item),
        );
        if (detail == null || detail.videoId.isEmpty) continue;
        detailsById[detail.videoId] = detail;
        batchDetails.add(detail);
      }
      if (batchDetails.isNotEmpty) {
        await _enrichedVideoCache.put(
          batchKey,
          batchDetails.map((detail) => detail.toJson()).toList(growable: false),
        );
      }
    }

    return source.map((video) {
      final detail = detailsById[video.videoId];
      if (detail == null) return video;
      return video.copyWith(
        viewCount: detail.viewCount ?? video.viewCount,
        durationSeconds: detail.durationSeconds ?? video.durationSeconds,
        liveStatus: detail.liveStatus.isNotEmpty ? detail.liveStatus : video.liveStatus,
        concurrentViewers: detail.concurrentViewers ?? video.concurrentViewers,
        liveStartTime: detail.liveStartTime ?? video.liveStartTime,
        channelId: detail.channelId.isNotEmpty ? detail.channelId : video.channelId,
        categoryId: detail.categoryId.isNotEmpty ? detail.categoryId : video.categoryId,
        description: detail.description.isNotEmpty ? detail.description : video.description,
      );
    }).toList(growable: false);
  }


  Future<YoutubeChannelDetails?> channelDetails(String channelId) async {
    final data = await _get(
      'channels',
      <String, String>{
        'part': 'snippet,contentDetails,statistics,brandingSettings',
        'id': channelId,
      },
    );
    final items = data['items'];
    if (items is! List || items.isEmpty) return null;
    final map = Map<String, dynamic>.from(items.first as Map);
    final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
    final content = Map<String, dynamic>.from(map['contentDetails'] as Map? ?? const {});
    final stats = Map<String, dynamic>.from(map['statistics'] as Map? ?? const {});
    final branding = Map<String, dynamic>.from(map['brandingSettings'] as Map? ?? const {});
    final image = Map<String, dynamic>.from(branding['image'] as Map? ?? const {});
    final related = Map<String, dynamic>.from(content['relatedPlaylists'] as Map? ?? const {});
    return YoutubeChannelDetails(
      id: map['id']?.toString() ?? channelId,
      title: snippet['title']?.toString() ?? 'Channel',
      handle: snippet['customUrl']?.toString() ?? '',
      description: snippet['description']?.toString() ?? '',
      avatarUrl: YoutubePublicResponseParser.thumbnail(snippet['thumbnails']),
      bannerUrl: image['bannerExternalUrl']?.toString() ?? '',
      subscriberCount: int.tryParse(stats['subscriberCount']?.toString() ?? ''),
      hiddenSubscriberCount: stats['hiddenSubscriberCount'] == true,
      videoCount: int.tryParse(stats['videoCount']?.toString() ?? ''),
      uploadsPlaylistId: related['uploads']?.toString() ?? '',
    );
  }


  Future<({List<YoutubeSearchResult> items, String? nextPageToken})> scanLiveVideos(
    String uploadsPlaylistId, {
    String? pageToken,
    int maxPages = 4,
    String channelTitle = '',
    String channelDescription = '',
  }) async {
    final found = <YoutubeSearchResult>[];
    String? token = pageToken;
    var pages = 0;
    do {
      final page = await playlistItemsPage(uploadsPlaylistId, pageToken: token);
      token = page.nextPageToken;
      pages++;
      if (page.items.isNotEmpty) {
        final detailed = await _enrichViewCounts(page.items);
        final musicOnly = detailed.where((video) =>
            video.liveStatus.isNotEmpty &&
            YoutubeSearchService.isMusicChannelUpload(
              video,
              channelTitle: channelTitle.isNotEmpty ? channelTitle : video.channelTitle,
              channelDescription: channelDescription,
            )).toList(growable: false);
        found.addAll(await YoutubeSearchService().removeShorts(musicOnly));
      }
    } while (token != null && pages < maxPages);
    return (items: found, nextPageToken: token);
  }

}
