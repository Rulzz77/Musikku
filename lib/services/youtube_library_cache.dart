import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_search_result.dart';
import '../models/youtube_account_models.dart';

/// Last-known YouTube library data for one Google account.
///
/// Nullable fields distinguish "no cached value" from a legitimately empty
/// list. This allows the UI to preserve each cached section independently
/// while network refreshes run in the background.
class YoutubeLibrarySnapshot {
  const YoutubeLibrarySnapshot({
    this.subscriptions,
    this.likedVideos,
    this.playlists,
    this.feed,
    this.updatedAt,
  });

  final List<YoutubeChannelSummary>? subscriptions;
  final List<YoutubeSearchResult>? likedVideos;
  final List<YoutubePlaylistSummary>? playlists;
  final List<YoutubeSearchResult>? feed;
  final DateTime? updatedAt;

  bool get hasData =>
      subscriptions != null ||
      likedVideos != null ||
      playlists != null ||
      feed != null;
}

/// Account-scoped persistence for the YouTube library.
///
/// Keys retain the v1 prefix used by previous MusikKu builds so the cache can
/// be migrated without discarding users' last-known playlist data.
class YoutubeLibraryCache {
  static const List<String> _fields = <String>[
    'subscriptions',
    'liked',
    'playlists',
    'feed',
  ];

  const YoutubeLibraryCache();

  String _normalizedEmail(String email) => email.trim().toLowerCase();

  String _fieldKey(String email, String field) {
    final accountKey = base64Url
        .encode(utf8.encode(_normalizedEmail(email)))
        .replaceAll('=', '');
    return 'youtube_hub_cache_v1_${accountKey}_$field';
  }

  String _updatedAtKey(String email) => _fieldKey(email, 'updated_at');

  Future<void> saveSubscriptions(
    String email,
    List<YoutubeChannelSummary> values,
  ) async {
    await _save(email, 'subscriptions', values.map((value) => <String, dynamic>{
      'id': value.id,
      'title': value.title,
      'description': value.description,
      'thumbnailUrl': value.thumbnailUrl,
      'uploadsPlaylistId': value.uploadsPlaylistId,
      'subscriberCount': value.subscriberCount,
    }).toList(growable: false));
  }

  Future<void> saveLikedVideos(
    String email,
    List<YoutubeSearchResult> values,
  ) async {
    await _save(
      email,
      'liked',
      values.map((value) => value.toJson()).toList(growable: false),
    );
  }

  Future<void> savePlaylists(
    String email,
    List<YoutubePlaylistSummary> values,
  ) async {
    await _save(email, 'playlists', values.map((value) => <String, dynamic>{
      'id': value.id,
      'title': value.title,
      'description': value.description,
      'privacyStatus': value.privacyStatus,
      'itemCount': value.itemCount,
      'thumbnailUrl': value.thumbnailUrl,
    }).toList(growable: false));
  }

  Future<void> saveFeed(
    String email,
    List<YoutubeSearchResult> values,
  ) async {
    await _save(
      email,
      'feed',
      values.map((value) => value.toJson()).toList(growable: false),
    );
  }

  Future<void> _save(
    String email,
    String field,
    List<Map<String, dynamic>> values,
  ) async {
    if (_normalizedEmail(email).isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fieldKey(email, field), jsonEncode(values));
      await prefs.setInt(
        _updatedAtKey(email),
        DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    } catch (error) {
      debugPrint('YOUTUBE LIBRARY CACHE SAVE ERROR ($field): $error');
    }
  }

  Future<YoutubeLibrarySnapshot> load(String email) async {
    if (_normalizedEmail(email).isEmpty) {
      return const YoutubeLibrarySnapshot();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_fields.any((field) => prefs.containsKey(_fieldKey(email, field)))) {
        return const YoutubeLibrarySnapshot();
      }

      List<Map<String, dynamic>>? readMaps(String field) {
        final raw = prefs.getString(_fieldKey(email, field));
        if (raw == null) return null;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is! List) return <Map<String, dynamic>>[];
          return decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false);
        } catch (_) {
          // A corrupt field is treated as an empty cached value; it should not
          // prevent the other independent sections from loading.
          return <Map<String, dynamic>>[];
        }
      }

      final subscriptionsJson = readMaps('subscriptions');
      final likedJson = readMaps('liked');
      final playlistsJson = readMaps('playlists');
      final feedJson = readMaps('feed');
      final updatedRaw = prefs.getInt(_updatedAtKey(email));

      return YoutubeLibrarySnapshot(
        subscriptions: subscriptionsJson?.map((item) => YoutubeChannelSummary(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? 'Channel',
          description: item['description']?.toString() ?? '',
          thumbnailUrl: item['thumbnailUrl']?.toString() ?? '',
          uploadsPlaylistId: item['uploadsPlaylistId']?.toString() ?? '',
          subscriberCount: item['subscriberCount'] is num
              ? (item['subscriberCount'] as num).toInt()
              : null,
        )).where((item) => item.id.isNotEmpty).toList(growable: false),
        likedVideos: likedJson
            ?.map(YoutubeSearchResult.fromJson)
            .where((item) => item.videoId.isNotEmpty)
            .toList(growable: false),
        playlists: playlistsJson?.map((item) => YoutubePlaylistSummary(
          id: item['id']?.toString() ?? '',
          title: item['title']?.toString() ?? 'Playlist',
          description: item['description']?.toString() ?? '',
          privacyStatus: item['privacyStatus']?.toString() ?? 'private',
          itemCount: item['itemCount'] is num
              ? (item['itemCount'] as num).toInt()
              : 0,
          thumbnailUrl: item['thumbnailUrl']?.toString() ?? '',
        )).where((item) => item.id.isNotEmpty).toList(growable: false),
        feed: feedJson
            ?.map(YoutubeSearchResult.fromJson)
            .where((item) => item.videoId.isNotEmpty)
            .toList(growable: false),
        updatedAt: updatedRaw == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(updatedRaw, isUtc: true),
      );
    } catch (error) {
      debugPrint('YOUTUBE LIBRARY CACHE LOAD ERROR: $error');
      return const YoutubeLibrarySnapshot();
    }
  }

  Future<void> clear(String email) async {
    if (_normalizedEmail(email).isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final field in <String>[..._fields, 'updated_at']) {
        await prefs.remove(_fieldKey(email, field));
      }
    } catch (error) {
      debugPrint('YOUTUBE LIBRARY CACHE CLEAR ERROR: $error');
    }
  }
}
