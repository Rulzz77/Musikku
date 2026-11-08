/// Cleans YouTube-style title decoration for player display without changing
/// the original title used by search, radio matching, or the source metadata.
class MusicTitleFormatter {
  MusicTitleFormatter._();

  static final RegExp _wrappedTag = RegExp(
    r'\s*[\(\[\{【]([^\)\]\}】]*)[\)\]\}】]',
    caseSensitive: false,
  );

  static final RegExp _tagWords = RegExp(
    r'\b(?:official|music\s*video|video\s*official|official\s*audio|'
    r'lyric(?:s)?(?:\s*video)?|lirik(?:\s*video)?|visuali[sz]er|audio\s*only|'
    r'hd|fhd|uhd|4k|8k|1080p|720p|mv|topic|shorts|sub\s*indo|'
    r'full\s*hd|high\s*definition|video\s*clip|lirik)\b',
    caseSensitive: false,
  );

  static final RegExp _trailingDecoration = RegExp(
    r'\s*(?:[-|•–—:]\s*)?'
    r'(?:official\s+(?:(?:music|lyric|lyrics)\s+)?video|official\s+mv|official\s+lyrics?|'
    r'official\s+audio|music\s+video|lyric\s+video|lirik\s+video|lyrics?|'
    r'visuali[sz]er|audio\s+only|high\s+definition|full\s*hd|'
    r'hd|fhd|uhd|4k|8k|1080p|720p|topic)\s*$',
    caseSensitive: false,
  );

  static final RegExp _promoHashtag = RegExp(
    r'\s+#(?:shorts|ytshorts|viral|trending|fyp)\b.*$',
    caseSensitive: false,
  );

  /// Returns a readable title, removing common metadata tags such as
  /// `[Official Video]`, `(Lyrics)`, `| Official Audio`, and HTML markup.
  /// Meaningful text such as `feat. Artist`, apostrophes, medley separators,
  /// and words like `Remix` are deliberately preserved.
  static String clean(String raw) {
    final original = raw.trim();
    if (original.isEmpty) return original;

    var title = original.replaceAll(RegExp(r'<[^>]*>'), ' ');
    const entities = <String, String>{
      '&amp;': '&',
      '&quot;': '"',
      '&#34;': '"',
      '&#39;': "'",
      '&#x27;': "'",
      '&apos;': "'",
      '&lt;': '<',
      '&gt;': '>',
      '&nbsp;': ' ',
    };
    for (final entry in entities.entries) {
      title = title.replaceAll(entry.key, entry.value);
    }

    title = title.replaceAllMapped(_wrappedTag, (match) {
      final contents = match.group(1) ?? '';
      return _tagWords.hasMatch(contents) ? ' ' : match.group(0)!;
    });
    title = title.replaceAll(_trailingDecoration, ' ');
    title = title.replaceAll(_promoHashtag, ' ');
    title = title.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    title = title.replaceAll(RegExp(r'^[|•–—:\-\s]+'), '');
    title = title.replaceAll(RegExp(r'[|•–—:\-\s]+$'), '').trim();

    return title.isEmpty ? original : title;
  }
}
