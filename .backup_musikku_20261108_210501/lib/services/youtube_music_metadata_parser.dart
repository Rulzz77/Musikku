/// Extracts conservative artist/album credits from YouTube Music auto-generated
/// descriptions. It deliberately ignores ordinary descriptions and promotional
/// mentions so a label/channel name is not mistaken for the performer.
class YoutubeMusicReleaseMetadata {
  const YoutubeMusicReleaseMetadata({
    this.artistName = '',
    this.album = '',
  });

  final String artistName;
  final String album;
}

class YoutubeMusicMetadataParser {
  static const _empty = YoutubeMusicReleaseMetadata();

  static YoutubeMusicReleaseMetadata parse({
    required String title,
    required String description,
  }) {
    if (title.trim().isEmpty ||
        description.trim().isEmpty ||
        !RegExp(r'provided to youtube by', caseSensitive: false)
            .hasMatch(description)) {
      return _empty;
    }

    var artistName = '';
    var album = '';
    final titleKey = _normalizeTitle(title);
    final lines = description
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(40);

    for (final line in lines) {
      final albumMatch = RegExp(
        r'^(?:album|album title)\s*[:\-]\s*(.+?)\s*$',
        caseSensitive: false,
      ).firstMatch(line);
      if (albumMatch != null && album.isEmpty) {
        album = _cleanCredit(albumMatch.group(1) ?? '');
        continue;
      }

      final artistMatch = RegExp(
        r'^(?:artist|artists|performed by|vocals? by|dinyanyikan oleh)\s*[:\-]\s*(.+?)\s*$',
        caseSensitive: false,
      ).firstMatch(line);
      if (artistMatch != null && artistName.isEmpty) {
        artistName = _primaryArtist(_cleanCredit(artistMatch.group(1) ?? ''));
        continue;
      }

      if (artistName.isNotEmpty) continue;
      final separator = RegExp(r'\s+(?:[·•]|[-–—])\s+').firstMatch(line);
      if (separator == null) continue;
      final possibleTitle = line.substring(0, separator.start).trim();
      final possibleArtist = _primaryArtist(
        _cleanCredit(line.substring(separator.end).trim()),
      );
      if (possibleArtist.isEmpty || _normalizeTitle(possibleArtist).isEmpty) {
        continue;
      }
      if (_titleCoverage(titleKey, _normalizeTitle(possibleTitle)) >= 0.90) {
        artistName = possibleArtist;
      }
    }

    if (artistName.isEmpty && album.isEmpty) return _empty;
    return YoutubeMusicReleaseMetadata(
      artistName: artistName,
      album: album,
    );
  }

  static String _primaryArtist(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';
    const commaStageNames = <String>{
      'tyler, the creator',
      'earth, wind & fire',
      'crosby, stills & nash',
      'emerson, lake & palmer',
    };
    if (commaStageNames.contains(normalized.toLowerCase())) return normalized;
    return normalized
        .split(RegExp(
          r',|&|[·•]|\s+feat(?:uring)?\.?\s+|\s+ft\.?\s+|\s+x\s+',
          caseSensitive: false,
        ))
        .first
        .trim();
  }

  static String _cleanCredit(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\s*[·•]\s*$'), '')
      .trim();

  static String _normalizeTitle(String value) {
    var normalized = value.toLowerCase().replaceFirst(
      RegExp(r'\s+[-–—]\s*from\s+.+$', caseSensitive: false),
      '',
    );
    normalized = normalized
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
        )
        .replaceAll(
          RegExp(
            r'\s*[-–—]\s*(?:official\s+)?(?:audio|video|music video|lyrics?|visualizer).*$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
  }

  static double _titleCoverage(String expected, String candidate) {
    final expectedTokens = expected.split(' ').where((token) => token.isNotEmpty).toSet();
    final candidateTokens = candidate.split(' ').where((token) => token.isNotEmpty).toSet();
    if (expectedTokens.isEmpty || candidateTokens.isEmpty) return 0;
    return expectedTokens.intersection(candidateTokens).length /
        expectedTokens.length;
  }
}
