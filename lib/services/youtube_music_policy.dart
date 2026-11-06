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
    final titleAndChannel = '${video.title} ${video.channelTitle}';
    final shortMarker = RegExp(
      r'''(?:#shorts?\b|\bytshorts\b|\byoutube\s+shorts\b|\bshorts?\s*(?:video|music|song|remix)\b|\bshort\s+video\b|\bvertical\s+(?:video|music)\b|\bshort-form\b)''',
      caseSensitive: false,
    );

    // Deskripsi resmi sering berisi hashtag #Shorts sebagai template promosi.
    // Hanya penanda kuat pada judul/channel yang dipakai agar lagu asli tidak
    // hilang hanya karena hashtag generik di bagian deskripsi.
    return shortMarker.hasMatch(titleAndChannel);
  }

  /// Menolak versi yang jelas bukan rilisan original. Pola cover sengaja
  /// spesifik: judul lagu sah seperti "Cover Me in Sunshine" tidak dibuang.
  static bool isLikelyUnofficialMusicVersion(YoutubeSearchResult video) {
    const rejected =
        r'''\bkaraoke\b|\b(?:fan[ -]?made|unofficial|tribute|nightcore|sped[ -]?up|slowed(?:\s*(?:and|&|\+)\s*reverb)?|reverb\s+version|8d\s+audio|8d\s+music|mash[ -]?up|bootleg|fan[ -]?edit)\b|\bcover(?:ed)?\s+(?:by|version|song|lagu|music|musik|of)\b|\b(?:song|track|music|lagu)\s+covers?\b|\b(?:acoustic|piano|guitar|gitar|live|instrumental|singing|vocal)\s+cover\b|\b(?:my|our)\s+cover\b|\bversi\s+cover\b|\bkover\b|(?:\(|\[|[-–—|])\s*cover(?:\s+by\s+[^)\]]+)?\s*(?:\)|\])?$''';
    final title = video.title.trim();
    final description = video.description;
    final titleHasReject = RegExp(rejected, caseSensitive: false).hasMatch(title);
    final titleHasParenthesizedCover = RegExp(
          r'(?:\(|\[|[-–—|])[^)\]]{0,60}\bcover\b[^)\]]*(?:\)|\])?$',
          caseSensitive: false,
        ).hasMatch(title) &&
        !RegExp(r'\b(?:cover\s+art|album\s+cover|cover\s+artwork)\b',
                caseSensitive: false)
            .hasMatch(title);
    if (titleHasReject || titleHasParenthesizedCover) return true;

    // Deskripsi boleh menyebut cover artwork; hanya frasa yang menyatakan
    // cover lagu/karaoke yang dihitung sebagai versi non-original.
    final descriptionHasCover = RegExp(
      r'''\b(?:my|our|this is a|this is my|acoustic|piano|guitar|gitar)\s+cover\s+(?:of|song|lagu|version)\b|\bcover\s+(?:song|lagu|music|musik|version|of|by)\b|\b(?:song|track|music|lagu)\s+cover\b|\bversi\s+cover\b|\bkover\b|\bkaraoke\s+(?:version|track|song|lyrics?|instrumental)\b|\b(?:fan[ -]?made|unofficial)\s+(?:cover|version|song|music|audio|video)\b|\btribute\s+(?:to|version)\b''',
      caseSensitive: false,
    ).hasMatch(description);
    return descriptionHasCover;
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
      'reaction video',
      'reacting to',
      'reaction to',
      'album review',
      'song review',
      'review of',
      'tutorial',
      'how to',
      'cara membuat',
      'news update',
      'breaking news',
      'news report',
      'daily news',
      'berita terkini',
      'berita terbaru',
      'laporan berita',
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
      'panel discussion',
      'forum diskusi',
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
    final description = video.description.toLowerCase();
    final combined = '$title $channel $description';

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
      'made with suno',
      'generated with suno',
      'created with suno',
      'suno generated',
      'made with udio',
      'generated with udio',
      'created with udio',
      'udio generated',
    ];

    if (strongMarkers.any(combined.contains)) {
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

  /// A public catalogue item must represent one standalone track, not a
  /// multi-track album/playlist upload. Text markers are checked even when
  /// duration metadata is missing (as happens in some search responses).
  /// A 15-minute ceiling catches long-form compilations whose titles are vague;
  /// normal extended singles up to this limit remain eligible.
  static const int maxStandaloneTrackDurationSeconds = 15 * 60;

  static bool isLikelyAlbumOrPlaylist(YoutubeSearchResult video) {
    if (video.isLocal) return false;

    final title = video.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // These phrases describe a multi-track upload, not a single song. Include
    // common Indonesian wording because local uploads often do not use English
    // metadata. Do not block the bare words "album" or "playlist"; a song can
    // legitimately have either word as its title.
    final collectionMarkers = RegExp(
      r'\b(?:'
      r'full (?:length )?album|complete album|entire album|whole album|'
      r'album (?:full|lengkap|penuh|komplit|kompilasi)|'
      r'(?:full|complete|entire|whole) playlist|'
      r'playlist (?:lengkap|penuh|full|lagu|musik|songs?|music|mix|of|terbaik|pilihan|terbaru|galau|pop|indonesia|viral|hits)|'
      r'daftar putar|'
      r'kumpulan (?:lagu|musik|songs?|tracks?)|'
      r'koleksi (?:lagu|musik|songs?|tracks?)|'
      r'kompilasi(?: (?:lagu|musik|songs?|tracks?|album))?|'
      r'(?:semua|seluruh) (?:lagu|songs?|tracks?|album)|'
      r'(?:all|every) (?:songs?|tracks?|albums?)|'
      r'greatest hits|best of (?:collection|album|songs?|tracks?|hits?|discography)|best songs?|top \d+ (?:lagu|songs?|tracks?)|'
      r'\d+ (?:lagu|songs?|tracks?) (?:terbaik|hits|pilihan)|'
      r'lagu (?:terbaik|hits|pilihan)|'
      r'(?:song|music) collection|'
      r'full discography|complete discography|discography|'
      r'full mix|continuous mix|non ?stop|longplay|medley|'
      r'\d+ (?:hours?|hrs?|jam)|'
      r'(?:music|songs?|lagu|musik) (?:\d+ )?(?:hours?|hrs?|jam)'
      r')\b',
      caseSensitive: false,
    );
    if (collectionMarkers.hasMatch(title)) return true;

    final seconds = video.durationSeconds;
    return seconds != null && seconds > maxStandaloneTrackDurationSeconds;
  }

  /// Filter ketat untuk hasil katalog publik MusikKu: prioritaskan rilis
  /// single resmi saja. youtube_explode_dart tidak mengekspos badge
  /// verifikasi channel secara konsisten, jadi keputusan ini berbasis marker
  /// resmi pada judul/channel dan tidak bisa menjamin status resmi 100%.
  static bool isOfficialMusicReleaseCandidate(YoutubeSearchResult video) {
    if (video.isLocal) return true;

    final title = video.title.toLowerCase().trim();
    final channel = video.channelTitle.toLowerCase().trim();

    if (title.isEmpty || video.videoId.isEmpty) return false;
    if (video.isLive ||
        video.isUpcoming ||
        isLikelyShortForm(video) ||
        isLikelyNonMusicVideo(video) ||
        _hasExplicitNonMusicShortLabel(video) ||
        isLikelyAiGeneratedMusic(video) ||
        isLikelyUnofficialMusicVersion(video) ||
        isLikelyAlbumOrPlaylist(video)) {
      return false;
    }

    final seconds = video.durationSeconds;
    if (seconds != null && seconds <= 30) return false;

    // Kalau YouTube Data API mengidentifikasi video sebagai kategori Music,
    // itu sinyal positif yang lebih baik daripada mewajibkan kata "Official".
    // Penolakan cover/karaoke/AI, album/playlist, dan durasi panjang sudah di atas.
    if (video.categoryId.trim() == '10') return true;

    // Lagu DJ/remix (funkot, breakbeat, slow bass, dsb.) hampir selalu diunggah
    // channel DJ non-resmi, jadi tidak punya penanda "official". Tanpa
    // pengecualian ini mereka ikut terbuang oleh syarat rilis resmi di bawah.
    final isDjTrack = RegExp(
      r'\b(?:dj|remix|funkot|breakbeat|jedag\s*jedug|slow\s*bass|bass\s*boosted|'
      r'tiktok\s+viral|mashup\s+dj)\b',
      caseSensitive: false,
    ).hasMatch(title);

    if (isDjTrack) {
      // Untuk lagu DJ, hanya tolak yang memang cover/karaoke/AI. Label seperti
      // slowed, sped up, nightcore, 8D, mashup, bootleg adalah gaya DJ yang wajar.
      return !isLikelyUnofficialMusicVersion(video);
    }

    // Tolak versi non-original yang biasa mencemari hasil pencarian.
    if (isLikelyUnofficialMusicVersion(video)) return false;

    // Explicit title markers for official singles/audio/video/visualizer.
    final officialTitle = RegExp(
      r'\b(?:official(?:\s+(?:music|audio|lyrics?|lyric|visualizer|performance|mv))*\s+(?:video|audio|lyrics?|visualizer|performance|mv)|audio\s+resmi|video\s+(?:musik|klip)\s+resmi|lirik\s+resmi|mv\s+official)\b',
      caseSensitive: false,
    ).hasMatch(title);

    // Topic channels are YouTube-generated artist-track channels. Also accept
    // common artist/label official-channel naming conventions.
    final officialChannel = RegExp(
      r'(?:-\s*topic$|\bvevo\b|\bofficial\b|\b(?:universal music|warner music|sony music|republic records|atlantic records|interscope records|capitol records|emi records|musica studios?|trinity optima|aquarius musikindo|nagaswara|gp records|sony music indonesia|warner music indonesia|universal music indonesia|sm entertainment|jyp entertainment|yg entertainment|hybe labels|big hit music|t-series|zee music company|saregama|lahari music|aditya music|times music|speed records|white hill music|my music records|stone music entertainment|1thek|smtown|mnet k[ -]?pop|indosemar records|proaktif|pelangi records|3d entertainment|musik proaktif|milady record|berkah talenta|wahana records?|sandi records?|you musik|cmp label|global musik era digital|warna warni musik|santara indonesia|yi production|music interactive|himawan musik entertainment)\b)',
      caseSensitive: false,
    ).hasMatch(channel);

    // Banyak official artist channels memakai nama artis saja. Saat judul
    // diawali nama channel lalu pemisah judul, perlakukan sebagai kandidat
    // official (tetap sudah lolos filter cover/AI/karaoke/album di atas).
    final normalizedChannel = channel.replaceAll(RegExp(r'\s+'), ' ').trim();
    final normalizedTitle = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final artistNamedChannelRelease = normalizedChannel.length >= 3 &&
        normalizedTitle.startsWith(normalizedChannel) &&
        normalizedTitle.length > normalizedChannel.length &&
        RegExp(r'^\s*(?:[-–—|:])\s*')
            .hasMatch(normalizedTitle.substring(normalizedChannel.length));

    return officialTitle || officialChannel || artistNamedChannelRelease;
  }

  /// Allows normal-length tracks when the searched artist is credited in the
  /// title/description or the channel name. This fills the gap for releases
  /// uploaded by labels that do not carry an official marker on the title.
  /// It is query-scoped for artist names; generic genre/song searches use the
  /// safe music-candidate policy without requiring an official-name marker.
  static bool isOfficialMusicReleaseCandidateForQuery(
    YoutubeSearchResult video, {
    required String query,
  }) {
    if (video.isLocal) return true;
    if (video.videoId.isEmpty ||
        video.title.trim().isEmpty ||
        video.isLive ||
        video.isUpcoming ||
        isLikelyShortForm(video) ||
        isLikelyNonMusicVideo(video) ||
        _hasExplicitNonMusicShortLabel(video) ||
        isLikelyAiGeneratedMusic(video) ||
        isLikelyUnofficialMusicVersion(video) ||
        isLikelyAlbumOrPlaylist(video)) {
      return false;
    }

    final artistQuery = _normalizeArtistSearchName(query);
    if (artistQuery.isEmpty) return false;

    const genericMusicTerms = <String>{
      'pop', 'rock', 'jazz', 'metal', 'indie', 'dangdut', 'koplo', 'dj',
      'remix', 'k', 'hip', 'hop', 'lofi', 'lo', 'fi', 'radio',
      'soundtrack', 'instrumental', 'karaoke', 'chill', 'blues', 'reggae',
      'classical', 'country', 'folk', 'edm', 'house', 'techno', 'trance',
      'ambient', 'indonesia', 'indonesian', 'inggris', 'english', 'jawa',
      'javanese', 'akustik', 'religi', 'film', 'mix', 'music', 'song',
      'lagu', 'galau', 'nostalgia', 'viral', 'terbaru', 'latest', 'top',
      'hits', 'best', '50', '2024', '2025', '2026', 'r', 'b',
    };
    final genericTokens = artistQuery.split(' ').where((word) => word.isNotEmpty).toSet();
    if (genericTokens.isNotEmpty &&
        genericTokens.every(genericMusicTerms.contains)) {
      return isMusicCandidate(video);
    }

    final queryTokens = artistQuery.split(' ').where((word) => word.length > 1).toSet();
    if (queryTokens.isEmpty || queryTokens.length > 4) {
      // Query panjang berisi genre/bahasa/konteks tambahan; jangan buang semua
      // lagu hanya karena parser tidak bisa memastikan satu nama artis.
      return isMusicCandidate(video);
    }

    final channel = _normalizeArtistSearchName(video.channelTitle);
    final channelTokens = channel.split(' ').where((word) => word.length > 1).toSet();
    final channelMatchesArtist = channel.isNotEmpty &&
        queryTokens.every(channelTokens.contains);

    // Banyak rilisan asli diunggah oleh label/distributor, bukan channel artis.
    // Dalam kasus itu, nama artis justru muncul pada judul video, misalnya
    // "Fiersa Besari - Celengan Rindu" dari channel label. Filter lama hanya
    // mencocokkan nama channel sehingga hasil seperti ini selalu dibuang.
    bool containsArtistPhrase(String text) =>
        text == artistQuery ||
        text.startsWith('$artistQuery ') ||
        text.endsWith(' $artistQuery') ||
        text.contains(' $artistQuery ');

    final normalizedTitle = _normalizeArtistSearchName(video.title);
    final normalizedDescription = _normalizeArtistSearchName(video.description);
    final titleCreditsArtist = containsArtistPhrase(normalizedTitle);
    final descriptionCreditsArtist = containsArtistPhrase(normalizedDescription);
    if (!channelMatchesArtist && !titleCreditsArtist && !descriptionCreditsArtist) {
      return false;
    }

    // An exact artist/channel or explicit artist credit is a strong signal,
    // but do not admit covers, karaoke, fan edits, AI versions, or promo snippets.
    if (isLikelyUnofficialMusicVersion(video)) return false;
    if (titleCreditsArtist && normalizedTitle == artistQuery) return false;

    final seconds = video.durationSeconds;
    if (seconds != null && seconds <= 30) {
      return false;
    }
    return true;
  }

  static String _normalizeArtistSearchName(String value) => value
      .toLowerCase()
      .replaceAll(
        RegExp(
          r'\b(?:official(?:\s+music)?(?:\s+channel)?|vevo|topic|music\s+channel|'
          r'channel|songs?|song|lagu(?:nya)?|music|musik|audio|video|mv|'
          r'lyrics?|lyric|lirik|terbaru|latest|single|album)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Kandidat musik yang aman untuk daftar, riwayat, Radio, dan queue.
  /// YouTube tidak menyediakan badge resmi yang konsisten pada hasil search;
  /// karena itu lagu berdurasi normal tidak boleh ditolak hanya karena judulnya
  /// tidak menyertakan kata Official/VEVO/Topic. Penanda cover/karaoke/AI,
  /// album/playlist, Shorts, dan konten nonmusik tetap dikeluarkan.
  static bool isMusicCandidate(YoutubeSearchResult video) {
    if (video.isLocal) return true;
    if (video.videoId.isEmpty ||
        video.title.trim().isEmpty ||
        video.isLive ||
        video.isUpcoming ||
        isLikelyShortForm(video) ||
        isLikelyNonMusicVideo(video) ||
        _hasExplicitNonMusicShortLabel(video) ||
        isLikelyAiGeneratedMusic(video) ||
        isLikelyUnofficialMusicVersion(video) ||
        isLikelyAlbumOrPlaylist(video)) {
      return false;
    }

    final seconds = video.durationSeconds;
    if (seconds != null && seconds <= 30) return false;

    final category = video.categoryId.trim();
    if (category == '10') return true;

    // youtube_explode_dart tidak mengembalikan categoryId. Untuk hasil dari
    // pencarian musik, durasi single yang wajar adalah fallback ketika channel
    // artis/label tidak memakai kata "official" pada nama atau judul.
    return isOfficialMusicReleaseCandidate(video) ||
        seconds == null ||
        (seconds > 30 &&
            seconds <= maxStandaloneTrackDurationSeconds);
  }

  /// Label non-musik yang sering muncul pada Shorts. Dipakai hanya untuk video
  /// maksimal 3 menit agar tidak memblokir lagu berdurasi normal.
  static bool _hasExplicitNonMusicShortLabel(YoutubeSearchResult video) {
    final duration = video.durationSeconds;
    if (duration == null || duration > 180 || duration <= 0) return false;
    return RegExp(
      r'\b(?:comedy|komedi|skit|prank|iseng|meme|funny\s+moments?|momen\s+lucu|fail(?:s|ed)?|blooper(?:s)?|unboxing|kecelakaan|accident|viral\s+moments?|random\s+moments?|cute\s+(?:cat|dog)|cat\s+video|dog\s+video|animal\s+video|pet\s+video|hewan\s+lucu|kucing\s+lucu|anjing\s+lucu)\b',
      caseSensitive: false,
    ).hasMatch(video.title);
  }


  /// Detects a channel profile that is likely focused on music. This is used
  /// only for subscription/channel discovery; it is intentionally permissive
  /// enough for independent artists and cover-song creators, not only official
  /// artist channels.
  static bool isLikelyMusicChannelProfile(String title, String description) {
    final profile = '$title $description'.toLowerCase();
    return RegExp(
      r'\b(?:music|musik|cover|covers|song|songs|lagu|sing|singing|nyanyi|menyanyi|bernyanyi|singer|singers|penyanyi|vocalist|vocal|vokal|musician|musisi|band|guitarist|gitaris|pianist|drummer|composer|komposer|songwriter|penulis\s+lagu|karaoke|instrumental|acoustic|akustik|orchestra|orkestra|choir|paduan\s+suara|remix|lirik|lyrics|music\s+channel|channel\s+musik)\b',
      caseSensitive: false,
    ).hasMatch(profile);
  }

  /// Classifies a channel's upload without requiring its YouTube category to
  /// be `10`. Independent artists can publish official singles under
  /// Entertainment/People & Blogs; explicit cover/karaoke/AI uploads are still
  /// rejected by the shared policy.
  static bool isMusicChannelUpload(
    YoutubeSearchResult video, {
    String channelTitle = '',
    String channelDescription = '',
  }) {
    if (video.isLocal) return true;
    final seconds = video.durationSeconds;
    if (seconds != null && seconds <= 30) return false;

    if (video.videoId.isEmpty ||
        video.title.trim().isEmpty ||
        isLikelyShortForm(video) ||
        _hasExplicitNonMusicShortLabel(video) ||
        isLikelyNonMusicVideo(video) ||
        isLikelyAiGeneratedMusic(video) ||
        isLikelyUnofficialMusicVersion(video) ||
        isLikelyAlbumOrPlaylist(video)) {
      return false;
    }

    final title = video.title.toLowerCase();
    final videoDescription = video.description.toLowerCase();
    // These labels describe clearly non-music formats even when uploaded by a
    // music channel. Keep this list title-based so channel names do not wrongly
    // suppress their music uploads.
    final clearlyNonMusic = RegExp(
      r'\b(?:podcast|interview|wawancara|talk\s*show|talkshow|reaction\s+(?:video|to)|reacting\s+to|album\s+review|song\s+review|review\s+of|tutorial|how\s+to|cara\s+membuat|vlog|daily\s+vlog|trailer|teaser|gameplay|gaming|livestream|live\s+stream|web\s+series|panel\s+discussion|forum\s+diskusi|unboxing|q\s*&\s*a|question\s+and\s+answer|news\s+update|breaking\s+news|news\s+report|daily\s+news|berita\s+terkini|berita\s+terbaru|laporan\s+berita)\b',
      caseSensitive: false,
    ).hasMatch(title);
    if (clearlyNonMusic) return false;

    // A clear song/performance marker wins over ambiguous words in song titles
    // such as "Talking to the Moon" or "No News Is Good News".
    final explicitMusicTitle = RegExp(
      r'\b(?:song|songs|lagu|music|musik|official\s+audio|audio\s+resmi|track|single|album|lyrics?|lirik|instrumental|acoustic|akustik|remix|piano|guitar|gitar|bass|drums?|violin|biola|vocal|vokal|sing|singing|nyanyi|menyanyi|bernyanyi|singer|penyanyi|unplugged|medley|soundtrack|ost|orchestra|orkestra|choir|paduan\s+suara|music\s+video|official\s+music\s+video|live\s+performance|live\s+session)\b',
      caseSensitive: false,
    ).hasMatch(title);
    final explicitMusicDescription = RegExp(
      r'\b(?:performed\s+by|sung\s+by|vocals?\s+by|singing\s+by|dinyanyikan\s+oleh|dibawakan\s+oleh|instrumental\s+version|acoustic\s+version|official\s+audio|official\s+lyrics|music\s+video|live\s+performance|remix|medley)\b',
      caseSensitive: false,
    ).hasMatch(videoDescription);
    if (explicitMusicTitle || explicitMusicDescription) return true;

    // Category 10 is a strong positive signal, after explicit non-music formats
    // have been removed.
    if (video.categoryId.trim() == '10') return true;

    // Generic song titles can be admitted when the channel identifies itself as
    // a singer, cover artist, band, instrumentalist, or music channel.
    return isLikelyMusicChannelProfile(
      channelTitle.isNotEmpty ? channelTitle : video.channelTitle,
      channelDescription,
    );
  }

  /// Strict category gate used by the public trending feed, which explicitly
  /// requests YouTube category 10. Artist search and channel uploads must use
  /// [isMusicCandidate] / [isMusicChannelUpload] so legitimate releases tagged
  /// under Entertainment or People & Blogs are not discarded.
  static bool isMusicCatalogItem(
    YoutubeSearchResult video, {
    bool requireCategoryId = false,
  }) {
    if (video.isLocal) return true;
    final category = video.categoryId.trim();
    if (category.isNotEmpty && category != '10') return false;
    if (requireCategoryId && category != '10') return false;
    return isMusicCandidate(video);
  }
}
