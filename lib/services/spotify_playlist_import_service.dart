import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// One track entry exposed by Spotify's public playlist embed page.
/// This intentionally contains metadata only; it never resolves Spotify audio.
class SpotifyPlaylistTrack {
  const SpotifyPlaylistTrack({
    required this.title,
    required this.artists,
    this.spotifyTrackId = '',
    this.durationMs,
  });

  final String title;
  final List<String> artists;
  final String spotifyTrackId;
  final int? durationMs;

  String get primaryArtist => artists.isEmpty ? '' : artists.first;
}

class SpotifyPlaylistSnapshot {
  const SpotifyPlaylistSnapshot({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.tracks,
    this.description = '',
    this.totalTrackCount,
    this.mayBePartial = false,
  });

  final String id;
  final String title;
  final String sourceUrl;
  final String description;
  final List<SpotifyPlaylistTrack> tracks;
  /// Total count when Spotify includes it in the public embed payload.
  /// This is metadata only; it does not grant access to missing pages.
  final int? totalTrackCount;

  /// Public embed pages may expose only the first page of a large playlist.
  /// This is a warning state, not a promise that a continuation page exists.
  final bool mayBePartial;

  int get knownMissingTrackCount {
    final total = totalTrackCount;
    if (total == null || total <= tracks.length) return 0;
    return total - tracks.length;
  }
}

class SpotifyPlaylistImportException implements Exception {
  const SpotifyPlaylistImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Imports metadata from Spotify's publicly embeddable playlist HTML.
///
/// No Spotify Web API, developer key, OAuth, Spotify login, anonymous token, or
/// private endpoint is used. The parser keeps every track row present in the
/// returned HTML, but public embeds may omit later pages of large playlists.
class SpotifyPlaylistImportService {
  SpotifyPlaylistImportService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _requestTimeout = Duration(seconds: 18);
  static const int _maximumHtmlBytes = 8 * 1024 * 1024;

