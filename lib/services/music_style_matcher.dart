import '../models/youtube_search_result.dart';

/// Heuristik internal genre, subgenre, dan bahasa untuk Smart Shuffle/Radio.
/// Nilai ini hanya memengaruhi pemilihan kandidat; jangan tampilkan sebagai label UI.
///
/// YouTube Data API tidak menyediakan genre atau bahasa lagu yang akurat untuk
/// setiap video. Karena itu, hasil di bawah merupakan petunjuk dari query,
/// judul, artis/channel, dan metadata yang tersedia. Saat genre terkait sudah
/// teridentifikasi, kandidat tanpa gaya yang dikenal tidak boleh mencampur pool.
class MusicStyleMatcher {
  MusicStyleMatcher._();

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s&+#]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // RegExp dikompilasi sekali. Sebelumnya setiap panggilan _matches membuat
  // RegExp baru, padahal styleFromText/languageFromText dipanggil untuk setiap
  // kandidat berkali-kali.
  static final Map<String, RegExp> _regexCache = <String, RegExp>{};

  static bool _matches(String text, String pattern) =>
      (_regexCache[pattern] ??= RegExp(pattern, caseSensitive: false)).hasMatch(text);

  static final RegExp _hangul = RegExp(r'[\uAC00-\uD7AF]');
  static final RegExp _kana = RegExp(r'[\u3040-\u30FF]');
  static final RegExp _arabicScript = RegExp(r'[\u0600-\u06FF]');
  static final RegExp _devanagari = RegExp(r'[\u0900-\u097F]');
  static final RegExp _thaiScript = RegExp(r'[\u0E00-\u0E7F]');

  /// Cocokkan sebagai frasa utuh (batas kata), bukan substring. Sebelumnya
  /// 'ive' cocok dengan "live", 'sia' dengan "asia", 'ado' dengan "adorable",
  /// 'iu' dengan "ciuman", sehingga judul biasa salah dianggap artis tertentu.
  /// [text] harus sudah dinormalisasi.
  static bool _containsAnyPhrase(String text, Iterable<String> phrases) {
    final padded = ' $text ';
    return phrases.any((phrase) => padded.contains(' $phrase '));
  }

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

  static const Set<String> _javaneseArtists = <String>{
    'denny caknan', 'ndarboy genk', 'guyon waton', 'aftershine',
    'happy asmara', 'gilga sahid', 'niken salindry', 'jihan audy',
    'difarina indra', 'farel prayoga', 'woro widowati', 'hendra kumbara',
    'didi kempot',
  };

  static const Set<String> _dangdutArtists = <String>{
    'nella kharisma', 'siti badriah', 'lesti kejora', 'rhoma irama',
    'elvy sukaesih', 'tasya rosmala', 'via vallen', 'dewi perssik',
    'inul daratista', 'zaskia gotik', 'ayu ting ting',
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
    'psy', 'bigbang', 'girls generation', 'itzy', 'enhypen', 'txt',
  };

  static const Set<String> _japaneseArtists = <String>{
    'yoasobi', 'ado', 'kenshi yonezu', 'official hige dandism', 'aimyon',
    'one ok rock', 'king gnu', 'radwimps',
  };

