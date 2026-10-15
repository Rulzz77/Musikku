import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/lyric.dart';
import 'disk_cache.dart';

class _LyricsQuery {
  final String title;
  final String artist;

  const _LyricsQuery({required this.title, required this.artist});
}

class LyricsService {
  static final Map<String, LyricsResult?> _cache = {};

  static const int _cacheLimit = 25;

  /// Cache di HP supaya lirik tidak diunduh ulang tiap app dibuka.
  static const DiskCache _disk = DiskCache(
    namespace: 'lyrics',
    maxEntries: 40,
    ttl: Duration(days: 14),
  );

  /// Lagu tanpa lirik dicoba lagi setelah beberapa hari.
  static const Duration _negativeTtl = Duration(days: 3);

  static Map<String, dynamic> _toJson(LyricsResult result) {
    return {
      'synced': result.synced,
      'lines': [
        for (final line in result.lines) [line.time.inMilliseconds, line.text],
      ],
    };
  }

  static LyricsResult? _fromCache(Map data) {
    final rawLines = data['lines'];

    if (rawLines is! List) {
      return null;
    }

    final lines = <LyricLine>[];

    for (final item in rawLines) {
      if (item is List && item.length == 2 && item[0] is int && item[1] is String) {
        lines.add(
          LyricLine(
            time: Duration(milliseconds: item[0] as int),
            text: item[1] as String,
          ),
        );
      }
    }

    if (lines.isEmpty) {
      return null;
    }

    return LyricsResult(lines: lines, synced: data['synced'] == true);
  }

  static void _remember(String key, LyricsResult? value) {
    _putCache(key, value);

    unawaited(
      _disk.put(
        key,
        value == null
            ? {
                'none': true,
                'until': DateTime.now().add(_negativeTtl).millisecondsSinceEpoch,
              }
            : _toJson(value),
      ),
    );
  }

  static void _putCache(String key, LyricsResult? value) {
    _cache.remove(key);
    _cache[key] = value;

    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  static const Map<String, String> _headers = {
    'User-Agent': 'MusikKu/1.0',
    'Accept': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 10);

  static Future<LyricsResult?> getLyrics({
    required String title,
    required String artist,
  }) async {
    final cacheKey = '${title.toLowerCase().trim()}|${artist.toLowerCase().trim()}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    final diskHit = await _disk.get(cacheKey);

    if (diskHit is Map) {
      if (diskHit['none'] == true) {
        final until = diskHit['until'];

        if (until is int && DateTime.now().millisecondsSinceEpoch < until) {
          _putCache(cacheKey, null);

          return null;
        }
      } else {
        final cachedResult = _fromCache(diskHit);

        if (cachedResult != null) {
          _putCache(cacheKey, cachedResult);

          return cachedResult;
        }
      }
    }

    final queries = _buildQueries(title, artist);
    var hadError = false;

    // 1. Coba pencocokan persis (judul & artis sudah dibersihkan).
    for (final query in queries) {
      try {
        final result = await _fetchExact(query);

        if (result != null) {
          _remember(cacheKey, result);
          return result;
        }
      } catch (e) {
        hadError = true;
        debugPrint('Lyrics error: $e');
      }
    }

    // 2. Fallback: pencarian bebas.
    try {
      final result = await _search(queries.first);

      if (result != null) {
        _remember(cacheKey, result);
        return result;
      }
    } catch (e) {
      hadError = true;
      debugPrint('Lyrics search error: $e');
    }

    // Error jaringan tidak disimpan di cache supaya bisa dicoba lagi.
    if (!hadError) {
      _remember(cacheKey, null);
    }

    return null;
  }

  // ==========================================================
  // REQUEST
  // ==========================================================

  static Future<LyricsResult?> _fetchExact(_LyricsQuery query) async {
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': query.title,
      'artist_name': query.artist,
    });

    final response =
        await http.get(uri, headers: _headers).timeout(_timeout);

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw Exception('Lyrics API error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map) {
      return null;
    }

