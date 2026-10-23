import 'dart:math' as math;

import '../models/youtube_search_result.dart';

/// Heuristik internal genre, subgenre, dan bahasa untuk Smart Shuffle/Radio.
/// Nilai ini hanya memengaruhi pemilihan kandidat; jangan tampilkan sebagai label UI.
///
/// YouTube Data API tidak menyediakan genre atau bahasa lagu yang akurat untuk
/// setiap video. Karena itu, hasil di bawah merupakan petunjuk dari query,
/// judul, artis/channel, dan metadata yang tersedia; nilai "unknown" tetap
/// diperbolehkan sebagai fallback agar antrean tidak mudah habis.
class MusicStyleMatcher {
  MusicStyleMatcher._();

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s&+#]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _matches(String text, String pattern) =>
      RegExp(pattern, caseSensitive: false).hasMatch(text);

  static bool _containsAny(String text, Iterable<String> values) =>
      values.any((value) => text.contains(value));

  static const Map<String, Set<String>> _relatedStyles = <String, Set<String>>{
    'pop': <String>{'pop', 'pop_dj', 'dj_remix', 'rnb', 'indie', 'acoustic', 'rock', 'kpop'},
    'pop_dj': <String>{'pop_dj', 'pop', 'dj_remix', 'dangdut', 'melayu'},
    'dj_remix': <String>{'dj_remix', 'pop_dj', 'pop', 'dangdut', 'jawa', 'melayu'},
    'dangdut': <String>{'dangdut', 'jawa', 'melayu', 'dj_remix'},
    'jawa': <String>{'jawa', 'dangdut', 'melayu', 'dj_remix'},
    'sunda': <String>{'sunda', 'jawa'},
    'kpop': <String>{'kpop', 'pop', 'rnb', 'indie', 'rock', 'acoustic'},
    'hip_hop': <String>{'hip_hop', 'rnb'},
    'rnb': <String>{'rnb', 'pop', 'hip_hop'},
    'rock': <String>{'rock', 'indie', 'pop'},
    'indie': <String>{'indie', 'pop', 'rock', 'acoustic'},
    'acoustic': <String>{'acoustic', 'pop', 'indie'},
    'reggae': <String>{'reggae', 'ska'},
    'ska': <String>{'ska', 'reggae'},
    'melayu': <String>{'melayu', 'dangdut', 'jawa', 'dj_remix'},
    'religi': <String>{'religi'},
    'jazz': <String>{'jazz', 'blues'},
    'blues': <String>{'blues', 'jazz', 'rock'},
    'country': <String>{'country', 'acoustic'},
    'instrumental': <String>{'instrumental', 'acoustic', 'jazz'},
  };

  static const Set<String> _englishArtists = <String>{
    'taylor swift', 'sabrina carpenter', 'ed sheeran', 'bruno mars',
    'ariana grande', 'the weeknd', 'billie eilish', 'olivia rodrigo',
    'justin bieber', 'dua lipa', 'coldplay', 'maroon 5', 'miley cyrus',
    'adele', 'sam smith', 'harry styles', 'one direction', 'rihanna',
    'beyonce', 'lady gaga', 'katy perry', 'selena gomez', 'shawn mendes',
    'charlie puth', 'post malone', 'imagine dragons', 'linkin park',
    'eminem', 'drake', 'lana del rey', 'sia', 'avril lavigne',
    'backstreet boys', 'westlife', 'queen', 'the beatles', 'elton john',
  };

  static const Set<String> _indonesianArtists = <String>{
    'tulus', 'raisa', 'rossa', 'mahalini', 'tiara andini', 'rizky febian',
    'judika', 'afgan', 'andmesh kamaleng', 'lyodra', 'keisya levronka',
    'yura yunita', 'isyana sarasvati', 'vidi aldiano', 'bunga citra lestari',
    'dewa 19', 'sheila on 7', 'noah', 'peterpan', 'ungu', 'kotak',
    'armada', 'letto', 'nidji', 'geisha', 'fourtwnty', 'payung teduh',
    'denny caknan', 'ndarboy genk', 'guyon waton', 'aftershine',
    'happy asmara', 'gilga sahid', 'niken salindry', 'jihan audy',
    'difarina indra', 'farel prayoga', 'woro widowati', 'hendra kumbara',
    'didi kempot', 'nella kharisma', 'siti badriah', 'lesti kejora',
    'rhoma irama', 'elvy sukaesih', 'tasya rosmala', 'via vallen',
    'dewi perssik', 'inul daratista', 'zaskia gotik', 'ayu ting ting',
  };

