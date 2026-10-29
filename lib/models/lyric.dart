class LyricWord {
  final String text;
  final Duration start;
  final Duration? end;

  const LyricWord({
    required this.text,
    required this.start,
    this.end,
  });
}

class LyricLine {
  final Duration time;
  final String text;
  /// Real word timestamps when the provider has word-level synchronization.
  /// Regular LRC sources only have line timestamps, so this remains empty.
  final List<LyricWord> words;
  final Duration? endTime;

  const LyricLine({
    required this.time,
    required this.text,
    this.words = const <LyricWord>[],
    this.endTime,
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