    return _fromJson(decoded);
  }

  static Future<LyricsResult?> _search(_LyricsQuery query) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'q': '${query.title} ${query.artist}',
    });

    final response =
        await http.get(uri, headers: _headers).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Lyrics search error: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! List) {
      return null;
    }

    LyricsResult? plainFallback;

    for (final item in decoded.take(8)) {
      if (item is! Map) {
        continue;
      }

      final result = _fromJson(item);

      if (result == null) {
        continue;
      }

      // Lirik bertimestamp lebih diutamakan.
      if (result.synced) {
        return result;
      }

      plainFallback ??= result;
    }

    return plainFallback;
  }

  static LyricsResult? _fromJson(Map decoded) {
    final syncedLyrics = decoded['syncedLyrics'];

    if (syncedLyrics is String && syncedLyrics.trim().isNotEmpty) {
      final parsed = _parseSyncedLyrics(syncedLyrics);

      if (parsed.isNotEmpty) {
        return LyricsResult(lines: parsed, synced: true);
      }
    }

    final plainLyrics = decoded['plainLyrics'];

    if (plainLyrics is String && plainLyrics.trim().isNotEmpty) {
      final lines = plainLyrics
          .split('\n')
          .map((text) => LyricLine(time: Duration.zero, text: text.trim()))
          .where((line) => line.text.isNotEmpty)
          .toList();

      if (lines.isNotEmpty) {
        return LyricsResult(lines: lines, synced: false);
      }
    }

    return null;
  }

  // ==========================================================
  // MEMBERSIHKAN JUDUL YOUTUBE
  // ==========================================================
  //
  // Judul YouTube biasanya kotor:
  //   "Adele - Hello (Official Music Video)"
  // sedangkan LRCLIB butuh:
  //   judul = "Hello", artis = "Adele"
  //

  static List<_LyricsQuery> _buildQueries(String rawTitle, String rawArtist) {
    final channel = _cleanArtist(rawArtist);
    final title = _cleanTitle(rawTitle);

    final queries = <_LyricsQuery>[];

    final separator = RegExp(r'\s[-–—]\s');
    final match = separator.firstMatch(title);

    if (match != null) {
      final left = title.substring(0, match.start).trim();
      final right = title.substring(match.end).trim();

      if (left.isNotEmpty && right.isNotEmpty) {
        queries.add(_LyricsQuery(title: right, artist: left));
      }
    }

    queries.add(_LyricsQuery(title: title, artist: channel));

    return queries;
  }

  static String _cleanTitle(String raw) {
    var text = raw.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]|【[^】]*】'), ' ');

    text = text.split('|').first;

    text = text.replaceAll(
      RegExp(
        r'\b(official|lyrics?)\b(\s+(official|music|lyrics?|video|audio))*\s*$',
        caseSensitive: false,
      ),
      ' ',
    );

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    return text.isEmpty ? raw.trim() : text;
  }

  static String _cleanArtist(String raw) {
    var text = raw.replaceAll(
      RegExp(r'\s*-\s*Topic$', caseSensitive: false),
      '',
    );

    text = text.replaceAll(RegExp(r'VEVO$', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'\s*Official$', caseSensitive: false), '');

    return text.trim();
  }

  // ==========================================================
  // PARSE LRC
  // ==========================================================

  static List<LyricLine> _parseSyncedLyrics(String raw) {
    final result = <LyricLine>[];

    final regex = RegExp(r'^\[(\d{1,3}):(\d{2})(?:\.(\d{1,3}))?\]\s*(.*)$');

    for (final line in raw.split('\n')) {
      final match = regex.firstMatch(line.trim());

      if (match == null) {
        continue;
      }

      final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
      final fraction = match.group(3) ?? '0';

      int milliseconds;

      if (fraction.length == 1) {
        milliseconds = int.parse(fraction) * 100;
      } else if (fraction.length == 2) {
        milliseconds = int.parse(fraction) * 10;
      } else {
        milliseconds = int.tryParse(fraction) ?? 0;
      }

      final text = (match.group(4) ?? '').trim();

      if (text.isEmpty) {
        continue;
      }

      result.add(
        LyricLine(
          time: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: text,
        ),
      );
    }

    result.sort((a, b) => a.time.compareTo(b.time));

    return result;
  }
}
