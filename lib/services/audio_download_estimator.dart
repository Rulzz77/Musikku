import '../models/youtube_search_result.dart';

/// A transparent, duration-based storage estimate for audio files.
///
/// This does not resolve stream URLs or inspect provider media. The estimate
/// uses a nominal bitrate and must be presented as approximate; final file
/// sizes are only known after a provider-authorized download completes.
class AudioDownloadEstimate {
  const AudioDownloadEstimate({
    required this.estimatedBytes,
    required this.minimumBytes,
    required this.maximumBytes,
    required this.knownFileSizeTracks,
    required this.knownDurationTracks,
    required this.unknownDurationTracks,
  });

  static const double nominalBitrateKbps = 128;
  static const double minimumBitrateKbps = 96;
  static const double maximumBitrateKbps = 192;
  static const double maximumTrackDurationSeconds = 24 * 60 * 60;

  final int estimatedBytes;
  final int minimumBytes;
  final int maximumBytes;
  final int knownFileSizeTracks;
  final int knownDurationTracks;
  final int unknownDurationTracks;

  bool get hasEstimate => knownFileSizeTracks > 0 || knownDurationTracks > 0;

  static AudioDownloadEstimate fromSongs(
    Iterable<YoutubeSearchResult> songs, {
    Map<String, int> knownFileSizes = const <String, int>{},
  }) {
    var estimated = 0.0;
    var minimum = 0.0;
    var maximum = 0.0;
    var knownFileSizesCount = 0;
    var known = 0;
    var unknown = 0;

    for (final song in songs) {
      final knownBytes = knownFileSizes[song.videoId];
      if (knownBytes != null && knownBytes > 0) {
        knownFileSizesCount++;
        estimated += knownBytes;
        minimum += knownBytes;
        maximum += knownBytes;
        continue;
      }

      final duration = song.durationSeconds;
      if (duration == null ||
          !duration.isFinite ||
          duration <= 0 ||
          duration > maximumTrackDurationSeconds) {
        unknown++;
        continue;
      }

      known++;
      estimated += _bytesFor(duration, nominalBitrateKbps);
      minimum += _bytesFor(duration, minimumBitrateKbps);
      maximum += _bytesFor(duration, maximumBitrateKbps);
    }

    return AudioDownloadEstimate(
      estimatedBytes: estimated.round(),
      minimumBytes: minimum.round(),
      maximumBytes: maximum.round(),
      knownFileSizeTracks: knownFileSizesCount,
      knownDurationTracks: known,
      unknownDurationTracks: unknown,
    );
  }

  static double _bytesFor(double seconds, double bitrateKbps) =>
      seconds * bitrateKbps * 1000 / 8;
}