  static const Set<String> _koreanArtists = <String>{
    'blackpink', 'stray kids', 'newjeans', 'seventeen', 'twice', 'exo',
    'bts', 'aespa', 'ive', 'le sserafim', 'red velvet', 'nct', 'iu',
    'ps y', 'bigbang', 'girls generation', 'itzy', 'enhypen', 'txt',
  };

  static const Set<String> _japaneseArtists = <String>{
    'yoasobi', 'ado', 'kenshi yonezu', 'official hige dandism', 'aimyon',
    'one ok rock', 'king gnu', 'radwimps',
  };

  /// Mengembalikan genre yang terdeteksi secara eksplisit dari query/metadata.
  /// Urutan penting: Pop DJ dipisahkan dari DJ/remix biasa, dan subgenre lokal
  /// tidak boleh jatuh ke Pop umum.
  static String? styleFromText(String raw) {
    final text = normalize(raw);
    if (text.isEmpty) return null;

    if (_matches(
      text,
      r'\b(?:jawa|javanese|campursari|langgam jawa|pop jawa|koplo jawa|ndangdut jawa)\b',
    )) {
      return 'jawa';
    }

    if (_matches(text, r'\b(?:sunda|sundanese|jaipongan|degung|pop sunda)\b')) {
      return 'sunda';
    }

    if (_matches(text, r'\b(?:k\s*pop|kpop|korean pop|lagu korea|korean song)\b')) {
      return 'kpop';
    }

    if (_matches(text, r'\b(?:pop\s*dj|dj\s*pop|pop\s*remix|remix\s*pop)\b')) {
      return 'pop_dj';
    }

    if (_matches(
      text,
      r'\b(?:dj|remix|funkot|jedag jedug|breakbeat|nightcore|slowed|sped up|bass boosted|slow bass)\b',
    )) {
      return 'dj_remix';
    }

    if (_matches(
      text,
      r'\b(?:sholawat|shalawat|qasidah|nasheed|nasyid|lagu religi|musik religi|lagu islami|rohani)\b',
    )) {
      return 'religi';
    }

    if (_matches(
      text,
      r'\b(?:dangdut|koplo|pantura|tarling|kendang kempul|orkes melayu|om adella|new pallapa)\b',
    )) {
      return 'dangdut';
    }

    if (_matches(text, r'\b(?:hip hop|hiphop|rap|rap indonesia)\b')) return 'hip_hop';
    if (_matches(text, r'\b(?:r&b|rnb|rhythm and blues|soul music)\b')) return 'rnb';
    if (_matches(text, r'\b(?:rock|hard rock|alternative rock|metal|heavy metal|punk rock)\b')) {
      return 'rock';
    }
    if (_matches(text, r'\b(?:reggae|ska)\b')) return text.contains('ska') ? 'ska' : 'reggae';
    if (_matches(text, r'\b(?:jazz|smooth jazz|bebop)\b')) return 'jazz';
    if (_matches(text, r'\bblues\b')) return 'blues';
    if (_matches(text, r'\b(?:country|bluegrass)\b')) return 'country';
    if (_matches(text, r'\b(?:akustik|acoustic|unplugged)\b')) return 'acoustic';
    if (_matches(text, r'\b(?:indie|indie pop|indie folk)\b')) return 'indie';
    if (_matches(text, r'\b(?:instrumental|piano instrumental|music without vocals)\b')) {
      return 'instrumental';
    }
    if (_matches(text, r'\b(?:melayu|malaysia|slow rock malaysia|lagu malaysia)\b')) {
      return 'melayu';
    }
    if (_matches(text, r'\b(?:pop|ballad|top 40)\b')) return 'pop';

    // Artist cues help when a video title does not explicitly mention genre.
    if (_containsAny(text, _englishArtists)) return 'pop';
    if (_containsAny(text, _indonesianArtists)) {
      if (_containsAny(text, const ['denny caknan', 'ndarboy genk', 'guyon waton', 'aftershine', 'happy asmara', 'gilga sahid', 'niken salindry', 'jihan audy', 'difarina indra', 'farel prayoga', 'woro widowati', 'hendra kumbara', 'didi kempot'])) {
        return 'jawa';
      }
      if (_containsAny(text, const ['nella kharisma', 'siti badriah', 'lesti kejora', 'rhoma irama', 'elvy sukaesih', 'tasya rosmala', 'via vallen', 'dewi perssik', 'inul daratista', 'zaskia gotik', 'ayu ting ting'])) {
        return 'dangdut';
      }
      return 'pop';
    }
    if (_containsAny(text, _koreanArtists)) return 'kpop';

    return null;
  }

