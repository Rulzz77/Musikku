import '../services/youtube_music_metadata_parser.dart';
import 'youtube_search_result.dart';

/// Stable identity for a track in a user playlist.
/// Video ID is authoritative. Spotify imports may resolve to a different
/// YouTube video ID later, so a conservative title + performer check follows.
class PlaylistTrackIdentity {
  static bool matches(YoutubeSearchResult first, YoutubeSearchResult second) {
    if (first.videoId.isNotEmpty && first.videoId == second.videoId) {
      return true;
    }
    if (first.isLocal || second.isLocal) return false;
    if (_isAlternateOrUnofficialUpload(first) ||
        _isAlternateOrUnofficialUpload(second)) {
      return false;
    }

    final artistNames = <String>{
      ..._artistNames(first),
      ..._artistNames(second),
    };
    final firstTitle = _canonicalTitle(first.title, artistNames);
    final secondTitle = _canonicalTitle(second.title, artistNames);
    if (firstTitle.isEmpty || secondTitle.isEmpty || firstTitle != secondTitle) {
      return false;
    }

    return _artistEvidenceMatches(first, second);
  }

  static bool _artistEvidenceMatches(
    YoutubeSearchResult first,
    YoutubeSearchResult second,
  ) {
    final firstArtist = _explicitArtist(first);
    final secondArtist = _explicitArtist(second);

    // A collaboration can surface under a different primary artist on
    // YouTube than Spotify's display order. Accept a shared credited performer
    // from the Spotify collaborator list, but never match on title alone.
    if (firstArtist.isNotEmpty && secondArtist.isNotEmpty) {
      if (_sameArtist(firstArtist, secondArtist)) return true;
      if (_channelCreditsContain(first.channelTitle, secondArtist) ||
          _channelCreditsContain(second.channelTitle, firstArtist)) {
        return true;
      }
      return false;
    }

    // Spotify-imported entries have a canonical artistName. A later YouTube
    // result may be uploaded by a label, so channelTitle alone must not be
    // mistaken for the performer. Look for structured music credits, an
    // artist-owned/Topic channel, or an artist credit in the video title.
    if (firstArtist.isNotEmpty) {
      return _hasArtistEvidence(
        second,
        firstArtist,
        referenceTitle: first.title,
        referenceSourceChannel: first.sourceChannelTitle,
      );
    }
    if (secondArtist.isNotEmpty) {
      return _hasArtistEvidence(
        first,
        secondArtist,
        referenceTitle: second.title,
        referenceSourceChannel: second.sourceChannelTitle,
      );
    }

    // Legacy playlist entries without structured credits use channel identity.
    final firstChannel = _normalizeArtist(_cleanChannel(first.channelTitle));
    final secondChannel = _normalizeArtist(_cleanChannel(second.channelTitle));
    return firstChannel.isNotEmpty &&
        secondChannel.isNotEmpty &&
        _sameArtist(firstChannel, secondChannel);
  }

  static String _explicitArtist(YoutubeSearchResult song) {
    final stored = _normalizeArtist(song.artistName);
    if (stored.isNotEmpty) return stored;

    // Re-read structured credits for older saved results that predate
    // artistName being populated by the YouTube response parser.
    final metadata = YoutubeMusicMetadataParser.parse(
      title: song.title,
      description: song.description,
    );
    return _normalizeArtist(metadata.artistName);
  }

  static bool _hasArtistEvidence(
    YoutubeSearchResult song,
    String expectedArtist, {
    required String referenceTitle,
    required String referenceSourceChannel,
  }) {
    final expected = _normalizeArtist(expectedArtist);
    if (expected.isEmpty) return false;

    final explicit = _explicitArtist(song);
    if (explicit.isNotEmpty) return _sameArtist(explicit, expected);

    // A channel counts as performer evidence only if its identity matches the
    // credited artist. A label/distributor channel is not the singer.
    final candidateChannels = <String>[
      song.channelTitle,
      song.sourceChannelTitle,
    ];
    for (final rawChannel in candidateChannels) {
      final channel = _normalizeArtist(_cleanChannel(rawChannel));
      if (channel.isNotEmpty && _sameArtist(channel, expected)) return true;
    }

    // If the playlist entry was imported from a label/distributor, another
    // result from that same exact uploader is also a valid identity match.
    // This is useful when the search result has no description/artist field.
    final referenceChannel = _normalizeArtist(
      _cleanChannel(referenceSourceChannel),
    );
    if (referenceChannel.isNotEmpty &&
        candidateChannels.any((raw) =>
            _normalizeArtist(_cleanChannel(raw)) == referenceChannel)) {
      return true;
    }

    // The artist appearing in the title is not enough on an unknown uploader;
    // a fan re-upload can copy those words. Allow this fallback only for a
    // known label/distributor channel. Other labels should carry structured
    // YouTube Music metadata, handled above by _explicitArtist().
    final fromKnownLabel = candidateChannels.any(_looksLikeLabel);
    return fromKnownLabel &&
        _titleContainsArtist(song.title, referenceTitle, expected);
  }

