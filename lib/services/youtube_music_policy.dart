import '../models/youtube_search_result.dart';

/// Centralized policy for keeping the audio catalogue focused on music.
/// Methods are pure so they can be tested without network access.
class YoutubeMusicPolicy {
  /// Classifies the status from GET/HEAD /shorts/{id} when redirects are not
  /// followed. A 3xx response is a normal-route redirect. A 200 needs canonical
  /// page metadata because some YouTube edge servers also serve ordinary video
  /// pages with status 200. Other statuses are ambiguous.
  static bool? classifyShortsProbeStatus(
    int statusCode, {
    String? location,
  }) {
    if (statusCode < 300 || statusCode >= 400) return null;
    final redirect = location == null ? null : Uri.tryParse(location);
    if (redirect == null) return null;
    if (redirect.path == '/watch' || redirect.path.startsWith('/watch/')) {
      return false;
    }
    if (redirect.path.startsWith('/shorts/')) return true;
    return null;
  }

  /// Reads canonical/og URL hints from the first part of a YouTube page.
  /// Returns null when the response has no clear video-route metadata.
  static bool? classifyShortsPageHtml(String html) {
    final links = RegExp(r'<link\b[^>]*>', caseSensitive: false);
    final relPattern = RegExp(r'''\brel\s*=\s*["']([^"']+)["']''', caseSensitive: false);
    final hrefPattern = RegExp(r'''\bhref\s*=\s*["']([^"']+)["']''', caseSensitive: false);

    for (final match in links.allMatches(html)) {
      final tag = match.group(0) ?? '';
      final rel = relPattern.firstMatch(tag)?.group(1)?.toLowerCase() ?? '';
      if (!rel.split(RegExp(r'\s+')).contains('canonical')) continue;
      final href = hrefPattern.firstMatch(tag)?.group(1);
      final uri = href == null ? null : Uri.tryParse(href);
      if (uri == null) continue;
      if (uri.path.startsWith('/shorts/')) return true;
      if (uri.path == '/watch' || uri.path.startsWith('/watch/')) return false;
    }

    // YouTube can expose the canonical route inside escaped player config
    // before the <link> element is present in a truncated response.
    final normalized = html.replaceAll(r'\/', '/').toLowerCase();
    if (RegExp(r'''"canonicalbaseurl"\s*:\s*"(?:https?://[^"]+)?/shorts/''').hasMatch(normalized)) {
      return true;
    }
    if (RegExp(r'''"canonicalbaseurl"\s*:\s*"(?:https?://[^"]+)?/watch''').hasMatch(normalized)) {
      return false;
    }
    return null;
  }

  static bool isLikelyShortForm(YoutubeSearchResult video) {
    final title = video.title.toLowerCase();
    final channel = video.channelTitle.toLowerCase();
    final combined = '$title $channel';

    // Menangkap label yang umum dipakai pada Shorts / short-form uploads.
    return RegExp(
      r'''(?:#shorts?\b|\bytshorts\b|\byoutube\s+shorts\b|\bshorts?\s*(?:video|music|song|remix)\b|\bshort\s+video\b|\bvertical\s+(?:video|music)\b|\bshort-form\b)''',
      caseSensitive: false,
    ).hasMatch(combined);
  }


  /// Tolak video yang secara jelas bukan lagu/musik. Search API sudah
  /// memakai videoCategoryId=10, tetapi beberapa upload berkategori Musik
  /// masih berupa podcast, interview, reaction, tutorial, berita, trailer,
  /// dan konten percakapan. Auto-next sebaiknya tidak memasukkan jenis ini.
  static bool isLikelyNonMusicVideo(YoutubeSearchResult video) {
    final title = video.title.toLowerCase();
    final channel = video.channelTitle.toLowerCase();
    final combined = '$title $channel';

    const blocked = <String>[
      'podcast',
      'interview',
      'wawancara',
      'talkshow',
      'talk show',
      'reaction',
      'reaksi',
      'review',
      'tutorial',
      'how to',
      'cara membuat',
      'berita',
      'news',
      'vlog',
      'daily vlog',
      'trailer',
      'teaser',
      'gameplay',
      'gaming',
      'streaming',
      'livestream',
      'live stream',
      'web series',
      'webseries',
      'talking',
      'diskusi',
    ];

    // Match whole words/phrases, not arbitrary substrings. Generic substring
    // checks incorrectly excluded artists such as Newsboys or names containing
    // "pod" even when the upload was a real song.
    final normalized = combined.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    for (final word in blocked) {
      final phrase = word.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (phrase.isEmpty) continue;
      final pattern = RegExp(r'(^|\s)' + RegExp.escape(phrase) + r'(\s|$)');
      if (pattern.hasMatch(normalized)) return true;
    }

    return false;
  }

  static bool isLikelyAiGeneratedMusic(YoutubeSearchResult video) {
    final title = video.title.toLowerCase();
    final channel = video.channelTitle.toLowerCase();
    final combined = '$title $channel';

    // Tidak ada flag API yang menyatakan 'AI music' secara sempurna. Karena
    // itu filter memakai sinyal yang kuat dan spesifik, bukan sekadar kata
    // 'ai' tunggal agar nama artis/lagu normal tidak ikut terblokir.
    const strongMarkers = <String>[
      'ai cover',
      'ai version',
      'ai music',
      'ai song',
      'ai vocals',
      'ai voice',
      'ai generated',
      'ai-generated',
      'generated by ai',
      'made with ai',
      'musicgen',
      'voice clone',
      'voice-cloned',
      'deepfake voice',
      'suno ai',
      'udio ai',
    ];

    if (strongMarkers.any(combined.contains)) {
      return true;
    }

    if (RegExp(r'\b(?:suno|udio)\b').hasMatch(channel)) {
      return true;
    }

    // Banyak channel generatif memberi label 'AI' di nama channel, misalnya
    // 'Kacaw AI'. Untuk radio musik, hindari channel yang secara eksplisit
    // menandai dirinya sebagai AI.
    if (RegExp(r'(?:^|[\s_-])ai(?:$|[\s_-])').hasMatch(channel)) {
      return true;
    }

    return RegExp(r'\b(?:artificial\s+intelligence|synthetic\s+voice)\b')
        .hasMatch(combined);
  }

  static List<YoutubeSearchResult> filterAiMusicCandidates(
    List<YoutubeSearchResult> videos,
  ) {
    return videos.where((video) => !isLikelyAiGeneratedMusic(video)).toList();
  }

  static bool isMusicCandidate(YoutubeSearchResult video) {
    return !isLikelyShortForm(video) &&
        !isLikelyNonMusicVideo(video) &&
        !isLikelyAiGeneratedMusic(video);
  }

  /// MusicKu's main catalogue filter. Search/trending endpoints already ask
  /// YouTube for category 10; account uploads must provide category 10 after
  /// videos.list enrichment, or they are omitted instead of leaking non-music.
  /// AI-made tracks are not rejected here because they are still music.
  static bool isMusicCatalogItem(
    YoutubeSearchResult video, {
    bool requireCategoryId = false,
  }) {
    if (video.isLocal) return true;
    final category = video.categoryId.trim();
    if (category.isNotEmpty && category != '10') return false;
    if (requireCategoryId && category != '10') return false;
    return !isLikelyShortForm(video) && !isLikelyNonMusicVideo(video);
  }
}
