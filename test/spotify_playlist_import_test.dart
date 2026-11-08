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
        spotifyTrackId: 'spotify-satru-recording',
        durationMs: 282000,
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
      expect(imported.sourceChannelTitle, 'Music Label - Topic');
      expect(imported.sourceVideoTitle, 'Satru Official Audio');
      expect(imported.spotifyTrackId, 'spotify-satru-recording');
      expect(imported.spotifyDurationMs, 282000);
      final restored = YoutubeSearchResult.fromJson(imported.toJson());
      expect(restored.sourceChannelTitle, 'Music Label - Topic');
      expect(restored.sourceVideoTitle, 'Satru Official Audio');
      expect(restored.spotifyTrackId, 'spotify-satru-recording');
      expect(restored.spotifyDurationMs, 282000);
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
      int? viewCount,
      String musicDataTitle = '',
      String musicDataArtist = '',
    }) => YoutubeSearchResult(
          videoId: id,
          title: title,
          channelTitle: channel,
          description: description,
          thumbnailUrl: '',
          durationSeconds: durationSeconds,
          viewCount: viewCount,
          musicDataTitle: musicDataTitle,
          musicDataArtist: musicDataArtist,
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

    test('prefers the artist channel over an official-title label fallback', () {
      final labelFallback = candidate(
        id: 'label-fallback',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Musica Studios',
      );
      final artistChannel = candidate(
        id: 'artist-channel-priority',
        title: 'Celengan Rindu',
        channel: 'Fiersa Besari',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [labelFallback, artistChannel],
        )?.videoId,
        'artist-channel-priority',
      );
      expect(
        SpotifyYoutubeTrackMatcher.hasPreferredOfficialMatch(
          spotifyTrack,
          [labelFallback],
        ),
        isFalse,
      );
    });

    test('keeps searching after finding a structured label release', () {
      final labelRelease = candidate(
        id: 'structured-label-first',
        title: 'Celengan Rindu (Official Audio)',
        channel: 'Musica Studios',
        description: 'Provided to YouTube by Musica Studios\n'
            'Celengan Rindu · Fiersa Besari\n'
            'Auto-generated by YouTube.',
      );
      final artistChannel = candidate(
        id: 'artist-channel-later',
        title: 'Celengan Rindu',
        channel: 'Fiersa Besari',
      );

      expect(
        SpotifyYoutubeTrackMatcher.hasPreferredOfficialMatch(
          spotifyTrack,
          [labelRelease],
        ),
        isFalse,
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [labelRelease, artistChannel],
        )?.videoId,
        'artist-channel-later',
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

    test('does not trust a channel that only appends a known label name', () {
      final spoofedLabel = candidate(
        id: 'spoofed-label',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Musica Studios Backup',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [spoofedLabel]),
        isNull,
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


    test('rejects a matching title and copied artist name from an unknown uploader', () {
      final copiedTitleMirror = candidate(
        id: 'copied-title-mirror',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Lagu Viral 2026',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [copiedTitleMirror]),
        isNull,
      );
    });


    test('rejects a known label channel when there is no official upload or distributor credit', () {
      final labelMirror = candidate(
        id: 'label-mirror-without-credits',
        title: 'Fiersa Besari - Celengan Rindu',
        channel: 'Musica Studios',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [labelMirror]),
        isNull,
      );
    });

    test('does not accept a lyric or tribute channel as an official source', () {
      final lyricChannel = candidate(
        id: 'lyrics-channel',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Fiersa Besari Lyrics Channel',
      );
      final tributeChannel = candidate(
        id: 'tribute-channel',
        title: 'Fiersa Besari - Celengan Rindu (Official Music Video)',
        channel: 'Fiersa Besari Tribute',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [lyricChannel, tributeChannel],
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
            'Celengan Rindu · Fiersa Besari · ℗ Musica Studios\n'
            'Auto-generated by YouTube.',
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
        description: 'Provided to YouTube by Musica Studios\n'
            'Celengan Rindu · Fiersa Besari\n'
            'Artist: Fiersa Besari\n'
            'Auto-generated by YouTube.',
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
        title: 'Celengan Rindu (Official Audio)',
        channel: 'Fiersa Besari',
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

    test('accepts a Spotify-credited collaborator when the duet upload is under their channel', () {
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
        channel: 'Independent Distributor',
        description: 'Provided to YouTube by Independent Distributor\n'
            'Dumes · OMWAWES · Guyon Waton\n'
            'Dumes · OMWAWES · Guyon Waton · ℗ Independent Distributor\n'
            'Auto-generated by YouTube.',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(collaboration, [secondaryOnly])?.videoId,
        'secondary-only',
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
      expect(imported.sourceChannelTitle, 'Musica Studios');
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

    test('builds title-only and artist/title search fallbacks without feat suffix noise', () {
      const track = SpotifyPlaylistTrack(
        title: 'Song Name (feat. Guest Artist)',
        artists: ['Main Artist', 'Guest Artist'],
      );

      final queries = SpotifyYoutubeTrackMatcher.buildSearchQueries(track);

      expect(queries, contains('Main Artist Song Name'));
      expect(queries, contains('Song Name Main Artist'));
      expect(queries, contains('Song Name'));
      expect(queries.any((query) => query == 'Song Name Guest Artist'), isFalse);
    });

    test('builds a compact first-pass query set for fast Spotify imports', () {
      const track = SpotifyPlaylistTrack(
        title: 'Satru 2 (feat. Happy Asmara)',
        artists: ['Denny Caknan', 'Happy Asmara'],
      );

      expect(
        SpotifyYoutubeTrackMatcher.buildFastSearchQueries(track),
        ['Denny Caknan Satru 2', 'Happy Asmara Satru 2', 'Satru 2'],
      );
    });

    test('only stops the fast pass for a corroborated original, not a cover', () {
      const track = SpotifyPlaylistTrack(
        title: 'Nemen',
        artists: ['Guyon Waton'],
        durationMs: 260000,
      );
      final official = candidate(
        id: 'nemen-fast-official',
        title: 'Nemen (Official Music Video)',
        channel: 'GUYONWATON OFFICIAL',
        durationSeconds: 260,
      );
      final cover = candidate(
        id: 'nemen-fast-cover',
        title: 'Nemen',
        channel: 'Independent Cover Channel',
        durationSeconds: 260,
        viewCount: 20000,
      );

      expect(
        SpotifyYoutubeTrackMatcher.hasHighConfidenceMatch(track, [official]),
        isTrue,
      );
      expect(
        SpotifyYoutubeTrackMatcher.hasHighConfidenceMatch(track, [cover]),
        isFalse,
      );
    });

    test('matches a one-character song title when artist identity is verified', () {
      const track = SpotifyPlaylistTrack(
        title: 'A',
        artists: ['Artist One'],
        durationMs: 182000,
      );
      final officialUpload = candidate(
        id: 'one-letter-song',
        title: 'Artist One - A (Official Audio)',
        channel: 'Artist One',
        durationSeconds: 182,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [officialUpload])?.videoId,
        'one-letter-song',
      );
    });

    test('matches the core song when Spotify title has a featured-artist suffix', () {
      const track = SpotifyPlaylistTrack(
        title: 'Song Name (feat. Guest Artist)',
        artists: ['Main Artist', 'Guest Artist'],
      );
      final officialUpload = candidate(
        id: 'featured-song',
        title: 'Main Artist - Song Name (Official Audio)',
        channel: 'Main Artist',
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [officialUpload])?.videoId,
        'featured-song',
      );
      expect(
        SpotifyYoutubeTrackMatcher.applySpotifyMetadata(track, officialUpload).title,
        'Song Name (feat. Guest Artist)',
      );
    });

    test('accepts exact YouTube Music song and artist metadata without a view threshold', () {
      final structuredRelease = candidate(
        id: 'structured-low-view-release',
        title: 'Celengan Rindu',
        channel: 'Independent Distributor',
        musicDataTitle: 'Celengan Rindu',
        musicDataArtist: 'Fiersa Besari',
        viewCount: 1200,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [structuredRelease],
        )?.videoId,
        'structured-low-view-release',
      );
    });

    test('accepts a parsed YouTube distributor artist credit without a view threshold', () {
      final parsedCreditRelease = YoutubeSearchResult(
        videoId: 'parsed-credit-release',
        title: 'Celengan Rindu',
        channelTitle: 'Independent Music Channel',
        artistName: 'Fiersa Besari',
        thumbnailUrl: '',
        durationSeconds: 248,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [parsedCreditRelease],
        )?.videoId,
        'parsed-credit-release',
      );
    });

    test('collects up to eight likely Spotify candidates for metadata enrichment', () {
      final candidates = List<YoutubeSearchResult>.generate(
        10,
        (index) => candidate(
          id: 'metadata-candidate-$index',
          title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
          channel: 'Music Distributor $index',
          viewCount: 10000 + index,
        ),
      );

      expect(
        SpotifyYoutubeTrackMatcher.metadataLookupCandidates(
          spotifyTrack,
          candidates,
        ),
        hasLength(8),
      );
    });

    test('allows a popular exact-title third-party upload with explicit artist credit', () {
      final popularRelease = candidate(
        id: 'popular-third-party-original',
        title: 'Fiersa Besari - Celengan Rindu',
        channel: 'Musik Populer Indonesia',
        viewCount: 250000,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [popularRelease],
        )?.videoId,
        'popular-third-party-original',
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

    test('accepts popular third-party upload only with exact structured MusicData credit', () {
      final popularIndependentUpload = candidate(
        id: 'popular-independent-upload',
        title: 'Celengan Rindu',
        channel: 'Musik Populer Nusantara',
        viewCount: 850000,
        musicDataTitle: 'Celengan Rindu',
        musicDataArtist: 'Fiersa Besari',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [popularIndependentUpload],
        )?.videoId,
        'popular-independent-upload',
      );
    });

    test('popular third-party upload is accepted only with exact title and artist in title', () {
      final popularThirdParty = candidate(
        id: 'popular-third-party',
        title: 'Fiersa Besari - Celengan Rindu',
        channel: 'Musik Viral Nusantara',
        viewCount: 900000,
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [popularThirdParty])?.videoId,
        'popular-third-party',
      );
    });

    test('rejects a title-copy upload when structured MusicData credits another singer', () {
      final mismatchedStructuredCredit = candidate(
        id: 'copied-title-wrong-musicdata-artist',
        title: 'Fiersa Besari - Celengan Rindu (Official Audio)',
        channel: 'Viral Music Archive',
        viewCount: 9500000,
        musicDataTitle: 'Celengan Rindu',
        musicDataArtist: 'Penyanyi Lain',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          spotifyTrack,
          [mismatchedStructuredCredit],
        ),
        isNull,
      );
    });

    test('accepts a matching structured credit when Spotify adds a genre suffix', () {
      const reggaeTrack = SpotifyPlaylistTrack(
        title: 'TAMU UNDANGAN - Reggae',
        artists: ['Niken Salindry'],
      );
      final officialUpload = candidate(
        id: 'tamu-undangan-reggae-official',
        title: 'Niken Salindry - TAMU UNDANGAN (Reggae) Official Music Video',
        channel: 'Niken Salindry Official',
        musicDataTitle: 'Tamu Undangan',
        musicDataArtist: 'Niken Salindry',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(reggaeTrack, [officialUpload])?.videoId,
        'tamu-undangan-reggae-official',
      );
    });

    test('finds Dian Anic - Kecewa from the Musik Proaktif official video', () {
      const track = SpotifyPlaylistTrack(
        title: 'Kecewa',
        artists: ['Dian Anic'],
        durationMs: 386000,
      );
      const officialLabelUpload = YoutubeSearchResult(
        videoId: 'dian-anic-kecewa-official',
        title: 'Dian Anic - Kecewa (Official Music Video)',
        channelTitle: 'Musik Proaktif',
        description: 'Video klip terbaru Dian Anic yang berjudul Kecewa.\n'
            'Title: Kecewa\nArtist : Dian Anic\n'
            'Label : PT. Media Musik Proaktif',
        thumbnailUrl: '',
        durationSeconds: 386,
        viewCount: 6218578,
      );

      expect(YoutubeMusicPolicy.isSpotifyImportCandidate(officialLabelUpload), isTrue);
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [officialLabelUpload])?.videoId,
        'dian-anic-kecewa-official',
      );
    });

    test('uses a clearly attributed cover only when the original is unavailable', () {
      const track = SpotifyPlaylistTrack(
        title: 'Kecewa',
        artists: ['Dian Anic'],
        durationMs: 386000,
      );
      const coverUpload = YoutubeSearchResult(
        videoId: 'kecewa-fanny-sabila-cover',
        title: 'KECEWA - DIAN ANIC [SOSOK] | COVER BY FANNY SABILA',
        channelTitle: 'fannysabila official',
        description: 'DIAN ANIC - KECEWA\nVOCAL COVER: FANNY SABILA',
        thumbnailUrl: '',
        durationSeconds: 353,
        viewCount: 5983261,
      );

      expect(YoutubeMusicPolicy.isSpotifyImportCandidate(coverUpload), isTrue);
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [coverUpload])?.videoId,
        'kecewa-fanny-sabila-cover',
      );
    });

    test('prefers original label upload over a popular cover', () {
      const track = SpotifyPlaylistTrack(
        title: 'Kecewa',
        artists: ['Dian Anic'],
        durationMs: 386000,
      );
      const original = YoutubeSearchResult(
        videoId: 'kecewa-original',
        title: 'Dian Anic - Kecewa (Official Music Video)',
        channelTitle: 'Musik Proaktif',
        description: 'Title: Kecewa\nArtist: Dian Anic',
        thumbnailUrl: '',
        durationSeconds: 386,
        viewCount: 2000,
      );
      const cover = YoutubeSearchResult(
        videoId: 'kecewa-cover',
        title: 'KECEWA - DIAN ANIC | COVER BY FANNY SABILA',
        channelTitle: 'fannysabila official',
        description: 'VOCAL COVER: FANNY SABILA',
        thumbnailUrl: '',
        durationSeconds: 353,
        viewCount: 5983261,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [cover, original])?.videoId,
        'kecewa-original',
      );
    });

    test('finds Keloas from Global Musik Era Digital official live music upload', () {
      const track = SpotifyPlaylistTrack(
        title: 'Keloas',
        artists: ['Rena Movies', 'Ageng Music'],
        durationMs: 393000,
      );
      const officialLiveUpload = YoutubeSearchResult(
        videoId: 'keloas-rena-movies-ageng-music',
        title: 'Rena Movies ft Ageng Music - Keloas (Official Live Music)',
        channelTitle: 'Global Musik Era Digital',
        description: 'Official Live Music : Rena Movies ft Ageng Music - Keloas\n'
            'Artist : Rena Movies ft Ageng Music\nSongwriter : Yahya',
        thumbnailUrl: '',
        durationSeconds: 393,
        viewCount: 7431245,
      );

      expect(YoutubeMusicPolicy.isSpotifyImportCandidate(officialLiveUpload), isTrue);
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [officialLiveUpload])?.videoId,
        'keloas-rena-movies-ageng-music',
      );
      // It is an acceptable fallback, but it must not stop a deeper query
      // that may still find the studio/original release.
      expect(
        SpotifyYoutubeTrackMatcher.hasHighConfidenceMatch(
          track,
          [officialLiveUpload],
        ),
        isFalse,
      );
    });

    test('prefers studio original over a more popular official live recording', () {
      const track = SpotifyPlaylistTrack(
        title: 'Keloas',
        artists: ['Rena Movies', 'Ageng Music'],
        durationMs: 393000,
      );
      const liveUpload = YoutubeSearchResult(
        videoId: 'keloas-live-popular',
        title: 'Rena Movies ft Ageng Music - Keloas (Official Live Music)',
        channelTitle: 'Global Musik Era Digital',
        description: 'Artist: Rena Movies ft Ageng Music',
        thumbnailUrl: '',
        durationSeconds: 393,
        viewCount: 7000000,
      );
      const studioOriginal = YoutubeSearchResult(
        videoId: 'keloas-studio-original',
        title: 'Rena Movies ft Ageng Music - Keloas (Official Audio)',
        channelTitle: 'Rena Movies Official',
        description: 'Official audio release',
        thumbnailUrl: '',
        durationSeconds: 393,
        viewCount: 15000,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(
          track,
          [liveUpload, studioOriginal],
        )?.videoId,
        'keloas-studio-original',
      );
    });

    test('allows a Keloas cover as fallback when Spotify performer is not on the upload', () {
      const track = SpotifyPlaylistTrack(
        title: 'Keloas',
        artists: ['Dewi Kirana'],
        durationMs: 300000,
      );
      const coverUpload = YoutubeSearchResult(
        videoId: 'keloas-susi-ngapak-cover',
        title: 'KELOAS - SUSI NGAPAK (Live Cover x oQinawa)',
        channelTitle: 'Susi Ngapak Official',
        description: 'Original Song: Keloas. Vocal cover by Susi Ngapak.',
        thumbnailUrl: '',
        durationSeconds: 300,
        viewCount: 20000,
      );

      expect(YoutubeMusicPolicy.isSpotifyImportCandidate(coverUpload), isTrue);
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [coverUpload])?.videoId,
        'keloas-susi-ngapak-cover',
      );
    });

    test('cover fallback does not make karaoke or AI uploads importable', () {
      const karaoke = YoutubeSearchResult(
        videoId: 'keloas-karaoke',
        title: 'Keloas Karaoke Cover',
        channelTitle: 'Karaoke Channel',
        thumbnailUrl: '',
        durationSeconds: 300,
      );
      const aiCover = YoutubeSearchResult(
        videoId: 'keloas-ai-cover',
        title: 'Keloas AI Cover by Singer',
        channelTitle: 'AI Music',
        thumbnailUrl: '',
        durationSeconds: 300,
      );

      expect(YoutubeMusicPolicy.isSpotifyImportCandidate(karaoke), isFalse);
      expect(YoutubeMusicPolicy.isSpotifyImportCandidate(aiCover), isFalse);
    });


    test('matches official YouTube examples from the Javanese Spotify import report', () {
      final examples = <({SpotifyPlaylistTrack track, YoutubeSearchResult upload})>[
        (
          track: const SpotifyPlaylistTrack(
            title: 'Satru 2', artists: ['Denny Caknan', 'Happy Asmara'], durationMs: 280000,
          ),
          upload: candidate(
            id: 'satru-2-topic', title: 'Satru 2', channel: 'DENNY CAKNAN - Topic',
            description: 'Provided to YouTube by DC Production\n\n'
                'Satru 2 · Denny Caknan · Happy Asmara\nAlbum: Satru 2',
            durationSeconds: 280, viewCount: 1300000,
          ),
        ),
        (
          track: const SpotifyPlaylistTrack(
            title: 'Kartonyono Medot Janji', artists: ['Denny Caknan'], durationMs: 300000,
          ),
          upload: candidate(
            id: 'kartonyono-official',
            title: 'Denny Caknan - Kartonyono Medot Janji (Official Music Video)',
            channel: 'DENNY CAKNAN', durationSeconds: 300, viewCount: 320000000,
          ),
        ),
        (
          track: const SpotifyPlaylistTrack(title: 'Nemen', artists: ['Guyon Waton'], durationMs: 260000),
          upload: candidate(
            id: 'nemen-official', title: 'Nemen - Guyon Waton (Official Music Video)',
            channel: 'Guyon Waton Official', durationSeconds: 260, viewCount: 10000000,
          ),
        ),
        (
          track: const SpotifyPlaylistTrack(title: 'Bubrah', artists: ['Northsle', 'Agiff'], durationMs: 250000),
          upload: candidate(
            id: 'bubrah-official', title: 'Northsle feat. Agiff - Bubrah (Official Music Video)',
            channel: 'NorthSle', durationSeconds: 250, viewCount: 29000000,
          ),
        ),
        (
          track: const SpotifyPlaylistTrack(title: 'TAMU UNDANGAN - Reggae', artists: ['Niken Salindry'], durationMs: 235000),
          upload: candidate(
            id: 'tamu-undangan-topic', title: 'TAMU UNDANGAN (Reggae)',
            channel: 'Niken Salindry - Topic',
            description: 'Provided to YouTube by Berkarya Record\n\n'
                'TAMU UNDANGAN (Reggae) · Niken Salindry',
            durationSeconds: 235, viewCount: 23000000,
          ),
        ),
        (
          track: const SpotifyPlaylistTrack(title: 'Ora Ngemis Bali', artists: ['Lavora', 'Ratih SDE'], durationMs: 270000),
          upload: candidate(
            id: 'ora-ngemis-bali-official',
            title: 'Ora Ngemis Bali - LAVORA Ft Ratih SDE (Official Music Video)',
            channel: 'LAVORA Official', durationSeconds: 270, viewCount: 13000000,
          ),
        ),
        (
          track: const SpotifyPlaylistTrack(title: 'Sigar', artists: ['Denny Caknan'], durationMs: 270000),
          upload: candidate(
            id: 'sigar-official', title: 'Denny Caknan - Sigar (Official Music Video)',
            channel: 'DENNY CAKNAN', durationSeconds: 270, viewCount: 72000000,
          ),
        ),
        (
          track: const SpotifyPlaylistTrack(title: 'Anak Lanang', artists: ['Ndarboy Genk'], durationMs: 270000),
          upload: candidate(
            id: 'anak-lanang-official',
            title: 'Ndarboy Genk - Anak Lanang Original (Official Music Video)',
            channel: 'Ndarboy Genk', durationSeconds: 270, viewCount: 23000000,
          ),
        ),
        (
          track: const SpotifyPlaylistTrack(title: 'Nangisi Lungamu', artists: ['Aftershine'], durationMs: 280000),
          upload: candidate(
            id: 'nangisi-lungamu-official',
            title: 'Nangisi Lungamu - Aftershine ft Tiara Linggar (Official Music Video)',
            channel: 'AFTERSHINE Official', durationSeconds: 280, viewCount: 7400000,
          ),
        ),
      ];

      for (final example in examples) {
        expect(
          SpotifyYoutubeTrackMatcher.bestMatch(example.track, [example.upload])?.videoId,
          example.upload.videoId,
          reason: '${example.track.title} by ${example.track.artists.join(', ')} should match',
        );
      }
    });

    test('keeps the song title when YouTube places featured artists before it', () {
      const track = SpotifyPlaylistTrack(
        title: 'Bubrah',
        artists: ['Northsle', 'Agiff'],
        durationMs: 250000,
      );
      final officialUpload = candidate(
        id: 'bubrah-feature-before-title',
        title: 'Northsle feat. Agiff - Bubrah (Official Music Video)',
        channel: 'NorthSle Official Artist Channel',
        durationSeconds: 250,
        viewCount: 29000000,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [officialUpload])?.videoId,
        'bubrah-feature-before-title',
        reason: 'featured artist prefix must not erase the actual song title',
      );
    });

    test('matches a multi-artist release when all credits precede the title', () {
      const track = SpotifyPlaylistTrack(
        title: 'Salam Dariku',
        artists: ['Didik Budi', 'Cindi Cintya', 'Fywrizki', 'Cantika'],
        durationMs: 240000,
      );
      final officialUpload = candidate(
        id: 'salam-dariku-multi-credit',
        title: 'Didik Budi feat. Cindi Cintya, Fywrizki & Cantika - Salam Dariku (Official Music Video)',
        channel: 'Didik Budi Official',
        durationSeconds: 240,
        viewCount: 1200000,
      );

      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [officialUpload])?.videoId,
        'salam-dariku-multi-credit',
      );
    });

    test('accepts an unlabelled third-party upload with exact artist, title, and duration', () {
      const track = SpotifyPlaylistTrack(
        title: 'Nemen',
        artists: ['Guyon Waton'],
        durationMs: 260000,
      );
      final unlabelledRelease = candidate(
        id: 'nemen-third-party-duration-match',
        title: 'Guyon Waton - Nemen',
        channel: 'Regional Music Archive',
        durationSeconds: 260,
        viewCount: 4500,
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [unlabelledRelease])?.videoId,
        'nemen-third-party-duration-match',
      );
    });

    test('matches NDX A.K.A. when YouTube formats the abbreviation as NDX AKA', () {
      const track = SpotifyPlaylistTrack(
        title: 'Kelingan Mantan',
        artists: ['NDX A.K.A.'],
      );
      final upload = candidate(
        id: 'ndx-aka-kelingan-mantan',
        title: 'NDX AKA - Kelingan Mantan (Official Music Video)',
        channel: 'NDX AKA Official',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [upload])?.videoId,
        'ndx-aka-kelingan-mantan',
      );
    });

    test('matches concatenated official channel names such as GUYONWATON', () {
      const track = SpotifyPlaylistTrack(
        title: 'Nemen',
        artists: ['Guyon Waton'],
      );
      final upload = candidate(
        id: 'guyonwaton-nemen-topic-style',
        title: 'Nemen (Official Music Video)',
        channel: 'GUYONWATON OFFICIAL',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [upload])?.videoId,
        'guyonwaton-nemen-topic-style',
      );
    });

    test('does not use a live concert recording for a studio Spotify track', () {
      final liveVersion = candidate(
        id: 'studio-track-live-concert',
        title: 'Fiersa Besari - Celengan Rindu (Live Concert)',
        channel: 'Fiersa Besari',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [liveVersion]),
        isNull,
      );
    });

    test('searches each Spotify collaborator separately', () {
      const track = SpotifyPlaylistTrack(
        title: 'Satru 2', artists: ['Denny Caknan', 'Happy Asmara'],
      );
      final queries = SpotifyYoutubeTrackMatcher.buildSearchQueries(track);
      expect(queries, contains('Happy Asmara Satru 2'));
      expect(queries, contains('Satru 2 Happy Asmara'));
    });

    test('fast search includes punctuation-free NDX A.K.A. aliases', () {
      const track = SpotifyPlaylistTrack(
        title: 'Kelingan Mantan',
        artists: ['NDX A.K.A.'],
      );
      final fastQueries = SpotifyYoutubeTrackMatcher.buildFastSearchQueries(track);
      expect(fastQueries, contains('NDX A.K.A. Kelingan Mantan'));
      expect(fastQueries, contains('NDX AKA Kelingan Mantan'));
      expect(fastQueries, contains('NDXAKA Kelingan Mantan'));
      final fullQueries = SpotifyYoutubeTrackMatcher.buildSearchQueries(track);
      expect(fullQueries, contains('NDX AKA Kelingan Mantan'));
    });

    test('does not let a viral cover stop the search for the original', () {
      const track = SpotifyPlaylistTrack(
        title: 'Kelingan Mantan',
        artists: ['NDX A.K.A.'],
        durationMs: 270000,
      );
      final cover = candidate(
        id: 'ndx-cover',
        title: 'Kelingan Mantan - Cover by Another Singer',
        channel: 'Viral Cover Official',
        durationSeconds: 270,
        viewCount: 9000000,
      );
      expect(
        SpotifyYoutubeTrackMatcher.hasHighConfidenceMatch(track, [cover]),
        isFalse,
      );
    });

    test('rejects an artist-channel remix even when title and channel match', () {
      const track = SpotifyPlaylistTrack(
        title: 'Apa Kabar Mantan',
        artists: ['NDX A.K.A.'],
        durationMs: 270000,
      );
      final remix = candidate(
        id: 'ndx-remix',
        title: 'NDX AKA - Apa Kabar Mantan (Official Remix)',
        channel: 'NDX A.K.A. Official',
        durationSeconds: 270,
        viewCount: 2000000,
      );
      expect(YoutubeMusicPolicy.isSpotifyImportCandidate(remix), isTrue);
      expect(SpotifyYoutubeTrackMatcher.bestMatch(track, [remix]), isNull);
    });

    test('matches the full regional playlist sample when artist credits precede song titles', () {
      final tracks = <SpotifyPlaylistTrack>[
        const SpotifyPlaylistTrack(title: 'Satru 2', artists: ['Denny Caknan', 'Happy Asmara']),
        const SpotifyPlaylistTrack(title: 'Kartonyono Medot Janji', artists: ['Denny Caknan']),
        const SpotifyPlaylistTrack(title: 'Nemen', artists: ['Guyon Waton']),
        const SpotifyPlaylistTrack(title: 'Bubrah', artists: ['Northsle', 'Agiff']),
        const SpotifyPlaylistTrack(title: 'Gampil', artists: ['Guyon Waton']),
        const SpotifyPlaylistTrack(title: 'Sigar', artists: ['Denny Caknan']),
        const SpotifyPlaylistTrack(title: 'TAMU UNDANGAN - Reggae', artists: ['Niken Salindry']),
        const SpotifyPlaylistTrack(title: 'Ora Ngemis Bali', artists: ['Lavora', 'Ratih SDE']),
        const SpotifyPlaylistTrack(title: 'Kelingan Mantan', artists: ['NDX A.K.A.']),
        const SpotifyPlaylistTrack(title: 'Anak Lanang', artists: ['Ndarboy Genk']),
        const SpotifyPlaylistTrack(title: 'Nangisi Lungamu', artists: ['Aftershine']),
        const SpotifyPlaylistTrack(title: 'Lungaku', artists: ['Guyon Waton']),
        const SpotifyPlaylistTrack(title: 'Aku Cah Kerjo', artists: ['Pendhoza']),
        const SpotifyPlaylistTrack(title: 'Rasah Bali', artists: ['Lavora', 'Ena Vika']),
        const SpotifyPlaylistTrack(title: 'Apa Kabar Mantan', artists: ['NDX A.K.A.']),
        const SpotifyPlaylistTrack(title: 'Salam Dariku', artists: ['Didik Budi', 'Cindi Cintya', 'Fywrizki', 'Cantika']),
        const SpotifyPlaylistTrack(title: 'Menepi', artists: ['NGATMOMBILUNG']),
        const SpotifyPlaylistTrack(title: 'Nresnani', artists: ['Lavora', 'Damara De']),
        const SpotifyPlaylistTrack(title: 'Kelangan', artists: ['Guyon Waton']),
        const SpotifyPlaylistTrack(title: 'Sinarengan', artists: ['Denny Caknan', 'Bella Bonita']),
      ];

      for (var index = 0; index < tracks.length; index++) {
        final track = tracks[index];
        final creditedArtists = track.artists.join(' feat. ');
        final upload = candidate(
          id: 'regional-playlist-$index',
          title: '$creditedArtists - ${track.title} (Official Music Video)',
          channel: '${track.primaryArtist} Official',
        );
        expect(
          SpotifyYoutubeTrackMatcher.bestMatch(track, [upload])?.videoId,
          upload.videoId,
          reason: 'failed to match ${track.title} — ${track.artists.join(', ')}',
        );
      }
    });

    test('does not treat an unlabelled same-title upload as a cover without explicit attribution', () {
      const track = SpotifyPlaylistTrack(
        title: 'Nemen', artists: ['Guyon Waton'], durationMs: 260000,
      );
      final cover = candidate(
        id: 'nemen-unlabelled-cover', title: 'Nemen',
        channel: 'Independent Singer', durationSeconds: 260, viewCount: 1500,
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(track, [cover]),
        isNull,
      );
    });

    test('view count alone never authenticates a third-party uploader', () {
      final viralWrongTrack = candidate(
        id: 'viral-wrong-track',
        title: 'Lagu Viral Terbaru 2026',
        channel: 'Musik Viral 2026',
        viewCount: 9000000,
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [viralWrongTrack]),
        isNull,
      );
    });

    test('structured MusicData for a different singer is rejected even when popular', () {
      final wrongPerformer = candidate(
        id: 'wrong-structured-performer',
        title: 'Celengan Rindu',
        channel: 'Popular Music Channel',
        viewCount: 2000000,
        musicDataTitle: 'Celengan Rindu',
        musicDataArtist: 'Penyanyi Lain',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [wrongPerformer]),
        isNull,
      );
    });

    test('accepts exact structured MusicData for a low-view track upload', () {
      final lowViewTrackUpload = candidate(
        id: 'low-view-track-upload',
        title: 'Celengan Rindu',
        channel: 'Personal Music Uploads',
        viewCount: 1200,
        musicDataTitle: 'Celengan Rindu',
        musicDataArtist: 'Fiersa Besari',
      );
      expect(
        SpotifyYoutubeTrackMatcher.bestMatch(spotifyTrack, [lowViewTrackUpload])?.videoId,
        'low-view-track-upload',
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
