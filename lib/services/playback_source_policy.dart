import '../models/youtube_search_result.dart';

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
