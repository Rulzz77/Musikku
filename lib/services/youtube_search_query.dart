/// Parsed intent used to tune YouTube search without changing the user's query.
class SmartSearchIntent {
  final String originalQuery;
  final String apiQuery;
  final String label;
  final bool latest;
  final bool musicContext;

  const SmartSearchIntent({
    required this.originalQuery,
    required this.apiQuery,
    required this.label,
    required this.latest,
    required this.musicContext,
  });
}

/// Pure query normalization and intent detection; no API or cache side effects.
///
/// Semua pencocokan memakai batas kata (`\b`), bukan substring, supaya kata
/// seperti "NewJeans", "populer", atau "Madjid" tidak dianggap sebagai "new",
/// "pop", atau "dj".
class YoutubeSearchQueryParser {
  // Akhiran yang umum menempel pada kata kunci: "lagunya", "remixes", "songs".
  static const String _suffix = r'(?:nya|es|s)?';

  /// Hanya frasa yang jelas bermakna "terbaru". Kata ambigu seperti "new" atau
  /// "baru" yang berdiri sendiri sengaja tidak dihitung (mis. "New Order",
  /// "Hari Baru"), karena akan memaksa urutan berdasarkan tanggal upload.
  static final RegExp _latestPattern = RegExp(
    r'\b(?:'
    r'terbaru|terkini|latest|newest|rilis(?:an)?'
    r'|(?:lagu|musik|rilis(?:an)?|album|single|video)\s+baru'
    r'|new\s+(?:releases?|songs?|music|hits?|singles?|albums?)'
    r')\b',
    caseSensitive: false,
  );

  // Adjacent string literals (bukan operator +) supaya suffix disisipkan
  // lewat interpolasi. Potongan terakhir bukan raw string, jadi \b ditulis \\b.
  static final RegExp _musicPattern = RegExp(
    r'\b(?:'
    r'dj|pop|rock|dangdut|remix|disco|jazz|hip[\s-]?hop|k-?pop|metal|indie'
    r'|akustik|galau|nostalgia|lagu|musik|song'
    r')'
    '$_suffix\\b',
    caseSensitive: false,
  );

  static final RegExp _eraPattern = RegExp(
    r'\b(19[5-9]0|20[0-2]0)s?\b',
    caseSensitive: false,
  );

  // "90an", "80-an" -> 1990s, 1980s.
  static final RegExp _eraShortPattern = RegExp(
    r'\b([5-9]0)-?an\b',
    caseSensitive: false,
  );

  static final RegExp _indonesiaPattern = RegExp(
    r'\b(?:indonesia|indo)\b',
    caseSensitive: false,
  );

  static final RegExp _whitespace = RegExp(r'\s+');

  static SmartSearchIntent interpret(String query) {
    // Rapikan spasi ganda agar query yang sama berbagi kunci cache.
    final original = query.trim().replaceAll(_whitespace, ' ');

    final latest = _latestPattern.hasMatch(original);
    final musicContext = _musicPattern.hasMatch(original);

    String? eraLabel;
    final era = _eraPattern.firstMatch(original);
    if (era != null) {
      eraLabel = '${era.group(1)}s';
    } else {
      final shortEra = _eraShortPattern.firstMatch(original);
      if (shortEra != null) eraLabel = '19${shortEra.group(1)}s';
    }

    final hasIndonesia = _indonesiaPattern.hasMatch(original);
    final addIndonesia = musicContext && !hasIndonesia;

    final labels = <String>[
      if (musicContext) 'musik',
      if (latest) 'terbaru',
      ?eraLabel,
      if (addIndonesia) 'Indonesia',
    ];

    final apiQuery = [
      original,
      if (addIndonesia) 'Indonesia',
    ].join(' ').trim();

    return SmartSearchIntent(
      originalQuery: original,
      apiQuery: apiQuery,
      label: labels.isEmpty ? 'pencarian biasa' : labels.join(' • '),
      latest: latest,
      musicContext: musicContext,
    );
  }
}