import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/spotify_service.dart';

void main() {
  test('parses Spotify account export playlist JSON without API credentials', () {
    const raw = '''
    {
      "playlists": [
        {
          "name": "Lagu Favorit",
          "playlistUri": "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M",
          "description": "Daftar lagu pilihan",
          "items": [
            {
              "track": {
                "trackName": "Lagu Pertama",
                "artistName": "Artis A",
                "albumName": "Album A",
                "trackUri": "spotify:track:4uLU6hMCjMI75M1A2tKUQC"
              },
              "episode": null,
              "localTrack": null,
              "addedDate": "2025-01-01"
            },
            {
              "track": {
                "trackName": "Lagu Kedua",
                "artistName": "Artis B",
                "albumName": "Album B",
                "trackUri": "spotify:track:1301WleyT98MSxVHPZCA6M"
              },
              "episode": null,
              "localTrack": null,
              "addedDate": "2025-01-02"
            }
          ]
        }
      ]
    }
    ''';

    final imported = SpotifyService.parseExportJson(raw);
    expect(imported, hasLength(1));
    expect(imported.first.playlist.name, 'Lagu Favorit');
    expect(imported.first.playlist.spotifyUrl, 'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M');
    expect(imported.first.tracks, hasLength(2));
    expect(imported.first.tracks[0].name, 'Lagu Pertama');
    expect(imported.first.tracks[0].artists, <String>['Artis A']);
    expect(imported.first.tracks[1].albumName, 'Album B');
  });

  test('rejects a Spotify streaming-history JSON file with a helpful error', () {
    expect(
      () => SpotifyService.parseExportJson('{"streamingHistory": []}'),
      throwsA(isA<FormatException>()),
    );
  });

  test('imported playlist round-trips with ordered tracks and metadata', () {
    final source = SpotifyImportedPlaylist(
      playlist: const SpotifyPlaylist(
        id: 'import-a1b2c3d4',
        name: 'Lagu Favorit',
        description: 'Playlist test',
        ownerName: 'Ekspor Spotify',
        imageUrl: '',
        spotifyUrl: '',
        trackCount: 2,
      ),
      tracks: const <SpotifyTrack>[
        SpotifyTrack(
          id: 'local-track-1',
          name: 'Lagu Pertama',
          artists: <String>['Artis A'],
          albumName: 'Album A',
          imageUrl: '',
          spotifyUrl: '',
          isExplicit: false,
        ),
        SpotifyTrack(
          id: 'local-track-2',
          name: 'Lagu Kedua',
          artists: <String>['Artis B', 'Artis C'],
          albumName: 'Album B',
          imageUrl: '',
          spotifyUrl: '',
          isExplicit: true,
        ),
      ],
      importedAt: DateTime.utc(2026, 10, 16),
    );

    final restored = SpotifyImportedPlaylist.fromJson(source.toJson());

    expect(restored.playlist.id, 'import-a1b2c3d4');
    expect(restored.playlist.name, 'Lagu Favorit');
    expect(restored.playlist.spotifyUrl, isEmpty);
    expect(restored.tracks, hasLength(2));
    expect(restored.tracks[0].name, 'Lagu Pertama');
    expect(restored.tracks[0].artists, <String>['Artis A']);
    expect(restored.tracks[1].isExplicit, isTrue);
    expect(restored.tracks[1].spotifyUrl, isEmpty);
    expect(restored.importedAt, DateTime.utc(2026, 10, 16));
  });
}
