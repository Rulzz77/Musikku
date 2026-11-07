import 'dart:convert';

import 'package:flutter_application_5/models/listening_stat.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/album_artwork_service.dart';
import 'package:flutter_application_5/services/spotify_playlist_import_service.dart';
import 'package:flutter_application_5/services/spotify_youtube_track_matcher.dart';
import 'package:flutter_application_5/services/youtube_music_metadata_parser.dart';
import 'package:flutter_application_5/services/youtube_music_policy.dart';
import 'package:flutter_application_5/services/youtube_search_response_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Listening stat artwork artist metadata', () {
    test('round-trips primary artist separately from full display credits', () {
      const source = ListeningStat(
        videoId: 'satru-video',
        title: 'Satru',
        artist: 'Denny Caknan, Happy Asmara',
        artistName: 'Denny Caknan',
        thumbnailUrl: 'https://example.com/satru.jpg',
        playCount: 1,
        listenedSeconds: 60,
      );
      final restored = ListeningStat.fromJson(source.toJson());
      expect(restored.artist, 'Denny Caknan, Happy Asmara');
      expect(restored.artistName, 'Denny Caknan');
    });
  });

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

    test('splits Spotify subtitle collaborator credits in display order', () {
      const html = '''
        <html><body>
          <script id="__NEXT_DATA__" type="application/json">
          {
            "props": {"pageProps": {"state": {"data": {"entity": {
              "type": "playlist",
              "name": "Playlist Jawa",
              "trackList": [
                {
                  "uri": "spotify:track:3333333333333333333333",
                  "title": "Dumes",
                  "subtitle": "OMWAWES, Guyon Waton",
                  "duration": 266000,
                  "entityType": "track"
                },
                {
                  "uri": "spotify:track:4444444444444444444444",
                  "title": "Satru",
                  "subtitle": "Denny Caknan, Happy Asmara",
                  "duration": 311000,
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

      expect(snapshot.tracks[0].artists, ['OMWAWES', 'Guyon Waton']);
      expect(snapshot.tracks[0].primaryArtist, 'OMWAWES');
      expect(snapshot.tracks[1].artists, ['Denny Caknan', 'Happy Asmara']);
      expect(snapshot.tracks[1].primaryArtist, 'Denny Caknan');
    });

    test('falls back to Spotify subtitle when artists array is empty', () {
      const html = '''
        <html><body>
          <script id="__NEXT_DATA__" type="application/json">
          {
            "props": {"pageProps": {"state": {"data": {"entity": {
              "type": "playlist",
              "name": "Subtitle fallback",
              "trackList": [
                {
                  "uri": "spotify:track:5555555555555555555555",
                  "title": "Cundamani",
                  "artists": [],
                  "subtitle": "Denny Caknan",
                  "duration": 287000,
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
      expect(snapshot.tracks.single.primaryArtist, 'Denny Caknan');
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

    test('treats a 100-row embed count as a lower bound, not the playlist total', () {
      final trackList = List<Map<String, dynamic>>.generate(100, (index) {
        final id = index.toString().padLeft(22, '0');
        return <String, dynamic>{
          'uri': 'spotify:track:$id',
          'title': 'Track $index',
          'subtitle': 'Artist $index',
          'duration': 180000,
          'entityType': 'track',
        };
      });
      final payload = <String, dynamic>{
        'entity': <String, dynamic>{
          'type': 'playlist',
          'name': 'Playlist over one hundred',
          // Some embed payloads expose the capped row count here.
          'totalCount': 100,
          'trackList': trackList,
        },
      };
      final html = '<script id="__NEXT_DATA__" type="application/json">'
          '${jsonEncode(payload)}</script>';
      final snapshot = SpotifyPlaylistImportService.parseEmbedHtml(
        html,
        playlistId: '12345678901234567890',
        sourceUrl: 'https://open.spotify.com/playlist/12345678901234567890',
      );

      expect(snapshot.tracks, hasLength(100));
      expect(snapshot.totalTrackCount, isNull);
      expect(snapshot.mayBePartial, isTrue);
      expect(snapshot.knownMissingTrackCount, 0);
    });

    test('stores primary artist separately from the upload channel after import', () {
      const spotifyTrack = SpotifyPlaylistTrack(
        title: 'Satru',
        artists: ['Denny Caknan', 'Happy Asmara'],
        album: 'Satru (Single)',
      );
      const candidate = YoutubeSearchResult(
        videoId: 'video123',
        title: 'Satru Official Audio',
        channelTitle: 'Music Label - Topic',
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );
      final imported = SpotifyYoutubeTrackMatcher.applySpotifyMetadata(
        spotifyTrack,
        candidate,
      );
      expect(imported.artistName, 'Denny Caknan');
      expect(imported.channelTitle, 'Denny Caknan, Happy Asmara');
      expect(imported.album, 'Satru (Single)');
    });


    test('reads album title only from a structured YouTube Music description', () {
      const track = SpotifyPlaylistTrack(
        title: 'Sinarengan',
        artists: ['Denny Caknan', 'Bella Bonita'],
      );
      const candidate = YoutubeSearchResult(
        videoId: 'album-description-video',
        title: 'Sinarengan Official Audio',
        channelTitle: 'Denny Caknan - Topic',
        description: 'Provided to YouTube by Example Label\n'
            'Sinarengan\n'
            'Denny Caknan\n'
            'Album: Sinarengan (Single)\n'
            'Auto-generated by YouTube.',
        thumbnailUrl: 'https://example.com/cover.jpg',
      );
      final imported = SpotifyYoutubeTrackMatcher.applySpotifyMetadata(
        track,
        candidate,
      );
      expect(imported.album, 'Sinarengan (Single)');
    });

    test('parses album metadata when the public embed supplies it', () {
      const html = '''
        <html><body>
          <script id="__NEXT_DATA__" type="application/json">
          {
            "props": {"pageProps": {"state": {"data": {"entity": {
              "type": "playlist",
              "name": "Album metadata",
              "trackList": [
                {
                  "uri": "spotify:track:3333333333333333333333",
                  "title": "Sinarengan",
                  "subtitle": "Denny Caknan, Bella Bonita",
                  "duration": 333000,
                  "album": {"name": "Sinarengan"},
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
      expect(snapshot.tracks.single.album, 'Sinarengan');
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
      double durationSeconds = 248,
    }) => YoutubeSearchResult(
          videoId: id,
          title: title,
          channelTitle: channel,
          description: description,
          thumbnailUrl: '',
          durationSeconds: durationSeconds,
        );

    test('prefers the artist official channel over a closer fan mirror', () {
      final fanMirror = candidate(
        id: 'fan-mirror',
        title: 'Fiersa Besari - Celengan Rindu',
        channel: 'Musik Hits Indonesia',
      );
      final artistOfficial = candidate(
        id: 'artist-official',
        title: 'Celengan Rindu (Official Music Video)',
        channel: 'Fiersa Besari - Official Artist Channel',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [fanMirror, artistOfficial],
        )?.videoId,
        'artist-official',
      );
    });

    test('only treats high-confidence official candidates as a search stop', () {
      final titleOnlyOfficial = candidate(
        id: 'title-only-official',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Lagu Hits Terbaru',
      );
      final artistChannel = candidate(
        id: 'artist-channel',
        title: 'Celengan Rindu',
        channel: 'Fiersa Besari - Official Artist Channel',
      );

      expect(
        SpotifyYoutubeTrackMatcher.hasPreferredOfficialMatch(
          spotifyTrack,
          [titleOnlyOfficial],
        ),
        isFalse,
      );
      expect(
        SpotifyYoutubeTrackMatcher.hasPreferredOfficialMatch(
          spotifyTrack,
          [titleOnlyOfficial, artistChannel],
        ),
        isTrue,
      );
    });

    test('prefers Topic or VEVO sources over ordinary re-uploads', () {
      final reupload = candidate(
        id: 'ordinary-reupload',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Lagu Hits Terbaru',
      );
      final topicUpload = candidate(
        id: 'topic-upload',
        title: 'Celengan Rindu',
        channel: 'Fiersa Besari - Topic',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [reupload, topicUpload],
        )?.videoId,
        'topic-upload',
      );
    });

    test('rejects explicit fan and re-upload channels even with official title text', () {
      final fanChannel = candidate(
        id: 'fan-channel',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Fiersa Besari Fans Channel',
      );
      final reuploadChannel = candidate(
        id: 'reupload-channel',
        title: 'Celengan Rindu (Official Music Video)',
        channel: 'Music Reupload Archive',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [fanChannel, reuploadChannel],
        ),
        isNull,
      );
    });

    test('uses structured label credits as an official source signal', () {
      final fanMirror = candidate(
        id: 'fan-mirror',
        title: 'Fiersa Besari - Celengan Rindu',
        channel: 'Musik Hits Indonesia',
      );
      final labelRelease = candidate(
        id: 'label-release',
        title: 'Celengan Rindu (Official Audio)',
        channel: 'Musica Studios',
        description: 'Provided to YouTube by Musica Studios\n'
            'Celengan Rindu · Fiersa Besari\n'
            'Celengan Rindu · Fiersa Besari · ℗ Musica Studios',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [fanMirror, labelRelease],
        )?.videoId,
        'label-release',
      );
    });

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

    test('does not accept an artist name mentioned casually in description', () {
      final wrongPerformer = candidate(
        id: 'wrong-description-artist',
        title: 'Celengan Rindu (Official Audio)',
        channel: 'Musik Hits Indonesia',
        description: 'Playlist lagu populer untuk penggemar Fiersa Besari.',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [wrongPerformer]),
        isNull,
      );
    });

    test('accepts direct structured performer credit from a label upload', () {
      final labelUpload = candidate(
        id: 'label-credit',
        title: 'Celengan Rindu (Official Audio)',
        channel: 'Musica Studios',
        description: 'Artist: Fiersa Besari\nProvided to YouTube by Musica Studios.',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [labelUpload])?.videoId,
        'label-credit',
      );
    });


    test('accepts YouTube Music autogenerated track and performer credit block', () {
      final labelUpload = candidate(
        id: 'autogenerated-credit',
        title: 'Cundamani (Official Audio)',
        channel: 'Musica Studios',
        description: 'Provided to YouTube by Musica Studios\n\n'
            'Cundamani · Denny Caknan\n\n'
            'Cundamani · Denny Caknan · ℗ 2023 Musica Studios',
      );
      const track = SpotifyPlaylistTrack(
        title: 'Cundamani',
        artists: ['Denny Caknan'],
        durationMs: 287000,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [labelUpload])?.videoId,
        'autogenerated-credit',
      );
    });

    test('allows query tokens in reversed title and artist order across metadata', () {
      final labelUpload = candidate(
        id: 'reversed-title-order',
        title: 'Cundamani',
        channel: 'Musica Studios',
        description: 'Denny Caknan · official audio · Cundamani',
      );

      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          labelUpload,
          query: 'Denny Caknan Cundamani',
        ),
        isTrue,
      );
    });

    test('uses Spotify duration to rank candidates without rejecting valid video edits', () {
      const track = SpotifyPlaylistTrack(
        title: 'Celengan Rindu',
        artists: ['Fiersa Besari'],
        durationMs: 248000,
      );
      final longerVideoEdit = candidate(
        id: 'longer-video-edit',
        title: 'Fiersa Besari - Celengan Rindu (Official Music Video)',
        channel: 'Fiersa Besari',
        durationSeconds: 356,
      );
      final matchingDuration = candidate(
        id: 'matching-duration',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Musica Studios',
        durationSeconds: 249,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          track,
          [longerVideoEdit, matchingDuration],
        )?.videoId,
        'matching-duration',
      );
    });

    test('matches soundtrack song when YouTube omits Spotify From attribution', () {
      const track = SpotifyPlaylistTrack(
        title: 'Koyo Jogja Istimewa - From Cidro Asmoro',
        artists: ['Ndarboy Genk'],
      );
      final candidateWithoutAttribution = candidate(
        id: 'cidro-asmoro-no-attribution',
        title: 'Ndarboy Genk - Koyo Jogja Istimewa (Official Music Video)',
        channel: 'Ndarboy Genk',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          track,
          [candidateWithoutAttribution],
        )?.videoId,
        'cidro-asmoro-no-attribution',
      );
    });

    test('requires Spotify primary artist for a multi-artist collaboration', () {
      const collaboration = SpotifyPlaylistTrack(
        title: 'Dumes',
        artists: ['OMWAWES', 'Guyon Waton'],
      );
      final secondaryOnly = candidate(
        id: 'secondary-only',
        title: 'Guyon Waton - Dumes (Official Audio)',
        channel: 'Guyon Waton',
      );
      final primaryCredited = candidate(
        id: 'both-credits',
        title: 'OMWAWES, Guyon Waton - Dumes (Official Audio)',
        channel: 'Music Label',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(collaboration, [secondaryOnly]),
        isNull,
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(collaboration, [primaryCredited])?.videoId,
        'both-credits',
      );
    });

    test('supports a non-essential one-letter prefix in artist metadata', () {
      const spotifyTrackWithPrefix = SpotifyPlaylistTrack(
        title: 'Mencintai Dengan Ngeyel',
        artists: ['E Woro Widowati'],
      );
      final officialArtistChannel = candidate(
        id: 'woro-widowati',
        title: 'Mencintai Dengan Ngeyel (Official Music Video)',
        channel: 'Woro Widowati',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrackWithPrefix,
          [officialArtistChannel],
        )?.videoId,
        'woro-widowati',
      );
    });

    test('supports a one-letter artist prefix for a single-word artist name', () {
      const track = SpotifyPlaylistTrack(
        title: 'Tresno Liyane',
        artists: ['E Northsle', 'Agiff'],
      );
      final officialUpload = candidate(
        id: 'northsle-upload',
        title: 'Northsle - Tresno Liyane (Official Audio)',
        channel: 'Northsle',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [officialUpload])?.videoId,
        'northsle-upload',
      );
    });

    test('keeps meaningful parenthetical subtitle text in long song titles', () {
      const track = SpotifyPlaylistTrack(
        title: 'Koyo Jogja Istimewa - From Cidro Asmoro',
        artists: ['Ndarboy Genk'],
      );
      final candidateWithSubtitle = candidate(
        id: 'cidro-asmoro',
        title: 'Ndarboy Genk - Koyo Jogja Istimewa (From Cidro Asmoro) [Official Video]',
        channel: 'Ndarboy Genk',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [candidateWithSubtitle])?.videoId,
        'cidro-asmoro',
      );
    });

    test('overrides imported display metadata with exact Spotify title and artists', () {
      final youtubeResult = candidate(
        id: 'canonical-display',
        title: 'Denny Caknan - Cundamani (Official Music Video)',
        channel: 'Musica Studios',
      );
      const spotifyResult = SpotifyPlaylistTrack(
        title: 'Cundamani',
        artists: ['Denny Caknan'],
      );

      final imported = SpotifyYoutubeTrackMatcher.applySpotifyMetadata(
        spotifyResult,
        youtubeResult,
      );

      expect(imported.videoId, 'canonical-display');
      expect(imported.title, 'Cundamani');
      expect(imported.channelTitle, 'Denny Caknan');
      expect(imported.channelId, youtubeResult.channelId);
    });

    test('preserves all Spotify collaborator names for imported playlist display', () {
      const spotifyTrack = SpotifyPlaylistTrack(
        title: 'Dumes',
        artists: ['OMWAWES', 'Guyon Waton'],
      );
      final youtubeResult = candidate(
        id: 'dumes-official',
        title: 'OMWAWES, Guyon Waton - Dumes (Official Audio)',
        channel: 'Music Label',
      );

      final imported = SpotifyYoutubeTrackMatcher.applySpotifyMetadata(
        spotifyTrack,
        youtubeResult,
      );

      expect(imported.title, 'Dumes');
      expect(imported.channelTitle, 'OMWAWES, Guyon Waton');
      expect(imported.videoId, 'dumes-official');
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
        artists: ['Nadin Amizah', 'Hindia'],
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

  group('YouTube official music metadata parser', () {
    test('extracts artist and album from an auto-generated music description', () {
      const description = '''
Provided to YouTube by Believe SAS

Cundamani · Denny Caknan
Album: Cundamani
Released on: 2023-07-17
Auto-generated by YouTube.
''';
      final metadata = YoutubeMusicMetadataParser.parse(
        title: 'Cundamani (Official Audio)',
        description: description,
      );
      expect(metadata.artistName, 'Denny Caknan');
      expect(metadata.album, 'Cundamani');
    });

    test('does not trust artist names in an ordinary promotional description', () {
      final metadata = YoutubeMusicMetadataParser.parse(
        title: 'Cundamani',
        description: 'Provided to YouTube by Believe SAS\nSubscribe to Denny Caknan and listen now.',
      );
      expect(metadata.artistName, isEmpty);
      expect(metadata.album, isEmpty);
    });

    test('requires the embedded title line to match before taking artist credit', () {
      final metadata = YoutubeMusicMetadataParser.parse(
        title: 'Satru',
        description: 'Provided to YouTube by Label\nCundamani · Denny Caknan',
      );
      expect(metadata.artistName, isEmpty);
    });

    test('parses soundtrack source suffix and keeps primary credited performer', () {
      final metadata = YoutubeMusicMetadataParser.parse(
        title: 'Koyo Jogja Istimewa - From "Cidro Asmoro"',
        description: 'Provided to YouTube by Label\n'
            'Koyo Jogja Istimewa · Ndarboy Genk, Niken Salindry\n'
            'Album: Cidro Asmoro',
      );
      expect(metadata.artistName, 'Ndarboy Genk');
      expect(metadata.album, 'Cidro Asmoro');
    });

    test('uses the first artist from explicit collaborative credits', () {
      final metadata = YoutubeMusicMetadataParser.parse(
        title: 'Satru',
        description: 'Provided to YouTube by Label\n'
            'Artist: Denny Caknan, Happy Asmara\n'
            'Album: Satru',
      );
      expect(metadata.artistName, 'Denny Caknan');
    });
  });


  group('Spotify public embed count metadata', () {
    test('reads an advertised count above the visible embed rows', () {
      final trackList = List<Map<String, dynamic>>.generate(100, (index) {
        final id = index.toString().padLeft(22, '0');
        return <String, dynamic>{
          'uri': 'spotify:track:$id',
          'title': 'Track $index',
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
                  'totalLength': 145,
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
      expect(snapshot.tracks, hasLength(100));
      expect(snapshot.totalTrackCount, 145);
      expect(snapshot.knownMissingTrackCount, 45);
    });

    test('uses a public embed description count only when it exceeds visible rows', () {
      final trackList = List<Map<String, dynamic>>.generate(100, (index) {
        final id = index.toString().padLeft(22, '0');
        return <String, dynamic>{
          'uri': 'spotify:track:$id',
          'title': 'Track $index',
          'subtitle': 'Artist $index',
          'duration': 180000,
          'entityType': 'track',
        };
      });
      final payload = <String, dynamic>{
        'entity': <String, dynamic>{
          'type': 'playlist',
          'name': 'Large playlist',
          'trackList': trackList,
        },
      };
      final html = '<html><head><meta property="og:description" '
          'content="A playlist with 152 songs" /></head><body>'
          '<script id="__NEXT_DATA__" type="application/json">'
          '${jsonEncode(payload)}</script></body></html>';
      final snapshot = SpotifyPlaylistImportService.parseEmbedHtml(
        html,
        playlistId: '12345678901234567890',
        sourceUrl: 'https://open.spotify.com/playlist/12345678901234567890',
      );
      expect(snapshot.totalTrackCount, 152);
      expect(snapshot.knownMissingTrackCount, 52);
    });


    test('keeps the largest advertised total across embed payload scripts', () {
      final trackList = List<Map<String, dynamic>>.generate(100, (index) {
        final id = index.toString().padLeft(22, '0');
        return <String, dynamic>{
          'uri': 'spotify:track:$id',
          'title': 'Track $index',
          'subtitle': 'Artist $index',
          'duration': 180000,
          'entityType': 'track',
        };
      });
      final previewPayload = <String, dynamic>{
        'entity': <String, dynamic>{
          'type': 'playlist',
          'totalCount': 100,
          'trackList': trackList,
        },
      };
      final fullCountPayload = <String, dynamic>{
        'entity': <String, dynamic>{
          'type': 'playlist',
          'totalTrackCount': 168,
          'trackList': trackList,
        },
      };
      final html = '<html><body>'
          '<script type="application/json">${jsonEncode(previewPayload)}</script>'
          '<script type="application/json">${jsonEncode(fullCountPayload)}</script>'
          '</body></html>';
      final snapshot = SpotifyPlaylistImportService.parseEmbedHtml(
        html,
        playlistId: '12345678901234567890',
        sourceUrl: 'https://open.spotify.com/playlist/12345678901234567890',
      );
      expect(snapshot.tracks, hasLength(100));
      expect(snapshot.totalTrackCount, 168);
      expect(snapshot.knownMissingTrackCount, 68);
    });
  });


  group('Verified album cover selection', () {
    test('selects the highest-resolution approved front cover only', () {
      final selected = AlbumArtworkService.selectApprovedFrontImageUrl([
        {
          'approved': false,
          'front': true,
          'thumbnails': {'1200': 'https://covers.example/unapproved.jpg'},
        },
        {
          'approved': true,
          'front': false,
          'types': ['Back'],
          'thumbnails': {'1200': 'https://covers.example/back.jpg'},
        },
        {
          'approved': true,
          'front': true,
          'thumbnails': {
            '250': 'https://covers.example/front-250.jpg',
            '500': 'https://covers.example/front-500.jpg',
            '1200': 'https://covers.example/front-1200.jpg',
          },
        },
      ]);
      expect(selected, 'https://covers.example/front-1200.jpg');
    });

    test('does not return unapproved or back-cover images', () {
      final selected = AlbumArtworkService.selectApprovedFrontImageUrl([
        {
          'approved': false,
          'front': true,
          'image': 'https://covers.example/unapproved.jpg',
        },
        {
          'approved': true,
          'front': false,
          'types': ['Back'],
          'image': 'https://covers.example/back.jpg',
        },
      ]);
      expect(selected, isNull);
    });
  });

  group('YouTube artwork thumbnail selection', () {
    test('prefers max-resolution thumbnails for song artwork', () {
      final url = YoutubeSearchResponseParser.pickThumbnail({
        'default': {'url': 'https://img.example/default.jpg'},
        'medium': {'url': 'https://img.example/medium.jpg'},
        'high': {'url': 'https://img.example/high.jpg'},
        'maxres': {'url': 'https://img.example/maxres.jpg'},
      });
      expect(url, 'https://img.example/maxres.jpg');
    });
  });

}
