import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Read-only Spotify account integration for browsing playlists and their items.
/// Spotify metadata is held in memory only; credentials are kept in encrypted storage.
class SpotifyService {
  SpotifyService._();

  static final SpotifyService instance = SpotifyService._();

  static const String clientId = String.fromEnvironment('SPOTIFY_CLIENT_ID');
  // Register this exact loopback URI in Spotify Developer Dashboard.
  // A fixed port avoids dashboard validation issues with a portless URI.
  // This is a public client flow using Authorization Code + PKCE.
  static const int callbackPort = 43821;
  static const String registeredRedirectUri =
      'http://127.0.0.1:43821/callback';
  static const List<String> scopes = <String>[
    'user-read-private',
    'playlist-read-private',
    'playlist-read-collaborative',
  ];

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _refreshTokenKey = 'spotify_refresh_token_v1';
  static const String _clientIdKey = 'spotify_client_id_v1';
  static const String _importedPlaylistsKey = 'spotify_imported_playlists_v1';

  String? _accessToken;
  String? _refreshToken;
  DateTime _accessTokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get isConfigured => clientId.trim().isNotEmpty;
  bool get isConnected => _refreshToken != null && _refreshToken!.isNotEmpty;

  /// Restores a session only when the stored token belongs to the currently
  /// configured client ID. Returns false when no session exists.
  Future<bool> restoreSession() async {
    if (!isConfigured) return false;
    final savedClientId = await _secureStorage.read(key: _clientIdKey);
    final savedRefreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (savedRefreshToken == null || savedRefreshToken.isEmpty) return false;
    if (savedClientId != clientId) {
      await disconnect();
      return false;
    }
    _refreshToken = savedRefreshToken;
    await _refreshAccessToken();
    return true;
  }

  Future<void> connect() async {
    if (!isConfigured) {
      throw const SpotifyIntegrationException(
        'Spotify belum dikonfigurasi. Tambahkan SPOTIFY_CLIENT_ID di GitHub Repository Variables lalu build ulang APK.',
      );
    }

    final verifier = _randomBase64Url(64);
    final challenge = base64Url
        .encode(sha256.convert(utf8.encode(verifier)).bytes)
        .replaceAll('=', '');
    final state = _randomBase64Url(24);

    // Use the same fixed loopback port registered in Spotify Dashboard.
    // If another process occupies it, ask the user to close the conflicting app
    // and retry rather than silently sending a mismatched redirect URI.
    final redirect = Uri.parse(registeredRedirectUri);
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      callbackPort,
    );
    final authorizationUri = Uri.https(
      'accounts.spotify.com',
      '/authorize',
      <String, String>{
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': redirect.toString(),
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': state,
        'scope': scopes.join(' '),
      },
    );