  Future<SpotifyPlaylistSnapshot> fetchPublicPlaylist(String input) async {
    final playlistId = await _resolvePlaylistId(input);
    final embedUri = Uri.https(
      'open.spotify.com',
      '/embed/playlist/$playlistId',
    );

    late http.Response response;
    try {
      response = await _client.get(
        embedUri,
        headers: const <String, String>{
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.9,id;q=0.8',
          'Cache-Control': 'no-cache',
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        },
      ).timeout(_requestTimeout);
    } catch (error) {
      throw SpotifyPlaylistImportException(
        'Tidak bisa membuka halaman embed Spotify. Periksa koneksi lalu coba lagi. ($error)',
      );
    }

    if (response.statusCode == 404 || response.statusCode == 410) {
      throw const SpotifyPlaylistImportException(
        'Playlist tidak ditemukan atau sudah tidak tersedia secara publik.',
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SpotifyPlaylistImportException(
        'Spotify tidak mengizinkan halaman playlist ini dibaca. Pastikan playlist bisa dibuka dan di-embed secara publik.',
      );
    }
    if (response.statusCode == 429) {
      throw const SpotifyPlaylistImportException(
        'Spotify sedang membatasi permintaan. Coba impor lagi beberapa saat nanti.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SpotifyPlaylistImportException(
        'Halaman Spotify gagal dibaca (HTTP ${response.statusCode}).',
      );
    }
    if (response.bodyBytes.length > _maximumHtmlBytes) {
      throw const SpotifyPlaylistImportException(
        'Halaman playlist terlalu besar untuk diproses dengan aman.',
      );
    }

    return parseEmbedHtml(
      response.body,
      playlistId: playlistId,
      sourceUrl: 'https://open.spotify.com/playlist/$playlistId',
    );
  }

  Future<String> _resolvePlaylistId(String input) async {
    final value = input.trim();
    if (value.isEmpty) {
      throw const SpotifyPlaylistImportException('Tempel link playlist Spotify dulu.');
    }

    final spotifyUri = RegExp(
      r'^spotify:playlist:([A-Za-z0-9]+)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (spotifyUri != null) {
      final id = spotifyUri.group(1)!;
      if (RegExp(r'^[A-Za-z0-9]{10,64}$').hasMatch(id)) return id;
      throw const SpotifyPlaylistImportException(
        'ID playlist Spotify pada URI tidak valid.',
      );
    }

    final normalizedLink = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(normalizedLink);
    if (uri == null || !uri.hasScheme || !{'http', 'https'}.contains(uri.scheme)) {
      throw const SpotifyPlaylistImportException(
        'Link tidak valid. Gunakan link playlist Spotify, bukan link lagu atau album.',
      );
    }

    final host = uri.host.toLowerCase();
    if (host != 'open.spotify.com' &&
        host != 'www.open.spotify.com' &&
        host != 'spotify.link') {
      throw const SpotifyPlaylistImportException(
        'Link harus berasal dari open.spotify.com atau spotify.link.',
      );
    }

    var resolvedUri = uri;
    if (host == 'spotify.link') {
      try {
        // Resolve redirects manually so the final destination is explicit and
        // can be checked before any playlist URL is accepted. Some HTTP clients
        // keep response.request.url set to the original short URL even after
        // following redirects automatically.
        var current = uri;
        var reachedSpotify = false;
        for (var redirectCount = 0; redirectCount < 6; redirectCount++) {
          final request = http.Request('GET', current)
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers.addAll(const <String, String>{
              'User-Agent':
                  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36',
              'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
            });
          final streamed = await _client.send(request).timeout(_requestTimeout);
          final status = streamed.statusCode;
          final location = streamed.headers['location'];
          await streamed.stream.drain<void>();

          if (status >= 300 && status < 400 && location != null) {
            final next = current.resolve(location);
            final nextHost = next.host.toLowerCase();
            if (nextHost != 'spotify.link' &&
                nextHost != 'open.spotify.com' &&
                nextHost != 'www.open.spotify.com') {
              throw const SpotifyPlaylistImportException(
                'Link pendek tidak mengarah ke halaman playlist Spotify.',
              );
            }
            current = next;
            if (nextHost == 'open.spotify.com' ||
                nextHost == 'www.open.spotify.com') {
              reachedSpotify = true;
              break;
            }
            continue;
          }

          throw const SpotifyPlaylistImportException(
            'Spotify tidak memberikan pengalihan playlist yang valid dari link pendek.',
          );
        }

        if (!reachedSpotify) {
          throw const SpotifyPlaylistImportException(
            'Pengalihan link pendek Spotify terlalu panjang atau tidak lengkap.',
          );
        }
        resolvedUri = current;
      } on SpotifyPlaylistImportException {
        rethrow;
      } catch (error) {
        throw SpotifyPlaylistImportException(
          'Link pendek Spotify tidak bisa dibuka. Coba salin link playlist lengkap. ($error)',
        );
      }
    }

    final segments = resolvedUri.pathSegments;
    final playlistIndex = segments.indexOf('playlist');
    if (playlistIndex < 0 || playlistIndex + 1 >= segments.length) {
      throw const SpotifyPlaylistImportException(
        'Link ini bukan playlist Spotify. Tempel link yang bentuknya /playlist/....',
      );
    }

    final id = segments[playlistIndex + 1].trim();
    if (!RegExp(r'^[A-Za-z0-9]{10,64}$').hasMatch(id)) {
      throw const SpotifyPlaylistImportException(
        'ID playlist Spotify pada link tidak valid.',
      );
    }
    return id;
  }

  /// Parses the JSON data embedded in a public Spotify playlist HTML page.
  /// Exposed as a pure method so parser behavior can be regression-tested.
  static SpotifyPlaylistSnapshot parseEmbedHtml(
    String html, {
    required String playlistId,
    required String sourceUrl,
  }) {
    final document = html_parser.parse(html);
    final titleFromMeta =
        document.querySelector('meta[property="og:title"]')?.attributes['content'] ??
            document.querySelector('meta[name="twitter:title"]')?.attributes['content'] ??
            '';
    final description =
        document.querySelector('meta[property="og:description"]')?.attributes['content'] ??
            '';

    var bestTracks = <SpotifyPlaylistTrack>[];
    var titleFromJson = '';
    int? totalTrackCount;

    for (final script in document.querySelectorAll('script')) {
      final source = script.text.trim();
      if (source.isEmpty || source.length > _maximumHtmlBytes) continue;
      final decoded = _decodeJsonScript(source);
      if (decoded == null) continue;

      final tracks = _extractTracks(decoded);
      if (tracks.length > bestTracks.length) {
        bestTracks = tracks;
      }
      totalTrackCount ??= _findPlaylistTrackCount(decoded);
      if (titleFromJson.isEmpty) {
        titleFromJson = _findPlaylistTitle(decoded);
      }
    }

    // Some Spotify embed builds serialize their page payload in a script
    // attribute or a non-standard script block. Try a conservative raw-page
    // JSON extraction before reporting that the playlist cannot be imported.
    if (bestTracks.isEmpty) {
      final rawPayload = RegExp(
        r'''<script[^>]*id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)</script>''',
        caseSensitive: false,
      ).firstMatch(html)?.group(1);
      if (rawPayload != null) {
        final decoded = _decodeJsonScript(rawPayload.trim());
        if (decoded != null) {
          bestTracks = _extractTracks(decoded);
          totalTrackCount ??= _findPlaylistTrackCount(decoded);
          if (titleFromJson.isEmpty) titleFromJson = _findPlaylistTitle(decoded);
        }
      }
    }

    final title = _cleanPlaylistTitle(
      titleFromJson.isNotEmpty ? titleFromJson : titleFromMeta,
    );
    if (bestTracks.isEmpty) {
      throw const SpotifyPlaylistImportException(
        'Spotify tidak menampilkan daftar lagu pada halaman embed ini. Playlist mungkin privat, dibatasi, atau format halaman Spotify berubah. MusikKu tidak akan membuat playlist kosong.',
      );
    }

    return SpotifyPlaylistSnapshot(
      id: playlistId,
      title: title.isEmpty ? 'Playlist Spotify' : title,
      sourceUrl: sourceUrl,
      description: description,
      tracks: List<SpotifyPlaylistTrack>.unmodifiable(bestTracks),
      totalTrackCount: totalTrackCount,
      // Some public embed variants expose only a finite first section. If the
      // payload reports a total, compare it with the parsed rows. Otherwise
      // warn conservatively at the observed embed page size. Never fabricate
      // tracks or call undocumented/private pagination endpoints.
      mayBePartial: totalTrackCount != null
          ? totalTrackCount > bestTracks.length
          : bestTracks.length >= 50,
    );
  }

  /// Reads a playlist's advertised item count when the public embed provides it.
  /// Spotify has used several field names across embed payload versions. This
  /// deliberately ignores generic counts outside playlist/track-list objects.
  static int? _findPlaylistTrackCount(Object? node) {
    if (node is List) {
      for (final child in node) {
        final count = _findPlaylistTrackCount(child);
        if (count != null) return count;
      }
      return null;
    }
    if (node is! Map) return null;

    final map = Map<String, dynamic>.from(node);
    final type = _firstString(map, const ['type', 'entityType', 'entity_type'])
        .toLowerCase();
    final looksLikePlaylist = type == 'playlist' ||
        map.containsKey('trackList') ||
        map.containsKey('tracks');
    if (looksLikePlaylist) {
      for (final key in const [
        'totalTrackCount',
        'total_track_count',
        'trackCount',
        'track_count',
        'totalTracks',
        'total_tracks',
        'totalCount',
      ]) {
        final value = map[key];
        if (value is num && value >= 0) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null && parsed >= 0) return parsed;
        }
      }
      final tracks = map['tracks'];
      if (tracks is Map) {
        final trackMap = Map<String, dynamic>.from(tracks);
        for (final key in const ['total', 'totalCount', 'total_count']) {
          final value = trackMap[key];
          if (value is num && value >= 0) return value.toInt();
          if (value is String) {
            final parsed = int.tryParse(value.trim());
            if (parsed != null && parsed >= 0) return parsed;
          }
        }
      }
      final trackList = map['trackList'];
      if (trackList is Map) {
        final listMap = Map<String, dynamic>.from(trackList);
        for (final key in const ['total', 'totalCount', 'total_count']) {
          final value = listMap[key];
          if (value is num && value >= 0) return value.toInt();
          if (value is String) {
            final parsed = int.tryParse(value.trim());
            if (parsed != null && parsed >= 0) return parsed;
          }
        }
      }
    }

