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
class YoutubeSearchQueryParser {
  static SmartSearchIntent interpret(String query) {
    final original = query.trim();
    final lower = original.toLowerCase();

    final latestWords = <String>[
      'terbaru',
      'terkini',
      'baru',
      'new',
      'latest',
      'rilis',
    ];
    final latest = latestWords.any(lower.contains);

    final musicWords = <String>[
      'dj',
      'pop',
      'rock',
      'dangdut',
      'remix',
      'disco',
      'jazz',
      'hip hop',
      'hiphop',
      'kpop',
      'k-pop',
      'metal',
      'indie',
      'akustik',
      'galau',
      'nostalgia',
      'lagu',
      'musik',
      'song',
    ];
    final musicContext = musicWords.any(lower.contains);

    final era = RegExp(r'\b(19[5-9]0|20(?:0|1|2)0)[sS]?\b').firstMatch(lower);
    final eraLabel = era?.group(1);
    final hasIndonesia = lower.contains('indonesia') ||
        RegExp(r'(^|\s)indo($|\s)').hasMatch(lower);

    final labels = <String>[];
    if (musicContext) labels.add('musik');
    if (latest) labels.add('terbaru');
    if (eraLabel != null) labels.add('${eraLabel}s');
    if (!hasIndonesia && musicContext) labels.add('Indonesia');

    final extra = <String>[];
    if (musicContext && !hasIndonesia) extra.add('Indonesia');

    final apiQuery = [
      original,
      ...extra,
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
