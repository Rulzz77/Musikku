import '../models/youtube_search_result.dart';
import 'youtube_music_policy.dart';

/// Keeps playback sessions attached to the source the user explicitly chose.
class PlaybackSourcePolicy {
  const PlaybackSourcePolicy._();

  /// Returns a de-duplicated list matching [selected]'s source type.
  /// Used for mixed views such as history/discovery, not explicit playlists.
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


  /// A track may enter an automatic YouTube transition only when the shared
  /// catalogue policy accepts it. Local files are user-owned media and are
  /// not subject to YouTube title/duration heuristics.
  static bool isAllowedForAutomaticNext(YoutubeSearchResult video) =>
      video.isLocal || YoutubeMusicPolicy.isMusicCandidate(video);

  /// Finds the next allowed item without changing the source list. Invalid
  /// YouTube collection uploads are skipped in-place, so the relative order
  /// of the user's remaining playlist entries is preserved. Direct user taps
  /// and manually queued items intentionally bypass this helper.
  static YoutubeSearchResult? nextAllowedInOrder(
    List<YoutubeSearchResult> candidates, {
    required String currentVideoId,
    required bool repeatAll,
  }) {
    if (candidates.isEmpty) return null;

    final currentIndex =
        candidates.indexWhere((item) => item.videoId == currentVideoId);
    final startIndex = currentIndex < 0 ? 0 : currentIndex + 1;

    for (var index = startIndex; index < candidates.length; index++) {
      final candidate = candidates[index];
      if (isAllowedForAutomaticNext(candidate)) return candidate;
    }

    if (!repeatAll || currentIndex < 0) return null;

    // Wrap in the original order. Including currentIndex as the final checked
    // position means a one-item valid playlist can repeat itself.
    for (var index = 0; index <= currentIndex; index++) {
      final candidate = candidates[index];
      if (isAllowedForAutomaticNext(candidate)) return candidate;
    }
    return null;
  }

  /// Explicit playlists are honored as authored: keep their order and local +
  /// remote items, removing only malformed IDs and exact duplicate video IDs.
  static List<YoutubeSearchResult> explicitPlaylistItems(
    Iterable<YoutubeSearchResult> candidates,
  ) {
    final result = <YoutubeSearchResult>[];
    final seen = <String>{};
    for (final item in candidates) {
      final id = item.videoId.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      result.add(item);
    }
    return result;
  }
}