    for (final value in map.values) {
      final count = _findPlaylistTrackCount(value);
      if (count != null) return count;
    }
    return null;
  }

  static Object? _decodeJsonScript(String source) {
    try {
      return jsonDecode(source);
    } catch (_) {
      // Next.js sometimes wraps JSON with an assignment. Only decode the JSON
      // object itself; do not execute any script from the remote page.
      final start = source.indexOf('{');
      final end = source.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      try {
        return jsonDecode(source.substring(start, end + 1));
      } catch (_) {
        return null;
      }
    }
  }

  static List<SpotifyPlaylistTrack> _extractTracks(Object? root) {
    List<SpotifyPlaylistTrack> best = <SpotifyPlaylistTrack>[];

    SpotifyPlaylistTrack? extractItem(Object? node, {String parentKey = ''}) {
      if (node is! Map) return null;
      final map = Map<String, dynamic>.from(node);
      final direct = _trackFromMap(map, parentKey: parentKey);
      if (direct != null) return direct;
      for (final key in const <String>['track', 'item', 'data', 'trackMetadata']) {
        final nested = map[key];
        if (nested is Map) {
          final found = extractItem(nested, parentKey: key);
          if (found != null) return found;
        }
      }
      return null;
    }

    void visit(Object? node) {
      if (node is List) {
        final candidate = <SpotifyPlaylistTrack>[];
        for (final item in node) {
          final track = extractItem(item);
          if (track != null) candidate.add(track);
        }
        if (candidate.length > best.length) best = candidate;
        for (final child in node) {
          visit(child);
        }
        return;
      }
      if (node is Map) {
        for (final value in node.values) {
          visit(value);
        }
      }
    }

    visit(root);
    return best;
  }

