import '../services/youtube_music_metadata_parser.dart';
import 'youtube_search_result.dart';

/// Stable identity for a track in a user playlist.
/// Video ID is authoritative. Spotify imports may resolve to a different
/// YouTube video ID later, so a conservative title + performer check follows.
class PlaylistTrackIdentity {
  static bool matches(YoutubeSearchResult first, YoutubeSearchResult second) {
    // A YouTube video ID is the strongest identity for a saved media item.
    if (first.videoId.isNotEmpty && first.videoId == second.videoId) {
      return true;
    }
    if (first.isLocal || second.isLocal) return false;

    // Spotify's track ID identifies the recording, not merely its display
    // title. When both sides carry it, never collapse different Spotify tracks.
    final firstSpotifyId = first.spotifyTrackId.trim();
    final secondSpotifyId = second.spotifyTrackId.trim();
    if (firstSpotifyId.isNotEmpty && secondSpotifyId.isNotEmpty) {
      return firstSpotifyId == secondSpotifyId;
    }

    // The import stores the original YouTube title separately because the
    // visible title is replaced with Spotify's clean display title. Compare
    // version tags before falling back to title/artist matching: studio and
    // live/remix/acoustic/cover recordings are not interchangeable.
    if (!_sameVersionFamily(first, second)) return false;

    if (_isAlternateOrUnofficialUpload(first) ||
        _isAlternateOrUnofficialUpload(second)) {
      return false;
    }

    final firstDuration = _durationMilliseconds(first);
    final secondDuration = _durationMilliseconds(second);
    // Same title + same singer is not enough. If the source durations are not
    // available, only exact video ID or Spotify ID above can prove identity.
    if (firstDuration == null || secondDuration == null) return false;
    final tolerance = (firstDuration * 0.04).clamp(8000, 14000).toDouble();
    if ((firstDuration - secondDuration).abs() > tolerance) return false;

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

  static int? _durationMilliseconds(YoutubeSearchResult song) {
    final spotifyDuration = song.spotifyDurationMs;
    if (spotifyDuration != null && spotifyDuration > 0) return spotifyDuration;
    final seconds = song.durationSeconds;
    if (seconds == null || seconds <= 0) return null;
    return (seconds * 1000).round();
  }

  static bool _sameVersionFamily(
    YoutubeSearchResult first,
    YoutubeSearchResult second,
  ) {
    final firstMarkers = _versionMarkers(first);
    final secondMarkers = _versionMarkers(second);
    return firstMarkers.length == secondMarkers.length &&
        firstMarkers.containsAll(secondMarkers);
  }

  static Set<String> _versionMarkers(YoutubeSearchResult song) {
    final rawTitle = [
      song.sourceVideoTitle,
      song.title,
    ].where((value) => value.trim().isNotEmpty).join(' ').toLowerCase();
    final markers = <String>{};
    void add(String marker, String pattern) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(rawTitle)) {
        markers.add(marker);
      }
    }

    add('live', r'\blive\b|\blive\s+(?:music|session|performance|concert)\b');
    add('remix', r'\bremix(?:ed)?\b');
    add('acoustic', r'\bacoustic\b');
    add('instrumental', r'\binstrumental\b');
    add('karaoke', r'\bkaraoke\b');
    add('cover', r'\bcover(?:ed)?\b|\bkover\b');
    add('slowed', r'\bslowed\b');
    add('sped-up', r'\bsped[ -]?up\b');
    add('nightcore', r'\bnightcore\b');
    add('reverb', r'\breverb\b');
    add('piano-version', r'\bpiano\s+(?:version|cover)\b');
    add('guitar-version', r'\b(?:guitar|gitar)\s+(?:version|cover)\b');
    return markers;
  }

  static bool _artistEvidenceMatches(
    YoutubeSearchResult first,
    YoutubeSearchResult second,
  ) {
    final firstArtists = _explicitArtists(first);
    final secondArtists = _explicitArtists(second);

    // Spotify imports store the full collaborator list in channelTitle while
    // artistName contains only the primary performer. A YouTube Topic result
    // may surface under the second collaborator, so compare the complete
    // credited sets instead of requiring the primary artist on both sides.
    if (firstArtists.isNotEmpty && secondArtists.isNotEmpty) {
      if (firstArtists.any((left) =>
          secondArtists.any((right) => _sameArtist(left, right)))) {
        return true;
      }
      for (final expected in firstArtists) {
        if (_hasArtistEvidence(
          second,
          expected,
          referenceTitle: first.title,
          referenceSourceChannel: first.sourceChannelTitle,
        )) {
          return true;
        }
      }
      for (final expected in secondArtists) {
        if (_hasArtistEvidence(
          first,
          expected,
          referenceTitle: second.title,
          referenceSourceChannel: second.sourceChannelTitle,
        )) {
          return true;
        }
      }
      return false;
    }

    if (firstArtists.isNotEmpty) {
      return firstArtists.any((expected) => _hasArtistEvidence(
            second,
            expected,
            referenceTitle: first.title,
            referenceSourceChannel: first.sourceChannelTitle,
          ));
    }
    if (secondArtists.isNotEmpty) {
      return secondArtists.any((expected) => _hasArtistEvidence(
            first,
            expected,
            referenceTitle: second.title,
            referenceSourceChannel: second.sourceChannelTitle,
          ));
    }

    // Legacy playlist entries without structured credits use channel identity.
    final firstChannel = _normalizeArtist(_cleanChannel(first.channelTitle));
    final secondChannel = _normalizeArtist(_cleanChannel(second.channelTitle));
    return firstChannel.isNotEmpty &&
        secondChannel.isNotEmpty &&
        _sameArtist(firstChannel, secondChannel);
  }

  static Set<String> _explicitArtists(YoutubeSearchResult song) {
    final names = <String>{};
    void addCredits(String raw) {
      final cleaned = raw.trim();
      const stageNameExceptions = <String>{
        'earth, wind & fire',
        'crosby, stills & nash',
        'emerson, lake & palmer',
        'tyler, the creator',
      };
      if (stageNameExceptions.contains(cleaned.toLowerCase())) {
        final normalized = _normalizeArtist(cleaned);
        if (normalized.isNotEmpty) names.add(normalized);
        return;
      }
      for (final part in cleaned.split(RegExp(
        r',|\s+&\s+|\s+feat(?:uring)?\.?\s+|\s+ft\.?\s+',
        caseSensitive: false,
      ))) {
        final normalized = _normalizeArtist(part);
        if (normalized.isNotEmpty) names.add(normalized);
      }
    }

    addCredits(song.artistName);
    final metadata = YoutubeMusicMetadataParser.parse(
      title: song.title,
      description: song.description,
    );
    addCredits(metadata.artistName);

    // Only treat channelTitle as a multi-artist credit when the entry carries
    // Spotify-import metadata. On ordinary YouTube search results it is the
    // uploader name, not necessarily the performer.
    if (song.spotifyTrackId.trim().isNotEmpty ||
        song.spotifyDurationMs != null ||
        song.sourceVideoTitle.trim().isNotEmpty) {
      addCredits(song.channelTitle);
    }
    return names;
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
