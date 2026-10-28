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

  /// Best-effort artist label for UI surfaces. Prefer an artist inferred from
  /// a title like "Artist - Song"; use the video owner only after removing
  /// common platform suffixes and rejecting obvious label/network names.
  /// YouTube metadata does not always identify the performing artist, so this
  /// deliberately returns a neutral fallback rather than inventing a name.
  static String artistLabel({
    required String title,
    String channelTitle = '',
  }) {
    String normalized(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    String cleanOwner(String value) {
      var owner = value.trim().replaceAll(
        RegExp(
          r'\b(?:official(?:\s+music)?(?:\s+channel)?|vevo|topic|music\s+channel|channel)\b',
          caseSensitive: false,
        ),
        ' ',
      );
      owner = owner.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (owner.isEmpty || RegExp(
        r'\b(?:records?|music|musik|entertainment|production|productions|media\s+group|network|label|digital|vibe|audio\s+network)\b',
        caseSensitive: false,
      ).hasMatch(owner)) {
        return '';
      }
      return owner;
    }

    bool matches(String candidate, String owner) {
      final a = normalized(candidate);
      final b = normalized(owner);
      if (a.isEmpty || b.isEmpty) return false;
      return a == b || a.startsWith('$b ') || b.startsWith('$a ');
    }

    final readableTitle = clean(title);
    final pieces = readableTitle
        .split(RegExp(r'\s+(?:-|–|—|\|)\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final owner = cleanOwner(channelTitle);
    if (pieces.length > 1) {
      if (owner.isNotEmpty && matches(pieces.first, owner)) return pieces.first;
      if (owner.isNotEmpty && matches(pieces[1], owner)) return pieces[1];
      if (pieces.first.length <= 52) return pieces.first;
    }
    if (owner.isNotEmpty) return owner;
    return 'Artis tidak diketahui';
  }

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
