import '../models/youtube_search_result.dart';

/// Keeps a playback session within one source type.
///
/// YouTube tracks and device-local files share a UI model, but should not be
/// combined by Shuffle simply because they coexist in history/favorites.
class PlaybackSourcePolicy {
  const PlaybackSourcePolicy._();

  /// Returns a de-duplicated list matching [selected]'s source type.
  /// The selected track is inserted at the front if absent from [candidates].
  static List<YoutubeSearchResult> sameSourceAs(
    Iterable<YoutubeSearchResult> candidates, {
    required YoutubeSearchResult selected,
  }) {
    final result = <YoutubeSearchResult>[];
    final seen = <String>{};

    for (final candidate in candidates) {
      if (candidate.isLocal != selected.isLocal ||
          candidate.videoId.trim().isEmpty ||
          !seen.add(candidate.videoId)) {
        continue;
      }
      result.add(candidate);
    }

    if (!seen.contains(selected.videoId)) {
      result.insert(0, selected);
    }
    return result;
  }
}
