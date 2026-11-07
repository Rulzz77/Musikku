import '../models/youtube_search_result.dart';
import 'spotify_playlist_import_service.dart';
import 'youtube_music_policy.dart';

/// Conservative matcher between Spotify track metadata and MusikKu's
/// YouTube Music search results. A match must agree on the complete song title
/// and the Spotify primary artist; a name buried in an arbitrary description
/// is not sufficient evidence.
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
      final acceptable = titleCoverage >= 0.90 &&
          titleScore >= 0.60 &&
          artistScore >= 0.88 &&
          score >= 0.72;
      if (!acceptable) continue;

      // YouTube search relevance is not a source-authenticity signal. Prefer
      // Topic/VEVO, structured distributor credits, and the artist's own
      // channel over a fan/re-upload mirror whenever both match the same song.
      // Score and duration are tie-breakers only within the same authority tier.
      final officialRank = _officialSourceRank(spotifyTrack, candidate);
      // Never import an unknown uploader merely because the artist name was
      // copied into the video title. Require an artist-owned channel, Topic/
      // VEVO, a known label, or YouTube's structured distributor credits.
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

    // A known label with an explicit official-title marker is a fallback only.
    // It must not stop the query loop before artist-owned results are checked.
    if (_isKnownMusicLabelChannel(channelRaw) && officialTitle) return 3;

    // An official title by itself is not source authentication.
    if (officialTitle || _isKnownMusicLabelChannel(channelRaw) || officialChannel) {
      return 2;
    }
    return 0;
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
        r'\b(?:fan(?:s|[ -]?(?:made|account|page|club|upload(?:s)?))?|unofficial|re-?upload(?:s|ed)?|mirror(?:s)?|archive(?:s)?|karaoke|cover(?:s)?|lyrics?|tribute|nightcore|slowed|sped[ -]?up|reaction(?:s)?|ai[ -]?music)\b',
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
    // the YouTube upload title, e.g. "Song - From \"Film Name\"".
    // Keep it in Spotify's displayed title, but omit that attribution only
    // from matching so a valid soundtrack single is not marked missing.
    final withoutSourceAttribution = value.replaceFirst(
      RegExp(r'\s+[-–—]\s*from\s+.+$', caseSensitive: false),
      '',
    );
    return _normalize(withoutSourceAttribution);
  }

  static Set<String> _tokens(String value) => _normalizeTrackTitle(value)
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

    // Do not accept a candidate merely because the artist name occurs somewhere
    // in its description, tags, or promotional text. Only the title, channel,
    // or a direct "performed by / artist:" credit is considered reliable.
    if (!primaryInTitle && !primaryInChannel && !primaryExplicitlyCredited) {
      return 0;
    }

    var score = primaryInTitle
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
