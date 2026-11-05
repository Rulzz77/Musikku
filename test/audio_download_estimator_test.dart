import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/audio_download_estimator.dart';

YoutubeSearchResult _song(String id, double? seconds) => YoutubeSearchResult(
      videoId: id,
      title: 'Track $id',
      channelTitle: 'Artist',
      thumbnailUrl: '',
      durationSeconds: seconds,
    );

void main() {
  group('AudioDownloadEstimate', () {
    test('uses 128 kbps as the nominal estimate', () {
      final result = AudioDownloadEstimate.fromSongs([_song('one', 60)]);

      expect(result.knownFileSizeTracks, 0);
      expect(result.knownDurationTracks, 1);
      expect(result.unknownDurationTracks, 0);
      expect(result.estimatedBytes, 960000);
      expect(result.minimumBytes, 720000);
      expect(result.maximumBytes, 1440000);
      expect(result.hasEstimate, isTrue);
    });

    test('counts missing and invalid durations as unknown', () {
      final result = AudioDownloadEstimate.fromSongs([
        _song('missing', null),
        _song('zero', 0),
        _song('nan', double.nan),
        _song('too-long', 24 * 60 * 60 + 1),
      ]);

      expect(result.knownFileSizeTracks, 0);
      expect(result.knownDurationTracks, 0);
      expect(result.unknownDurationTracks, 4);
      expect(result.estimatedBytes, 0);
      expect(result.hasEstimate, isFalse);
    });

    test('sums all tracks without overflowing for normal playlist lengths', () {
      final result = AudioDownloadEstimate.fromSongs([
        _song('one', 180),
        _song('two', 240),
        _song('three', 120),
      ]);

      expect(result.knownDurationTracks, 3);
      expect(result.estimatedBytes, 8640000);
    });

    test('subtracts bytes already present in a resumable partial file', () {
      final result = AudioDownloadEstimate.fromSongs(
        [_song('known', 60), _song('estimate', 60)],
        knownFileSizes: const {'known': 1500000},
        alreadyDownloadedBytes: const {'known': 500000, 'estimate': 100000},
      );

      expect(result.estimatedBytes, 1860000);
      expect(result.minimumBytes, 1620000);
      expect(result.maximumBytes, 2340000);
    });

    test('prefers an already known in-progress file size', () {
      final result = AudioDownloadEstimate.fromSongs(
        [_song('known', 60), _song('estimate', 60)],
        knownFileSizes: const {'known': 1500000},
      );

      expect(result.knownFileSizeTracks, 1);
      expect(result.knownDurationTracks, 1);
      expect(result.unknownDurationTracks, 0);
      expect(result.estimatedBytes, 2460000);
      expect(result.minimumBytes, 2220000);
      expect(result.maximumBytes, 2940000);
    });
  });
}
