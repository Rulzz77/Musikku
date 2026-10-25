import '../models/youtube_search_result.dart';
import 'music_title_formatter.dart';
import 'youtube_search_service.dart';

/// Attempts to replace an explicitly-labelled cover in Radio's Next flow with
/// a high-confidence official/original recording. It deliberately falls back
/// to the selected result whenever metadata is ambiguous; it must never invent
/// the identity of an original song.
class OriginalTrackResolver {
  OriginalTrackResolver(this._searchService);

  final YoutubeSearchService _searchService;
  final Map<String, YoutubeSearchResult?> _resolvedCache =
      <String, YoutubeSearchResult?>{};
  final Set<String> _resolvedKeys = <String>{};
  final Map<String, Future<YoutubeSearchResult?>> _inFlight =
      <String, Future<YoutubeSearchResult?>>{};

  Future<YoutubeSearchResult> resolveIfCover(YoutubeSearchResult selected) async {
    if (selected.isLocal || !isExplicitCover(selected.title)) return selected;
    final target = targetFor(selected);
    if (target == null) return selected;

    final key = selected.videoId;
    if (_resolvedKeys.contains(key)) return _resolvedCache[key] ?? selected;
    final pending = _inFlight[key];
    if (pending != null) return (await pending) ?? selected;

    late final Future<YoutubeSearchResult?> request;
    request = _resolve(selected, target).whenComplete(() {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    });
    _inFlight[key] = request;
    final result = await request;
    _resolvedKeys.add(key);
    _resolvedCache[key] = result;
    while (_resolvedKeys.length > 120) {
      final oldest = _resolvedKeys.first;
      _resolvedKeys.remove(oldest);
      _resolvedCache.remove(oldest);
    }
    return result ?? selected;
  }

  Future<YoutubeSearchResult?> _resolve(
    YoutubeSearchResult selected,
    OriginalTrackTarget target,
  ) async {
    try {
      // YoutubeSearchService caches equivalent queries on device, so retrying
      // the same cover does not spend a fresh search request every time.
      final page = await _searchService
          .searchLatest(target.query)
          .timeout(const Duration(seconds: 6));
      final results = page.results;
      return selectOriginalCandidate(
        results,
        target: target,
        currentVideoId: selected.videoId,
      );
    } catch (_) {
      // Network/quota failure should not stop playback; keep the selected cover.
      return null;
    }
  }

  static bool isExplicitCover(String rawTitle) {
    final title = rawTitle.trim();
    if (title.isEmpty) return false;
    return RegExp(
      r'[\(\[\{【][^\)\]\}】]*\bcover\b[^\)\]\}】]*[\)\]\}】]',
      caseSensitive: false,
    ).hasMatch(title) ||
        RegExp(
          r'\b(?:cover\s+(?:by|of|from|version|song|lagu)|covered\s+by|'
          r'versi\s+cover|(?:acoustic|piano|guitar|gitar|live)\s+cover|'
          r'cover\s+version|cover\s+lagu|karaoke\s+version)\b',
          caseSensitive: false,
        ).hasMatch(title) ||
        RegExp(r'\s[-–—|:]\s*cover\s*$', caseSensitive: false).hasMatch(title) ||
        RegExp(r'\s+cover\s*$', caseSensitive: false).hasMatch(title) ||
        RegExp(r'^.+?\s+(?:covers?|covering)\s+.+$', caseSensitive: false).hasMatch(title);
  }

