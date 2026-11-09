import '../models/youtube_search_result.dart';
import 'spotify_playlist_import_service.dart';
import 'youtube_music_policy.dart';

/// Matcher between Spotify track metadata and MusikKu's YouTube search
/// results. A match must agree on the complete song title and at least one
/// Spotify-credited performer; arbitrary names in promotional descriptions are
/// not sufficient evidence.
class SpotifyYoutubeTrackMatcher {
  /// Produces bounded query variants for Spotify import. Keep the Spotify
  /// display title intact; only remove soundtrack/featured-artist suffixes
  /// from the search core so a valid original upload is easier to discover.
  static List<String> buildSearchQueries(SpotifyPlaylistTrack track) {
    final coreTitle = _searchCoreTitle(track.title);
    if (coreTitle.isEmpty) return const <String>[];

    final queries = <String>{};
    final primaryVariants = _artistQueryVariants(track.primaryArtist);
    for (final artist in primaryVariants) {
      queries.add('$artist $coreTitle');
      queries.add('$coreTitle $artist');
    }
    // Spotify collaborations can surface under any credited performer.
    for (final artist in track.artists.skip(1).take(4)) {
      for (final variant in _artistQueryVariants(artist).take(2)) {
        queries.add('$variant $coreTitle');
        queries.add('$coreTitle $variant');
      }
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

  /// A short query set that includes punctuation-free artist aliases. This is
  /// especially useful for Indonesian stage names such as `NDX A.K.A.` which
  /// YouTube indexes as `NDX AKA` or `NDXAKA`.
  static List<String> buildFastSearchQueries(SpotifyPlaylistTrack track) {
    final coreTitle = _searchCoreTitle(track.title);
    if (coreTitle.isEmpty) return const <String>[];

    final queries = <String>{};
    final primaryVariants = _artistQueryVariants(track.primaryArtist);
    // Try every useful spelling for punctuation-heavy aliases such as
    // NDX A.K.A. -> NDX AKA -> NDXAKA. The exact and compact forms matter
    // because YouTube search indexes these channel names inconsistently.
    for (final artist in primaryVariants.take(3)) {
      queries.add('$artist $coreTitle');
    }

    if (track.artists.length > 1) {
      final collaborator = track.artists[1].trim();
      if (collaborator.isNotEmpty) queries.add('$collaborator $coreTitle');
    }

    queries.add(coreTitle);
    return queries
        .map((query) => query.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((query) => query.isNotEmpty)
        .take(5)
        .toList(growable: false);
  }

  /// Title-only fallbacks run after focused artist+title queries. YouTube
  /// sometimes indexes a song under its title while keeping the performer only
  /// in structured credits; the final matcher still verifies title, artist and
  /// duration before importing anything.
  static List<String> buildTitleOnlyFallbackQueries(SpotifyPlaylistTrack track) {
    final queries = <String>{};
    final coreTitle = _searchCoreTitle(track.title);
    if (coreTitle.isNotEmpty) queries.add(coreTitle);
    final fullTitle = track.title.trim();
    if (fullTitle.isNotEmpty) queries.add(fullTitle);
    return queries.toList(growable: false);
  }

  /// Artist-only fallback queries run only after focused artist+title search.
  /// Every returned video still passes the strict title/artist/duration matcher.
  static List<String> buildArtistOnlyFallbackQueries(SpotifyPlaylistTrack track) {
    final queries = <String>{};
    for (var index = 0; index < track.artists.length && index < 4; index++) {
      final artist = track.artists[index];
      // The primary artist gets all three useful forms (e.g. NDX A.K.A.,
      // NDX AKA, NDXAKA); collaborator fallbacks stay bounded to two forms.
      final variants = _artistQueryVariants(artist).take(index == 0 ? 3 : 2);
      for (final variant in variants) {
        final normalized = variant.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (normalized.isNotEmpty) queries.add(normalized);
      }
    }
    return queries.toList(growable: false);
  }

  static List<String> _artistQueryVariants(String rawArtist) {
    final artist = rawArtist.trim();
    if (artist.isEmpty) return const <String>[];
    final variants = <String>{artist};
    final punctuationFree = artist
        .replaceAll(RegExp(r'[.]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (punctuationFree.isNotEmpty) variants.add(punctuationFree);
    final compact = punctuationFree.replaceAll(
      RegExp(r'[^a-zA-Z0-9\u0080-\uFFFF]'),
      '',
    );
    if (compact.length >= 6 && compact != punctuationFree) {
      variants.add(compact);
    }
    return variants.toList(growable: false);
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
    var bestScore = double.negativeInfinity;
    var bestOfficialRank = -1;
    for (final candidate in candidates) {
      final explicitlyMarkedCover =
          YoutubeMusicPolicy.isExplicitCoverVersion(candidate);
      if (candidate.isLocal ||
          !YoutubeMusicPolicy.isSpotifyImportCandidate(candidate) ||
          (_isClearlyUnofficialChannel(candidate.channelTitle) &&
              !explicitlyMarkedCover)) {
        continue;
      }

      // Structured YouTube Music performer/title credits are stronger than
      // a copied artist name in a fan-upload title. If both fields are present
      // and contradict Spotify, do not pass this off as the original recording.
      if (!explicitlyMarkedCover &&
          _hasContradictoryStructuredMusicData(spotifyTrack, candidate)) {
        continue;
      }

      if (!explicitlyMarkedCover &&
          _hasUnrequestedAlternateVersion(candidate.title, spotifyTrack.title)) {
        final expectedSeconds = spotifyTrack.durationMs == null
            ? null
            : spotifyTrack.durationMs! / 1000.0;
        final actualSeconds = candidate.durationSeconds;
        final sameRecordingLength = expectedSeconds != null &&
            actualSeconds != null &&
            (expectedSeconds - actualSeconds).abs() <= 8;
        final isOfficialLiveMusic = RegExp(
          r'\bofficial\s+live\s+music\b',
          caseSensitive: false,
        ).hasMatch(candidate.title);
        final containsOtherAlternate = RegExp(
          r'\b(?:remix|acoustic|instrumental|slowed|sped[ -]?up|nightcore|reverb|karaoke)\b',
          caseSensitive: false,
        ).hasMatch(candidate.title);
        // Some Indonesian labels publish their full-song upload under the
        // conventional title `Official Live Music`. Accept that special case
        // only with verified label/artist credits and an almost exact runtime.
        // Remix/acoustic/slowed variants are never promoted as the original.
        if (!isOfficialLiveMusic || containsOtherAlternate ||
            _officialSourceRank(spotifyTrack, candidate) < 4 ||
            !sameRecordingLength) {
          continue;
        }
      }

      final titleCoverage = _tokenCoverage(spotifyTrack.title, candidate.title);
      final titleScore = _similarity(spotifyTrack.title, candidate.title);
      final artistScore = _artistSimilarity(spotifyTrack, candidate);
      final durationPenalty = _durationMismatchPenalty(spotifyTrack, candidate);
      final alternatePenalty = _alternateVersionPenalty(
        candidate.title,
        spotifyTrack.title,
      );

      int officialRank;
      double score;
      final expectedSecondsForFallback = spotifyTrack.durationMs == null
          ? null
          : spotifyTrack.durationMs! / 1000.0;
      final actualSecondsForFallback = candidate.durationSeconds;
      final fallbackDurationClose = expectedSecondsForFallback != null &&
          actualSecondsForFallback != null &&
          (expectedSecondsForFallback - actualSecondsForFallback).abs() <= 25;
      final fallbackPopular = (candidate.viewCount ?? 0) >= 100000;
      if (explicitlyMarkedCover) {
        // A cover is a deliberate fallback for Spotify import only. The
        // original/artist-owned/label candidate always outranks it. Require a
        // near-exact song title plus corroboration from duration or popularity
        // so a different song with a generic title is not selected by accident.
        final expectedSeconds = spotifyTrack.durationMs == null
            ? null
            : spotifyTrack.durationMs! / 1000.0;
        final actualSeconds = candidate.durationSeconds;
        final durationClose = expectedSeconds != null &&
            actualSeconds != null &&
            (expectedSeconds - actualSeconds).abs() <= 90;
        final establishedCover = (candidate.viewCount ?? 0) >= 1000;
        final titleMatchesStrongly = titleCoverage >= 0.95 && titleScore >= 0.76;
        if (!titleMatchesStrongly || (!durationClose && !establishedCover)) {
          continue;
        }
        officialRank = 1; // lower priority than every verified original source
        score = (titleScore * 0.82) +
            (durationClose ? 0.12 : 0) +
            ((candidate.viewCount ?? 0) >= 10000 ? 0.06 : 0) -
            durationPenalty;
      } else {
        // Do not replace a Spotify studio recording with a different-length
        // recording just because the title and singer happen to match. Small
        // intros/outros are tolerated; large duration gaps are treated as a
        // different arrangement/version. Explicit covers use their own fallback
        // gate above and are considered only after originals are exhausted.
        if (expectedSecondsForFallback != null &&
            actualSecondsForFallback != null &&
            (expectedSecondsForFallback - actualSecondsForFallback).abs() > 24) {
          continue;
        }
        score = (titleScore * 0.64) + (artistScore * 0.36) -
            durationPenalty - alternatePenalty;

        // Require near-complete title coverage and a strong Spotify-performer
        // signal before considering source authority. A fake "Official" label
        // can never rescue a wrong title or wrong performer.
        final acceptable = titleCoverage >= 0.85 &&
            titleScore >= 0.62 &&
            artistScore >= 0.82 &&
            score >= 0.70;
        if (!acceptable) continue;

        // YouTube search relevance is not a source-authenticity signal. Prefer
        // Topic/VEVO, structured distributor credits, and artist/label uploads.
        officialRank = _officialSourceRank(spotifyTrack, candidate);
        if (_hasUnrequestedAlternateVersion(candidate.title, spotifyTrack.title) &&
            officialRank > 2) {
          // The sole alternate upload admitted above is a verified Official
          // Live Music fallback. Keep it below studio/original releases even
          // when its uploader is an artist Topic channel or a trusted label.
          officialRank = 2;
        }
        // Rank 2 means YouTube's result has an explicit official/resmi marker,
        // but the channel could not be mapped to a known artist/label account.
        // That is acceptable only after the independent title + artist gates
        // above have already passed; a copied "Official" word alone cannot win.
        if (officialRank < 2) {
          // Some Indonesian label/distributor uploads have no `Official`
          // marker and are not on a channel that can be mapped to the artist.
          // Since Spotify import may use a cover as a fallback, allow this
          // lower-confidence tier only when the title is near-exact, a Spotify
          // performer is independently visible in the candidate, and either
          // duration or substantial views corroborate the recording. Explicit
          // official/Topic/VEVO/structured-credit matches retain higher ranks.
          final corroboratedUnlabelledUpload = titleCoverage >= 0.95 &&
              titleScore >= 0.84 &&
              artistScore >= 0.90 &&
              alternatePenalty == 0 &&
              (fallbackDurationClose || fallbackPopular);
          if (!corroboratedUnlabelledUpload) continue;
          officialRank = 2;
        }
      }

      // Verified official/original uploads outrank covers regardless of views.
      // Among equal source tiers, prefer the stronger title/artist/duration fit.
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
      final isCover = YoutubeMusicPolicy.isExplicitCoverVersion(candidate);
      if (candidate.isLocal ||
          !YoutubeMusicPolicy.isSpotifyImportCandidate(candidate) ||
          (_isClearlyUnofficialChannel(candidate.channelTitle) && !isCover)) {
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
    if (match == null ||
        YoutubeMusicPolicy.isExplicitCoverVersion(match) ||
        _hasUnrequestedAlternateVersion(match.title, spotifyTrack.title)) {
      return false;
    }
    return _officialSourceRank(spotifyTrack, match) >= 5;
  }

  /// Only a verified original/label/artist source ends the fallback search.
  /// Rank 3 popular third-party uploads and every cover keep searching so a
  /// later query can still find the actual recording.
  static bool hasHighConfidenceMatch(
    SpotifyPlaylistTrack spotifyTrack,
    List<YoutubeSearchResult> candidates,
  ) {
    final match = bestMatch(spotifyTrack, candidates);
    if (match == null ||
        YoutubeMusicPolicy.isExplicitCoverVersion(match) ||
        _hasUnrequestedAlternateVersion(match.title, spotifyTrack.title)) {
      return false;
    }
    return _officialSourceRank(spotifyTrack, match) >= 4;
  }

  static int _officialSourceRank(
    SpotifyPlaylistTrack track,
    YoutubeSearchResult candidate,
  ) {
    final artists = track.artists
        .map(_normalizeChannelIdentity)
        .where((artist) => artist.isNotEmpty)
        .toList(growable: false);
    if (artists.isEmpty) return 0;

    bool matchesAnyArtist(bool Function(String artist) test) =>
        artists.any(test);

    final channelRaw = candidate.channelTitle.trim();
    final title = candidate.title.toLowerCase();
    final description = candidate.description;
    final artistOwnChannel = matchesAnyArtist(
      (artist) => _isArtistOwnedChannel(channelRaw, artist),
    );
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
      r'\b(?:official\s+(?:audio|video|music\s+video|live\s+music|live\s+performance|lyrics?|visualizer)|music\s+video\s+official|audio\s+resmi|video\s+resmi)\b',
      caseSensitive: false,
    ).hasMatch(title);
    final providedToYoutube = RegExp(
      r'provided to youtube by',
      caseSensitive: false,
    ).hasMatch(description);
    final normalizedTrackTitle = _normalizeTrackTitle(track.title);
    final structuredDistributorCredit = providedToYoutube &&
        matchesAnyArtist(
          (artist) => _hasExplicitDescriptionCredit(
            description,
            artist,
            normalizedTrackTitle,
          ),
        );
    final directLabelArtistCredit = matchesAnyArtist(
      (artist) => _hasDirectDescriptionArtistCredit(description, artist),
    );

    // Any credited Spotify collaborator may own the source channel. This
    // handles duet uploads where YouTube puts the second performer first.
    if ((topicChannel || vevoChannel) && artistOwnChannel) return 6;
    if (artistOwnChannel) return 5;

    if (structuredDistributorCredit ||
        (directLabelArtistCredit &&
            (officialTitle || officialChannel ||
                _isKnownMusicLabelChannel(channelRaw)))) {
      return 4;
    }

    if (_matchesStructuredMusicData(track, candidate)) return 4;
    final parsedArtist = _normalizeArtistText(candidate.artistName);
    final parsedCreditMatches = parsedArtist.isNotEmpty &&
        matchesAnyArtist(
          (artist) => _artistCreditMatches(
            parsedArtist,
            _normalizeArtistText(artist),
          ),
        ) &&
        _tokenCoverage(track.title, candidate.title) >= 0.90 &&
        _similarity(track.title, candidate.title) >= 0.78;
    if (parsedCreditMatches) return 4;

    final views = candidate.viewCount ?? 0;
    final popularThirdParty = views >= 100000;
    final establishedThirdParty = views >= 25000;
    final titleCreditsArtist = matchesAnyArtist(
      (artist) => _artistCreditMatches(
        _normalizeArtistText(candidate.title),
        _normalizeArtistText(artist),
      ),
    );
    final titleIsNearExact =
        _tokenCoverage(track.title, candidate.title) >= 0.98 &&
        _similarity(track.title, candidate.title) >= 0.90;

    final expectedDuration = track.durationMs == null
        ? null
        : track.durationMs! / 1000.0;
    final actualDuration = candidate.durationSeconds;
    final durationCorroborates = expectedDuration != null &&
        actualDuration != null &&
        (expectedDuration - actualDuration).abs() <= 12;

    if (titleIsNearExact &&
        titleCreditsArtist &&
        (popularThirdParty || (establishedThirdParty && durationCorroborates))) {
      return 3;
    }
    if (_isKnownMusicLabelChannel(channelRaw) && officialTitle) return 3;

    // The final matcher has already verified a near-complete song title and a
    // credited Spotify performer. Let an explicit official marker serve as
    // the last source signal even when the channel is a small regional label.
    if (officialTitle || officialChannel) return 2;
    if (_isKnownMusicLabelChannel(channelRaw)) return 2;
    return 0;
  }

  static bool _hasContradictoryStructuredMusicData(
    SpotifyPlaylistTrack track,
    YoutubeSearchResult candidate,
  ) {
    final dataTitle = candidate.musicDataTitle.trim();
    final dataArtist = candidate.musicDataArtist.trim();
    if (dataTitle.isEmpty || dataArtist.isEmpty) return false;
    // Metadata services sometimes omit a Spotify title suffix such as
    // `- Reggae`; allow a partial but clearly related title while still
    // rejecting a structured credit for an unrelated song.
    final titleMatches = _tokenCoverage(track.title, dataTitle) >= 0.60 &&
        _similarity(track.title, dataTitle) >= 0.68;
    final artistMatches = track.artists.any(
      (artist) => _artistCreditMatches(
        _normalizeArtistText(dataArtist),
        _normalizeArtistText(artist),
      ),
    );
    return !titleMatches || !artistMatches;
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
    final artistMatches = track.artists.any((artist) => _artistCreditMatches(
          _normalizeArtistText(structuredArtist),
          _normalizeArtistText(artist),
        ));
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
      'musik proaktif',
      'proaktif',
      'global musik era digital',
      'pelita utama',
      'henny adella',
      'milady record official',
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
      sourceVideoTitle: candidate.sourceVideoTitle.isNotEmpty
          ? candidate.sourceVideoTitle
          : candidate.title,
      spotifyTrackId: track.spotifyTrackId,
      spotifyDurationMs: track.durationMs,
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
    final withoutCoverAttribution = withoutFeature
        .replaceFirst(
          RegExp(r'\s*[|–—-]\s*(?:cover(?:ed)?\s+by|cover)\b.*$', caseSensitive: false),
          '',
        )
        .replaceFirst(
          RegExp(r'\s*\((?:[^)]{0,50}\bcover\b[^)]*)\)\s*$', caseSensitive: false),
          '',
        );
    return _normalize(withoutCoverAttribution);
  }

  static Set<String> _tokens(String value) => _normalizeTrackTitle(value)
      .split(' ')
      .where((token) => token.isNotEmpty)
      .toSet();

  // Spotify's title is canonical metadata, so its `feat.` suffix can be
  // removed from the expected song title. A YouTube title is different: many
  // official regional releases put the performers BEFORE the song title, for
  // example `Northsle feat. Agiff - Bubrah`. Running `_searchCoreTitle` on that
  // candidate would delete everything after `feat.` including `Bubrah`, which
  // made real releases look like zero-title/empty matches.
  static String _normalizeCandidateTrackTitle(String value) {
    final withoutSourceAttribution = value.replaceFirst(
      RegExp(r'\s+[-–—]\s*from\s+.+$', caseSensitive: false),
      '',
    );
    final withoutCoverAttribution = withoutSourceAttribution
        .replaceFirst(
          RegExp(
            r'\s*[|–—-]\s*(?:cover(?:ed)?\s+by|cover)\b.*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(r'\s*\((?:[^)]{0,50}\bcover\b[^)]*)\)\s*$', caseSensitive: false),
          '',
        );
    // Keep collaborator names as harmless extra tokens. `_normalize` removes
    // the word `feat` itself, while title coverage still finds the full song
    // name regardless of whether the title occurs before or after the credit.
    return _normalize(withoutCoverAttribution);
  }

  static Set<String> _candidateTokens(String value) =>
      _normalizeCandidateTrackTitle(value)
          .split(' ')
          .where((token) => token.isNotEmpty)
          .toSet();

  static double _tokenCoverage(String expectedTitle, String candidateTitle) {
    final expected = _tokens(expectedTitle);
    final candidate = _candidateTokens(candidateTitle);
    if (expected.isEmpty || candidate.isEmpty) return 0;
    return expected.intersection(candidate).length / expected.length;
  }

  static double _similarity(String first, String second) {
    final a = _tokens(first);
    final b = _candidateTokens(second);
    if (a.isEmpty || b.isEmpty) return 0;

    final intersection = a.intersection(b).length;
    final dice = (2 * intersection) / (a.length + b.length);
    final titleCoverage = intersection / a.length;
    final normalizedA = _normalizeTrackTitle(first);
    final normalizedB = _normalizeCandidateTrackTitle(second);
    if (normalizedA.isNotEmpty &&
        (normalizedA == normalizedB ||
            normalizedB.startsWith('$normalizedA ') ||
            normalizedB.endsWith(' $normalizedA'))) {
      return dice < 0.94 ? 0.94 : dice;
    }

    // YouTube often prefixes several performer credits or appends the artist
    // after a dash. Full Spotify title coverage therefore matters more than raw
    // token Dice, especially for short regional song titles.
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
    final structuredArtist = _normalizeArtistText(candidate.musicDataArtist);
    final parsedOfficialArtist = _normalizeArtistText(candidate.artistName);
    final structuredMusicDataMatches =
        _matchesStructuredMusicData(spotifyTrack, candidate);

    var bestScore = 0.0;
    for (var index = 0; index < artists.length; index++) {
      final normalizedArtist = _normalizeArtistText(artists[index]);
      if (normalizedArtist.length < 2) continue;

      final inTitle = _artistCreditMatches(titleText, normalizedArtist);
      final inChannel = _artistCreditMatches(channelText, normalizedArtist);
      final explicitlyCredited = _hasExplicitDescriptionCredit(
        candidate.description,
        normalizedArtist,
        _normalizeTrackTitle(spotifyTrack.title),
      );
      final directlyCredited = _hasDirectDescriptionArtistCredit(
        candidate.description,
        normalizedArtist,
      );
      final inStructuredData = structuredArtist.isNotEmpty &&
          _artistCreditMatches(structuredArtist, normalizedArtist);
      final inParsedCredit = parsedOfficialArtist.isNotEmpty &&
          _artistCreditMatches(parsedOfficialArtist, normalizedArtist);

      if (!inTitle &&
          !inChannel &&
          !explicitlyCredited &&
          !directlyCredited &&
          !structuredMusicDataMatches &&
          !inStructuredData &&
          !inParsedCredit) {
        continue;
      }

      var score = (inStructuredData || inParsedCredit ||
              structuredMusicDataMatches || inTitle)
          ? 1.0
          : inChannel
              ? 0.96
              : (explicitlyCredited || directlyCredited)
                  ? 0.94
                  : 0.90;
      // Primary credit is strongest, but a second Spotify collaborator can be
      // the visible YouTube performer on a duet/label upload. Keep that evidence
      // strong enough to match while retaining a tiny primary-credit preference.
      if (index > 0) score -= 0.015;
      if (score > bestScore) bestScore = score;
    }
    return bestScore;
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

    // Some official channel/title spellings concatenate the performer name
    // (`GUYONWATON`) or remove punctuation from abbreviations (`NDX AKA`),
    // while Spotify stores the spaced form (`Guyon Waton`, `NDX A.K.A.`).
    // Compact matching is restricted to longer names to avoid accidental hits
    // on short artist names embedded in unrelated words.
    final compactArtist = normalizedArtist.replaceAll(' ', '');
    if (compactArtist.length >= 6 &&
        normalizedText.replaceAll(' ', '').contains(compactArtist)) {
      return true;
    }

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

  static bool _hasDirectDescriptionArtistCredit(
    String rawDescription,
    String normalizedArtist,
  ) {
    if (rawDescription.trim().isEmpty || normalizedArtist.isEmpty) return false;
    final lines = rawDescription.split(RegExp(r'[\r\n]+'));
    final creditLine = RegExp(
      r'^\s*(?:artist|artist name|singer|vocal(?:s)?|performer|penyanyi|'
      r'dinyanyikan oleh|dibawakan oleh)\s*[:\-]\s*(.+?)\s*$',
      caseSensitive: false,
    );
    for (final line in lines) {
      final match = creditLine.firstMatch(line);
      if (match == null) continue;
      final creditedArtist = _normalizeArtistText(match.group(1) ?? '');
      if (_artistCreditMatches(creditedArtist, normalizedArtist)) return true;
    }
    return false;
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
    // delivery marker AND a nearby block that credits this exact track to a
    // Spotify-listed performer. This prevents copied artist mentions in promo
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
              .intersection(_candidateTokens(window))
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

  static bool _hasUnrequestedAlternateVersion(
    String candidateTitle,
    String expectedTitle,
  ) {
    final candidate = candidateTitle.toLowerCase();
    final expected = expectedTitle.toLowerCase();
    const markers = <String, String>{
      'live': r'\blive\b|\blive\s+(?:music|session|performance|concert)\b',
      'remix': r'\bremix(?:ed)?\b',
      'acoustic': r'\bacoustic\b',
      'instrumental': r'\binstrumental\b',
      'slowed': r'\bslowed\b',
      'sped-up': r'\bsped[ -]?up\b',
      'nightcore': r'\bnightcore\b',
      'reverb': r'\breverb\b',
      'karaoke': r'\bkaraoke\b',
    };
    for (final entry in markers.entries) {
      if (RegExp(entry.value, caseSensitive: false).hasMatch(candidate) &&
          !RegExp(entry.value, caseSensitive: false).hasMatch(expected)) {
        return true;
      }
    }
    return false;
  }

  static double _alternateVersionPenalty(
    String candidateTitle,
    String expectedTitle,
  ) {
    const alternateMarkers = <String>[
      r'\bacoustic\b',
      r'\binstrumental\b',
      r'\bremix\b',
      r'\bsped\s*up\b',
      r'\bslowed\b',
      r'\bnightcore\b',
      r'\blive\s+concert\b',
      r'\blive\s+performance\b',
      r'\bconcert\s+version\b',
    ];
    final candidate = candidateTitle.toLowerCase();
    final expected = expectedTitle.toLowerCase();
    // A verified `Official Live Music` upload is allowed only as a fallback
    // for regional releases, but it must lose to a studio candidate of the
    // same source tier. Keep the penalty modest so it remains usable alone.
    if (RegExp(r'\bofficial\s+live\s+music\b').hasMatch(candidate) &&
        !RegExp(r'\blive\b').hasMatch(expected)) {
      return 0.12;
    }
    for (final marker in alternateMarkers) {
      if (RegExp(marker).hasMatch(candidate) &&
          !RegExp(marker).hasMatch(expected)) {
        return 0.31;
      }
    }
    return 0;
  }
}