    final callbackCompleter = Completer<Uri>();
    final serverSubscription = server.listen((request) async {
      if (request.uri.path != '/callback') {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.html;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.headers.set('Pragma', 'no-cache');
      request.response.write(
        '<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Spotify - MusikKu</title></head><body style="font-family:Arial,sans-serif;padding:32px;line-height:1.5">'
        '<h2>Spotify berhasil diarahkan kembali</h2>'
        '<p>Kamu bisa kembali ke aplikasi MusikKu untuk melihat playlist.</p></body></html>',
      );
      await request.response.close();
      if (!callbackCompleter.isCompleted) callbackCompleter.complete(request.uri);
    });

    late final Uri callbackUri;
    try {
      final opened = await launchUrl(
        authorizationUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw const SpotifyIntegrationException(
          'Browser tidak bisa dibuka. Coba lagi atau periksa browser perangkat.',
        );
      }
      callbackUri = await callbackCompleter.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw const SpotifyIntegrationException(
          'Login Spotify kedaluwarsa. Kembali ke MusikKu lalu coba hubungkan lagi.',
        ),
      );
    } finally {
      await serverSubscription.cancel();
      await server.close(force: true);
    }
    final usedRedirectUri = redirect.toString();
    final returnedState = callbackUri.queryParameters['state'];
    if (returnedState != state) {
      throw const SpotifyIntegrationException(
        'Verifikasi OAuth Spotify gagal. Silakan coba hubungkan ulang.',
      );
    }
    final authError = callbackUri.queryParameters['error'];
    if (authError != null) {
      if (authError == 'access_denied') {
        throw const SpotifyIntegrationException('Izin Spotify dibatalkan.');
      }
      throw SpotifyIntegrationException('Spotify menolak login: $authError');
    }
    final code = callbackUri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw const SpotifyIntegrationException(
        'Spotify tidak mengembalikan kode login. Periksa Redirect URI di Spotify Developer Dashboard.',
      );
    }

    final response = await http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'client_id': clientId,
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': usedRedirectUri,
        'code_verifier': verifier,
      },
    );
    if (response.statusCode != 200) {
      throw SpotifyIntegrationException(_tokenError(response));
    }
    await _acceptTokenResponse(response.body, persistRefreshToken: true);
  }

  Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    _accessTokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(0);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _clientIdKey);
  }

  Future<SpotifyProfile> getCurrentUser() async {
    final json = await _getJson(Uri.https('api.spotify.com', '/v1/me'));
    return SpotifyProfile(
      id: _string(json['id']),
      displayName: _string(json['display_name']).trim().isEmpty
          ? 'Akun Spotify'
          : _string(json['display_name']).trim(),
    );
  }

  Future<List<SpotifyPlaylist>> getMyPlaylists() async {
    final result = <SpotifyPlaylist>[];
    var offset = 0;
    while (offset <= 100000) {
      final json = await _getJson(
        Uri.https('api.spotify.com', '/v1/me/playlists', <String, String>{
          'limit': '50',
          'offset': '$offset',
        }),
      );
      final rows = json['items'];
      if (rows is! List || rows.isEmpty) break;
      for (final value in rows) {
        if (value is Map<String, dynamic>) {
          result.add(SpotifyPlaylist.fromJson(value));
        } else if (value is Map) {
          result.add(SpotifyPlaylist.fromJson(Map<String, dynamic>.from(value)));
        }
      }
      final total = _int(json['total']);
      offset += rows.length;
      if (rows.length < 50 || (total > 0 && offset >= total)) break;
    }
    return result;
  }

  Future<List<SpotifyTrack>> getPlaylistItems(String playlistId) async {
    if (playlistId.trim().isEmpty) return const <SpotifyTrack>[];
    final tracks = <SpotifyTrack>[];
    var offset = 0;
    while (offset <= 100000) {
      final json = await _getJson(
        Uri.https('api.spotify.com', '/v1/playlists/$playlistId/items', <String, String>{
          'limit': '50',
          'offset': '$offset',
          'additional_types': 'track',
        }),
      );
      final rows = json['items'];
      if (rows is! List || rows.isEmpty) break;
      for (final row in rows) {
        if (row is! Map) continue;
        // Spotify's 2026 API response uses `item`; support `track` defensively
        // for older responses while following the current `/items` endpoint.
        final rawItem = row['item'] ?? row['track'];
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        if (_string(item['type']) != 'track' || _string(item['id']).isEmpty) continue;
        tracks.add(SpotifyTrack.fromJson(item));
      }
      final total = _int(json['total']);
      offset += rows.length;
      if (rows.length < 50 || (total > 0 && offset >= total)) break;
    }
    return tracks;
  }

  /// Playlist yang diimpor adalah data lokal milik pengguna di MusikKu.
  /// Data bisa dilihat tanpa membuka/memutar Spotify dan bisa dihapus kapan saja.
  Future<List<SpotifyImportedPlaylist>> loadImportedPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_importedPlaylistsKey);
      if (raw == null || raw.isEmpty) return <SpotifyImportedPlaylist>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SpotifyImportedPlaylist>[];
      return decoded
          .whereType<Map>()
          .map((item) => SpotifyImportedPlaylist.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.playlist.id.isNotEmpty)
          .toList();
    } catch (_) {
      return <SpotifyImportedPlaylist>[];
    }
  }

  /// Mengimpor metadata playlist dan lagu ke library lokal MusikKu.
  /// Jika playlist sudah pernah diimpor, data lama diganti dengan snapshot terbaru.
  Future<void> importPlaylist(
    SpotifyPlaylist playlist,
    List<SpotifyTrack> tracks,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadImportedPlaylists();
    existing.removeWhere((item) => item.playlist.id == playlist.id);
    existing.insert(
      0,
      SpotifyImportedPlaylist(
        playlist: playlist,
        tracks: List<SpotifyTrack>.unmodifiable(tracks),
        importedAt: DateTime.now(),
      ),
    );
    await prefs.setString(
      _importedPlaylistsKey,
      jsonEncode(existing.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> removeImportedPlaylist(String playlistId) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadImportedPlaylists();
    existing.removeWhere((item) => item.playlist.id == playlistId);
    await prefs.setString(
      _importedPlaylistsKey,
      jsonEncode(existing.map((item) => item.toJson()).toList()),
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    await _ensureAccessToken();
    var response = await http.get(uri, headers: <String, String>{
      'Authorization': 'Bearer $_accessToken',
      'Accept': 'application/json',
    });
    if (response.statusCode == 401 && _refreshToken != null) {
      await _refreshAccessToken();
      response = await http.get(uri, headers: <String, String>{
        'Authorization': 'Bearer $_accessToken',
        'Accept': 'application/json',
      });
    }
    if (response.statusCode != 200) {
      throw SpotifyIntegrationException(_apiError(response));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const SpotifyIntegrationException('Respons Spotify tidak valid.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _ensureAccessToken() async {
    if (_accessToken != null && DateTime.now().isBefore(_accessTokenExpiresAt)) return;
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      _refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    }
    if (_refreshToken == null || _refreshToken!.isEmpty) {
      throw const SpotifyIntegrationException('Hubungkan akun Spotify terlebih dahulu.');
    }
    await _refreshAccessToken();
  }

  Future<void> _refreshAccessToken() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const SpotifyIntegrationException('Sesi Spotify berakhir. Hubungkan akun lagi.');
    }
    final response = await http.post(
      Uri.https('accounts.spotify.com', '/api/token'),
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );
    if (response.statusCode != 200) {
      await disconnect();
      throw SpotifyIntegrationException(_tokenError(response));
    }
    await _acceptTokenResponse(response.body, persistRefreshToken: true);
  }

  Future<void> _acceptTokenResponse(
    String body, {
    required bool persistRefreshToken,
  }) async {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const SpotifyIntegrationException('Respons token Spotify tidak valid.');
    }
    final json = Map<String, dynamic>.from(decoded);
    final accessToken = _string(json['access_token']);
    if (accessToken.isEmpty) {
      throw const SpotifyIntegrationException('Spotify tidak memberikan access token.');
    }
    _accessToken = accessToken;
    final refreshToken = _string(json['refresh_token']);
    if (refreshToken.isNotEmpty) _refreshToken = refreshToken;
    final expiresIn = _int(json['expires_in']);
    _accessTokenExpiresAt = DateTime.now().add(
      Duration(seconds: max(30, expiresIn - 60)),
    );

    if (persistRefreshToken && _refreshToken != null) {
      await _secureStorage.write(key: _refreshTokenKey, value: _refreshToken);
      await _secureStorage.write(key: _clientIdKey, value: clientId);
    }
  }

  String _tokenError(http.Response response) {
    if (response.statusCode == 400 || response.statusCode == 401) {
      return 'Token Spotify ditolak (${response.statusCode}). Cek Client ID dan Redirect URI.';
    }
    return 'Gagal menghubungi layanan login Spotify (${response.statusCode}).';
  }

  String _apiError(http.Response response) {
    switch (response.statusCode) {
      case 401:
        return 'Sesi Spotify tidak valid. Hubungkan ulang akun Spotify.';
      case 403:
        return 'Spotify menolak akses. Cek izin playlist, status akun developer Premium, dan daftar pengguna aplikasi Spotify.';
      case 429:
        return 'Batas permintaan Spotify tercapai. Tunggu sebentar lalu coba lagi.';
      default:
        return 'Gagal memuat data Spotify (${response.statusCode}). Coba lagi nanti.';
    }
  }

  String _randomBase64Url(int byteCount) {
    final random = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _string(Object? value) => value is String ? value : '';
  static int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

class SpotifyIntegrationException implements Exception {
  final String message;
  const SpotifyIntegrationException(this.message);
  @override
  String toString() => message;
}

class SpotifyProfile {
  final String id;
  final String displayName;
  const SpotifyProfile({required this.id, required this.displayName});
}

class SpotifyPlaylist {
  final String id;
  final String name;
  final String description;
  final String ownerName;
  final String imageUrl;
  final String spotifyUrl;
  final int trackCount;

  const SpotifyPlaylist({
    required this.id,
    required this.name,
    required this.description,
    required this.ownerName,
    required this.imageUrl,
    required this.spotifyUrl,
    required this.trackCount,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'owner': <String, dynamic>{'display_name': ownerName},
        'images': imageUrl.isEmpty
            ? <dynamic>[]
            : <Map<String, dynamic>>[<String, dynamic>{'url': imageUrl}],
        'external_urls': <String, dynamic>{'spotify': spotifyUrl},
        'items': <String, dynamic>{'total': trackCount},
      };

  factory SpotifyPlaylist.fromJson(Map<String, dynamic> json) {
    final images = json['images'];
    var imageUrl = '';
    if (images is List && images.isNotEmpty && images.first is Map) {
      imageUrl = _value((images.first as Map)['url']);
    }
    final external = json['external_urls'];
    final owner = json['owner'];
    final items = json['items'];
    final oldTracks = json['tracks'];
    final itemCount = items is Map ? items['total'] : null;
    final oldCount = oldTracks is Map ? oldTracks['total'] : null;
    final id = _value(json['id']);
    return SpotifyPlaylist(
      id: id,
      name: _value(json['name']).isEmpty ? 'Playlist tanpa judul' : _value(json['name']),
      description: _value(json['description']),
      ownerName: owner is Map ? _value(owner['display_name']) : '',
      imageUrl: imageUrl,
      spotifyUrl: external is Map && _value(external['spotify']).isNotEmpty
          ? _value(external['spotify'])
          : 'https://open.spotify.com/playlist/$id',
      trackCount: itemCount is num ? itemCount.toInt() : oldCount is num ? oldCount.toInt() : 0,
    );
  }
}

class SpotifyTrack {
  final String id;
  final String name;
  final List<String> artists;
  final String albumName;
  final String imageUrl;
  final String spotifyUrl;
  final bool isExplicit;

  const SpotifyTrack({
    required this.id,
    required this.name,
    required this.artists,
    required this.albumName,
    required this.imageUrl,
    required this.spotifyUrl,
    required this.isExplicit,
  });

  String get artistLabel => artists.isEmpty ? 'Artis tidak diketahui' : artists.join(', ');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': 'track',
        'name': name,
        'artists': artists.map((name) => <String, dynamic>{'name': name}).toList(),
        'album': <String, dynamic>{
          'name': albumName,
          'images': imageUrl.isEmpty
              ? <dynamic>[]
              : <Map<String, dynamic>>[<String, dynamic>{'url': imageUrl}],
        },
        'external_urls': <String, dynamic>{'spotify': spotifyUrl},
        'explicit': isExplicit,
      };

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    final artistsJson = json['artists'];
    final artists = artistsJson is List
        ? artistsJson.whereType<Map>().map((item) => _value(item['name'])).where((name) => name.isNotEmpty).toList(growable: false)
        : const <String>[];
    final album = json['album'];
    final images = album is Map ? album['images'] : null;
    var imageUrl = '';
    if (images is List && images.isNotEmpty && images.first is Map) {
      imageUrl = _value((images.first as Map)['url']);
    }
    final external = json['external_urls'];
    final id = _value(json['id']);
    return SpotifyTrack(
      id: id,
      name: _value(json['name']).isEmpty ? 'Lagu tanpa judul' : _value(json['name']),
      artists: artists,
      albumName: album is Map ? _value(album['name']) : '',
      imageUrl: imageUrl,
      spotifyUrl: external is Map && _value(external['spotify']).isNotEmpty
          ? _value(external['spotify'])
          : 'https://open.spotify.com/track/$id',
      isExplicit: json['explicit'] == true,
    );
  }

  static String _value(Object? value) => value is String ? value : '';
}

class SpotifyImportedPlaylist {
  final SpotifyPlaylist playlist;
  final List<SpotifyTrack> tracks;
  final DateTime importedAt;

  const SpotifyImportedPlaylist({
    required this.playlist,
    required this.tracks,
    required this.importedAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'playlist': playlist.toJson(),
        'tracks': tracks.map((track) => track.toJson()).toList(),
        'importedAt': importedAt.toIso8601String(),
      };

  factory SpotifyImportedPlaylist.fromJson(Map<String, dynamic> json) {
    final playlistJson = json['playlist'];
    final rawTracks = json['tracks'];
    final parsedTracks = rawTracks is List
        ? rawTracks
            .whereType<Map>()
            .map((item) => SpotifyTrack.fromJson(Map<String, dynamic>.from(item)))
            .where((track) => track.id.isNotEmpty)
            .toList(growable: false)
        : const <SpotifyTrack>[];
    return SpotifyImportedPlaylist(
      playlist: playlistJson is Map
          ? SpotifyPlaylist.fromJson(Map<String, dynamic>.from(playlistJson))
          : const SpotifyPlaylist(
              id: '',
              name: 'Playlist',
              description: '',
              ownerName: '',
              imageUrl: '',
              spotifyUrl: '',
              trackCount: 0,
            ),
      tracks: parsedTracks,
      importedAt: DateTime.tryParse(json['importedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

String _value(Object? value) => value is String ? value : '';