  /// Genre yang disebut eksplisit lewat kata kunci (tanpa petunjuk artis).
  /// Urutan penting: Pop DJ dipisahkan dari DJ/remix biasa, dan subgenre lokal
  /// tidak boleh jatuh ke Pop umum. [text] harus sudah dinormalisasi.
  static String? _styleFromKeywords(String text) {
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

    // Harus sebelum 'rock': "slow rock malaysia" adalah Melayu, bukan rock.
    if (_matches(text, r'\b(?:melayu|malaysia|slow rock malaysia|lagu malaysia)\b')) {
      return 'melayu';
    }

    if (_matches(text, r'\b(?:hip hop|hiphop|rap|rap indonesia)\b')) return 'hip_hop';
    if (_matches(text, r'\b(?:r&b|rnb|rhythm and blues|soul music)\b')) return 'rnb';
    if (_matches(text, r'\b(?:rock|hard rock|alternative rock|metal|heavy metal|punk rock)\b')) {
      return 'rock';
    }
    // Word boundary: sebelumnya text.contains('ska') cocok dengan "baskara", "maskara", dll.
    if (_matches(text, r'\bska\b')) return 'ska';
    if (_matches(text, r'\breggae\b')) return 'reggae';
    if (_matches(text, r'\b(?:jazz|smooth jazz|bebop)\b')) return 'jazz';
    if (_matches(text, r'\bblues\b')) return 'blues';
    if (_matches(text, r'\b(?:country|bluegrass)\b')) return 'country';
    if (_matches(text, r'\b(?:akustik|acoustic|unplugged)\b')) return 'acoustic';
    if (_matches(text, r'\b(?:indie|indie pop|indie folk)\b')) return 'indie';
    if (_matches(text, r'\b(?:instrumental|piano instrumental|music without vocals)\b')) {
      return 'instrumental';
    }
    if (_matches(text, r'\b(?:pop|ballad|top 40)\b')) return 'pop';

    return null;
  }

  /// Mengembalikan genre yang terdeteksi dari query/metadata.
  static String? styleFromText(String raw) {
    final text = normalize(raw);
    if (text.isEmpty) return null;

    final explicit = _styleFromKeywords(text);
    if (explicit != null) return explicit;

    // Artist cues help when a video title does not explicitly mention genre.
    if (_containsAnyPhrase(text, _englishArtists)) return 'pop';
    if (_containsAnyPhrase(text, _indonesianArtists)) {
      if (_containsAnyPhrase(text, _javaneseArtists)) return 'jawa';
      if (_containsAnyPhrase(text, _dangdutArtists)) return 'dangdut';
      return 'pop';
    }
    if (_containsAnyPhrase(text, _koreanArtists)) return 'kpop';

    return null;
  }

  /// True only when the query explicitly names a genre, rather than merely
  /// mentioning an artist whose music style is known.
  /// Memakai aturan yang sama dengan [styleFromText] agar daftar kata kunci
  /// tidak bisa menyimpang (sebelumnya ada dua daftar terpisah).
  static bool hasExplicitStyleHint(String raw) =>
      _styleFromKeywords(normalize(raw)) != null;

  /// Broad language hints used to understand seeds and metadata. Some hints
  /// also name music styles (for example K-pop or lagu Jawa).
  static bool hasExplicitLanguageHint(String raw) {
    // Pakai teks ternormalisasi: "K-Pop" menjadi "k pop". Sebelumnya `lower`
    // dipakai sehingga "K-Pop"/"J-Pop" dengan tanda hubung tidak terdeteksi.
    final text = normalize(raw);
    return _matches(
          text,
          r'\b(?:english|inggris|bahasa inggris|lagu barat|western music|western pop|american pop|british pop|us pop|uk pop|english songs?|songs in english)\b',
        ) ||
        _matches(
          text,
          r'\b(?:indonesia|indonesian|bahasa indonesia|lagu indo|pop indo|musik indonesia|lagu indonesia)\b',
        ) ||
        _matches(text, r'\b(?:korean|korea|k pop|kpop|lagu korea|japanese|jepang|anime song|spanish|spanyol|latin pop|hindi|bollywood|arabic|thai music|mandarin)\b') ||
        _matches(text, r'\b(?:javanese|lagu jawa|pop jawa|sundanese|lagu sunda|pop sunda)\b') ||
        _hangul.hasMatch(raw) ||
        _kana.hasMatch(raw) ||
        _arabicScript.hasMatch(raw) ||
        _devanagari.hasMatch(raw) ||
        _thaiScript.hasMatch(raw);
  }

