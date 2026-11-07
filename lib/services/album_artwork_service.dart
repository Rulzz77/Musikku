import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_search_result.dart';
import 'youtube_music_metadata_parser.dart';

/// Resolves square album artwork from MusicBrainz/Cover Art Archive.
///
/// Resolves verified front covers for every visible track tile and player.
/// Only approved front images from MusicBrainz/Cover Art Archive are accepted;
/// exact album metadata is preferred when available. The selected track's own
/// high-resolution YouTube thumbnail is the fallback, never a random search image.
/// Positive and negative results are cached to avoid repeat network lookups.
class AlbumArtworkService {
  AlbumArtworkService._();

  static const String _cachePrefix = 'musikku_album_artwork_v5_';
  static const String _noArtwork = '__no_album_artwork__';
  static const Duration _positiveCacheTtl = Duration(days: 180);
  static const Duration _negativeCacheTtl = Duration(days: 5);
  static const Duration _requestTimeout = Duration(seconds: 9);
  static const Duration _minimumMusicBrainzInterval = Duration(milliseconds: 1100);

  static final Map<String, Future<String?>> _pending = <String, Future<String?>>{};
  static final Map<String, String?> _memoryCache = <String, String?>{};
  static Future<void> _musicBrainzQueue = Future<void>.value();
  static DateTime _lastMusicBrainzRequest = DateTime.fromMillisecondsSinceEpoch(0);

