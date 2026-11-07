import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/spotify_playlist_import_service.dart';
import 'package:flutter_application_5/services/spotify_youtube_track_matcher.dart';

void main() {
  group('Spotify public embed playlist parser', () {
    test('extracts playlist name and ordered track metadata from embedded JSON', () {
      const html = '''
        <!doctype html>
        <html><head>
          <meta property="og:title" content="Indie Mix · Spotify" />
          <meta property="og:description" content="A public playlist" />
        </head><body>
          <script id="__NEXT_DATA__" type="application/json">
          {
            "props": {"pageProps": {"state": {"data": {"entity": {
              "type": "playlist",
              "name": "Indie Mix",
              "tracks": {"items": [
                {"track": {
                  "type": "track",
                  "uri": "spotify:track:aaaaaaaaaaaaaaaaaaaaaa",
                  "name": "Evaluasi",
                  "artists": [{"name": "Hindia"}],
                  "duration": {"totalMilliseconds": 223000}
                }},
                {"track": {
                  "type": "track",
                  "uri": "spotify:track:bbbbbbbbbbbbbbbbbbbbbb",
                  "name": "Celengan Rindu",
                  "artists": [{"name": "Fiersa Besari"}],
                  "duration_ms": 248000
                }}
              ]}
            }}}}}
          }
          </script>
        </body></html>
      ''';

      final snapshot = SpotifyPlaylistImportService.parseEmbedHtml(
        html,
        playlistId: '12345678901234567890',
        sourceUrl: 'https://open.spotify.com/playlist/12345678901234567890',
      );

      expect(snapshot.title, 'Indie Mix');
      expect(snapshot.description, 'A public playlist');
      expect(snapshot.tracks, hasLength(2));
      expect(snapshot.tracks[0].title, 'Evaluasi');
      expect(snapshot.tracks[0].artists, ['Hindia']);
      expect(snapshot.tracks[0].durationMs, 223000);
      expect(snapshot.tracks[1].title, 'Celengan Rindu');
      expect(snapshot.tracks[1].primaryArtist, 'Fiersa Besari');
      expect(snapshot.mayBePartial, isFalse);
    });

    test('parses the current embed entity trackList shape', () {
      const html = '''
        <html><head>
          <meta property="og:title" content="Daily Mix · Spotify" />
        </head><body>
          <script id="__NEXT_DATA__" type="application/json">
          {
            "props": {"pageProps": {"state": {"data": {"entity": {
              "type": "playlist",
              "name": "Daily Mix",
              "trackList": [
                {
                  "uri": "spotify:track:1111111111111111111111",
                  "title": "Evaluasi",
                  "subtitle": "Hindia",
                  "duration": 223000,
                  "entityType": "track"
                },
                {
                  "uri": "spotify:track:2222222222222222222222",
                  "title": "Celengan Rindu",
                  "subtitle": "Fiersa Besari",
                  "duration": 248000,
                  "entityType": "track"
                }
              ]
            }}}}}
          }
          </script>
        </body></html>
      ''';

      final snapshot = SpotifyPlaylistImportService.parseEmbedHtml(
        html,
        playlistId: '12345678901234567890',
        sourceUrl: 'https://open.spotify.com/playlist/12345678901234567890',
      );

      expect(snapshot.title, 'Daily Mix');
      expect(snapshot.tracks, hasLength(2));
      expect(snapshot.tracks.first.title, 'Evaluasi');
      expect(snapshot.tracks.first.primaryArtist, 'Hindia');
      expect(snapshot.tracks.last.title, 'Celengan Rindu');
      expect(snapshot.tracks.last.primaryArtist, 'Fiersa Besari');
      expect(snapshot.tracks.last.durationMs, 248000);
    });

    test('parses more than 100 tracks when the public embed includes them', () {
      final trackList = List<Map<String, dynamic>>.generate(125, (index) {
        final id = index.toString().padLeft(22, '0');
        return <String, dynamic>{
          'uri': 'spotify:track:$id',
          'title': 'Song $index',
          'subtitle': 'Artist $index',
          'duration': 180000,
          'entityType': 'track',
        };
      });
      final payload = <String, dynamic>{
        'props': <String, dynamic>{
          'pageProps': <String, dynamic>{
            'state': <String, dynamic>{
              'data': <String, dynamic>{
                'entity': <String, dynamic>{
                  'type': 'playlist',
                  'name': 'Large playlist',
                  'totalCount': 180,
                  'trackList': trackList,
                },
              },
            },
          },
        },
      };
      final html = '<html><body><script id="__NEXT_DATA__" '
          'type="application/json">${jsonEncode(payload)}</script></body></html>';

      final snapshot = SpotifyPlaylistImportService.parseEmbedHtml(
        html,
        playlistId: '12345678901234567890',
        sourceUrl: 'https://open.spotify.com/playlist/12345678901234567890',
      );

      expect(snapshot.tracks, hasLength(125));
      expect(snapshot.tracks.first.title, 'Song 0');
      expect(snapshot.tracks.last.title, 'Song 124');
      expect(snapshot.totalTrackCount, 180);
      expect(snapshot.knownMissingTrackCount, 55);
      expect(snapshot.mayBePartial, isTrue);
    });

    test('does not treat podcast episodes as playlist songs', () {
      const html = '''
        <html><body>
          <script id="__NEXT_DATA__" type="application/json">
          {
            "props": {"pageProps": {"state": {"data": {"entity": {
              "type": "playlist",
              "name": "Music and Podcasts",
              "trackList": [
                {
                  "uri": "spotify:episode:eeeeeeeeeeeeeeeeeeeeee",
                  "title": "Podcast episode",
                  "subtitle": "Podcast Host",
                  "duration": 1800000,
                  "entityType": "episode"
                },
                {
                  "uri": "spotify:track:tttttttttttttttttttttt",
                  "title": "Evaluasi",
                  "subtitle": "Hindia",
                  "duration": 223000,
                  "entityType": "track"
                }
              ]
            }}}}}
          }
          </script>
        </body></html>
      ''';

      final snapshot = SpotifyPlaylistImportService.parseEmbedHtml(
        html,
        playlistId: '12345678901234567890',
        sourceUrl: 'https://open.spotify.com/playlist/12345678901234567890',
      );
      expect(snapshot.tracks, hasLength(1));
      expect(snapshot.tracks.single.title, 'Evaluasi');
    });

    test('does not invent tracks when the page contains no track list', () {
      expect(
        () => SpotifyPlaylistImportService.parseEmbedHtml(
          '<html><head><meta property="og:title" content="Private" /></head></html>',
          playlistId: '12345678901234567890',
          sourceUrl: 'https://open.spotify.com/playlist/12345678901234567890',
        ),
        throwsA(isA<SpotifyPlaylistImportException>()),
      );
    });
  });

  group('Spotify to YouTube track matching', () {
    const spotifyTrack = SpotifyPlaylistTrack(
      title: 'Celengan Rindu',
      artists: ['Fiersa Besari'],
      spotifyTrackId: 'aaaaaaaaaaaaaaaaaaaaaa',
    );

    YoutubeSearchResult candidate({
      required String id,
      required String title,
      required String channel,
      String description = '',
    }) => YoutubeSearchResult(
          videoId: id,
          title: title,
          channelTitle: channel,
          description: description,
          thumbnailUrl: '',
          durationSeconds: 248,
        );

    test('chooses the correct track and artist from candidates', () {
      final correct = candidate(
        id: 'correct-video',
        title: 'Fiersa Besari - Celengan Rindu (Official Music Video)',
        channel: 'Musica Studios',
      );
      final wrongArtist = candidate(
        id: 'wrong-video',
        title: 'Celengan Rindu',
        channel: 'Penyanyi Lain',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [wrongArtist, correct],
        )?.videoId,
        'correct-video',
      );
    });

    test('rejects same-title candidates without an artist match', () {
      final wrongArtist = candidate(
        id: 'wrong-video',
        title: 'Celengan Rindu',
        channel: 'Penyanyi Lain',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [wrongArtist]),
        isNull,
      );
    });

    test('supports non-Latin titles when the YouTube title includes the artist', () {
      const koreanTrack = SpotifyPlaylistTrack(
        title: '봄날',
        artists: ['BTS'],
      );
      final koreanUpload = candidate(
        id: 'korean-video',
        title: 'BTS - 봄날 (Official Music Video)',
        channel: 'HYBE LABELS',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(koreanTrack, [koreanUpload])?.videoId,
        'korean-video',
      );
    });

    test('does not substitute a live version for the Spotify studio track', () {
      final liveVersion = candidate(
        id: 'live-video',
        title: 'Fiersa Besari - Celengan Rindu (Live Concert)',
        channel: 'Fiersa Besari',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [liveVersion]),
        isNull,
      );
    });

    test('rejects a partial title even when the artist matches', () {
      final partialTitle = candidate(
        id: 'partial-video',
        title: 'Fiersa Besari - Celengan (Official Audio)',
        channel: 'Fiersa Besari',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [partialTitle]),
        isNull,
      );
    });

    test('matches short titles when YouTube prepends multiple artist credits', () {
      const collaborativeTrack = SpotifyPlaylistTrack(
        title: 'Secukupnya',
        artists: ['Nadin Amizah, Hindia'],
      );
      final officialUpload = candidate(
        id: 'collab-video',
        title: 'Nadin Amizah - Secukupnya (Official Music Video)',
        channel: 'Nadin Amizah',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          collaborativeTrack,
          [officialUpload],
        )?.videoId,
        'collab-video',
      );
    });

    test('rejects karaoke, cover, and AI results even with a matching name', () {
      final blocked = [
        candidate(
          id: 'karaoke-video',
          title: 'Celengan Rindu Karaoke',
          channel: 'Fiersa Besari Karaoke',
        ),
        candidate(
          id: 'cover-video',
          title: 'Celengan Rindu - Cover by Someone',
          channel: 'Fiersa Besari Fan',
        ),
        candidate(
          id: 'ai-video',
          title: 'Fiersa Besari AI Cover - Celengan Rindu',
          channel: 'AI Music',
        ),
      ];
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, blocked),
        isNull,
      );
    });
  });
}
