import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/spotify_service.dart';

void main() {
  test('Spotify callback URI matches the fixed loopback registration', () {
    expect(
      SpotifyService.registeredRedirectUri,
      'http://127.0.0.1:43821/callback',
    );
    expect(SpotifyService.callbackPort, 43821);
  });

  test('Spotify imported playlist round-trips with ordered tracks and metadata', () {
    final source = SpotifyImportedPlaylist(
      playlist: const SpotifyPlaylist(
        id: 'playlist-1',
        name: 'Lagu Favorit',
        description: 'Playlist test',
        ownerName: 'Pengguna',
        imageUrl: 'https://example.com/cover.jpg',
        spotifyUrl: 'https://open.spotify.com/playlist/playlist-1',
        trackCount: 2,
      ),
      tracks: const <SpotifyTrack>[
        SpotifyTrack(
          id: 'track-1',
          name: 'Lagu Pertama',
          artists: <String>['Artis A'],
          albumName: 'Album A',
          imageUrl: 'https://example.com/album-a.jpg',
          spotifyUrl: 'https://open.spotify.com/track/track-1',
          isExplicit: false,
        ),
        SpotifyTrack(
          id: 'track-2',
          name: 'Lagu Kedua',
          artists: <String>['Artis B', 'Artis C'],
          albumName: 'Album B',
          imageUrl: '',
          spotifyUrl: 'https://open.spotify.com/track/track-2',
          isExplicit: true,
        ),
      ],
      importedAt: DateTime.utc(2026, 10, 16),
    );

    final restored = SpotifyImportedPlaylist.fromJson(source.toJson());

    expect(restored.playlist.id, 'playlist-1');
    expect(restored.playlist.name, 'Lagu Favorit');
    expect(restored.playlist.imageUrl, 'https://example.com/cover.jpg');
    expect(restored.tracks, hasLength(2));
    expect(restored.tracks[0].name, 'Lagu Pertama');
    expect(restored.tracks[0].artists, <String>['Artis A']);
    expect(restored.tracks[1].isExplicit, isTrue);
    expect(restored.importedAt, DateTime.utc(2026, 10, 16));
  });
}
