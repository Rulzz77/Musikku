import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_search_result.dart';

/// Resolves square album artwork from MusicBrainz/Cover Art Archive.
///
/// This service is intentionally used only for the active/mini player, not for
/// every search result. Results (including negative matches) are cached to
/// avoid repeatedly querying public community services.
class AlbumArtworkService {
  AlbumArtworkService._();

  static const String _cachePrefix = 'musikku_album_artwork_v1_';
  static const String _noArtwork = '__no_album_artwork__';
  static const Duration _positiveCacheTtl = Duration(days: 180);
  static const Duration _negativeCacheTtl = Duration(days: 5);
  static const Duration _requestTimeout = Duration(seconds: 9);
  static const Duration _minimumMusicBrainzInterval = Duration(milliseconds: 1100);

  static final Map<String, Future<String?>> _pending = <String, Future<String?>>{};
  static Future<void> _musicBrainzQueue = Future<void>.value();
  static DateTime _lastMusicBrainzRequest = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns an album-cover URL, falling back to the YouTube thumbnail.
  /// Local files are handled by [UnifiedArtwork] and should not call this.
  static Future<String> resolveCoverUrl(YoutubeSearchResult track) async {
    final fallback = track.coverUrl;
    if (track.isLocal) return fallback;

    final title = _cleanTitle(track.title, track.channelTitle);
    final artist = _cleanArtist(track.channelTitle);
    if (title.isEmpty || artist.isEmpty) return fallback;

    final cacheKey = _cacheKey(title, artist);
    try {
      final cached = await _readCache(cacheKey);
      if (cached != null) return cached.isEmpty ? fallback : cached;
    } catch (_) {
      // Storage being unavailable must not block normal playback.
    }

    final future = _pending.putIfAbsent(
      cacheKey,
      () => _lookupAndCache(cacheKey, title, artist),
    );
    try {
      return (await future) ?? fallback;
    } catch (_) {
      return fallback;
    } finally {
      if (identical(_pending[cacheKey], future)) {
        _pending.remove(cacheKey);
      }
    }
  }

  static String _cacheKey(String title, String artist) {
    final normalized = '${_matchKey(artist)}|${_matchKey(title)}';
    return '$_cachePrefix${sha256.convert(utf8.encode(normalized))}';
  }

