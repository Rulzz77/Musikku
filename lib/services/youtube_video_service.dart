import 'dart:convert';

import 'package:http/http.dart' as http;

import 'disk_cache.dart';

class YoutubeVideoDetails {
  final String videoId;
  final String title;
  final String description;
  final String channelId;
  final String channelTitle;
  final String thumbnailUrl;
  final int? viewCount;
  final int? likeCount;
  final int? commentCount;
  final DateTime? publishedAt;
  final String liveBroadcastContent;
  final String activeLiveChatId;

  const YoutubeVideoDetails({
    required this.videoId,
    required this.title,
    required this.description,
    required this.channelId,
    required this.channelTitle,
    required this.thumbnailUrl,
    this.viewCount,
    this.likeCount,
    this.commentCount,
    this.publishedAt,
    this.liveBroadcastContent = '',
    this.activeLiveChatId = '',
  });
}

class YoutubeCommentReply {
  final String id;
  final String author;
  final String authorAvatarUrl;
  final String text;
  final int likeCount;
  final DateTime? publishedAt;

  const YoutubeCommentReply({
    required this.id,
    required this.author,
    required this.authorAvatarUrl,
    required this.text,
    required this.likeCount,
    this.publishedAt,
  });
}

class YoutubeComment {
  final String id;
  final String author;
  final String authorAvatarUrl;
  final String text;
  final int likeCount;
  final int replyCount;
  final List<YoutubeCommentReply> replies;
  final DateTime? publishedAt;

  const YoutubeComment({
    required this.id,
    required this.author,
    required this.authorAvatarUrl,
    required this.text,
    required this.likeCount,
    required this.replyCount,
    this.replies = const [],
    this.publishedAt,
  });
}

class YoutubeLiveChatPage {
  final List<YoutubeComment> messages;
  final String? nextPageToken;
  final int? pollingIntervalMillis;

  const YoutubeLiveChatPage({
    required this.messages,
    this.nextPageToken,
    this.pollingIntervalMillis,
  });
}

class YoutubeVideoService {
  YoutubeVideoService({this.apiKey = const String.fromEnvironment('YOUTUBE_API_KEY')});

  final String apiKey;
  static const _base = 'https://www.googleapis.com/youtube/v3';
  static const DiskCache _detailsCache = DiskCache(
    namespace: 'yt_details_v2',
    maxEntries: 120,
    ttl: Duration(days: 3),
  );
  static const DiskCache _commentsCache = DiskCache(
    namespace: 'yt_comments_v2',
    maxEntries: 60,
    ttl: Duration(hours: 8),
  );

