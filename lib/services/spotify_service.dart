import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local importer for the JSON account-data export downloaded from Spotify.
/// It intentionally does not call Spotify's Web API or require OAuth/Premium.
class SpotifyService {
  SpotifyService._();

  static final SpotifyService instance = SpotifyService._();
  static const String _importedPlaylistsKey = 'spotify_imported_playlists_v1';

  /// Parses Spotify's account-data export JSON (for example Playlist1.json).
  /// Supports Spotify's export shape and a playlist JSON object containing
  /// track/items data. No network request is made.
  static List<SpotifyImportedPlaylist> parseExportJson(String rawJson) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } on FormatException {
      rethrow;
    }

    final List<dynamic> rawPlaylists;
    if (decoded is Map) {
      final root = Map<String, dynamic>.from(decoded);
      final nested = _listField(root, const ['playlists', 'Playlists']);
      if (nested != null) {
        rawPlaylists = nested;
      } else if (_looksLikePlaylist(root)) {
        rawPlaylists = <dynamic>[root];
      } else {
        throw const FormatException(
          'File JSON ini bukan ekspor playlist Spotify. Pilih file Playlist*.json dari arsip data Spotify.',
        );
      }
    } else if (decoded is List) {
      rawPlaylists = decoded;
    } else {
      throw const FormatException(
        'Format file tidak dikenali. Pilih file JSON ekspor playlist Spotify.',
      );
    }

    final imported = <SpotifyImportedPlaylist>[];
    for (var i = 0; i < rawPlaylists.length; i++) {
      final value = rawPlaylists[i];
      if (value is! Map) continue;
      final playlistJson = Map<String, dynamic>.from(value);
      if (!_looksLikePlaylist(playlistJson)) continue;
      final name = _firstString(playlistJson, const [
            'name',
            'playlistName',
            'title',
          ])
          .trim();
      if (name.isEmpty) continue;

      final rawItems = _playlistItems(playlistJson);
      final provisionalKey = '$name|$i|${jsonEncode(rawItems)}';
      final rawPlaylistUri = _firstString(playlistJson, const [
        'playlistUri',
        'uri',
      ]);
      final providedId = _firstString(playlistJson, const ['id']);
      final uriId = _entityId(rawPlaylistUri, 'playlist');
      final providedIdLooksSpotify = RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(providedId);
      final realPlaylistId = uriId ?? (providedIdLooksSpotify ? providedId : null);
      final playlistId = realPlaylistId ?? 'import-${_stableHash(provisionalKey)}';

      final tracks = <SpotifyTrack>[];
      for (var trackIndex = 0; trackIndex < rawItems.length; trackIndex++) {
        final track = _parseTrack(rawItems[trackIndex], playlistId, trackIndex);
        if (track != null) tracks.add(track);
      }

      final external = _mapField(playlistJson, 'external_urls');
      final externalUrl = _stringValue(external?['spotify']);
      final explicitUrl = _firstString(playlistJson, const ['spotifyUrl', 'url']);
      final sourceUrl = _validSpotifyPlaylistUrl(externalUrl)
          ? externalUrl
          : _validSpotifyPlaylistUrl(explicitUrl)
              ? explicitUrl
              : realPlaylistId == null
                  ? ''
                  : 'https://open.spotify.com/playlist/$realPlaylistId';
      final owner = _mapField(playlistJson, 'owner');
      final description = _firstString(playlistJson, const ['description']);
      final ownerName = _firstString(playlistJson, const ['ownerName']).isNotEmpty
          ? _firstString(playlistJson, const ['ownerName'])
          : _stringValue(owner?['display_name']);

      imported.add(
        SpotifyImportedPlaylist(
          playlist: SpotifyPlaylist(
            id: playlistId,
            name: name,
            description: description,
            ownerName: ownerName.isEmpty ? 'Ekspor Spotify' : ownerName,
            imageUrl: _playlistImage(playlistJson),
            spotifyUrl: sourceUrl,
            trackCount: tracks.length,
          ),
          tracks: List<SpotifyTrack>.unmodifiable(tracks),
          importedAt: DateTime.now(),
        ),
      );
    }

    if (imported.isEmpty) {
      throw const FormatException(
        'Tidak ada playlist yang dapat dibaca. Pilih file Playlist*.json dari ekspor data Spotify, bukan file riwayat streaming.',
      );
    }
    return imported;
  }

  /// Parses a Spotify account-data JSON file and saves each playlist locally.
  /// Existing playlists with the same stable ID are replaced by the new copy.
  Future<int> importExportJson(String rawJson) async {
    final playlists = parseExportJson(rawJson);
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadImportedPlaylists();
    // Insert in reverse so the playlist order in the export remains the order
    // shown in the local collection after each item is placed at the top.
    for (final imported in playlists.reversed) {
      existing.removeWhere((item) => item.playlist.id == imported.playlist.id);
      existing.insert(0, imported);
    }
    await prefs.setString(
      _importedPlaylistsKey,
      jsonEncode(existing.map((item) => item.toJson()).toList()),
    );
    return playlists.length;
  }

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

  static bool _looksLikePlaylist(Map<String, dynamic> value) {
    final hasName = _firstString(value, const ['name', 'playlistName', 'title']).trim().isNotEmpty;
    final tracksPage = _mapField(value, 'tracks');
    final hasItems = _listField(value, const ['items', 'tracks', 'playlistItems']) != null ||
        (tracksPage != null && tracksPage['items'] is List);
    return hasName && hasItems;
  }

  static List<dynamic> _playlistItems(Map<String, dynamic> playlist) {
    final items = _listField(playlist, const ['items', 'playlistItems']);
    if (items != null) return items;
    final tracks = playlist['tracks'];
    if (tracks is List) return tracks;
    if (tracks is Map && tracks['items'] is List) {
      return tracks['items'] as List<dynamic>;
    }
    return const <dynamic>[];
  }

  static SpotifyTrack? _parseTrack(Object? raw, String playlistId, int index) {
    if (raw is! Map) return null;
    final entry = Map<String, dynamic>.from(raw);
    final candidate = entry['track'] ?? entry['item'] ?? entry['localTrack'] ?? entry;
    if (candidate is! Map) return null;
    final track = Map<String, dynamic>.from(candidate);

    final name = _firstString(track, const [
      'trackName',
      'name',
      'title',
      'track_name',
    ]).trim();
    if (name.isEmpty) return null;

    final artists = <String>[];
    final exportedArtist = _firstString(track, const ['artistName', 'artist', 'artist_name']).trim();
    if (exportedArtist.isNotEmpty) {
      artists.add(exportedArtist);
    } else {
      final rawArtists = track['artists'] ?? track['artistNames'];
      if (rawArtists is List) {
        for (final artist in rawArtists) {
          final artistName = artist is Map
              ? _stringValue(artist['name'] ?? artist['artistName'])
              : _stringValue(artist);
          if (artistName.trim().isNotEmpty) artists.add(artistName.trim());
        }
      } else if (rawArtists is String && rawArtists.trim().isNotEmpty) {
        artists.add(rawArtists.trim());
      }
    }

    final album = _mapField(track, 'album');
    final albumName = _firstString(track, const ['albumName', 'album_name']).isNotEmpty
        ? _firstString(track, const ['albumName', 'album_name'])
        : _stringValue(album?['name']);
    final rawUri = _firstString(track, const ['trackUri', 'uri']);
    final external = _mapField(track, 'external_urls');
    final externalUrl = _stringValue(external?['spotify']);
    final providedId = _firstString(track, const ['id']);
    final uriId = _entityId(rawUri, 'track');
    final candidateId = uriId ?? (RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(providedId) ? providedId : null);
    final id = candidateId ?? 'local-${_stableHash('$playlistId|$index|$name|${artists.join(',')}|$albumName')}';
    final spotifyUrl = _validSpotifyTrackUrl(externalUrl)
        ? externalUrl
        : _validSpotifyTrackUrl(_firstString(track, const ['spotifyUrl', 'url']))
            ? _firstString(track, const ['spotifyUrl', 'url'])
            : candidateId == null
                ? ''
                : 'https://open.spotify.com/track/$candidateId';

    return SpotifyTrack(
      id: id,
      name: name,
      artists: List<String>.unmodifiable(artists),
      albumName: albumName,
      imageUrl: _albumImage(track),
      spotifyUrl: spotifyUrl,
      isExplicit: track['explicit'] == true || track['isExplicit'] == true,
    );
  }

  static String _playlistImage(Map<String, dynamic> playlist) {
    final images = playlist['images'];
    if (images is List && images.isNotEmpty && images.first is Map) {
      return _stringValue((images.first as Map)['url']);
    }
    return _firstString(playlist, const ['imageUrl', 'coverArt']);
  }

  static String _albumImage(Map<String, dynamic> track) {
    final album = _mapField(track, 'album');
    final images = album?['images'];
    if (images is List && images.isNotEmpty && images.first is Map) {
      return _stringValue((images.first as Map)['url']);
    }
    return _firstString(track, const ['imageUrl', 'coverArt']);
  }

  static List<dynamic>? _listField(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) return value;
    }
    return null;
  }

  static Map? _mapField(Map<String, dynamic> map, String key) {
    final value = map[key];
    return value is Map ? value : null;
  }

  static String _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  static String _stringValue(Object? value) => value is String ? value : '';

  static String? _entityId(String value, String type) {
    final raw = value.trim();
    final uriMatch = RegExp('^spotify:${RegExp.escape(type)}:([A-Za-z0-9]+)\$').firstMatch(raw);
    if (uriMatch != null) return uriMatch.group(1);
    final urlMatch = RegExp('(?:open\\.spotify\\.com)/$type/([A-Za-z0-9]+)').firstMatch(raw);
    if (urlMatch != null) return urlMatch.group(1);
    return null;
  }

  static bool _validSpotifyPlaylistUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host == 'open.spotify.com' && uri.pathSegments.length >= 2 && uri.pathSegments.first == 'playlist';
  }

  static bool _validSpotifyTrackUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.host == 'open.spotify.com' && uri.pathSegments.length >= 2 && uri.pathSegments.first == 'track';
  }

  static String _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
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
      imageUrl = SpotifyService._stringValue((images.first as Map)['url']);
    }
    final external = json['external_urls'];
    final owner = json['owner'];
    final items = json['items'];
    final oldTracks = json['tracks'];
    final itemCount = items is Map ? items['total'] : null;
    final oldCount = oldTracks is Map ? oldTracks['total'] : null;
    final id = json['id'] is String ? json['id'] as String : '';
    final externalUrl = external is Map ? SpotifyService._stringValue(external['spotify']) : '';
    final syntheticId = id.startsWith('import-');
    return SpotifyPlaylist(
      id: id,
      name: json['name'] is String && (json['name'] as String).isNotEmpty
          ? json['name'] as String
          : 'Playlist tanpa judul',
      description: json['description'] is String ? json['description'] as String : '',
      ownerName: owner is Map ? SpotifyService._stringValue(owner['display_name']) : '',
      imageUrl: imageUrl,
      spotifyUrl: externalUrl.isNotEmpty
          ? externalUrl
          : syntheticId
              ? ''
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
        ? artistsJson.whereType<Map>().map((item) => SpotifyService._stringValue(item['name'])).where((name) => name.isNotEmpty).toList(growable: false)
        : const <String>[];
    final album = json['album'];
    final images = album is Map ? album['images'] : null;
    var imageUrl = '';
    if (images is List && images.isNotEmpty && images.first is Map) {
      imageUrl = SpotifyService._stringValue((images.first as Map)['url']);
    }
    final external = json['external_urls'];
    final id = json['id'] is String ? json['id'] as String : '';
    final externalUrl = external is Map ? SpotifyService._stringValue(external['spotify']) : '';
    return SpotifyTrack(
      id: id,
      name: json['name'] is String && (json['name'] as String).isNotEmpty
          ? json['name'] as String
          : 'Lagu tanpa judul',
      artists: artists,
      albumName: album is Map ? SpotifyService._stringValue(album['name']) : '',
      imageUrl: imageUrl,
      spotifyUrl: externalUrl.isNotEmpty
          ? externalUrl
          : id.startsWith('local-')
              ? ''
              : 'https://open.spotify.com/track/$id',
      isExplicit: json['explicit'] == true,
    );
  }
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