  /// True only when the user explicitly filters by a spoken/sung language.
  /// Style/culture terms such as K-pop, lagu Jawa, or anime song are not enough
  /// to lock an automatic Radio to one language.
  static bool hasExplicitLanguageFilter(String raw) {
    final text = normalize(raw);
    return _matches(
      text,
      r'\b(?:english|inggris|bahasa inggris|english songs?|songs in english|korean language|bahasa korea|japanese language|bahasa jepang|spanish language|bahasa spanyol|hindi language|bahasa hindi|arabic language|bahasa arab|thai language|bahasa thai|mandarin language|bahasa mandarin)\b',
    );
  }

  /// Infer language hints from query, title, and known artist metadata.
  /// This is heuristic and may return null when there is not enough evidence.
  static String? languageFromText(String raw) {
    if (raw.trim().isEmpty) return null;
    final text = normalize(raw);

    if (_hangul.hasMatch(raw) ||
        _matches(text, r'\b(?:korean|korea|k pop|kpop|lagu korea|korean song)\b')) {
      return 'korean';
    }
    if (_kana.hasMatch(raw) ||
        _matches(text, r'\b(?:japanese|jepang|anime song|j pop|jpop)\b') ||
        _containsAnyPhrase(text, _japaneseArtists)) {
      return 'japanese';
    }
    if (_arabicScript.hasMatch(raw) || _matches(text, r'\b(?:arabic|arab)\b')) {
      return 'arabic';
    }
    if (_devanagari.hasMatch(raw) || _matches(text, r'\b(?:hindi|bollywood)\b')) {
      return 'hindi';
    }
    if (_thaiScript.hasMatch(raw) || _matches(text, r'\bthai music\b')) {
      return 'thai';
    }

    if (_matches(
      text,
      r'\b(?:english|inggris|bahasa inggris|lagu barat|western music|western pop|american pop|british pop|us pop|uk pop|english songs?|songs in english)\b',
    )) {
      return 'english';
    }
    // Bahasa daerah dicek SEBELUM "indonesia": "lagu Jawa Indonesia" harus
    // javanese, bukan indonesian.
    if (_matches(text, r'\b(?:javanese|lagu jawa|pop jawa|campursari|koplo jawa)\b')) {
      return 'javanese';
    }
    if (_matches(text, r'\b(?:sundanese|lagu sunda|pop sunda|jaipongan)\b')) {
      return 'sundanese';
    }
    if (_matches(
      text,
      r'\b(?:indonesia|indonesian|bahasa indonesia|lagu indo|pop indo|musik indonesia|lagu indonesia)\b',
    )) {
      return 'indonesian';
    }
    if (_matches(text, r'\b(?:spanish|spanyol|latin pop|reggaeton)\b')) return 'spanish';
    if (_matches(text, r'\bmandarin\b')) return 'mandarin';

    if (_containsAnyPhrase(text, _koreanArtists)) return 'korean';
    if (_containsAnyPhrase(text, _englishArtists)) return 'english';
    if (_containsAnyPhrase(text, _indonesianArtists)) return 'indonesian';

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

  /// Hubungan antar-gaya dibuat simetris. Sebelumnya tabel satu arah: target
  /// pop_dj menerima dangdut, tetapi target dangdut menolak pop_dj (begitu
  /// juga sunda/jawa, melayu/pop_dj, blues/rock, country/acoustic, dst.),
  /// sehingga radio berperilaku berbeda tergantung lagu mana yang dimulai.
  static bool isRelatedStyle(String candidateStyle, String targetStyle) {
    if (candidateStyle == targetStyle) return true;
    return (_relatedStyles[targetStyle]?.contains(candidateStyle) ?? false) ||
        (_relatedStyles[candidateStyle]?.contains(targetStyle) ?? false);
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

  static double _similarityScore({
    required String? candidateStyle,
    required String? candidateLanguage,
    required String? targetStyle,
    required String? targetLanguage,
  }) {
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

    if (targetLanguage != null) {
      if (candidateLanguage == targetLanguage) {
        score += 2.5;
      } else if (candidateLanguage == null) {
        score += 1.25;
      }
    }
    return score;
  }

  /// Scores candidates by musical compatibility and a small language hint.
  /// Popularity/view count and freshness deliberately do not affect the score:
  /// Radio must keep relevance to the current track ahead of chart rank.
  static double radioSimilarityScore({
    required YoutubeSearchResult video,
    required String? targetStyle,
    String? targetLanguage,
  }) =>
      _similarityScore(
        candidateStyle: styleFromVideo(video),
        candidateLanguage: languageFromVideo(video),
        targetStyle: targetStyle,
        targetLanguage: targetLanguage,
      );

  /// Returns compatible tracks from all languages sorted by similarity.
  /// Pass allowCrossLanguage=false only for an explicitly language-filtered
  /// search; ordinary Radio should leave it enabled.
  static List<YoutubeSearchResult> rankForRadio(
    Iterable<YoutubeSearchResult> videos, {
    required String? targetStyle,
    String? targetLanguage,
    bool allowCrossLanguage = true,
  }) {
    // Hitung gaya/bahasa tiap video sekali. Sebelumnya skor dihitung ulang
    // (dengan puluhan regex) di dalam comparator sort pada setiap perbandingan.
    var entries = <({YoutubeSearchResult video, String? style, String? language, int index})>[];
    var index = 0;
    for (final video in videos) {
      final style = styleFromVideo(video);
      final language = languageFromVideo(video);

      if (!allowCrossLanguage &&
          targetLanguage != null &&
          language != null &&
          language != targetLanguage) {
        continue;
      }
      if (targetStyle != null && style != null && !isRelatedStyle(style, targetStyle)) {
        continue;
      }
      entries.add((video: video, style: style, language: language, index: index++));
    }

    // For a known current style, never dilute the radio with unclassified
    // tracks once at least one explicitly related candidate exists. If no
    // related style can be identified, the YouTube relevance order is the only
    // signal available; do not substitute a global popular-song catalogue.
    if (targetStyle != null) {
      final recognized = entries
          .where((e) => e.style != null && isRelatedStyle(e.style!, targetStyle))
          .toList();
      if (recognized.isNotEmpty) entries = recognized;
    }

    final scored = entries
        .map((e) => (
              video: e.video,
              index: e.index,
              score: _similarityScore(
                candidateStyle: e.style,
                candidateLanguage: e.language,
                targetStyle: targetStyle,
                targetLanguage: targetLanguage,
              ),
            ))
        .toList();
    scored.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      // Keep YouTube relevance order for candidates with equal compatibility.
      return scoreOrder != 0 ? scoreOrder : a.index.compareTo(b.index);
    });
    return scored.map((e) => e.video).toList(growable: false);
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

  /// Seed Radio harus menyebut lagu dan artis yang sedang diputar agar
  /// pencarian berikutnya tetap terkait track, bukan jatuh ke chart genre.
  static String recommendationSeedFor(YoutubeSearchResult video) {
    final title = _radioSeedTitle(video.title);
    final artist = _radioSeedArtist(video.channelTitle);
    final titleKey = normalize(title);
    final artistKey = normalize(artist);
    if (title.isEmpty && artist.isEmpty) return '';
    // Judul YouTube biasanya "Artis - Judul"; jangan tulis nama artis dua kali.
    final artistAlreadyInTitle = artistKey.isEmpty ||
        titleKey == artistKey ||
        ' $titleKey '.contains(' $artistKey ');
    return <String>[
      if (title.isNotEmpty) title,
      if (artist.isNotEmpty && !artistAlreadyInTitle) artist,
      'similar songs',
    ].join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _radioSeedTitle(String raw) {
    var title = raw.toLowerCase().replaceAll(RegExp(r'https?://\S+'), ' ');
    // Word boundary pada penanda metadata: sebelumnya "hd" cocok sebagai
    // substring sehingga kurung berisi judul/kata biasa ikut terhapus.
    const marker =
        r'(?:official|music video|official audio|lyrics?|visualizer|topic|4k|\bhd\b)';
    title = title
        .replaceAll(
          RegExp(r'\[(?=[^\]]*' + marker + r')[^\]]*\]', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'\((?=[^)]*' + marker + r')[^)]*\)', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(?:official music video|official video|official audio|music video|lyric video|lyrics?|visualizer|topic|vevo)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return title.replaceAll(RegExp(r'^[\s|:_-]+|[\s|:_-]+$'), '').trim();
  }

  static String _radioSeedArtist(String raw) {
    return raw.toLowerCase()
        .replaceAll(RegExp(r'\s*[-|]\s*(?:official(?:\s+(?:artist|channel))?|topic|vevo)\s*$', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\b(?:official|artist|channel|topic|vevo)\b', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s|:_-]+|[\s|:_-]+$'), '')
        .trim();
  }

  static String recommendationSeed({String? style, String? language}) {
    final resolvedStyle = style;
    final resolvedLanguage = language;

    if (resolvedStyle == 'jawa' || resolvedLanguage == 'javanese') {
      return 'lagu Jawa serupa';
    }
    if (resolvedStyle == 'sunda' || resolvedLanguage == 'sundanese') {
      return 'lagu Sunda serupa';
    }
    if (resolvedStyle == 'kpop' || resolvedLanguage == 'korean') {
      return 'K-pop songs similar';
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
          ? 'English songs similar'
          : 'English $styleLabel songs similar';
    }
    if (resolvedLanguage == 'indonesian') {
      return styleLabel == null
          ? 'lagu Indonesia serupa'
          : 'lagu $styleLabel Indonesia serupa';
    }
    if (resolvedLanguage == 'japanese') {
      return styleLabel == null
          ? 'Japanese songs similar'
          : 'Japanese $styleLabel songs similar';
    }
    if (resolvedLanguage == 'spanish') {
      return styleLabel == null
          ? 'Spanish songs similar'
          : 'Spanish $styleLabel songs similar';
    }
    if (resolvedLanguage == 'hindi') {
      return styleLabel == null
          ? 'Hindi songs similar'
          : 'Hindi $styleLabel songs similar';
    }
    if (resolvedLanguage == 'arabic') return 'Arabic songs similar';
    if (resolvedLanguage == 'thai') return 'Thai songs similar';
    if (resolvedLanguage == 'mandarin') return 'Mandarin songs similar';

    if (styleLabel != null) return '$styleLabel songs similar';
    return 'songs similar to this style';
  }

  static String seedForStyle(String style) => switch (style) {
        'jawa' => 'lagu Jawa serupa Indonesia',
        'sunda' => 'lagu Sunda serupa Indonesia',
        'kpop' => 'K-pop songs similar',
        'dj_remix' => 'DJ remix serupa Indonesia',
        'pop_dj' => 'pop DJ remix serupa Indonesia',
        'religi' => 'lagu religi serupa Indonesia',
        'dangdut' => 'lagu dangdut serupa Indonesia',
        'hip_hop' => 'hip hop serupa Indonesia',
        'rnb' => 'R&B songs similar',
        'rock' => 'lagu rock serupa Indonesia',
        'reggae' => 'lagu reggae serupa Indonesia',
        'ska' => 'lagu ska serupa',
        'jazz' => 'lagu jazz serupa',
        'blues' => 'lagu blues serupa',
        'country' => 'country songs similar',
        'acoustic' => 'lagu akustik serupa Indonesia',
        'indie' => 'lagu indie serupa Indonesia',
        'instrumental' => 'instrumental songs similar',
        'melayu' => 'lagu Melayu serupa Malaysia',
        'pop' => 'lagu pop serupa Indonesia',
        _ => 'lagu Indonesia serupa',
      };
}