  Future<YoutubeVideoDetails?> details(String videoId) async {
    if (videoId.trim().isEmpty) return null;
    final cached = await _detailsCache.get(videoId);
    if (cached is Map) {
      try {
        final decoded = Map<String, dynamic>.from(cached);
        return YoutubeVideoDetails(
          videoId: decoded['videoId']?.toString() ?? videoId,
          title: decoded['title']?.toString() ?? 'Video',
          description: decoded['description']?.toString() ?? '',
          channelId: decoded['channelId']?.toString() ?? '',
          channelTitle: decoded['channelTitle']?.toString() ?? 'YouTube',
          thumbnailUrl: decoded['thumbnailUrl']?.toString() ?? '',
          viewCount: (decoded['viewCount'] as num?)?.toInt(),
          likeCount: (decoded['likeCount'] as num?)?.toInt(),
          commentCount: (decoded['commentCount'] as num?)?.toInt(),
          publishedAt: DateTime.tryParse(decoded['publishedAt']?.toString() ?? ''),
          liveBroadcastContent: decoded['liveBroadcastContent']?.toString() ?? '',
          activeLiveChatId: decoded['activeLiveChatId']?.toString() ?? '',
        );
      } catch (_) {}
    }

    if (apiKey.trim().isEmpty) return null;

    final uri = Uri.parse('$_base/videos').replace(queryParameters: {
      'part': 'snippet,statistics,contentDetails,liveStreamingDetails',
      'id': videoId,
      'key': apiKey,
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('YouTube video ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body);
    final items = body is Map ? body['items'] : null;
    if (items is! List || items.isEmpty || items.first is! Map) return null;
    final item = Map<String, dynamic>.from(items.first as Map);
    final snippet = Map<String, dynamic>.from(item['snippet'] as Map? ?? const {});
    final stats = Map<String, dynamic>.from(item['statistics'] as Map? ?? const {});
    final live = Map<String, dynamic>.from(item['liveStreamingDetails'] as Map? ?? const {});
    final detailsToCache = <String, dynamic>{
      'videoId': videoId,
      'title': snippet['title']?.toString() ?? 'Video',
      'description': snippet['description']?.toString() ?? '',
      'channelId': snippet['channelId']?.toString() ?? '',
      'channelTitle': snippet['channelTitle']?.toString() ?? 'YouTube',
      'thumbnailUrl': _thumbnail(snippet['thumbnails']),
      'viewCount': int.tryParse(stats['viewCount']?.toString() ?? ''),
      'likeCount': int.tryParse(stats['likeCount']?.toString() ?? ''),
      'commentCount': int.tryParse(stats['commentCount']?.toString() ?? ''),
      'publishedAt': snippet['publishedAt']?.toString() ?? '',
      'liveBroadcastContent': snippet['liveBroadcastContent']?.toString() ?? '',
      'activeLiveChatId': live['activeLiveChatId']?.toString() ?? '',
    };
    await _detailsCache.put(videoId, detailsToCache);
    return YoutubeVideoDetails(
      videoId: videoId,
      title: detailsToCache['title'] as String,
      description: detailsToCache['description'] as String,
      channelId: detailsToCache['channelId'] as String,
      channelTitle: detailsToCache['channelTitle'] as String,
      thumbnailUrl: detailsToCache['thumbnailUrl'] as String,
      viewCount: detailsToCache['viewCount'] as int?,
      likeCount: detailsToCache['likeCount'] as int?,
      commentCount: detailsToCache['commentCount'] as int?,
      publishedAt: DateTime.tryParse(detailsToCache['publishedAt'] as String),
      liveBroadcastContent: detailsToCache['liveBroadcastContent'] as String,
      activeLiveChatId: detailsToCache['activeLiveChatId'] as String,
    );
  }

  Future<List<YoutubeComment>> comments(
    String videoId, {
    int maxResults = 100,
    String order = 'relevance',
    String? pageToken,
  }) async {
    if (videoId.trim().isEmpty) return const [];
    final cacheKey = '$videoId|$order';
    final cached = pageToken == null ? await _commentsCache.get(cacheKey) : null;
    if (cached is List) {
      try {
        return cached.whereType<Map>().map(_commentFromCache).toList(growable: false);
      } catch (_) {}
    }

    if (apiKey.trim().isEmpty) return const [];

    final params = <String, String>{
      'part': 'snippet,replies',
      'videoId': videoId,
      'maxResults': '${maxResults.clamp(1, 100)}',
      'order': order == 'time' ? 'time' : 'relevance',
      'textFormat': 'plainText',
      'key': apiKey,
    };
    if (pageToken != null && pageToken.isNotEmpty) params['pageToken'] = pageToken;
    final uri = Uri.parse('$_base/commentThreads').replace(queryParameters: params);
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode == 403 && response.body.contains('commentsDisabled')) return const [];
    if (response.statusCode != 200) {
      throw StateError('YouTube comments ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body);
    final items = body is Map ? body['items'] : null;
    if (items is! List) return const [];
    final parsed = items.whereType<Map>().map((raw) {
      final map = Map<String, dynamic>.from(raw);
      final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
      final top = Map<String, dynamic>.from(snippet['topLevelComment'] as Map? ?? const {});
      final topSnippet = Map<String, dynamic>.from(top['snippet'] as Map? ?? const {});
      final rawReplies = map['replies'] is Map
          ? (map['replies'] as Map)['comments']
          : null;
      final parsedReplies = <YoutubeCommentReply>[];
      if (rawReplies is List) {
        for (final replyRaw in rawReplies) {
          if (replyRaw is! Map) continue;
          final reply = Map<String, dynamic>.from(replyRaw);
          final replySnippet = Map<String, dynamic>.from(
            reply['snippet'] as Map? ?? const {},
          );
          final replyId = reply['id']?.toString() ?? '';
          if (replyId.isEmpty) continue;
          parsedReplies.add(
            YoutubeCommentReply(
              id: replyId,
              author: replySnippet['authorDisplayName']?.toString() ?? 'YouTube User',
              authorAvatarUrl: replySnippet['authorProfileImageUrl']?.toString() ?? '',
              text: replySnippet['textDisplay']?.toString() ?? '',
              likeCount: (replySnippet['likeCount'] as num?)?.toInt() ?? 0,
              publishedAt: DateTime.tryParse(replySnippet['publishedAt']?.toString() ?? ''),
            ),
          );
        }
      }
      return YoutubeComment(
        id: map['id']?.toString() ?? '',
        author: topSnippet['authorDisplayName']?.toString() ?? 'YouTube User',
        authorAvatarUrl: topSnippet['authorProfileImageUrl']?.toString() ?? '',
        text: topSnippet['textDisplay']?.toString() ?? '',
        likeCount: (topSnippet['likeCount'] as num?)?.toInt() ?? 0,
        replyCount: (snippet['totalReplyCount'] as num?)?.toInt() ?? 0,
        replies: parsedReplies,
        publishedAt: DateTime.tryParse(topSnippet['publishedAt']?.toString() ?? ''),
      );
    }).where((comment) => comment.id.isNotEmpty).toList(growable: false);

    if (pageToken == null) {
      final payload = parsed.map((comment) => {
        'id': comment.id,
        'author': comment.author,
        'authorAvatarUrl': comment.authorAvatarUrl,
        'text': comment.text,
        'likeCount': comment.likeCount,
        'replyCount': comment.replyCount,
        'publishedAt': comment.publishedAt?.toIso8601String() ?? '',
        'replies': comment.replies.map((reply) => {
          'id': reply.id,
          'author': reply.author,
          'authorAvatarUrl': reply.authorAvatarUrl,
          'text': reply.text,
          'likeCount': reply.likeCount,
          'publishedAt': reply.publishedAt?.toIso8601String() ?? '',
        }).toList(growable: false),
      }).toList(growable: false);
      await _commentsCache.put(cacheKey, payload);
    }

    return parsed;
  }

  YoutubeComment _commentFromCache(Map raw) {
    final repliesRaw = raw['replies'];
    final cachedReplies = <YoutubeCommentReply>[];
    if (repliesRaw is List) {
      for (final value in repliesRaw) {
        if (value is! Map) continue;
        cachedReplies.add(
          YoutubeCommentReply(
            id: value['id']?.toString() ?? '',
            author: value['author']?.toString() ?? 'YouTube User',
            authorAvatarUrl: value['authorAvatarUrl']?.toString() ?? '',
            text: value['text']?.toString() ?? '',
            likeCount: (value['likeCount'] as num?)?.toInt() ?? 0,
            publishedAt: DateTime.tryParse(value['publishedAt']?.toString() ?? ''),
          ),
        );
      }
    }
    return YoutubeComment(
      id: raw['id']?.toString() ?? '',
      author: raw['author']?.toString() ?? 'YouTube User',
      authorAvatarUrl: raw['authorAvatarUrl']?.toString() ?? '',
      text: raw['text']?.toString() ?? '',
      likeCount: (raw['likeCount'] as num?)?.toInt() ?? 0,
      replyCount: (raw['replyCount'] as num?)?.toInt() ?? 0,
      replies: cachedReplies,
      publishedAt: DateTime.tryParse(raw['publishedAt']?.toString() ?? ''),
    );
  }


  Future<List<YoutubeCommentReply>> replies(
    String parentCommentId, {
    int maxResults = 100,
    String? pageToken,
  }) async {
    if (parentCommentId.trim().isEmpty || apiKey.trim().isEmpty) return const [];
    final params = <String, String>{
      'part': 'snippet',
      'parentId': parentCommentId,
      'maxResults': '${maxResults.clamp(1, 100)}',
      'textFormat': 'plainText',
      'key': apiKey,
    };
    if (pageToken != null && pageToken.isNotEmpty) params['pageToken'] = pageToken;
    final uri = Uri.parse('$_base/comments').replace(queryParameters: params);
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode == 403 && response.body.contains('commentsDisabled')) return const [];
    if (response.statusCode != 200) {
      throw StateError('YouTube replies ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body);
    final items = body is Map ? body['items'] : null;
    if (items is! List) return const [];
    return items.whereType<Map>().map((raw) {
      final map = Map<String, dynamic>.from(raw);
      final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
      return YoutubeCommentReply(
        id: map['id']?.toString() ?? '',
        author: snippet['authorDisplayName']?.toString() ?? 'YouTube User',
        authorAvatarUrl: snippet['authorProfileImageUrl']?.toString() ?? '',
        text: snippet['textDisplay']?.toString() ?? '',
        likeCount: (snippet['likeCount'] as num?)?.toInt() ?? 0,
        publishedAt: DateTime.tryParse(snippet['publishedAt']?.toString() ?? ''),
      );
    }).where((reply) => reply.id.isNotEmpty).toList(growable: false);
  }

  Future<YoutubeLiveChatPage> liveChatMessages(
    String liveChatId, {
    String? pageToken,
    int maxResults = 50,
  }) async {
    if (liveChatId.trim().isEmpty || apiKey.trim().isEmpty) {
      return const YoutubeLiveChatPage(messages: []);
    }
    final params = <String, String>{
      'part': 'snippet,authorDetails',
      'liveChatId': liveChatId,
      'maxResults': '${maxResults.clamp(1, 2000)}',
      'key': apiKey,
    };
    if (pageToken != null && pageToken.isNotEmpty) {
      params['pageToken'] = pageToken;
    }
    final uri = Uri.parse('$_base/liveChat/messages').replace(queryParameters: params);
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw StateError('YouTube live chat ${response.statusCode}: ${response.body}');
    }
    final body = jsonDecode(response.body);
    final items = body is Map ? body['items'] : null;
    if (items is! List) return const YoutubeLiveChatPage(messages: []);

    final messages = <YoutubeComment>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final snippet = Map<String, dynamic>.from(map['snippet'] as Map? ?? const {});
      final author = Map<String, dynamic>.from(map['authorDetails'] as Map? ?? const {});
      messages.add(
        YoutubeComment(
          id: map['id']?.toString() ?? '',
          author: author['displayName']?.toString() ?? 'YouTube User',
          authorAvatarUrl: author['profileImageUrl']?.toString() ?? '',
          text: snippet['displayMessage']?.toString() ?? '',
          likeCount: (snippet['messageActionDetails'] is Map) ? 0 : 0,
          replyCount: 0,
        ),
      );
    }

    return YoutubeLiveChatPage(
      messages: messages.where((e) => e.id.isNotEmpty).toList(growable: false),
      nextPageToken: body is Map ? body['nextPageToken']?.toString() : null,
      pollingIntervalMillis: body is Map ? int.tryParse(body['pollingIntervalMillis']?.toString() ?? '') : null,
    );
  }

  String _thumbnail(dynamic raw) {
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
