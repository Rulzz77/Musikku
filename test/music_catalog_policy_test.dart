import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/youtube_music_policy.dart';
import 'package:flutter_application_5/services/youtube_search_response_parser.dart';
import 'package:flutter_application_5/services/youtube_search_query.dart';

YoutubeSearchResult _track({
  required String title,
  required String channel,
  double? duration = 220,
  String categoryId = '',
  String description = '',
}) {
  return YoutubeSearchResult(
    videoId: 'abcdefghijk',
    title: title,
    channelTitle: channel,
    thumbnailUrl: '',
    durationSeconds: duration,
    categoryId: categoryId,
    description: description,
  );
}

void main() {
  group('query-aware artist music catalogue', () {
    test(
      'accepts a normal single from an artist-named channel without official labels',
      () {
        final track = _track(
          title: 'Celengan Rindu',
          channel: 'Fiersa Besari',
        );

        expect(
          YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
            track,
            query: 'Fiersa Besari',
          ),
          isTrue,
        );
      },
    );

    test(
      'accepts an artist credited in the title when the upload channel is a label',
      () {
        final labelRelease = _track(
          title: 'Fiersa Besari - Celengan Rindu',
          channel: 'Independent Upload Channel',
        );
        expect(
          YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
            labelRelease,
            query: 'Fiersa Besari',
          ),
          isTrue,
        );
      },
    );

    test(
      'accepts artist credit after the track title on an official label upload',
      () {
        final labelRelease = _track(
          title: 'Celengan Rindu - Fiersa Besari',
          channel: 'Bintang Lokal',
        );
        expect(
          YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
            labelRelease,
            query: 'Fiersa Besari',
          ),
          isTrue,
        );
      },
    );

    test(
      'supports common Indonesian artist channels, not only Fiersa Besari',
      () {
        for (final artist in ['Fiersa Besari', 'Tulus', 'Raisa', 'Hindia']) {
          final track = _track(title: 'Single Resmi', channel: artist);
          expect(
            YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
              track,
              query: artist,
            ),
            isTrue,
            reason: 'Expected a normal release from $artist to be retained',
          );
        }
      },
    );

    test('keeps cached songs when one result has no channelId metadata', () {
      final restored = YoutubeSearchResponseParser.resultsFromJson([
        _track(
          title: 'Celengan Rindu',
          channel: 'Fiersa Besari',
        ).toJson(),
      ]);

      expect(restored, hasLength(1));
      expect(restored.single.title, 'Celengan Rindu');
      expect(restored.single.channelId, isEmpty);
    });

    test('does not force Indonesia onto known artist queries', () {
      expect(
        YoutubeSearchQueryParser.interpret('Fiersa Besari songs').apiQuery,
        'Fiersa Besari songs',
      );
      expect(
        YoutubeSearchQueryParser.interpret('Billie Eilish song').apiQuery,
        'Billie Eilish song',
      );
      expect(
        YoutubeSearchQueryParser.interpret('lagu pop').apiQuery,
        'lagu pop Indonesia',
      );
    });

    test('does not localize unknown international artist searches to Indonesia', () {
      for (final query in [
        'NewJeans songs',
        'Ethel Cain music',
        'The Last Dinner Party songs',
      ]) {
        expect(
          YoutubeSearchQueryParser.interpret(query).apiQuery,
          query,
          reason: 'Artist query should remain global: $query',
        );
      }
    });

    test('only adds Indonesia to a generic genre query, not a specific title', () {
      expect(
        YoutubeSearchQueryParser.interpret('lagu pop').apiQuery,
        'lagu pop Indonesia',
      );
      expect(
        YoutubeSearchQueryParser.interpret('rock music').apiQuery,
        'rock music',
      );
      expect(
        YoutubeSearchQueryParser.interpret('K-pop songs latest').apiQuery,
        'K-pop songs latest',
      );
      expect(
        YoutubeSearchQueryParser.interpret('Monokrom song').apiQuery,
        'Monokrom song',
      );
    });

    test('removes search qualifiers before matching the artist channel', () {
      final track = _track(
        title: 'Waktu Yang Salah',
        channel: 'Fiersa Besari',
      );

      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari songs official audio',
        ),
        isTrue,
      );
    });

    test('keeps normal songs in generic genre queries without official labels', () {
      final track = _track(
        title: 'Monokrom',
        channel: 'Tulus',
        duration: 240,
      );

      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Pop Indonesia',
        ),
        isTrue,
      );
    });

    test('does not accept an unrelated channel for an artist search', () {
      final track = _track(
        title: 'Celengan Rindu',
        channel: 'Fan Music Channel',
      );

      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari',
        ),
        isFalse,
      );
    });

    test(
      'does not admit an album-length result from a matching artist channel',
      () {
        final track = _track(
          title: 'Full Album - Semua Lagu',
          channel: 'Fiersa Besari',
          duration: 3600,
        );

        expect(
          YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
            track,
            query: 'Fiersa Besari',
          ),
          isFalse,
        );
      },
    );

    test('rejects album labels even if duration metadata looks like a single', () {
      final track = _track(
        title: 'Full Album - Semua Lagu',
        channel: 'Fiersa Besari',
        duration: 240,
      );

      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari',
        ),
        isFalse,
      );
    });


    test('accepts official artist-channel singles without official keywords', () {
      for (final entry in <({String artist, String title})>[
        (artist: 'Fiersa Besari', title: 'Celengan Rindu'),
        (artist: 'Tulus', title: 'Monokrom'),
        (artist: 'Raisa', title: 'Kali Kedua'),
        (artist: 'Hindia', title: 'Evaluasi'),
        (artist: 'Billie Eilish', title: 'What Was I Made For?'),
        (artist: 'Adele', title: 'Easy On Me'),
        (artist: 'Coldplay', title: 'Yellow'),
        (artist: 'Taylor Swift', title: 'Anti-Hero'),
        (artist: 'BTS', title: 'Spring Day'),
      ]) {
        final track = _track(title: entry.title, channel: entry.artist);
        expect(
          YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
            track,
            query: entry.artist,
          ),
          isTrue,
          reason: 'Official single by ${entry.artist} should not need an Official label',
        );
      }
    });

    test('accepts genre search singles without an official label marker', () {
      final track = _track(
        title: 'Monokrom',
        channel: 'Tulus',
        duration: 240,
      );
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'lagu pop Indonesia official music video',
        ),
        isTrue,
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
    });

    test('YouTube Music category is a positive signal without Official text', () {
      final track = _track(
        title: 'Easy On Me',
        channel: 'Adele',
        categoryId: '10',
      );
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate(track), isTrue);
      expect(YoutubeMusicPolicy.isMusicCatalogItem(track), isTrue);
    });

    test('keeps valid song when search duration metadata is missing', () {
      final track = _track(
        title: 'Yellow',
        channel: 'Coldplay',
        duration: null,
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Coldplay',
        ),
        isTrue,
      );
    });

    test('does not confuse a legitimate song title containing Cover with a cover', () {
      final track = _track(
        title: 'Cover Me in Sunshine',
        channel: 'P!nk',
      );
      expect(YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(track), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
    });

    test('does not classify long official music videos as Shorts because of description tags', () {
      final track = _track(
        title: 'Monokrom Official Music Video',
        channel: 'Tulus',
        duration: 240,
        description: 'Follow us #Shorts #NewMusic',
      );
      expect(YoutubeMusicPolicy.isLikelyShortForm(track), isFalse);
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate(track), isTrue);
    });


    test('does not discard a normal single because its description has a Shorts hashtag', () {
      final track = _track(
        title: 'Evaluasi',
        channel: 'Hindia',
        duration: 120,
        description: 'Official release. Follow #Shorts for updates.',
      );
      expect(YoutubeMusicPolicy.isLikelyShortForm(track), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
    });

    test('rejects karaoke even when uploaded from the artist channel', () {
      final track = _track(
        title: 'Celengan Rindu Karaoke',
        channel: 'Fiersa Besari',
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isFalse);
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari',
        ),
        isFalse,
      );
    });

    test('rejects AI music even when its channel imitates an artist name', () {
      final track = _track(
        title: 'Monokrom AI Version',
        channel: 'Tulus Official',
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isFalse);
    });


    test('does not mistake a singer named Ai for AI-generated music', () {
      final track = _track(
        title: 'Sakura',
        channel: 'Ai Otsuka',
        duration: 240,
      );
      expect(YoutubeMusicPolicy.isLikelyAiGeneratedMusic(track), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Ai Otsuka',
        ),
        isTrue,
      );
    });

    test('keeps an artist-matched official track even when its category is not Music', () {
      final track = _track(
        title: 'Celengan Rindu',
        channel: 'Fiersa Besari',
        categoryId: '24',
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari',
        ),
        isTrue,
      );
    });

    test('rejects explicit cover uploads from channel and artist query paths', () {
      final track = _track(
        title: 'Monokrom (Cover by Fan Singer)',
        channel: 'Tulus',
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isFalse);
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(track, channelTitle: 'Tulus'),
        isFalse,
      );
    });


    test('rejects acoustic and song-cover title variants', () {
      for (final title in [
        'Celengan Rindu - Acoustic Cover',
        'Celengan Rindu Song Cover',
        'Cover of Celengan Rindu',
      ]) {
        final track = _track(title: title, channel: 'Fan Singer');
        expect(
          YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(track),
          isTrue,
          reason: 'Expected cover form to be rejected: $title',
        );
        expect(YoutubeMusicPolicy.isMusicCandidate(track), isFalse);
      }
    });

    test('rejects AI markers even when the marker appears in description', () {
      final track = _track(
        title: 'Yellow',
        channel: 'Coldplay',
        description: 'AI-generated voice clone version made with Suno AI',
      );
      expect(YoutubeMusicPolicy.isLikelyAiGeneratedMusic(track), isTrue);
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isFalse);
    });

    test('rejects cover uploads even when the cover marker is in description', () {
      final track = _track(
        title: 'Celengan Rindu',
        channel: 'Fan Singer',
        description: 'This is my acoustic cover of Celengan Rindu',
      );
      expect(YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(track), isTrue);
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari',
        ),
        isFalse,
      );
    });

    test('continues to reject covers even on the matching artist channel', () {
      final track = _track(
        title: 'Celengan Rindu (Cover)',
        channel: 'Fiersa Besari',
      );

      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari',
        ),
        isFalse,
      );
    });


    test('keeps a short official single from an artist channel without labels', () {
      final track = _track(
        title: 'Evaluasi',
        channel: 'Hindia',
        duration: 45,
      );
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Hindia',
        ),
        isTrue,
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          track,
          channelTitle: 'Hindia',
          channelDescription: 'Indonesian singer and songwriter',
        ),
        isTrue,
      );
    });

    test('does not reject song titles that merely contain album or playlist', () {
      final albumTitle = _track(title: 'Album', channel: 'The Artist');
      final playlistTitle = _track(title: 'Playlist', channel: 'The Artist');
      expect(YoutubeMusicPolicy.isMusicCandidate(albumTitle), isTrue);
      expect(YoutubeMusicPolicy.isMusicCandidate(playlistTitle), isTrue);
    });

    test('still rejects explicit comedy clips even when short', () {
      final clip = _track(
        title: 'Funny Moments Challenge',
        channel: 'Hindia',
        duration: 105,
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(clip), isFalse);
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          clip,
          query: 'Hindia',
        ),
        isFalse,
      );
    });

    test('does not reject original song because description links karaoke content', () {
      final track = _track(
        title: 'Monokrom Official Music Video',
        channel: 'Tulus',
        description: 'Official video. For karaoke fans, visit our separate channel.',
      );
      expect(YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(track), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
    });

    test('accepts artist credit in description without official channel words', () {
      final track = _track(
        title: 'Celengan Rindu',
        channel: 'Bintang Lokal',
        description: 'Single by Fiersa Besari. Original release.',
      );
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari',
        ),
        isTrue,
      );
    });


    test('does not reject official song titles containing talking or news', () {
      for (final title in ['Talking to the Moon', 'News', 'Review']) {
        final track = _track(
          title: title,
          channel: 'Bruno Mars',
          duration: 240,
        );
        expect(YoutubeMusicPolicy.isLikelyNonMusicVideo(track), isFalse);
        expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
      }
    });

    test('rejects an explicitly labelled reaction video', () {
      final clip = _track(
        title: 'Reaction Video: New Song',
        channel: 'Music Commentary',
        duration: 240,
      );
      expect(YoutubeMusicPolicy.isLikelyNonMusicVideo(clip), isTrue);
      expect(YoutubeMusicPolicy.isMusicCandidate(clip), isFalse);
    });

    test('does not reject a normal-length song titled Challenge', () {
      final track = _track(
        title: 'Challenge',
        channel: 'Artist Official',
        duration: 210,
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
    });

    test('keeps an original single whose description only mentions karaoke links', () {
      final track = _track(
        title: 'Easy On Me Official Music Video',
        channel: 'Adele',
        description: 'Listen to the official single. Karaoke channel links are below.',
      );
      expect(YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(track), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
    });


    test('does not return a different official artist for a specific artist query', () {
      final track = _track(
        title: 'Easy On Me Official Music Video',
        channel: 'Adele',
        categoryId: '10',
      );
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Fiersa Besari',
        ),
        isFalse,
      );
    });


    test('rejects Indonesian cover labels and alternate cover wording', () {
      for (final title in [
        'Celengan Rindu - Cover Lagu',
        'Celengan Rindu (Versi Cover)',
        'Celengan Rindu Kover',
        'Celengan Rindu (Fiersa Besari Cover)',
        'Celengan Rindu - Cover Music',
        'Celengan Rindu - Singing Cover',
      ]) {
        final track = _track(title: title, channel: 'Fan Singer');
        expect(
          YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(track),
          isTrue,
          reason: 'Expected Indonesian cover form to be rejected: $title',
        );
        expect(YoutubeMusicPolicy.isMusicCandidate(track), isFalse);
      }
    });

    test('rejects music explicitly generated with Suno or Udio', () {
      for (final description in [
        'This track was generated with Suno.',
        'Created with Udio for this channel.',
        'Suno generated song, AI vocals.',
      ]) {
        final track = _track(
          title: 'New Song',
          channel: 'Independent Music Channel',
          description: description,
        );
        expect(
          YoutubeMusicPolicy.isLikelyAiGeneratedMusic(track),
          isTrue,
          reason: 'Expected generator disclosure to be detected: $description',
        );
        expect(YoutubeMusicPolicy.isMusicCandidate(track), isFalse);
      }
    });

    test('does not treat cover art as a performed cover version', () {
      final track = _track(
        title: 'Monokrom - Cover Art',
        channel: 'Tulus',
      );
      expect(YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(track), isFalse);
    });

    test('does not reject cover artwork references in a real music description', () {
      final track = _track(
        title: 'Monokrom Official Music Video',
        channel: 'Tulus',
        description: 'Cover artwork by the album designer. Original recording.',
      );
      expect(YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(track), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
    });

    test('rejects very short and very long tracks even in Music category', () {
      final short = _track(
        title: 'Short Clip',
        channel: 'Artist Official',
        duration: 20,
        categoryId: '10',
      );
      final long = _track(
        title: 'Live Session',
        channel: 'Artist Official',
        duration: 3600,
        categoryId: '10',
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(short), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(long), isFalse);
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate(short), isFalse);
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate(long), isFalse);
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(long, channelTitle: 'Artist Official'),
        isFalse,
      );
    });

    test('rejects Indonesian and English album/playlist collection titles', () {
      for (final title in <String>[
        'Album Lengkap Fiersa Besari',
        'Album Penuh - Semua Lagu Tulus',
        'Kumpulan Lagu Terbaik Raisa',
        'Playlist Lagu Galau Indonesia',
        'Daftar Putar Lagu Pop Terbaru',
        'Kompilasi Lagu 2000an',
        'Semua Lagu Hindia',
        'Seluruh Lagu Coldplay',
        'Full Album - The Complete Collection',
        'Best Of Adele - Greatest Hits',
        'Nonstop Music Mix 2026',
        '2 Hours of Indonesian Songs',
      ]) {
        final video = _track(
          title: title,
          channel: 'Official Music Channel',
          duration: 2400,
          categoryId: '10',
        );
        expect(
          YoutubeMusicPolicy.isMusicCandidate(video),
          isFalse,
          reason: 'Collection should be rejected: $title',
        );
        expect(
          YoutubeMusicPolicy.isOfficialMusicReleaseCandidate(video),
          isFalse,
          reason: 'Collection should be rejected: $title',
        );
        expect(
          YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
            video,
            query: 'Fiersa Besari',
          ),
          isFalse,
          reason: 'Collection should be rejected for artist search: $title',
        );
      }
    });

    test('rejects playlist labels even when YouTube omitted duration metadata', () {
      final playlist = _track(
        title: 'Playlist Terbaik Indonesia - Lagu Galau',
        channel: 'Music Channel',
        duration: null,
      );
      expect(YoutubeMusicPolicy.isLikelyAlbumOrPlaylist(playlist), isTrue);
      expect(YoutubeMusicPolicy.isMusicCandidate(playlist), isFalse);
    });

    test('rejects long single-video compilations even without title markers', () {
      final longUpload = _track(
        title: 'Lagu Pilihan Indonesia',
        channel: 'Official Music Channel',
        duration: 18 * 60,
        categoryId: '10',
      );
      expect(YoutubeMusicPolicy.isLikelyAlbumOrPlaylist(longUpload), isTrue);
      expect(YoutubeMusicPolicy.isMusicCandidate(longUpload), isFalse);
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          longUpload,
          channelTitle: 'Official Music Channel',
          channelDescription: 'Official music uploads',
        ),
        isFalse,
      );
    });

    test('keeps extended but still single-track uploads under 15 minutes', () {
      final extendedSingle = _track(
        title: 'Long Original Instrumental',
        channel: 'Artist Official',
        duration: 12 * 60,
        categoryId: '10',
      );
      expect(YoutubeMusicPolicy.isLikelyAlbumOrPlaylist(extendedSingle), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(extendedSingle), isTrue);
    });

    test('does not reject a legitimate single titled Best of Me', () {
      final track = _track(
        title: 'Best of Me',
        channel: 'The Artist',
        duration: 220,
      );
      expect(YoutubeMusicPolicy.isLikelyAlbumOrPlaylist(track), isFalse);
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
    });

    test('does not reject a song titled only Album or Playlist', () {
      expect(
        YoutubeMusicPolicy.isLikelyAlbumOrPlaylist(
          _track(title: 'Album', channel: 'The Artist', duration: 220),
        ),
        isFalse,
      );
      expect(
        YoutubeMusicPolicy.isLikelyAlbumOrPlaylist(
          _track(title: 'Playlist', channel: 'The Artist', duration: 220),
        ),
        isFalse,
      );
    });

    test('keeps short original tracks above 30 seconds', () {
      final track = _track(
        title: 'Interlude',
        channel: 'Artist Official',
        duration: 45,
      );
      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Artist',
        ),
        isTrue,
      );
    });
    test('splits explicit artist-title search into two validated intents', () {
      expect(
        YoutubeSearchQueryParser.splitExplicitArtistTitleQuery('Denny Caknan - Sigar'),
        ['Denny Caknan', 'Sigar'],
      );
      expect(
        YoutubeSearchQueryParser.splitExplicitArtistTitleQuery('NDX A.K.A. — Kelingan Mantan'),
        ['NDX A.K.A.', 'Kelingan Mantan'],
      );
    });

    test('does not split a normal title without an explicit separator', () {
      expect(
        YoutubeSearchQueryParser.splitExplicitArtistTitleQuery('Kartonyono Medot Janji'),
        isEmpty,
      );
    });

    test('keeps one-character title when artist and title are explicitly separated', () {
      expect(
        YoutubeSearchQueryParser.splitExplicitArtistTitleQuery('A - Alicia Keys'),
        ['A', 'Alicia Keys'],
      );
    });

  });
}