  /// True only when the query explicitly names a genre, rather than merely
  /// mentioning an artist whose music style is known.
  static bool hasExplicitStyleHint(String raw) {
    final text = normalize(raw);
    return _matches(
      text,
      r'\b(?:pop|ballad|top 40|pop dj|dj pop|pop remix|remix pop|dj|remix|funkot|jedag jedug|breakbeat|nightcore|slowed|sped up|bass boosted|slow bass|dangdut|koplo|pantura|tarling|campursari|langgam jawa|jawa|javanese|sunda|sundanese|jaipongan|degung|k pop|kpop|korean pop|hip hop|hiphop|rap|r&b|rnb|rhythm and blues|soul music|rock|metal|punk rock|reggae|ska|jazz|bebop|blues|country|bluegrass|acoustic|akustik|unplugged|indie|instrumental|melayu|lagu malaysia|sholawat|shalawat|qasidah|nasheed|nasyid|lagu religi|musik religi|lagu islami|rohani)\b',
    );
  }

  /// Broad language hints used to understand seeds and metadata. Some hints
  /// also name music styles (for example K-pop or lagu Jawa).
  static bool hasExplicitLanguageHint(String raw) {
    final lower = raw.toLowerCase();
    final text = normalize(raw);
    return _matches(
          lower,
          r'\b(?:english|inggris|bahasa inggris|lagu barat|western music|western pop|american pop|british pop|us pop|uk pop|english songs?|songs in english)\b',
        ) ||
        _matches(
          text,
          r'\b(?:indonesia|indonesian|bahasa indonesia|lagu indo|pop indo|musik indonesia|lagu indonesia)\b',
        ) ||
        _matches(lower, r'\b(?:korean|korea|k pop|kpop|lagu korea|japanese|jepang|anime song|spanish|spanyol|latin pop|hindi|bollywood|arabic|thai music|mandarin)\b') ||
        _matches(lower, r'\b(?:javanese|lagu jawa|pop jawa|sundanese|lagu sunda|pop sunda)\b') ||
        RegExp(r'[\uAC00-\uD7AF]').hasMatch(raw) ||
        RegExp(r'[\u3040-\u30FF]').hasMatch(raw) ||
        RegExp(r'[\u0600-\u06FF]').hasMatch(raw) ||
        RegExp(r'[\u0900-\u097F]').hasMatch(raw) ||
        RegExp(r'[\u0E00-\u0E7F]').hasMatch(raw);
  }

  /// True only when the user explicitly filters by a spoken/sung language.
  /// Style/culture terms such as K-pop, lagu Jawa, or anime song are not enough
  /// to lock an automatic Radio to one language.
  static bool hasExplicitLanguageFilter(String raw) {
    final lower = raw.toLowerCase();
    return _matches(
      lower,
      r'\b(?:english|inggris|bahasa inggris|english songs?|songs in english|korean language|bahasa korea|japanese language|bahasa jepang|spanish language|bahasa spanyol|hindi language|bahasa hindi|arabic language|bahasa arab|thai language|bahasa thai|mandarin language|bahasa mandarin)\b',
    );
  }