  /// Returns an album-cover URL, falling back to the YouTube thumbnail.
  /// Local files are handled by [UnifiedArtwork] and should not call this.
  static Future<String> resolveCoverUrl(YoutubeSearchResult track) async {
    final fallback = track.coverUrl;
    if (track.isLocal) return fallback;

    final releaseMetadata = YoutubeMusicMetadataParser.parse(
      title: track.title,
      description: track.description,
    );
    final artistSource = track.artistName.trim().isNotEmpty
        ? track.artistName
        : releaseMetadata.artistName.trim().isNotEmpty
            ? releaseMetadata.artistName
            : track.channelTitle;
    final title = _cleanTitle(track.title, artistSource);
    final rawAlbum = track.album.trim().isNotEmpty
        ? track.album
        : releaseMetadata.album;
    final album = _cleanAlbumTitle(_cleanTitle(rawAlbum, artistSource));
    final artist = _cleanArtist(artistSource);
    if (title.isEmpty || artist.isEmpty) return fallback;

    final cacheKey = _cacheKey(title, artist, album);
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey] ?? fallback;
    }
    try {
      final cached = await _readCache(cacheKey);
      if (cached != null) {
        if (cached.isNotEmpty) _memoryCache[cacheKey] = cached;
        return cached.isEmpty ? fallback : cached;
      }
    } catch (_) {
      // Storage being unavailable must not block normal playback.
    }

    final future = _pending.putIfAbsent(
      cacheKey,
      () => _lookupAndCache(cacheKey, title, artist, album),
    );
    try {
      final resolved = await future;
      if (resolved != null) _memoryCache[cacheKey] = resolved;
      return resolved ?? fallback;
    } catch (_) {
      return fallback;
    } finally {
      if (identical(_pending[cacheKey], future)) {
        _pending.remove(cacheKey);
      }
    }
  }

  static String _cacheKey(String title, String artist, String album) {
    final normalized = '${_matchKey(artist)}|${_matchKey(title)}|${_matchKey(album)}';
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

  static Future<String?> _lookupAndCache(
    String key,
    String title,
    String artist,
    String album,
  ) async {
    final lookup = await _findAlbumArtwork(title, artist, album);
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

  static Future<_ArtworkLookup> _findAlbumArtwork(
    String title,
    String artist,
    String album,
  ) async {
    final requestedArtist = _matchKey(artist);

    // Spotify/YouTube Music may provide an explicit album title. Search that
    // release group first so we use the actual album front cover rather than
    // an unrelated same-title single or another artist's artwork.
    if (album.isNotEmpty) {
      final albumQuery = 'release:"${_luceneEscape(album)}" AND artist:"${_luceneEscape(artist)}"';
      final albumUri = Uri.https('musicbrainz.org', '/ws/2/release-group/', <String, String>{
        'query': albumQuery,
        'fmt': 'json',
        'limit': '10',
      });
      final albumResponse = await _musicBrainzGet(albumUri);
      if (albumResponse.statusCode == 200) {
        final albumJson = jsonDecode(albumResponse.body);
        final groups = albumJson is Map && albumJson['release-groups'] is List
            ? (albumJson['release-groups'] as List).whereType<Map>().toList(growable: false)
            : const <Map>[];
        final matchingGroups = <_ReleaseCandidate>[];
        for (final group in groups) {
          final groupTitle = _matchKey(group['title']?.toString() ?? '');
          final groupCredit = _matchKey(_artistCredit(group['artist-credit']));
          final score = group['score'] is num
              ? (group['score'] as num).toDouble()
              : 0.0;
          if (!_isTitleCompatible(_matchKey(album), groupTitle) ||
              groupCredit.isEmpty ||
              !_artistCreditMatches(groupCredit, requestedArtist) ||
              score < 70) {
            continue;
          }
          final groupId = group['id']?.toString() ?? '';
          if (groupId.isNotEmpty) {
            matchingGroups.add(_ReleaseCandidate(
              groupId: groupId,
              releaseId: '',
              score: score,
              official: true,
            ));
          }
        }
        matchingGroups.sort((a, b) => b.score.compareTo(a.score));
        for (final candidate in matchingGroups.take(5)) {
          try {
            final url = await _coverArtUrl('release-group', candidate.groupId);
            if (url != null) return _ArtworkLookup(url, cacheable: true);
          } catch (_) {
            // A single unavailable archive image must not block other verified
            // releases for the same recording.
          }
        }
      }
      // A missing or temporarily unavailable album result should not block the
      // exact recording lookup below.
    }

    final query = 'recording:"${_luceneEscape(title)}" AND artist:"${_luceneEscape(artist)}"';
    final searchUri = Uri.https('musicbrainz.org', '/ws/2/recording/', <String, String>{
      'query': query,
      'fmt': 'json',
      'limit': '10',
    });

    final response = await _musicBrainzGet(searchUri);
    if (response.statusCode != 200) {
      return const _ArtworkLookup(null, cacheable: false);
    }

    final decoded = jsonDecode(response.body);
    final rows = decoded is Map && decoded['recordings'] is List
        ? (decoded['recordings'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    final requestedTitle = _matchKey(title);
    final releaseCandidates = <_ReleaseCandidate>[];
    String bestRecordingId = '';
    double bestRecordingScore = -1;

    for (final row in rows) {
      final rowTitle = _matchKey(row['title']?.toString() ?? '');
      final score = row['score'] is num
          ? (row['score'] as num).toDouble()
          : double.tryParse(row['score']?.toString() ?? '') ?? 0;
      final titleCompatible = _isTitleCompatible(requestedTitle, rowTitle);
      if (!titleCompatible || score < 70) continue;

      final creditedArtist = _artistCredit(row['artist-credit']);
      final normalizedCredit = _matchKey(creditedArtist);
      // Never accept an artwork result with a missing/unknown performer credit;
      // same-title songs by different artists are common.
      if (normalizedCredit.isEmpty ||
          !_artistCreditMatches(normalizedCredit, requestedArtist)) {
        continue;
      }
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
      }
    }

    if (releaseCandidates.isEmpty) {
      // One carefully scoped fallback search handles tracks without release
      // links on the recording entry. It is still rate-limited below.
      final fallbackQuery = 'release:"${_luceneEscape(title)}" AND artist:"${_luceneEscape(artist)}"';
      final fallbackUri = Uri.https('musicbrainz.org', '/ws/2/release-group/', <String, String>{
        'query': fallbackQuery,
        'fmt': 'json',
        'limit': '8',
      });
      final fallbackResponse = await _musicBrainzGet(fallbackUri);
      if (fallbackResponse.statusCode != 200) {
        return const _ArtworkLookup(null, cacheable: false);
      }
      final fallbackJson = jsonDecode(fallbackResponse.body);
      final groups = fallbackJson is Map && fallbackJson['release-groups'] is List
          ? (fallbackJson['release-groups'] as List).whereType<Map>().toList(growable: false)
          : const <Map>[];
      for (final group in groups) {
        final groupTitle = _matchKey(group['title']?.toString() ?? '');
        final groupCredit = _matchKey(_artistCredit(group['artist-credit']));
        final titleMatches = groupTitle.isNotEmpty &&
            (groupTitle == requestedTitle ||
                (requestedTitle.length > 3 && groupTitle.contains(requestedTitle)));
        if (!titleMatches ||
            groupCredit.isEmpty ||
            !_artistCreditMatches(groupCredit, requestedArtist)) {
          continue;
        }
        final id = group['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          releaseCandidates.add(_ReleaseCandidate(
            groupId: id,
            releaseId: '',
            score: 70,
            official: true,
          ));
        }
      }
    }

    if (releaseCandidates.isEmpty) return const _ArtworkLookup(null, cacheable: true);

    final visited = <String>{};
    for (final candidate in releaseCandidates.take(6)) {
      if (candidate.groupId.isNotEmpty && visited.add('g:${candidate.groupId}')) {
        try {
          final url = await _coverArtUrl('release-group', candidate.groupId);
          if (url != null) return _ArtworkLookup(url, cacheable: true);
        } catch (_) {
          // Try another exact release candidate before falling back.
        }
      }
      if (candidate.releaseId.isNotEmpty && visited.add('r:${candidate.releaseId}')) {
        try {
          final url = await _coverArtUrl('release', candidate.releaseId);
          if (url != null) return _ArtworkLookup(url, cacheable: true);
        } catch (_) {
          // Try another exact release candidate before falling back.
        }
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
          'User-Agent': 'MusikKu/5.5.6+49 (https://github.com/Rulzz77/flutter_application_5)',
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
      'User-Agent': 'MusikKu/5.5.6+49 (https://github.com/Rulzz77/flutter_application_5)',
    }).timeout(_requestTimeout);
    if (response.statusCode == 404 || response.statusCode == 204) return null;
    if (response.statusCode != 200) {
      throw StateError('Cover Art Archive returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final images = decoded is Map && decoded['images'] is List
        ? (decoded['images'] as List).whereType<Map>().toList(growable: false)
        : const <Map>[];
    return selectApprovedFrontImageUrl(images);
  }

  /// Pure selector shared with regression tests. It accepts only approved
  /// front-cover images and chooses the largest available CAA thumbnail.
  static String? selectApprovedFrontImageUrl(Iterable<Map> images) {
    final frontImages = <Map>[];
    for (final candidate in images) {
      if (candidate['approved'] != true) continue;
      final types = candidate['types'];
      final isFront = candidate['front'] == true ||
          (types is List &&
              types.any((type) => type.toString().toLowerCase() == 'front'));
      if (isFront) frontImages.add(candidate);
    }
    // A back cover, booklet scan, or unapproved contribution is not a suitable
    // album thumbnail. Prefer a verified front image with the largest ready
    // thumbnail; do not guess from unrelated image search results.
    frontImages.sort(
      (a, b) => _frontImageQuality(b).compareTo(_frontImageQuality(a)),
    );
    if (frontImages.isEmpty) return null;
    final image = frontImages.first;
    final thumbnails = image['thumbnails'];
    var url = thumbnails is Map
        ? (thumbnails['1200'] ?? thumbnails['500'] ?? thumbnails['250'])
                ?.toString() ??
            ''
        : '';
    if (url.isEmpty) url = image['image']?.toString() ?? '';
    if (url.isEmpty) return null;
    final parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasAuthority) return null;
    if (parsed.scheme == 'http') {
      return parsed.replace(scheme: 'https').toString();
    }
    if (parsed.scheme != 'https') return null;
    return url;
  }

  static int _frontImageQuality(Map image) {
    final thumbnails = image['thumbnails'];
    if (thumbnails is! Map) return image['image'] is String ? 1 : 0;
    if (thumbnails['1200'] is String &&
        (thumbnails['1200'] as String).isNotEmpty) {
      return 3;
    }
    if (thumbnails['500'] is String &&
        (thumbnails['500'] as String).isNotEmpty) {
      return 2;
    }
    if (thumbnails['250'] is String &&
        (thumbnails['250'] as String).isNotEmpty) {
      return 1;
    }
    return image['image'] is String ? 1 : 0;
  }

  static bool _isTitleCompatible(String expected, String candidate) {
    if (expected.isEmpty || candidate.isEmpty) return false;
    if (expected == candidate) return true;
    final expectedTokens = expected.split(' ').where((token) => token.length > 1).toSet();
    final candidateTokens = candidate.split(' ').where((token) => token.length > 1).toSet();
    if (expectedTokens.isEmpty || candidateTokens.isEmpty) return false;
    final coverage = expectedTokens.intersection(candidateTokens).length /
        expectedTokens.length;
    return coverage >= 0.92;
  }

  static bool _containsPhrase(String text, String phrase) {
    if (text.isEmpty || phrase.isEmpty) return false;
    return ' $text '.contains(' $phrase ');
  }

  static bool _artistCreditMatches(String normalizedCredit, String requested) {
    if (_containsPhrase(normalizedCredit, requested)) return true;
    final tokens = requested.split(' ');
    final significant = tokens
        .where((token) => token.length > 1)
        .toList(growable: false);
    final oneLetterPrefix = tokens.length == 2 &&
        tokens.first.length == 1 &&
        significant.length == 1 &&
        significant.single.length >= 4;
    if (significant.length < 2 && !oneLetterPrefix) return false;
    return _containsPhrase(normalizedCredit, significant.join(' '));
  }

  static String _artistCredit(Object? raw) {
    if (raw is String) return raw.trim();
    if (raw is Map) {
      final name = raw['name']?.toString() ?? '';
      return name.trim();
    }
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

  static String _cleanAlbumTitle(String raw) {
    return raw
        .replaceFirst(
          RegExp(
            r'\s*[\(\[]\s*(?:single|album|ep|deluxe(?:\s+edition)?|expanded\s+edition|remaster(?:ed)?)\s*[\)\]]\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(r'\s+-\s*(?:single|album|ep)\s*$', caseSensitive: false),
          '',
        )
        .trim();
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
    title = title.replaceFirst(
      RegExp(r'\s+[-–—]\s*from\s+.+$', caseSensitive: false),
      '',
    );
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
