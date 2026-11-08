import '../models/youtube_search_result.dart';
import 'spotify_playlist_import_service.dart';
import 'youtube_music_policy.dart';

/// Conservative matcher between Spotify track metadata and MusikKu's
/// YouTube Music search results. A match must agree on the complete song title
/// and the Spotify primary artist; a name buried in an arbitrary description
/// is not sufficient evidence.
class SpotifyYoutubeTrackMatcher {
  /// Produces bounded query variants for Spotify import. Keep the Spotify
  /// display title intact; only remove soundtrack/featured-artist suffixes
  /// from the search core so a valid original upload is easier to discover.
  static List<String> buildSearchQueries(SpotifyPlaylistTrack track) {
    final coreTitle = _searchCoreTitle(track.title);
    if (coreTitle.isEmpty) return const <String>[];

    final queries = <String>{};
    final primary = track.primaryArtist.trim();
    if (primary.isNotEmpty) {
      queries.add('$primary $coreTitle');
      queries.add('$coreTitle $primary');
      queries.add('$primary $coreTitle official audio');
    }
    if (track.artists.length > 1) {
      queries.add('$coreTitle ${track.artists.join(' ')}');
    }
    queries.add(coreTitle);
    final fullTitle = track.title.trim();
    if (fullTitle.isNotEmpty &&
        fullTitle.toLowerCase() != coreTitle.toLowerCase()) {
      queries.add(fullTitle);
    }

    return queries
        .map((query) => query.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((query) => query.isNotEmpty)
        .toList(growable: false);
  }

  static String _searchCoreTitle(String value) {
    var result = value.replaceFirst(
      RegExp(r'\s+[-–—]\s*from\s+.+$', caseSensitive: false),
      '',
    );
    result = result
        .replaceAll(
          RegExp(
            r'\s*[\[(]\s*(?:feat(?:uring)?|ft)\.?\s+[^)\]]+[)\]]',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceFirst(
          RegExp(r'\s+(?:feat(?:uring)?|ft)\.?\s+.+$', caseSensitive: false),
          '',
        );
    return result.trim();
  }

  static YoutubeSearchResult? bestMatch(
    SpotifyPlaylistTrack spotifyTrack,
    List<YoutubeSearchResult> candidates,
  ) {
    if (spotifyTrack.title.trim().isEmpty || spotifyTrack.artists.isEmpty) {
      return null;
    }

    YoutubeSearchResult? best;
    var bestScore = 0.0;
    var bestOfficialRank = -1;
    for (final candidate in candidates) {
      if (candidate.isLocal ||
          !YoutubeMusicPolicy.isMusicCandidate(candidate) ||
          _isClearlyUnofficialChannel(candidate.channelTitle)) {
        continue;
      }

      final titleCoverage = _tokenCoverage(spotifyTrack.title, candidate.title);
      final titleScore = _similarity(spotifyTrack.title, candidate.title);
      final artistScore = _artistSimilarity(spotifyTrack, candidate);
      final durationPenalty = _durationMismatchPenalty(spotifyTrack, candidate);
      final alternatePenalty = _alternateVersionPenalty(
        candidate.title,
        spotifyTrack.title,
      );
      final score = (titleScore * 0.64) + (artistScore * 0.36) -
          durationPenalty - alternatePenalty;

      // Require near-complete title coverage and a strong primary-artist
      // signal before considering source authority. A fake "Official" label
      // can never rescue a wrong title or wrong performer.
      final acceptable = titleCoverage >= 0.85 &&
          titleScore >= 0.62 &&
          artistScore >= 0.82 &&
          score >= 0.70;
      if (!acceptable) continue;

      // YouTube search relevance is not a source-authenticity signal. Prefer
      // Topic/VEVO, structured distributor credits, and the artist's own
      // channel over a fan/re-upload mirror whenever both match the same song.
      // Score and duration are tie-breakers only within the same authority tier.
      final officialRank = _officialSourceRank(spotifyTrack, candidate);
      // Unknown uploaders need independent verification: exact YouTube Music
      // credits, an explicit distributor block, or a popular near-exact title
      // carrying the expected artist. A copied song title alone is not enough.
      if (officialRank < 3) continue;
      if (officialRank > bestOfficialRank ||
          (officialRank == bestOfficialRank && score > bestScore)) {
        best = candidate;
        bestScore = score;
        bestOfficialRank = officialRank;
      }
    }
    return best;
  }

  /// Picks only the most plausible title candidates for a detail lookup.
  /// Full Video.musicData requests are intentionally capped because they are
  /// heavier than reading the initial search page. A high view count helps a
  /// candidate enter the shortlist, but never authenticates it by itself.
  static List<YoutubeSearchResult> metadataLookupCandidates(
    SpotifyPlaylistTrack spotifyTrack,
    List<YoutubeSearchResult> candidates, {
    int limit = 8,
  }) {
    final eligible = candidates.where((candidate) {
      if (candidate.isLocal ||
          !YoutubeMusicPolicy.isMusicCandidate(candidate) ||
          _isClearlyUnofficialChannel(candidate.channelTitle)) {
        return false;
      }
      return _tokenCoverage(spotifyTrack.title, candidate.title) >= 0.80 &&
          _similarity(spotifyTrack.title, candidate.title) >= 0.55;
    }).toList(growable: false);

    eligible.sort((a, b) {
      final aTitle = _similarity(spotifyTrack.title, a.title);
      final bTitle = _similarity(spotifyTrack.title, b.title);
      final titleOrder = bTitle.compareTo(aTitle);
      if (titleOrder != 0) return titleOrder;
      final artistA = _artistSimilarity(spotifyTrack, a);
      final artistB = _artistSimilarity(spotifyTrack, b);
      final artistOrder = artistB.compareTo(artistA);
      if (artistOrder != 0) return artistOrder;
      return (b.viewCount ?? 0).compareTo(a.viewCount ?? 0);
    });
    return eligible.take(limit.clamp(1, 10).toInt()).toList(growable: false);
  }

  /// True only when an artist-owned, Topic, or VEVO result is already present.
  /// A structured distributor/label result can be a safe final fallback, but
  /// it must not stop later queries from looking for the performer's own page.
  static bool hasPreferredOfficialMatch(
    SpotifyPlaylistTrack spotifyTrack,
    List<YoutubeSearchResult> candidates,
  ) {
    final match = bestMatch(spotifyTrack, candidates);
    return match != null && _officialSourceRank(spotifyTrack, match) >= 5;
  }

  static int _officialSourceRank(
    SpotifyPlaylistTrack track,
    YoutubeSearchResult candidate,
  ) {
    final primaryArtist = _normalizeChannelIdentity(track.primaryArtist);
    if (primaryArtist.isEmpty) return 0;

    final channelRaw = candidate.channelTitle.trim();
    final title = candidate.title.toLowerCase();
    final description = candidate.description;
    final artistOwnChannel = _isArtistOwnedChannel(channelRaw, primaryArtist);
    final topicChannel = RegExp(
      r'\s-\s*topic\s*$',
      caseSensitive: false,
    ).hasMatch(channelRaw);
    final vevoChannel = RegExp(r'\bvevo\b', caseSensitive: false)
        .hasMatch(channelRaw);
    final officialChannel = RegExp(
      r'\b(?:official|resmi)(?:\s+(?:artist|music|channel)){0,2}\b',
      caseSensitive: false,
    ).hasMatch(channelRaw);
    final officialTitle = RegExp(
      r'\b(?:official\s+(?:audio|video|music\s+video|lyrics?|visualizer)|music\s+video\s+official)\b',
      caseSensitive: false,
    ).hasMatch(title);
    final providedToYoutube = RegExp(
      r'provided to youtube by',
      caseSensitive: false,
    ).hasMatch(description);
    final structuredDistributorCredit = providedToYoutube &&
        _hasExplicitDescriptionCredit(
          description,
          primaryArtist,
          _normalizeTrackTitle(track.title),
        );

    // Rank artist-owned Topic/VEVO channels above label fallbacks. This is
    // important because a label's result may say "Official Audio" and appear
    // before the performer's own channel in YouTube search relevance order.
    if ((topicChannel || vevoChannel) && artistOwnChannel) return 6;
    if (artistOwnChannel) return 5;

    // A structured distributor delivery is strong evidence, but remains below
    // the artist's own channel so the original performer upload wins when both
    // are available.
    if (structuredDistributorCredit) return 4;

    // Structured YouTube Music song/artist credits are stronger evidence than
    // uploader identity or popularity. Do not require an arbitrary view-count
    // threshold when YouTube itself exposes an exact track + performer pair.
    if (_matchesStructuredMusicData(track, candidate)) return 4;
    final parsedArtist = _normalizeArtistText(candidate.artistName);
    final parsedCreditMatches = parsedArtist.isNotEmpty &&
        _artistCreditMatches(
          parsedArtist,
          _normalizeArtistText(track.primaryArtist),
        ) &&
        _tokenCoverage(track.title, candidate.title) >= 0.90 &&
        _similarity(track.title, candidate.title) >= 0.78;
    if (parsedCreditMatches) return 4;

    final views = candidate.viewCount ?? 0;
    final popularThirdParty = views >= 100000;
    final establishedThirdParty = views >= 25000;
    final titleCreditsArtist = _artistCreditMatches(
      _normalizeArtistText(candidate.title),
      _normalizeArtistText(track.primaryArtist),
    );
    final titleIsNearExact =
        _tokenCoverage(track.title, candidate.title) >= 0.98 &&
        _similarity(track.title, candidate.title) >= 0.90;

    // Some legitimate catalogue tracks are uploaded by channels that are not
    // the artist/label account, and MusicData is not always exposed. Permit a
    // widely-played fallback only when the title itself carries the correct
    // performer credit and the song title is an almost exact match. A viral
    // video with only the same song name (or the wrong singer) still fails.
    final expectedDuration = track.durationMs == null
        ? null
        : track.durationMs! / 1000.0;
    final actualDuration = candidate.durationSeconds;
    final durationCorroborates = expectedDuration != null &&
        actualDuration != null &&
        (expectedDuration - actualDuration).abs() <= 12;

    // Allow a popular independent upload when both title and performer are
    // explicitly present. For the lower popularity band, require a near-exact
    // duration as a second independent signal. Views never authenticate a
    // wrong singer, and a copied title alone remains insufficient.
    if (titleIsNearExact &&
        titleCreditsArtist &&
        (popularThirdParty || (establishedThirdParty && durationCorroborates))) {
      return 3;
    }

    // A known label with an explicit official-title marker is a fallback only.
    // It must not stop the query loop before artist-owned results are checked.
    if (_isKnownMusicLabelChannel(channelRaw) && officialTitle) return 3;

    // An official title by itself is not source authentication.
    if (officialTitle || _isKnownMusicLabelChannel(channelRaw) || officialChannel) {
      return 2;
    }
    return 0;
  }

  static bool _matchesStructuredMusicData(
    SpotifyPlaylistTrack track,
    YoutubeSearchResult candidate,
  ) {
    final structuredTitle = candidate.musicDataTitle.trim();
    final structuredArtist = candidate.musicDataArtist.trim();
    if (structuredTitle.isEmpty || structuredArtist.isEmpty ||
        track.primaryArtist.trim().isEmpty) {
      return false;
    }

    final titleCoverage = _tokenCoverage(track.title, structuredTitle);
    final titleSimilarity = _similarity(track.title, structuredTitle);
    final artistMatches = _artistCreditMatches(
      _normalizeArtistText(structuredArtist),
      _normalizeArtistText(track.primaryArtist),
    );
    return titleCoverage >= 0.90 && titleSimilarity >= 0.78 && artistMatches;
  }

  static bool _isArtistOwnedChannel(String rawChannel, String normalizedArtist) {
    final channel = _normalizeChannelIdentity(rawChannel);
    if (channel.isEmpty || normalizedArtist.isEmpty) return false;
    if (channel == normalizedArtist ||
        channel.replaceAll(' ', '') == normalizedArtist.replaceAll(' ', '')) {
      return true;
    }
    // Retain the one-letter-prefix compatibility used by some artist aliases.
    final channelTokens = channel.split(' ');
    final artistTokens = normalizedArtist.split(' ');
    if (artistTokens.length == channelTokens.length + 1 &&
        artistTokens.first.length == 1) {
      return artistTokens.skip(1).join(' ') == channel;
    }
    return false;
  }

  static String _normalizeChannelIdentity(String rawChannel) => rawChannel
      .replaceFirst(RegExp(r'\s*[-–—|]\s*topic$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*vevo$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+(?:official\s+)?(?:(?:artist|music)\s+)?channel$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+official$', caseSensitive: false), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _isClearlyUnofficialChannel(String rawChannel) => RegExp(
        r'\b(?:fan(?:s|[ -]?(?:made|account|page|club|upload(?:s)?))?|unofficial|re-?upload(?:s|ed)?|mirror(?:s)?|karaoke|cover(?:s)?|lyrics?|tribute|nightcore|slowed|sped[ -]?up|reaction(?:s)?|ai[ -]?music)\b',
        caseSensitive: false,
      ).hasMatch(rawChannel);

  static bool _isKnownMusicLabelChannel(String rawChannel) {
    // Check the raw channel text: artist normalization deliberately removes
    // generic words such as "music", which are meaningful in label names.
    final channel = _normalizeChannelIdentity(rawChannel);
    const labels = <String>[
      'musica studios',
      'trinity optima production',
      'sony music',
      'sony music india',
      'sony music indonesia',
      'universal music',
      'universal music group',
      'universal music indonesia',
      'warner music',
      'warner music indonesia',
      'warner records',
      'believe sas',
      'believe music',
      'md music',
      'nagaswara',
      'aquarius musikindo',
      'gp records',
      'ascada musik',
      'my music records',
      'falcon music',
      'star media nusantara',
      'emotion entertainment',
      'hybe labels',
      'bighit music',
      'jyp entertainment',
      'yg entertainment',
      'sm entertainment',
      'smtown',
      'ador',
      'source music',
      'pledis entertainment',
      'cube entertainment',
      'starship entertainment',
    ];
    // Do not trust a channel merely because its name starts with a label.
    // Re-upload and fan channels commonly append a label name to their own.
    // Explicit regional channels are listed above; the rest need structured
    // YouTube distributor credits that mention this exact track and artist.
    return labels.any(
      (label) => channel == _normalizeChannelIdentity(label),
    );
  }

  /// Keep Spotify's canonical song/artist metadata for the imported playlist.
  /// The YouTube video ID, channel ID, artwork, and playback source remain the
  /// selected YouTube candidate; only the display title and performer credits
  /// are normalized to the source playlist.
  static YoutubeSearchResult applySpotifyMetadata(
    SpotifyPlaylistTrack track,
    YoutubeSearchResult candidate,
  ) {
    final credits = track.artists
        .map((artist) => artist.trim())
        .where((artist) => artist.isNotEmpty)
        .join(', ');
    return candidate.copyWith(
      title: track.title.trim(),
      // Keep the visible Spotify credit aligned with the playlist while also
      // preserving the primary performer separately for verified album art.
      channelTitle: credits.isEmpty ? candidate.channelTitle : credits,
      artistName: track.primaryArtist,
      sourceChannelTitle: candidate.sourceChannelTitle.isNotEmpty
          ? candidate.sourceChannelTitle
          : candidate.channelTitle,
      album: track.album.trim().isNotEmpty
          ? track.album.trim()
          : (candidate.album.trim().isNotEmpty
              ? candidate.album.trim()
              : _albumFromOfficialDescription(candidate.description)),
    );
  }

  static String _albumFromOfficialDescription(String rawDescription) {
    if (!RegExp(r'provided to youtube by', caseSensitive: false)
        .hasMatch(rawDescription)) {
      return '';
    }
    final match = RegExp(
      r'^\s*(?:album|album title)\s*[:\-]\s*(.*?)\s*$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(rawDescription);
    return match?.group(1)?.trim() ?? '';
  }

  static String _normalize(String value) => value
      .toLowerCase()
      // Keep meaningful parenthetical title text such as "From Cidro Asmoro".
      // Formatting brackets are removed, then known upload labels are stripped.
      .replaceAll(RegExp(r'[()\[\]]'), ' ')
      .replaceAll(
        RegExp(
          r'\b(?:official|audio|video|music|lyrics?|lyric|visualizer|mv|hd|4k|feat|ft)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Artist matching must keep parenthetical text because some official uploads
  /// place the performer there, e.g. "Klebus (Guyon Waton) [Official Audio]".
  static String _normalizeArtistText(String value) => value
      .toLowerCase()
      .replaceAll(
        RegExp(
          r'\b(?:official|audio|video|lyrics?|lyric|visualizer|mv|hd|4k|topic|vevo|channel)\b',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _normalizeTrackTitle(String value) {
    // Spotify sometimes appends film/series attribution that is absent from
    // the YouTube upload title. Remove it only for matching.
    final withoutSourceAttribution = value.replaceFirst(
      RegExp(r'\s+[-–—]\s*from\s+.+$', caseSensitive: false),
      '',
    );
    // Drop the entire featured-artist suffix, not just the word "feat.".
    // Otherwise guest names become mandatory title tokens and valid single
    // uploads are incorrectly reported as missing.
    final withoutFeature = _searchCoreTitle(withoutSourceAttribution);
    return _normalize(withoutFeature);
  }

  static Set<String> _tokens(String value) => _normalizeTrackTitle(value)
      .split(' ')
      .where((token) => token.isNotEmpty)
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
    final normalizedA = _normalizeTrackTitle(first);
    final normalizedB = _normalizeTrackTitle(second);
    if (normalizedA.isNotEmpty &&
        (normalizedA == normalizedB ||
            normalizedB.startsWith('$normalizedA ') ||
            normalizedB.endsWith(' $normalizedA'))) {
      return dice < 0.94 ? 0.94 : dice;
    }

    // YouTube often prefixes the performer or appends the artist after a dash.
    // Full Spotify title coverage therefore matters more than raw token Dice.
    final coverageAware = (titleCoverage * 0.78) + (dice * 0.22);
    return coverageAware > dice ? coverageAware : dice;
  }

  static double _artistSimilarity(
    SpotifyPlaylistTrack spotifyTrack,
    YoutubeSearchResult candidate,
  ) {
    final artists = spotifyTrack.artists;
    if (artists.isEmpty) return 0;

    final titleText = _normalizeArtistText(candidate.title);
    final channelText = _normalizeArtistText(candidate.channelTitle);
    final primaryArtist = _normalizeArtistText(artists.first);
    if (primaryArtist.length < 2) return 0;

    final primaryInTitle = _artistCreditMatches(titleText, primaryArtist);
    final primaryInChannel = _artistCreditMatches(channelText, primaryArtist);
    final primaryExplicitlyCredited = _hasExplicitDescriptionCredit(
      candidate.description,
      primaryArtist,
      _normalizeTrackTitle(spotifyTrack.title),
    );
    final structuredArtist = _normalizeArtistText(candidate.musicDataArtist);
    final parsedOfficialArtist = _normalizeArtistText(candidate.artistName);
    final primaryInStructuredMusicData =
        _matchesStructuredMusicData(spotifyTrack, candidate);
    final primaryInParsedOfficialCredit =
        (structuredArtist.isNotEmpty &&
            _artistCreditMatches(structuredArtist, primaryArtist)) ||
        (parsedOfficialArtist.isNotEmpty &&
            _artistCreditMatches(parsedOfficialArtist, primaryArtist));

    // Do not accept a candidate merely because the artist name occurs somewhere
    // in its description, tags, or promotional text. Only title/channel,
    // direct performer credits, or YouTube's structured MusicData are trusted.
    if (!primaryInTitle &&
        !primaryInChannel &&
        !primaryExplicitlyCredited &&
        !primaryInStructuredMusicData &&
        !primaryInParsedOfficialCredit) {
      return 0;
    }

    var score = primaryInStructuredMusicData ||
            primaryInParsedOfficialCredit ||
            primaryInTitle
        ? 1.0
        : primaryInChannel
            ? 0.96
            : 0.90;

    // Additional Spotify collaborators strengthen a match when the upload
    // names them too, but they never replace a missing primary-artist credit.
    var collaboratorsMatched = 0;
    for (final artist in artists.skip(1)) {
      final normalized = _normalizeArtistText(artist);
      if (normalized.length >= 2 &&
          (_artistCreditMatches(titleText, normalized) ||
              _artistCreditMatches(channelText, normalized))) {
        collaboratorsMatched++;
      }
    }
    if (collaboratorsMatched > 0) {
      score = (score + (collaboratorsMatched * 0.02))
          .clamp(0.0, 1.0)
          .toDouble();
    }
    return score;
  }

  static bool _containsPhrase(String normalizedText, String normalizedPhrase) {
    if (normalizedText.isEmpty || normalizedPhrase.isEmpty) return false;
    return ' $normalizedText '.contains(' $normalizedPhrase ');
  }

  static bool _artistCreditMatches(
    String normalizedText,
    String normalizedArtist,
  ) {
    if (_containsPhrase(normalizedText, normalizedArtist)) return true;

    // Spotify sometimes includes a one-letter prefix in an artist credit while
    // YouTube omits it (e.g. "E Woro Widowati" vs "Woro Widowati"). Allow
    // this only when at least two substantial name tokens still match in order.
    final artistTokens = normalizedArtist.split(' ');
    final significantTokens = artistTokens
        .where((token) => token.length > 1)
        .toList(growable: false);
    final isSingleInitialPrefix = artistTokens.length == 2 &&
        artistTokens.first.length == 1 &&
        significantTokens.length == 1 &&
        significantTokens.single.length >= 4;
    if (significantTokens.length < 2 && !isSingleInitialPrefix) return false;
    return _containsPhrase(normalizedText, significantTokens.join(' '));
  }

  static bool _hasExplicitDescriptionCredit(
    String rawDescription,
    String normalizedArtist,
    String normalizedTrackTitle,
  ) {
    if (rawDescription.trim().isEmpty || normalizedArtist.isEmpty ||
        normalizedTrackTitle.isEmpty) {
      return false;
    }

    // A distributor phrase alone is not enough. Require YouTube's structured
    // delivery marker AND a nearby block that credits this exact track to the
    // Spotify primary artist. This prevents copied artist mentions in promo
    // text, tags, or unrelated descriptions from authenticating a re-upload.
    final isDistributorDelivery = RegExp(
      r'provided to youtube by|provided to youtube',
      caseSensitive: false,
    ).hasMatch(rawDescription);
    if (!isDistributorDelivery) return false;

    final expectedTitleTokens = _tokens(normalizedTrackTitle);
    if (expectedTitleTokens.isEmpty) return false;

    final lines = rawDescription
        .split(RegExp(r'[\r\n]+'))
        .map(_normalizeArtistText)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    for (var index = 0; index < lines.length; index++) {
      final window = lines
          .skip(index > 0 ? index - 1 : index)
          .take(3)
          .join(' ');
      final titleCoverage = expectedTitleTokens
              .intersection(_tokens(window))
              .length /
          expectedTitleTokens.length;
      if (titleCoverage >= 0.90 &&
          _artistCreditMatches(window, normalizedArtist)) {
        return true;
      }
    }
    return false;
  }

  static double _durationMismatchPenalty(
    SpotifyPlaylistTrack spotifyTrack,
    YoutubeSearchResult candidate,
  ) {
    final expectedMs = spotifyTrack.durationMs;
    final actualSeconds = candidate.durationSeconds;
    if (expectedMs == null || expectedMs <= 0 || actualSeconds == null || actualSeconds <= 0) {
      return 0;
    }

    final expectedSeconds = expectedMs / 1000.0;
    final difference = (actualSeconds - expectedSeconds).abs();
    // Ignore normal intro/outro differences up to 20 seconds, then apply a
    // small ranking penalty. This is not a rejection rule on its own.
    if (difference <= 20) return 0;
    return ((difference - 20) / 180).clamp(0.0, 0.12).toDouble();
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
        return 0.31;
      }
    }
    return 0;
  }
}