  /// Infer language hints from query, title, and known artist metadata.
  /// This is heuristic and may return null when there is not enough evidence.
  static String? languageFromText(String raw) {
    if (raw.trim().isEmpty) return null;
    final lower = raw.toLowerCase();
    final text = normalize(raw);

    if (RegExp(r'[\uAC00-\uD7AF]').hasMatch(raw) ||
        _matches(lower, r'\b(?:korean|korea|k pop|kpop|lagu korea|korean song)\b')) {
      return 'korean';
    }
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(raw) ||
        _matches(lower, r'\b(?:japanese|jepang|anime song|j pop|jpop)\b') ||
        _containsAny(text, _japaneseArtists)) {
      return 'japanese';
    }
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(raw) || _matches(lower, r'\b(?:arabic|arab)\b')) {
      return 'arabic';
    }
    if (RegExp(r'[\u0900-\u097F]').hasMatch(raw) || _matches(lower, r'\b(?:hindi|bollywood)\b')) {
      return 'hindi';
    }
    if (RegExp(r'[\u0E00-\u0E7F]').hasMatch(raw) || _matches(lower, r'\bthai music\b')) {
      return 'thai';
    }

    if (_matches(
      lower,
      r'\b(?:english|inggris|bahasa inggris|lagu barat|western music|western pop|american pop|british pop|us pop|uk pop|english songs?|songs in english)\b',
    )) {
      return 'english';
    }
    if (_matches(
      text,
      r'\b(?:indonesia|indonesian|bahasa indonesia|lagu indo|pop indo|musik indonesia|lagu indonesia)\b',
    )) {
      return 'indonesian';
    }
    if (_matches(text, r'\b(?:javanese|lagu jawa|pop jawa|campursari|koplo jawa)\b')) {
      return 'javanese';
    }
    if (_matches(text, r'\b(?:sundanese|lagu sunda|pop sunda|jaipongan)\b')) {
      return 'sundanese';
    }
    if (_matches(lower, r'\b(?:spanish|spanyol|latin pop|reggaeton)\b')) return 'spanish';
    if (_matches(lower, r'\bmandarin\b')) return 'mandarin';

    if (_containsAny(text, _koreanArtists)) return 'korean';
    if (_containsAny(text, _japaneseArtists)) return 'japanese';
    if (_containsAny(text, _englishArtists)) return 'english';
    if (_containsAny(text, _indonesianArtists)) return 'indonesian';

    return _languageFromWords(raw);
  }

  static String? _languageFromWords(String raw) {
    final words = normalize(raw).split(' ').where((word) => word.isNotEmpty).toList();
    if (words.isEmpty) return null;
    const englishWords = <String>{
      'love', 'loves', 'loved', 'story', 'you', 'your', 'youre', 'my', 'me', 'we',
      'our', 'i', 'the', 'and', 'is', 'are', 'was', 'were', 'with', 'without',
      'baby', 'heart', 'night', 'tonight', 'forever', 'never', 'stay', 'dance',
      'beautiful', 'lonely', 'somebody', 'nobody', 'someone', 'want', 'need',
      'feel', 'feeling', 'again', 'goodbye', 'hello', 'happy', 'sorry', 'life',
      'world', 'time', 'girl', 'boy', 'rain', 'fire', 'dream', 'dreams', 'angel',
      'only', 'one', 'more', 'everything', 'nothing', 'before', 'after', 'here',
      'there', 'where', 'when', 'what', 'why', 'how', 'like', 'light', 'dark',
    };
    const indonesianWords = <String>{
      'aku', 'kamu', 'engkau', 'dirimu', 'diriku', 'cinta', 'sayang', 'kasih',
      'hati', 'rindu', 'yang', 'tak', 'tidak', 'jangan', 'sudah', 'belum', 'untuk',
      'dengan', 'dari', 'sampai', 'ketika', 'namun', 'karena', 'selalu', 'kembali',
      'pergi', 'luka', 'menangis', 'dunia', 'bukan', 'ingin', 'biar', 'ku', 'mu',
      'kan', 'kita', 'dia', 'mencintai', 'terluka', 'bahagia', 'maaf', 'janji',
      'kenangan', 'berharap', 'terindah', 'pulang', 'hujan', 'bintang', 'malamku',
    };

    final englishScore = words.where(englishWords.contains).length;
    final indonesianScore = words.where(indonesianWords.contains).length;
    if (englishScore >= 2 && englishScore > indonesianScore) return 'english';
    if (indonesianScore >= 1 && indonesianScore >= englishScore) return 'indonesian';
    return null;
  }

  static String? languageFromVideo(YoutubeSearchResult? video) {
    if (video == null) return null;
    final metadata = '${video.title} ${video.channelTitle} ${video.album}';
    final explicit = languageFromText(metadata);
    if (explicit != null) return explicit;

    // Deskripsi video sering berisi tag eksplisit bahasa, tetapi tidak dipakai
    // untuk menghitung kata lirik biasa agar metadata promosi tidak mendominasi.
    final description = video.description.toLowerCase();
    if (_matches(description, r'\b(?:lyrics in english|english lyrics|english version|sung in english)\b')) {
      return 'english';
    }
    if (_matches(description, r'\b(?:lirik bahasa indonesia|lirik indonesia|versi bahasa indonesia)\b')) {
      return 'indonesian';
    }
    return _languageFromWords(video.title);
  }

  static String? styleFromVideo(YoutubeSearchResult? video) {
    if (video == null) return null;
    return styleFromText('${video.title} ${video.channelTitle} ${video.album}');
  }

  /// Query yang memang menyebut genre/bahasa diprioritaskan; kalau tidak,
  /// gunakan konteks track aktif agar Next tidak mengunci ke judul yang sama.
  static String? styleForContext({String query = '', YoutubeSearchResult? currentVideo}) {
    final queryStyle = styleFromText(query);
    return queryStyle ?? styleFromVideo(currentVideo);
  }

  static String? languageForContext({String query = '', YoutubeSearchResult? currentVideo}) {
    if (hasExplicitLanguageHint(query)) return languageFromText(query);
    return languageFromVideo(currentVideo) ?? languageFromText(query);
  }

  static bool isRelatedStyle(String candidateStyle, String targetStyle) {
    return _relatedStyles[targetStyle]?.contains(candidateStyle) ??
        candidateStyle == targetStyle;
  }

  static bool isCompatible({
    required YoutubeSearchResult video,
    required String? targetStyle,
    String? targetLanguage,
    bool allowCrossLanguage = false,
  }) {
    final candidateLanguage = languageFromVideo(video);
    // Language is normally a filter for an explicit user query. Radio started
    // from a track may cross languages when the musical style is compatible.
    if (!allowCrossLanguage &&
        targetLanguage != null &&
        candidateLanguage != null &&
        candidateLanguage != targetLanguage) {
      return false;
    }

    if (targetStyle == null) return true;
    final candidateStyle = styleFromVideo(video);
    // Genre unknown is held as a fallback rather than discarded outright.
    return candidateStyle == null || isRelatedStyle(candidateStyle, targetStyle);
  }

  /// Ranks Radio candidates like a lightweight song-radio mix: musical style
  /// dominates, language is only a small preference, and popularity helps
  /// surface familiar tracks. This is metadata-based, not Spotify's private
  /// audio/listening-history recommendation model.
  static double radioSimilarityScore({
    required YoutubeSearchResult video,
    required String? targetStyle,
    String? targetLanguage,
  }) {
    final candidateStyle = styleFromVideo(video);
    double score;
    if (targetStyle == null) {
      score = 22.0;
    } else if (candidateStyle == targetStyle) {
      score = 50.0;
    } else if (candidateStyle == null) {
      score = 15.0;
    } else if (isRelatedStyle(candidateStyle, targetStyle)) {
      score = 34.0;
    } else {
      score = -100.0;
    }

    // Do not hard-lock the language for a radio mix: same-language songs get
    // only a modest bonus, so a popular connected song in another language can
    // appear naturally instead of being rejected outright.
    final candidateLanguage = languageFromVideo(video);
    if (targetLanguage != null) {
      if (candidateLanguage == targetLanguage) {
        score += 2.5;
      } else if (candidateLanguage == null) {
        score += 1.25;
      }
    }

    final views = math.max(0, video.viewCount ?? 0);
    score += ((math.log(views + 1) / math.log(100000000)).clamp(0.0, 1.0) * 8.0).toDouble();

    final published = video.publishedAt;
    if (published != null) {
      final ageDays = math.max(0, DateTime.now().difference(published).inDays).toInt();
      if (ageDays < 365) score += ((365 - ageDays) / 365.0 * 1.5).toDouble();
    }
    return score;
  }

  /// Returns compatible tracks from all languages sorted by similarity.
  /// Pass allowCrossLanguage=false only for an explicitly language-filtered
  /// search; ordinary Radio should leave it enabled.
  static List<YoutubeSearchResult> rankForRadio(
    Iterable<YoutubeSearchResult> videos, {
    required String? targetStyle,
    String? targetLanguage,
    bool allowCrossLanguage = true,
  }) {
    var list = videos.where((video) => isCompatible(
      video: video,
      targetStyle: targetStyle,
      targetLanguage: targetLanguage,
      allowCrossLanguage: allowCrossLanguage,
    )).toList();

    // Unknown metadata is useful as a fallback, but if the pool already has
    // several songs with a recognized matching/related style, mixing unknowns
    // into the same shuffle makes Radio feel unrelated. Use metadata-known
    // candidates first and only fall back to unknowns when the known pool is
    // too small to form a useful next-song list.
    if (targetStyle != null) {
      final recognized = list.where((video) {
        final style = styleFromVideo(video);
        return style != null && isRelatedStyle(style, targetStyle);
      }).toList();
      if (recognized.length >= 2) {
        list = recognized;
      }
    }

    list.sort((a, b) => radioSimilarityScore(
      video: b,
      targetStyle: targetStyle,
      targetLanguage: targetLanguage,
    ).compareTo(radioSimilarityScore(
      video: a,
      targetStyle: targetStyle,
      targetLanguage: targetLanguage,
    )));
    return list;
  }

  /// Filter bahasa keras untuk jalur yang memang meminta bahasa tertentu.
  /// Song Radio menggunakan [rankForRadio] agar bahasa tidak mengunci hasil.
  static List<YoutubeSearchResult> prioritizeLanguage(
    Iterable<YoutubeSearchResult> videos,
    String? targetLanguage,
  ) {
    final list = videos.toList();
    if (targetLanguage == null) return list;
    final exact = list.where((video) => languageFromVideo(video) == targetLanguage).toList();
    if (exact.isNotEmpty) return exact;
    return list.where((video) => languageFromVideo(video) == null).toList();
  }

  /// Urutan rekomendasi: genre sama, genre berdekatan, lalu metadata genre
  /// belum diketahui. Bahasa yang berbeda tidak boleh menyalip bahasa target.
  static List<YoutubeSearchResult> prioritizeStyle(
    Iterable<YoutubeSearchResult> videos,
    String? targetStyle, {
    String? targetLanguage,
  }) {
    final languageFiltered = prioritizeLanguage(videos, targetLanguage);
    final compatible = languageFiltered
        .where((video) => isCompatible(
              video: video,
              targetStyle: targetStyle,
              targetLanguage: targetLanguage,
            ))
        .toList();

    if (targetStyle == null) return compatible;
    final exact = compatible
        .where((video) => styleFromVideo(video) == targetStyle)
        .toList();
    if (exact.isNotEmpty) return exact;

    final related = compatible.where((video) {
      final candidate = styleFromVideo(video);
      return candidate != null && isRelatedStyle(candidate, targetStyle);
    }).toList();
    if (related.isNotEmpty) return related;

    return compatible.where((video) => styleFromVideo(video) == null).toList();
  }

  /// Search seed untuk alur rekomendasi lagu, bukan untuk meniru judul track.
  /// Radio dari satu track memakai seed genre/style, lalu bahasa hanya menjadi
  /// sinyal lembut supaya lagu serupa lintas bahasa tetap dapat dipilih.
  static String recommendationSeedFor(YoutubeSearchResult video) {
    final style = styleFromVideo(video);
    // A track-started Radio should not turn detected language into a hard
    // search constraint. Keep culturally specific styles, but let regular Pop,
    // Rock, R&B, Indie, etc. discover connected tracks across languages.
    if (style == 'jawa' || style == 'sunda') {
      return recommendationSeed(style: style, language: languageFromVideo(video));
    }
    return recommendationSeed(style: style);
  }

  static String recommendationSeed({String? style, String? language}) {
    final resolvedStyle = style;
    final resolvedLanguage = language;

    if (resolvedStyle == 'jawa' || resolvedLanguage == 'javanese') {
      return 'lagu Jawa populer';
    }
    if (resolvedStyle == 'sunda' || resolvedLanguage == 'sundanese') {
      return 'lagu Sunda populer';
    }
    if (resolvedStyle == 'kpop' || resolvedLanguage == 'korean') {
      return 'popular K-pop songs';
    }

    final styleLabel = switch (resolvedStyle) {
      'pop' => 'pop',
      'pop_dj' => 'pop DJ remix',
      'dj_remix' => 'DJ remix',
      'dangdut' => 'dangdut',
      'hip_hop' => 'hip hop',
      'rnb' => 'R&B',
      'rock' => 'rock',
      'reggae' => 'reggae',
      'ska' => 'ska',
      'jazz' => 'jazz',
      'blues' => 'blues',
      'country' => 'country',
      'acoustic' => 'acoustic',
      'indie' => 'indie',
      'instrumental' => 'instrumental',
      'melayu' => 'Melayu',
      'religi' => 'religious',
      _ => null,
    };

    if (resolvedLanguage == 'english') {
      return styleLabel == null
          ? 'popular English songs'
          : 'popular English $styleLabel songs';
    }
    if (resolvedLanguage == 'indonesian') {
      return styleLabel == null
          ? 'lagu Indonesia populer'
          : 'lagu $styleLabel Indonesia populer';
    }
    if (resolvedLanguage == 'japanese') {
      return styleLabel == null
          ? 'popular Japanese songs'
          : 'popular Japanese $styleLabel songs';
    }
    if (resolvedLanguage == 'spanish') {
      return styleLabel == null
          ? 'popular Spanish songs'
          : 'popular Spanish $styleLabel songs';
    }
    if (resolvedLanguage == 'hindi') {
      return styleLabel == null
          ? 'popular Hindi songs'
          : 'popular Hindi $styleLabel songs';
    }
    if (resolvedLanguage == 'arabic') return 'popular Arabic songs';
    if (resolvedLanguage == 'thai') return 'popular Thai songs';
    if (resolvedLanguage == 'mandarin') return 'popular Mandarin songs';

    if (styleLabel != null) return 'popular $styleLabel songs';
    return 'popular music songs';
  }

  static String seedForStyle(String style) => switch (style) {
        'jawa' => 'lagu Jawa Indonesia',
        'sunda' => 'lagu Sunda Indonesia',
        'kpop' => 'K-pop songs',
        'dj_remix' => 'DJ remix Indonesia',
        'pop_dj' => 'pop DJ remix Indonesia',
        'religi' => 'lagu religi Indonesia',
        'dangdut' => 'lagu dangdut Indonesia',
        'hip_hop' => 'hip hop Indonesia',
        'rnb' => 'R&B music',
        'rock' => 'lagu rock Indonesia',
        'reggae' => 'lagu reggae Indonesia',
        'ska' => 'lagu ska',
        'jazz' => 'lagu jazz',
        'blues' => 'lagu blues',
        'country' => 'country music',
        'acoustic' => 'lagu akustik Indonesia',
        'indie' => 'lagu indie Indonesia',
        'instrumental' => 'instrumental music',
        'melayu' => 'lagu Melayu Malaysia',
        'pop' => 'lagu pop Indonesia',
        _ => 'lagu Indonesia',
      };
}
