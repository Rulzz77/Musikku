import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/lyric.dart';
import 'disk_cache.dart';
import 'music_title_formatter.dart';

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
    namespace: 'lyrics_v3',
    maxEntries: 40,
    ttl: Duration(days: 14),
  );

  /// Lagu tanpa lirik dicoba lagi setelah beberapa hari.
  static const Duration _negativeTtl = Duration(days: 3);

  static Map<String, dynamic> _toJson(LyricsResult result) {
    return {
      'synced': result.synced,
      'lines': [
        for (final line in result.lines)
          [
            line.time.inMilliseconds,
            line.text,
            line.endTime?.inMilliseconds,
            [
              for (final word in line.words)
                [word.text, word.start.inMilliseconds, word.end?.inMilliseconds],
            ],
          ],
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
      if (item is List && item.length >= 2 && item[0] is int && item[1] is String) {
        final words = <LyricWord>[];
        final rawWords = item.length > 3 ? item[3] : null;
        if (rawWords is List) {
          for (final rawWord in rawWords) {
            if (rawWord is! List ||
                rawWord.length < 2 ||
                rawWord[0] is! String ||
                rawWord[1] is! int) {
              continue;
            }
            words.add(
              LyricWord(
                text: rawWord[0] as String,
                start: Duration(milliseconds: rawWord[1] as int),
                end: rawWord.length > 2 && rawWord[2] is int
                    ? Duration(milliseconds: rawWord[2] as int)
                    : null,
              ),
            );
          }
        }

        lines.add(
          LyricLine(
            time: Duration(milliseconds: item[0] as int),
            text: item[1] as String,
            endTime: item.length > 2 && item[2] is int
                ? Duration(milliseconds: item[2] as int)
                : null,
            words: words,
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
    String albumName = '',
    double? durationSeconds,
  }) async {
    final validDuration = _validDuration(durationSeconds) ? durationSeconds!.round() : null;
    final cacheKey = '${title.toLowerCase().trim()}|${artist.toLowerCase().trim()}|'
        '${albumName.toLowerCase().trim()}|${validDuration ?? 'unknown'}';

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
    if (queries.isEmpty) {
      _remember(cacheKey, null);
      return null;
    }
    var hadError = false;

    // 1. Coba paling banyak dua kombinasi judul/artis yang paling terpercaya.
    // Batasi request agar lookup lirik tidak membuat UI menunggu terlalu lama.
    for (final query in queries.take(2)) {
      try {
        final result = await _fetchExact(
          query,
          albumName: albumName,
          durationSeconds: durationSeconds,
        );

        if (result != null) {
          _remember(cacheKey, result);
          return result;
        }
      } catch (e) {
        hadError = true;
        debugPrint('Lyrics error: $e');
      }
    }

    // 2. Fallback: search results are scored against both track title and
    // artist. Some lyric endpoints return a synced song for a similar title;
    // never accept it just because it appears first in the response.
    try {
      final result = await _search(queries.first, durationSeconds: durationSeconds);
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

  static Future<LyricsResult?> _fetchExact(
    _LyricsQuery query, {
    required String albumName,
    required double? durationSeconds,
  }) async {
    if (query.title.trim().isEmpty || query.artist.trim().isEmpty) return null;
    final params = <String, String>{
      'track_name': query.title,
      'artist_name': query.artist,
    };
    if (albumName.trim().isNotEmpty) params['album_name'] = albumName.trim();
    if (_validDuration(durationSeconds)) {
      params['duration'] = durationSeconds!.round().toString();
    }
    final uri = Uri.https('lrclib.net', '/api/get', params);

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

    // Some lyric services can return a nearby match for ambiguous titles.
    // Validate the metadata even for the exact endpoint before caching it.
    final returnedTitle = decoded['trackName']?.toString() ?? '';
    final returnedArtist = decoded['artistName']?.toString() ?? '';
    if (!_durationMatches(durationSeconds, decoded['duration'])) return null;
    if (_metadataMatchScore(query.title, returnedTitle) < 80) return null;
    if (query.artist.trim().isNotEmpty &&
        (returnedArtist.trim().isEmpty ||
            _metadataMatchScore(query.artist, returnedArtist) < 65)) {
      return null;
    }

    return _fromJson(decoded);
  }

  static Future<LyricsResult?> _search(
    _LyricsQuery query, {
    required double? durationSeconds,
  }) async {
    final params = <String, String>{'q': query.artist.trim().isEmpty ? query.title : '${query.title} ${query.artist}'};
    final uri = Uri.https('lrclib.net', '/api/search', params);
    final response = await http.get(uri, headers: _headers).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('Lyrics search error: ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return null;

    LyricsResult? bestResult;
    var bestScore = -1;
    for (final item in decoded.take(12)) {
      if (item is! Map) continue;
      final trackName = item['trackName']?.toString() ?? '';
      final artistName = item['artistName']?.toString() ?? '';
      final titleScore = _metadataMatchScore(query.title, trackName);
      if (titleScore < 80) continue;

      final expectedArtist = _normalizeMetadata(query.artist);
      final actualArtist = _normalizeMetadata(artistName);
      var artistScore = 0;
      if (expectedArtist.isNotEmpty) {
        artistScore = _metadataMatchScore(query.artist, artistName);
        // A title hit from a different artist can easily be a different song.
        if (actualArtist.isNotEmpty && artistScore < 65) continue;
      }

      final result = _fromJson(item);
      if (result == null) continue;
      // A search fallback must not use timestamped lyrics from a different
      // edit/live/video version. Plain text has no timeline to desync, so it
      // can still be shown when the provider has no duration for that result.
      if (result.synced && !_durationMatches(durationSeconds, item['duration'])) continue;
      final score = titleScore + artistScore + (result.synced ? 10 : 0);
      if (score > bestScore) {
        bestScore = score;
        bestResult = result;
      }
    }
    return bestResult;
  }

  static String _normalizeMetadata(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// A high-confidence textual match; exposed so ranking can be regression-tested.
  static int metadataMatchScoreForTesting(String expected, String actual) =>
      _metadataMatchScore(expected, actual);

  static int _metadataMatchScore(String expected, String actual) {
    final left = _normalizeMetadata(expected);
    final right = _normalizeMetadata(actual);
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 100;
    if (right.endsWith(' $left') || right.startsWith('$left ')) return 90;
    if (right.contains(' $left ')) return 86;

    final leftWords = left.split(' ').where((word) => word.isNotEmpty).toSet();
    final rightWords = right.split(' ').where((word) => word.isNotEmpty).toSet();
    if (leftWords.isEmpty) return 0;
    final overlap = leftWords.intersection(rightWords).length / leftWords.length;
    final extraWords = rightWords.length - leftWords.length;
    if (overlap >= 0.9 && extraWords <= 2) return 80;
    return 0;
  }

  static LyricsResult? _fromJson(Map decoded) {
    final lyricsFile = decoded['lyricsfile'];
    if (decoded['hasWordSync'] == true && lyricsFile is String && lyricsFile.trim().isNotEmpty) {
      final wordSynced = parseWordSyncedLyricsFile(lyricsFile);
      if (wordSynced.isNotEmpty) {
        return LyricsResult(lines: wordSynced, synced: true);
      }
    }

    final syncedLyrics = decoded['syncedLyrics'];

    if (syncedLyrics is String && syncedLyrics.trim().isNotEmpty) {
      final parsed = parseSyncedLyrics(syncedLyrics);

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

  static bool _validDuration(double? value) =>
      value != null && value.isFinite && value >= 1 && value <= 3600;

  static bool _durationMatches(double? requested, Object? returned) {
    if (!_validDuration(requested)) return true;
    if (returned is! num || !returned.isFinite) return false;
    // LRCLIB recommends duration matching within roughly +/-2 seconds.
    return (returned.toDouble() - requested!).abs() <= 2.5;
  }

  /// Reads the simple word-timed subset of LRCLIB's Lyricsfile YAML format.
  /// This keeps the app dependency-free and safely falls back to LRC lines
  /// when the provider returns a format we do not recognize.
  static List<LyricLine> parseWordSyncedLyricsFile(String raw) {
    final lines = <LyricLine>[];
    String? lineText;
    int? lineStart;
    int? lineEnd;
    List<LyricWord> words = <LyricWord>[];
    String? wordText;
    int? wordStart;
    int? wordEnd;
    var inLines = false;

    String unquote(String value) {
      final text = value.trim();
      if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
        return text.substring(1, text.length - 1)
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', '\\');
      }
      if (text.length >= 2 && text.startsWith("'") && text.endsWith("'")) {
        return text.substring(1, text.length - 1).replaceAll("''", "'");
      }
      return text;
    }

    void flushWord() {
      final text = wordText;
      final start = wordStart;
      if (text != null && text.isNotEmpty && start != null && start >= 0) {
        words.add(LyricWord(
          text: text,
          start: Duration(milliseconds: start),
          end: wordEnd != null && wordEnd! >= start
              ? Duration(milliseconds: wordEnd!)
              : null,
        ));
      }
      wordText = null;
      wordStart = null;
      wordEnd = null;
    }

    void flushLine() {
      flushWord();
      final text = lineText?.trim() ?? '';
      if (text.isNotEmpty && lineStart != null && lineStart! >= 0) {
        words.sort((a, b) => a.start.compareTo(b.start));
        lines.add(LyricLine(
          time: Duration(milliseconds: lineStart!),
          text: text,
          endTime: lineEnd != null && lineEnd! >= lineStart!
              ? Duration(milliseconds: lineEnd!)
              : null,
          words: List<LyricWord>.unmodifiable(words),
        ));
      }
      lineText = null;
      lineStart = null;
      lineEnd = null;
      words = <LyricWord>[];
    }

    for (final rawLine in raw.replaceAll('\r', '').split('\n')) {
      if (rawLine.trim() == 'lines:') {
        inLines = true;
        continue;
      }
      if (!inLines) continue;
      if (rawLine.trim().startsWith('plain:') ||
          (rawLine.trim().isNotEmpty && !rawLine.startsWith(' '))) {
        flushLine();
        break;
      }

      final lineMatch = RegExp(r'^  - text:\s*(.*)$').firstMatch(rawLine);
      if (lineMatch != null) {
        flushLine();
        lineText = unquote(lineMatch.group(1) ?? '');
        continue;
      }

      final wordMatch = RegExp(r'^      - text:\s*(.*)$').firstMatch(rawLine);
      if (wordMatch != null) {
        flushWord();
        wordText = unquote(wordMatch.group(1) ?? '');
        continue;
      }

      final lineStartMatch = RegExp(r'^    start_ms:\s*(-?\d+)\s*$').firstMatch(rawLine);
      if (lineStartMatch != null) {
        lineStart = int.tryParse(lineStartMatch.group(1)!);
        continue;
      }
      final lineEndMatch = RegExp(r'^    end_ms:\s*(-?\d+)\s*$').firstMatch(rawLine);
      if (lineEndMatch != null) {
        lineEnd = int.tryParse(lineEndMatch.group(1)!);
        continue;
      }
      final wordStartMatch = RegExp(r'^        start_ms:\s*(-?\d+)\s*$').firstMatch(rawLine);
      if (wordStartMatch != null) {
        wordStart = int.tryParse(wordStartMatch.group(1)!);
        continue;
      }
      final wordEndMatch = RegExp(r'^        end_ms:\s*(-?\d+)\s*$').firstMatch(rawLine);
      if (wordEndMatch != null) {
        wordEnd = int.tryParse(wordEndMatch.group(1)!);
      }
    }
    if (inLines && lineText != null) flushLine();
    lines.sort((a, b) => a.time.compareTo(b.time));
    if (!lines.any((line) => line.words.isNotEmpty)) {
      return const <LyricLine>[];
    }
    return lines;
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
    final coverArtist = _coverArtistCue(rawTitle);
    var source = rawTitle;

    // Remove only bracket groups that identify this upload as a cover. Other
    // meaningful title info, such as a featured artist, remains available.
    source = source.replaceAll(
      RegExp(r'[\(\[\{【][^\)\]\}】]*\bcover\b[^\)\]\}】]*[\)\]\}】]', caseSensitive: false),
      ' ',
    );
    source = source.replaceAll(
      RegExp(r'\b(?:cover(?:ed)?(?:\s+(?:song|version|lagu))?|versi\s+cover)\s+(?:by|oleh|dari|performed\s+by|sung\s+by|with)\s+[^|;–—-]+$', caseSensitive: false),
      ' ',
    );
    source = source.replaceAll(
      RegExp(
        r'\s*[-–—|:]\s*(?:(?:acoustic|piano|guitar|gitar|live)\s+)?'
        r'cover(?:\s+(?:version|song|lagu))?\s*$',
        caseSensitive: false,
      ),
      ' ',
    );
    source = source.replaceAll(
      RegExp(r'^\s*cover\s+by\s+.+?\s*[-–—]\s*', caseSensitive: false),
      '',
    );
    var cleaned = _cleanTitle(source);
    cleaned = cleaned
        .replaceAll(RegExp(r'\s*[-–—|:]\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final queries = <_LyricsQuery>[];
    final separator = RegExp(r'\s[-–—]\s').firstMatch(cleaned);
    if (separator != null) {
      final left = cleaned.substring(0, separator.start).trim();
      final right = cleaned.substring(separator.end).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        final artistFromTitle = coverArtist ?? left;
        queries.add(_LyricsQuery(title: right, artist: artistFromTitle));
        if (channel.isNotEmpty && channel.toLowerCase() != artistFromTitle.toLowerCase()) {
          queries.add(_LyricsQuery(title: right, artist: channel));
        }
        queries.add(_LyricsQuery(title: right, artist: ''));
      }
    }

    if (cleaned.isNotEmpty) {
      // A title such as "Kangen (Dewa 19 Cover)" contains the original
      // performer even when it has no "Artist - Title" separator. Try that
      // attribution before the channel name, which is usually the cover singer.
      if (separator == null && coverArtist != null && coverArtist.trim().isNotEmpty) {
        queries.add(_LyricsQuery(title: cleaned, artist: coverArtist.trim()));
      }
      if (channel.isNotEmpty) queries.add(_LyricsQuery(title: cleaned, artist: channel));
      queries.add(_LyricsQuery(title: cleaned, artist: ''));
    }

    final seen = <String>{};
    return queries.where((query) {
      final key = '${query.title.toLowerCase().trim()}|${query.artist.toLowerCase().trim()}';
      return query.title.trim().isNotEmpty && seen.add(key);
    }).take(4).toList(growable: false);
  }

  static String? _coverArtistCue(String rawTitle) {
    final bracketed = RegExp(r'[\(\[\{【]([^\)\]\}】]*\bcover\b[^\)\]\}】]*)[\)\]\}】]', caseSensitive: false);
    for (final match in bracketed.allMatches(rawTitle)) {
      final cue = (match.group(1) ?? '').trim();
      final beforeCover = RegExp(r'^(.+?)\s+(?:acoustic\s+|piano\s+|guitar\s+|gitar\s+)?cover(?:\s+(?:song|version))?$', caseSensitive: false).firstMatch(cue);
      final artist = beforeCover?.group(1)?.trim() ?? '';
      if (artist.isEmpty) continue;
      if (RegExp(r'^(?:acoustic|piano|guitar|gitar|live|female|male|instrumental|original|music)$', caseSensitive: false).hasMatch(artist)) continue;
      return artist;
    }
    return null;
  }

  static String _cleanTitle(String raw) => MusicTitleFormatter.clean(raw);

  static String _cleanArtist(String raw) {
    var text = raw.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'VEVO$', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'\s*Official$', caseSensitive: false), '');
    return text.trim();
  }

  /// Parses timestamped lyric lines, including LRC lines with multiple time tags.
  /// Public for deterministic regression tests and offline validation.
  static List<LyricLine> parseSyncedLyrics(String raw) {
    final result = <LyricLine>[];
    final timestampRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final source = raw.replaceAll('\uFEFF', '');
    final offsetMatch = RegExp(r'^\[offset:([+-]?\d+)\]', caseSensitive: false, multiLine: true)
        .firstMatch(source);
    final offsetMs = int.tryParse(offsetMatch?.group(1) ?? '0') ?? 0;

    for (final sourceLine in source.split('\n')) {
      final line = sourceLine.trim();
      if (line.isEmpty ||
          RegExp(r'^\[(?:ar|al|ti|by|re|ve|offset):', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      final matches = timestampRegex.allMatches(line).toList(growable: false);
      if (matches.isEmpty) continue;
      // A line can carry multiple timestamps, e.g. [00:01.20][00:03.40]Words.
      // All timestamps belong to the text after the final timestamp.
      final text = line.substring(matches.last.end).trim();
      if (text.isEmpty) continue;

      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '0') ?? 0;
        final fraction = match.group(3) ?? '0';
        final fractionalMs = fraction.length == 1
            ? int.parse(fraction) * 100
            : fraction.length == 2
                ? int.parse(fraction) * 10
                : (int.tryParse(fraction) ?? 0);
        final timestampMs = (minutes * 60 + seconds) * 1000 + fractionalMs + offsetMs;
        result.add(LyricLine(
          time: Duration(milliseconds: timestampMs < 0 ? 0 : timestampMs),
          text: text,
        ));
      }
    }

    result.sort((a, b) => a.time.compareTo(b.time));
    final deduplicated = <LyricLine>[];
    for (final line in result) {
      if (deduplicated.isEmpty ||
          deduplicated.last.time != line.time ||
          deduplicated.last.text != line.text) {
        deduplicated.add(line);
      }
    }
    return deduplicated;
  }

}
