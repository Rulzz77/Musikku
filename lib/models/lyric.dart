class LyricLine {
  final Duration time;
  final String text;

  const LyricLine({
    required this.time,
    required this.text,
  });
}

class LyricsResult {
  final List<LyricLine> lines;
  final bool synced;

  const LyricsResult({
    required this.lines,
    required this.synced,
  });
}