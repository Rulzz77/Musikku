import '../models/youtube_search_result.dart';
import 'spotify_playlist_import_service.dart';
import 'youtube_music_policy.dart';

/// Conservative matcher between Spotify track metadata and the app's YouTube
/// Music search results. Low-confidence matches are left for manual resolution.
class SpotifyYoutubeTrackMatcher {
  static YoutubeSearchResult? bestMatch(
    SpotifyPlaylistTrack spotifyTrack,
    List<YoutubeSearchResult> candidates,
  ) {
    if (spotifyTrack.title.trim().isEmpty || spotifyTrack.artists.isEmpty) {
      return null;
    }

    YoutubeSearchResult? best;
    var bestScore = 0.0;
    for (final candidate in candidates) {
      if (candidate.isLocal ||
          !YoutubeMusicPolicy.isMusicCandidate(candidate)) {
        continue;
      }

      final titleCoverage = _tokenCoverage(spotifyTrack.title, candidate.title);
      final titleScore = _similarity(spotifyTrack.title, candidate.title);
      final artistScore = _artistSimilarity(spotifyTrack.artists, candidate);
      final alternatePenalty = _alternateVersionPenalty(
        candidate.title,
        spotifyTrack.title,
      );
      final score = (titleScore * 0.72) + (artistScore * 0.28) - alternatePenalty;

      // Require the complete title and a credible artist credit. This avoids
      // importing same-title songs by another performer or a partial title.
      final acceptable = titleCoverage >= 0.80 &&
          titleScore >= 0.62 &&
          artistScore >= 0.65 &&
          score >= 0.66;
      if (acceptable && score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), ' ')
      .replaceAll(
        RegExp(
          r'\b(?:official|audio|video|music|lyrics?|lyric|visualizer|mv|hd|4k|feat|ft)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static Set<String> _tokens(String value) => _normalize(value)
      .split(' ')
      .where((token) => token.length > 1)
      .toSet();

  static double _tokenCoverage(String expectedTitle, String candidateTitle) {
    final expected = _tokens(expectedTitle);
    final candidate = _tokens(candidateTitle);
    if (expected.isEmpty || candidate.isEmpty) return 0;
    return expected.intersection(candidate).length / expected.length;
  }

  static double _similarity(String first, String second) {
    final a = _tokens(first);
    final b = _tokens(second);
    if (a.isEmpty || b.isEmpty) return 0;

    final intersection = a.intersection(b).length;
    final dice = (2 * intersection) / (a.length + b.length);
    final titleCoverage = intersection / a.length;
    final normalizedA = _normalize(first);
    final normalizedB = _normalize(second);
    if (normalizedA.isNotEmpty &&
        (normalizedA == normalizedB ||
            normalizedB.startsWith('$normalizedA ') ||
            normalizedB.endsWith(' $normalizedA'))) {
      return dice < 0.94 ? 0.94 : dice;
    }

    // YouTube commonly prefixes the performer before the song title. Dice
    // alone penalizes that valid format, particularly for short song titles.
    final coverageAware = (titleCoverage * 0.75) + (dice * 0.25);
    return coverageAware > dice ? coverageAware : dice;
  }

  static double _artistSimilarity(
    List<String> artists,
    YoutubeSearchResult candidate,
  ) {
    final candidateText = _normalize(
      '${candidate.channelTitle} ${candidate.title} ${candidate.description}',
    );
    if (candidateText.isEmpty) return 0;

    var best = 0.0;
    final candidateTokens = _tokens(candidateText);
    for (final artist in artists) {
      // Spotify embed can combine credits in one subtitle string. Keep the
      // full value first (e.g. "Tyler, The Creator"), then try split credits.
      final variants = <String>{artist.trim()};
      variants.addAll(
        artist
            .split(RegExp(r'\s*[;,]\s*'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );

      for (final variant in variants) {
        final normalizedArtist = _normalize(variant);
        if (normalizedArtist.length < 2) continue;
        final phrasePattern = RegExp(
          r'(^|\s)' + RegExp.escape(normalizedArtist) + r'(\s|$)',
        );
        if (phrasePattern.hasMatch('$candidateText ')) return 1;

        final artistTokens = _tokens(variant);
        if (artistTokens.isEmpty || candidateTokens.isEmpty) continue;
        final intersection = artistTokens.intersection(candidateTokens).length;
        final overlap = intersection / artistTokens.length;
        if (overlap > best) best = overlap;
      }
    }
    return best;
  }

  static double _alternateVersionPenalty(
    String candidateTitle,
    String expectedTitle,
  ) {
    const alternateMarkers = <String>[
      r'\blive\b',
      r'\bconcert\b',
      r'\bacoustic\b',
      r'\binstrumental\b',
      r'\bremix\b',
      r'\bsped\s*up\b',
      r'\bslowed\b',
      r'\bnightcore\b',
    ];
    final candidate = candidateTitle.toLowerCase();
    final expected = expectedTitle.toLowerCase();
    for (final marker in alternateMarkers) {
      if (RegExp(marker).hasMatch(candidate) &&
          !RegExp(marker).hasMatch(expected)) {
        // Do not substitute a live/remix/instrumental version for the Spotify
        // track. If no studio-equivalent candidate exists, leave it unmatched.
        return 0.31;
      }
    }
    return 0;
  }
}
