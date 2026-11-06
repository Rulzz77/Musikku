import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/youtube_music_policy.dart';
import 'package:flutter_application_5/services/youtube_search_response_parser.dart';
import 'package:flutter_application_5/services/youtube_search_query.dart';

YoutubeSearchResult _track({
  required String title,
  required String channel,
  double? duration = 220,
}) {
  return YoutubeSearchResult(
    videoId: 'abcdefghijk',
    title: title,
    channelTitle: channel,
    thumbnailUrl: '',
    durationSeconds: duration,
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

    test('does not loosen the strict filter for a generic genre query', () {
      final track = _track(
        title: 'Lagu Cinta',
        channel: 'Pop Indonesia',
      );

      expect(
        YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
          track,
          query: 'Pop Indonesia',
        ),
        isFalse,
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
  });
}