  static Set<String> _artistNames(YoutubeSearchResult song) {
    final names = <String>{};
    void add(String raw) {
      final cleaned = raw.trim();
      final normalized = _normalizeArtist(cleaned);
      if (normalized.length > 1) names.add(normalized);
      const stageNameExceptions = <String>{
        'earth, wind & fire',
        'crosby, stills & nash',
        'emerson, lake & palmer',
        'tyler, the creator',
      };
      if (stageNameExceptions.contains(cleaned.toLowerCase())) return;
      for (final part in cleaned.split(RegExp(
        r',|\s+&\s+|\s+feat(?:uring)?\.?\s+|\s+ft\.?\s+',
        caseSensitive: false,
      ))) {
        final partKey = _normalizeArtist(part);
        if (partKey.length > 1) names.add(partKey);
      }
    }

    add(song.artistName);
    final metadata = YoutubeMusicMetadataParser.parse(
      title: song.title,
      description: song.description,
    );
    add(metadata.artistName);

    final channel = _cleanChannel(song.channelTitle);
    if (!_looksLikeLabel(channel)) add(channel);
    return names;
  }

  static bool _isAlternateOrUnofficialUpload(YoutubeSearchResult song) {
    final searchable = '${song.title} ${song.channelTitle} ${song.sourceChannelTitle}';
    return RegExp(
      r'\b(?:karaoke|instrumental|nightcore|sped[ -]?up|slowed|re[ -]?upload|unofficial|fan[ -]?(?:made|upload)|cover[ -]?(?:by|version|song)|(?:acoustic|piano|guitar) cover|ai cover|suno|udio)\b',
      caseSensitive: false,
    ).hasMatch(searchable);
  }

  static bool _channelCreditsContain(String rawCredits, String expectedArtist) {
    final expected = _normalizeArtist(expectedArtist);
    if (expected.isEmpty || rawCredits.trim().isEmpty) return false;
    const stageNameExceptions = <String>{
      'earth, wind & fire',
      'crosby, stills & nash',
      'emerson, lake & palmer',
      'tyler, the creator',
    };
    final cleaned = rawCredits.trim();
    if (stageNameExceptions.contains(cleaned.toLowerCase())) {
      return _sameArtist(cleaned, expected);
    }
    final credits = cleaned.split(RegExp(
      r',|\s+&\s+|\s+feat(?:uring)?\.?\s+|\s+ft\.?\s+',
      caseSensitive: false,
    ));
    return credits.any((credit) => _sameArtist(credit, expected));
  }

  static bool _looksLikeLabel(String raw) {
    final value = _normalizeArtist(raw);
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
      'believe',
      'believe sas',
      'believe music',
      'md music',
      'nagaswara',
      'aquarius musikindo',
      'gp records',
      'ascada musik',
      'my music records',
      'falcon music',
      'source music',
      'pledis entertainment',
      'cube entertainment',
      'starship entertainment',
      'star media nusantara',
      'emotion entertainment',
      'hybe labels',
      'jyp entertainment',
      'yg entertainment',
      'sm entertainment',
      'smtown',
    ];
    return labels.any((label) => value == label);
  }

  static String _cleanChannel(String raw) => raw
      .replaceFirst(RegExp(r'\s*[-–—|]\s*topic$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*vevo$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+(?:official\s+)?(?:artist\s+)?channel$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s+official$', caseSensitive: false), '')
      .trim();

  static bool _sameArtist(String first, String second) {
    final a = _normalizeArtist(first);
    final b = _normalizeArtist(second);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.replaceAll(' ', '') == b.replaceAll(' ', '')) return true;

    final aTokens = a.split(' ');
    final bTokens = b.split(' ');
    if (aTokens.length == bTokens.length + 1 && aTokens.first.length == 1) {
      return aTokens.skip(1).join(' ') == b;
    }
    if (bTokens.length == aTokens.length + 1 && bTokens.first.length == 1) {
      return bTokens.skip(1).join(' ') == a;
    }
    return false;
  }

  static bool _titleContainsArtist(
    String candidateTitle,
    String referenceTitle,
    String artist,
  ) {
    final candidate = _normalizeTitle(candidateTitle);
    final reference = _normalizeTitle(referenceTitle);
    final artistKey = _normalizeArtist(artist);
    if (candidate.isEmpty || reference.isEmpty || artistKey.isEmpty) return false;
    if (candidate == reference) return false;

    final remainder = candidate.replaceAll(
      RegExp(r'(?:^|\s)' + RegExp.escape(reference) + r'(?=\s|$)'),
      ' ',
    );
    return _containsPhrase(_normalizeArtist(remainder), artistKey);
  }

  static String _canonicalTitle(String raw, Set<String> artistNames) {
    var value = _normalizeTitle(raw);
    final orderedNames = artistNames.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final artist in orderedNames) {
      if (artist.isEmpty) continue;
      value = value.replaceAll(
        RegExp(r'(?:^|\s)' + RegExp.escape(artist) + r'(?=\s|$)'),
        ' ',
      );
    }
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizeTitle(String raw) => raw
      .toLowerCase()
      .replaceFirst(RegExp(r'\s+[-–—]\s*from\s+.+$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'\s*\(\s*from\s+[^)]*\)\s*$', caseSensitive: false), '')
      .replaceAll(
        RegExp(r'[([][^)\]]*(?:official|audio|video|music\s+video|lyrics?|visualizer|4k|hd|mv)[^)\]]*[)\]]', caseSensitive: false),
        ' ',
      )
      .replaceAll(
        RegExp(r'\b(?:official\s+(?:audio|video|music\s+video|lyrics?|visualizer)|music\s+video|audio\s+only|lyrics?\s+video|visualizer|official)\b', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _normalizeArtist(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'\s*[-–—|]\s*(?:topic|vevo)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+(?:official\s+)?(?:artist\s+)?channel$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+official$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _containsPhrase(String text, String phrase) =>
      text.isNotEmpty && phrase.isNotEmpty && ' $text '.contains(' $phrase ');
}