  /// A null return from _readCache means cache miss; a cached negative result
  /// is represented by the empty string so it remains distinguishable.
  static Future<String?> _readCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    final map = jsonDecode(raw);
    if (map is! Map) return null;
    final expiry = map['expiresAt'] is num ? (map['expiresAt'] as num).toInt() : 0;
    if (expiry <= DateTime.now().millisecondsSinceEpoch) {
      await prefs.remove(key);
      return null;
    }
    final url = map['url']?.toString() ?? '';
    return url == _noArtwork ? '' : url;
  }

  static Future<String?> _lookupAndCache(String key, String title, String artist) async {
    final lookup = await _findAlbumArtwork(title, artist);
    if (!lookup.cacheable) return lookup.url;

    try {
      final prefs = await SharedPreferences.getInstance();
      final ttl = lookup.url == null ? _negativeCacheTtl : _positiveCacheTtl;
      await prefs.setString(
        key,
        jsonEncode(<String, Object>{
          'url': lookup.url ?? _noArtwork,
          'expiresAt': DateTime.now().add(ttl).millisecondsSinceEpoch,
        }),
      );
    } catch (_) {
      // Cache failure is non-fatal; artwork still works for this session.
    }
    return lookup.url;
  }

  static Future<_ArtworkLookup> _findAlbumArtwork(String title, String artist) async {
    final query = 'recording:"${_luceneEscape(title)}" AND artist:"${_luceneEscape(artist)}"';
    final searchUri = Uri.https('musicbrainz.org', '/ws/2/recording/', <String, String>{
      'query': query,
      'fmt': 'json',
      'limit': '5',
    });

    final response = await _musicBrainzGet(searchUri);
    if (response.statusCode != 200) {
      throw StateError('MusicBrainz returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final rows = decoded is Map && decoded['recordings'] is List
        ? (decoded['recordings'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final requestedTitle = _matchKey(title);
    final requestedArtist = _matchKey(artist);
    final releaseCandidates = <_ReleaseCandidate>[];
    String bestRecordingId = '';
    double bestRecordingScore = -1;

    for (final row in rows) {
      final rowTitle = _matchKey(row['title']?.toString() ?? '');
      final score = row['score'] is num
          ? (row['score'] as num).toDouble()
          : double.tryParse(row['score']?.toString() ?? '') ?? 0;
      final titleCompatible = rowTitle == requestedTitle ||
          (requestedTitle.length > 3 && (rowTitle.contains(requestedTitle) || requestedTitle.contains(rowTitle)));
      if (!titleCompatible || score < 65) continue;

      final creditedArtist = _artistCredit(row['artist-credit']);
      final normalizedCredit = _matchKey(creditedArtist);
      final artistCompatible = normalizedCredit.isEmpty ||
          normalizedCredit.contains(requestedArtist) ||
          requestedArtist.contains(normalizedCredit);
      if (!artistCompatible) continue;
      if (score > bestRecordingScore) {
        bestRecordingScore = score;
        bestRecordingId = row['id']?.toString() ?? '';
      }

      final releases = row['releases'];
      if (releases is! List) continue;
      for (final releaseValue in releases) {
        if (releaseValue is! Map) continue;
        final releaseId = releaseValue['id']?.toString() ?? '';
        final releaseGroupValue = releaseValue['release-group'];
        final groupId = releaseGroupValue is Map ? releaseGroupValue['id']?.toString() ?? '' : '';
        if (groupId.isEmpty && releaseId.isEmpty) continue;
        releaseCandidates.add(_ReleaseCandidate(
          groupId: groupId,
          releaseId: releaseId,
          score: score,
          official: (releaseValue['status']?.toString().toLowerCase() ?? '') == 'official',
        ));
      }
    }

    releaseCandidates.sort((a, b) {
      if (a.official != b.official) return a.official ? -1 : 1;
      return b.score.compareTo(a.score);
    });

    if (releaseCandidates.isEmpty && bestRecordingId.isNotEmpty) {
      // Some MusicBrainz search responses omit embedded releases. Resolve the
      // best recording once to get official releases without guessing an album.
      final lookupUri = Uri.https('musicbrainz.org', '/ws/2/recording/$bestRecordingId', <String, String>{
        'inc': 'releases',
        'fmt': 'json',
      });
      final lookupResponse = await _musicBrainzGet(lookupUri);
      if (lookupResponse.statusCode == 200) {
        final lookupJson = jsonDecode(lookupResponse.body);
        final releases = lookupJson is Map && lookupJson['releases'] is List
            ? (lookupJson['releases'] as List).whereType<Map>()
            : const <Map>[];
        for (final release in releases) {
          final releaseId = release['id']?.toString() ?? '';
          final group = release['release-group'];
          final groupId = group is Map ? group['id']?.toString() ?? '' : '';
          if (groupId.isNotEmpty || releaseId.isNotEmpty) {
            releaseCandidates.add(_ReleaseCandidate(
              groupId: groupId,
              releaseId: releaseId,
              score: bestRecordingScore,
              official: (release['status']?.toString().toLowerCase() ?? '') == 'official',
            ));
          }
        }
      } else if (lookupResponse.statusCode != 404) {
        throw StateError('MusicBrainz recording lookup returned ${lookupResponse.statusCode}');
      }
    }

    if (releaseCandidates.isEmpty) {
      // One carefully scoped fallback search handles tracks without release
      // links on the recording entry. It is still rate-limited below.
      final fallbackQuery = 'release:"${_luceneEscape(title)}" AND artist:"${_luceneEscape(artist)}"';
      final fallbackUri = Uri.https('musicbrainz.org', '/ws/2/release-group/', <String, String>{
        'query': fallbackQuery,
        'fmt': 'json',
        'limit': '4',
      });
      final fallbackResponse = await _musicBrainzGet(fallbackUri);
      if (fallbackResponse.statusCode != 200) {
        throw StateError('MusicBrainz release-group returned ${fallbackResponse.statusCode}');
      }
      final fallbackJson = jsonDecode(fallbackResponse.body);
      final groups = fallbackJson is Map && fallbackJson['release-groups'] is List
          ? (fallbackJson['release-groups'] as List).whereType<Map>().toList(growable: false)
          : const <Map>[];
      for (final group in groups) {
        final groupTitle = _matchKey(group['title']?.toString() ?? '');
        if (groupTitle.isNotEmpty &&
            (groupTitle == requestedTitle ||
                (requestedTitle.length > 3 && groupTitle.contains(requestedTitle)))) {
          final id = group['id']?.toString() ?? '';
          if (id.isNotEmpty) releaseCandidates.add(_ReleaseCandidate(groupId: id, releaseId: '', score: 70, official: true));
        }
      }
    }

    if (releaseCandidates.isEmpty) return const _ArtworkLookup(null, cacheable: true);

    final visited = <String>{};
    for (final candidate in releaseCandidates.take(4)) {
      if (candidate.groupId.isNotEmpty && visited.add('g:${candidate.groupId}')) {
        final url = await _coverArtUrl('release-group', candidate.groupId);
        if (url != null) return _ArtworkLookup(url, cacheable: true);
      }
      if (candidate.releaseId.isNotEmpty && visited.add('r:${candidate.releaseId}')) {
        final url = await _coverArtUrl('release', candidate.releaseId);
        if (url != null) return _ArtworkLookup(url, cacheable: true);
      }
    }
    return const _ArtworkLookup(null, cacheable: true);
  }

  static Future<http.Response> _musicBrainzGet(Uri uri) {
    final completer = Completer<http.Response>();
    _musicBrainzQueue = _musicBrainzQueue.then((_) async {
      try {
        final elapsed = DateTime.now().difference(_lastMusicBrainzRequest);
        if (elapsed < _minimumMusicBrainzInterval) {
          await Future<void>.delayed(_minimumMusicBrainzInterval - elapsed);
        }
        _lastMusicBrainzRequest = DateTime.now();
        final response = await http.get(uri, headers: const <String, String>{
          'Accept': 'application/json',
          'User-Agent': 'MusikKu/5.0.10 (Android album artwork metadata lookup)',
        }).timeout(_requestTimeout);
        completer.complete(response);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Future<String?> _coverArtUrl(String entityType, String mbid) async {
    final uri = Uri.https('coverartarchive.org', '/$entityType/$mbid');
    final response = await http.get(uri, headers: const <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'MusikKu/5.0.10 (Android album artwork metadata lookup)',
    }).timeout(_requestTimeout);
    if (response.statusCode == 404 || response.statusCode == 204) return null;
    if (response.statusCode != 200) {
      throw StateError('Cover Art Archive returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final images = decoded is Map && decoded['images'] is List
        ? (decoded['images'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    if (images.isEmpty) return null;
    Map? image;
    for (final candidate in images) {
      final types = candidate['types'];
      if (types is List && types.any((type) => type.toString().toLowerCase() == 'front')) {
        image = candidate;
        break;
      }
    }
    image ??= images.first;
    final thumbnails = image['thumbnails'];
    var url = thumbnails is Map
        ? (thumbnails['large'] ?? thumbnails['500'] ?? thumbnails['250'])?.toString() ?? ''
        : '';
    if (url.isEmpty) url = image['image']?.toString() ?? '';
    if (url.isEmpty) return null;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasAuthority) return null;
    if (parsed.scheme == 'http') return parsed.replace(scheme: 'https').toString();
    return url;
  }

  static String _artistCredit(Object? raw) {
    if (raw is! List) return '';
    final names = <String>[];
    for (final part in raw) {
      if (part is String) {
        names.add(part);
      } else if (part is Map) {
        final artist = part['artist'];
        final name = artist is Map ? artist['name']?.toString() : part['name']?.toString();
        if (name != null && name.trim().isNotEmpty) names.add(name.trim());
        final join = part['joinphrase']?.toString() ?? '';
        if (join.isNotEmpty && names.isNotEmpty) names[names.length - 1] = '${names.last}$join';
      }
    }
    return names.join().trim();
  }

  static String _cleanArtist(String raw) {
    var artist = raw.trim();
    artist = artist.replaceFirst(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
    artist = artist.replaceFirst(RegExp(r'\s*VEVO$', caseSensitive: false), '');
    artist = artist.replaceFirst(RegExp(r'\s+official(?:\s+channel)?$', caseSensitive: false), '');
    return artist.trim();
  }

  static String _cleanTitle(String raw, String artistRaw) {
    var title = raw.trim();
    title = title.replaceAll(RegExp(r'\((?:official|lyrics?|audio|music video|visuali[sz]er|hd|4k)[^)]*\)', caseSensitive: false), ' ');
    title = title.replaceAll(RegExp(r'\[(?:official|lyrics?|audio|music video|visuali[sz]er|hd|4k)[^\]]*\]', caseSensitive: false), ' ');
    title = title.replaceAll(RegExp(r'\s+(?:official music video|official video|official audio|lyrics video|lyric video|music video|visualizer|visualiser|audio official)\s*$', caseSensitive: false), ' ');
    final artist = _cleanArtist(artistRaw).toLowerCase();
    if (artist.isNotEmpty) {
      for (final separator in <String>[' - ', ' – ', ' — ', ' | ']) {
        final prefix = '$artist$separator';
        if (title.toLowerCase().startsWith(prefix)) {
          title = title.substring(prefix.length);
          break;
        }
      }
    }
    return title.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _matchKey(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[\-–—_(){}\[\],.!?:;|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _luceneEscape(String input) {
    const reserved = '+-!(){}[]^"~*?:\\/';
    final output = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (reserved.contains(char)) output.write('\\');
      output.write(char);
    }
    return output.toString();
  }
}

class _ReleaseCandidate {
  const _ReleaseCandidate({required this.groupId, required this.releaseId, required this.score, required this.official});
  final String groupId;
  final String releaseId;
  final double score;
  final bool official;
}

class _ArtworkLookup {
  const _ArtworkLookup(this.url, {required this.cacheable});
  final String? url;
  final bool cacheable;
}