  static SpotifyPlaylistTrack? _trackFromMap(
    Map<String, dynamic> map, {
    required String parentKey,
  }) {
    final name = _firstString(map, const ['name', 'title']);
    // Spotify embed variants do not always populate the same field. An empty
    // `artists: []` must not mask a valid `subtitle` credit.
    var artists = _readArtists(map['artists']);
    if (artists.isEmpty) artists = _readArtists(map['artist']);
    if (artists.isEmpty) artists = _readArtists(map['subtitle']);
    final rawUri = _firstString(map, const ['uri', 'trackUri', 'track_uri']);
    final type = _firstString(map, const ['type']).toLowerCase();
    final entityType = _firstString(map, const ['entityType', 'entity_type']).toLowerCase();
    final hasTrackIdentity = rawUri.startsWith('spotify:track:') ||
        type == 'track' ||
        entityType == 'track' ||
        parentKey.toLowerCase() == 'track';
    final hasTrackShape = map.containsKey('duration_ms') ||
        map.containsKey('durationMs') ||
        map.containsKey('duration') ||
        map.containsKey('album');

    if (name.isEmpty || artists.isEmpty || (!hasTrackIdentity && !hasTrackShape)) {
      return null;
    }
    if (rawUri.startsWith('spotify:episode:') ||
        type == 'episode' ||
        entityType == 'episode') {
      return null;
    }

    final id = rawUri.startsWith('spotify:track:')
        ? rawUri.substring('spotify:track:'.length)
        : _firstString(map, const ['id']);
    return SpotifyPlaylistTrack(
      title: name,
      artists: List<String>.unmodifiable(artists),
      spotifyTrackId: id,
      durationMs: _readDurationMs(map),
    );
  }

  static List<String> _readArtists(dynamic raw) {
    final names = <String>[];

    void addCredit(String value) {
      final cleaned = value.trim();
      if (cleaned.isEmpty) return;
      for (final artist in _splitArtistSubtitle(cleaned)) {
        if (artist.isNotEmpty && !names.contains(artist)) names.add(artist);
      }
    }

    if (raw is String) {
      addCredit(raw);
    } else if (raw is List) {
      for (final value in raw) {
        if (value is String) {
          addCredit(value);
        } else if (value is Map) {
          final name = _firstString(Map<String, dynamic>.from(value), const ['name']);
          addCredit(name);
        }
      }
    } else if (raw is Map) {
      final name = _firstString(Map<String, dynamic>.from(raw), const ['name']);
      addCredit(name);
    }
    return names;
  }

  /// Spotify's embed subtitle is a display string rather than an artists array
  /// (for example "OMWAWES, Guyon Waton"). Split its comma-separated credits so
  /// [SpotifyPlaylistTrack.primaryArtist] identifies the actual first credit.
  /// Preserve a few established stage names that contain an intrinsic comma.
  static List<String> _splitArtistSubtitle(String value) {
    final subtitle = value.replaceAll('\u00A0', ' ').trim();
    const commaNames = <String>{
      'tyler, the creator',
      'earth, wind & fire',
      'crosby, stills & nash',
      'emerson, lake & palmer',
    };
    if (commaNames.contains(subtitle.toLowerCase())) return [subtitle];

    return subtitle
        .split(RegExp(r'\s*,\s*'))
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .toList(growable: false);
  }

  static int? _readDurationMs(Map<String, dynamic> map) {
    final direct = map['duration_ms'] ?? map['durationMs'];
    if (direct is num) return direct.toInt();
    final duration = map['duration'];
    if (duration is num) return duration.toInt();
    if (duration is Map) {
      final value = duration['totalMilliseconds'] ??
          duration['total_milliseconds'] ??
          duration['milliseconds'];
      if (value is num) return value.toInt();
    }
    return null;
  }

  static String _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static String _findPlaylistTitle(Object? node) {
    if (node is List) {
      for (final child in node) {
        final value = _findPlaylistTitle(child);
        if (value.isNotEmpty) return value;
      }
    } else if (node is Map) {
      final map = Map<String, dynamic>.from(node);
      final type = _firstString(map, const ['type']).toLowerCase();
      final name = _firstString(map, const ['name', 'title']);
      if (type == 'playlist' && name.isNotEmpty) return name;
      for (final value in map.values) {
        final nested = _findPlaylistTitle(value);
        if (nested.isNotEmpty) return nested;
      }
    }
    return '';
  }

  static String _cleanPlaylistTitle(String value) {
    return value
        .replaceFirst(
          RegExp(r'\s*[·|—-]\s*playlist\s+by\s+.*$', caseSensitive: false),
          '',
        )
        .replaceFirst(RegExp(r'\s*\|\s*Spotify\s*$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*[·|—-]\s*Spotify\s*$', caseSensitive: false), '')
        .trim();
  }

  void close() => _client.close();
}