  static OriginalTrackTarget? targetFor(YoutubeSearchResult video) {
    final raw = video.title.trim();
    if (!isExplicitCover(raw)) return null;

    String? originalArtist;
    for (final match in RegExp(
      r'[\(\[\{【]([^\)\]\}】]*\bcover\b[^\)\]\}】]*)[\)\]\}】]',
      caseSensitive: false,
    ).allMatches(raw)) {
      final cue = (match.group(1) ?? '').trim();
      final artistMatch = RegExp(
        r'^(.+?)\s+(?:acoustic\s+|piano\s+|guitar\s+|gitar\s+)?cover(?:\s+(?:song|version))?$',
        caseSensitive: false,
      ).firstMatch(cue);
      final candidate = artistMatch?.group(1)?.trim() ?? '';
      if (candidate.isNotEmpty && !_isGenericCoverWord(candidate)) {
        originalArtist = candidate;
        break;
      }
    }

    final coverPerformerMatch = RegExp(
      r'\bcover(?:ed)?\s+by\s+([^()\[\]{}|:;–—-]+)',
      caseSensitive: false,
    ).firstMatch(raw);
    final coverPerformer = _normalize(coverPerformerMatch?.group(1) ?? '');

    var source = raw.replaceAll(
      RegExp(
        r'[\(\[\{【][^\)\]\}】]*\bcover\b[^\)\]\}】]*[\)\]\}】]',
        caseSensitive: false,
      ),
      ' ',
    );
    source = source.replaceAll(
      RegExp(
        r'\b(?:cover(?:ed)?(?:\s+(?:song|version|lagu))?|versi\s+cover)\s+'
        r'(?:by|oleh|dari|performed\s+by|sung\s+by|with)\s+[^|;–—-]+$',
        caseSensitive: false,
      ),
      ' ',
    );
    source = source.replaceAll(
      RegExp(
        r'\s*[-–—|:]\s*(?:(?:acoustic|piano|guitar|gitar|live)\s+)?'
        r'cover(?:\s+(?:version|song|lagu))?\s*$',
        caseSensitive: false,
      ),
      ' ',
    );
    source = source.replaceAll(
      RegExp(r'^\s*cover\s+by\s+.+?\s*[-–—]\s*', caseSensitive: false),
      '',
    );
    // Handle titles written as "Singer covers Song" without parentheses.
    final verbCover = RegExp(r'^(.+?)\s+(?:covers?|covering)\s+(.+)$', caseSensitive: false)
        .firstMatch(source.trim());
    if (verbCover != null) source = verbCover.group(2)!.trim();

    var cleaned = MusicTitleFormatter.clean(source)
        .replaceAll(RegExp(r'\s*[-–—|:]\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;

    final separator = RegExp(r'\s[-–—]\s').firstMatch(cleaned);
    if (separator != null) {
      final left = cleaned.substring(0, separator.start).trim();
      final right = cleaned.substring(separator.end).trim();
      if (left.isNotEmpty && right.isNotEmpty) {
        if (originalArtist == null) {
          final leftKey = _normalize(left);
          final channelKey = _normalize(video.channelTitle.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), ''));
          if (leftKey != coverPerformer &&
              !(channelKey.isNotEmpty && (channelKey == leftKey || channelKey.contains(leftKey)))) {
            originalArtist = left;
          }
        }
        cleaned = right;
      }
    }

    cleaned = MusicTitleFormatter.clean(cleaned);
    final titleKey = _normalize(cleaned);
    if (titleKey.length < 2) return null;

    final artist = originalArtist?.trim() ?? '';
    final query = artist.isEmpty
        ? '$cleaned original song official audio'
        : '$artist $cleaned original official audio';
    return OriginalTrackTarget(
      songTitle: cleaned,
      originalArtist: artist,
      query: query,
    );
  }

  static YoutubeSearchResult? selectOriginalCandidate(
    Iterable<YoutubeSearchResult> candidates, {
    required OriginalTrackTarget target,
    required String currentVideoId,
  }) {
    final songKey = _normalize(target.songTitle);
    if (songKey.isEmpty) return null;
    YoutubeSearchResult? best;
    var bestScore = -1;

    for (final candidate in candidates) {
      if (candidate.isLocal || candidate.videoId.isEmpty || candidate.videoId == currentVideoId) continue;
      if (isExplicitCover(candidate.title) ||
          YoutubeSearchService.isLikelyShortForm(candidate) ||
          YoutubeSearchService.isLikelyNonMusicVideo(candidate)) {
        continue;
      }

      final title = _normalize(MusicTitleFormatter.clean(candidate.title));
      if (title.isEmpty || !(title == songKey || title.contains(songKey))) continue;

      final artistKey = _normalize(target.originalArtist);
      final candidateArtistData = _normalize('${candidate.title} ${candidate.channelTitle}');
      final artistMatches = artistKey.isEmpty || candidateArtistData.contains(artistKey);
      if (!artistMatches) continue;

      final hasOfficialSignal = RegExp(
        r'\b(?:official\s+(?:audio|video|music\s+video|lyrics?)|vevo|topic|records?|recordings?|entertainment)\b',
        caseSensitive: false,
      ).hasMatch('${candidate.title} ${candidate.channelTitle}');
      // If the original performer isn't named in the cover title, do not make a
      // risky substitution to a random upload. Require an official/topic/label cue.
      if (artistKey.isEmpty && !hasOfficialSignal) continue;

      var score = title == songKey ? 100 : (title.endsWith(' $songKey') ? 92 : 84);
      if (artistKey.isNotEmpty && artistMatches) score += 40;
      if (hasOfficialSignal) score += 18;
      if (candidate.channelTitle.toLowerCase().contains(' - topic')) score += 8;
      if (RegExp(r'\bvevo\b', caseSensitive: false).hasMatch(candidate.channelTitle)) score += 8;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  static bool _isGenericCoverWord(String value) => RegExp(
        r'^(?:acoustic|piano|guitar|gitar|live|female|male|instrumental|original|music|the|a)$',
        caseSensitive: false,
      ).hasMatch(value.trim());

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class OriginalTrackTarget {
  const OriginalTrackTarget({
    required this.songTitle,
    required this.originalArtist,
    required this.query,
  });

  final String songTitle;
  final String originalArtist;
  final String query;
}
