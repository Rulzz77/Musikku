import 'dart:math' as math;

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
    'chappell roan', 'benson boone', 'teddy swims', 'lewis capaldi',
    'gracie abrams', 'tate mcrae', 'doja cat', 'sza', 'david guetta',
    'calvin harris', 'alan walker', 'martin garrix', 'marshmello',
    'the chainsmokers', 'ellie goulding', 'noah kahan', 'david kushner',
    'lauv', 'jvke', 'conan gray', 'tones and i', 'lizzo', 'ava max',
    'meghan trainor', 'camila cabello', 'anne marie', 'zayn', 'niall horan',
    'louis tomlinson', 'john legend', 'alicia keys', 'christina perri',
    'david archuleta', 'jason mraz', 'john mayer', };

  static const Set<String> _javaneseArtists = <String>{
    'denny caknan', 'ndarboy genk', 'guyon waton', 'aftershine',
    'happy asmara', 'gilga sahid', 'niken salindry', 'jihan audy',
    'difarina indra', 'farel prayoga', 'woro widowati', 'hendra kumbara',
    'didi kempot', 'mahesa', 'wandra', 'abah lala', 'sasya arkhisna',
    'nazia marwiana', 'shepin misa', 'arlida putri', 'esa risty',
    'kalia siska', 'syahiba saufa', 'cak sodiq', 'pendhoza', 'dike sabrina',
  };

  static const Set<String> _dangdutArtists = <String>{
    'nella kharisma', 'siti badriah', 'lesti kejora', 'rhoma irama',
    'elvy sukaesih', 'tasya rosmala', 'via vallen', 'dewi perssik',
    'inul daratista', 'zaskia gotik', 'ayu ting ting', 'shinta arsinta',
    'yeni inka', 'anggun pramudita', 'vita alvia', 'safira inema',
    'arya galih', 'fendik adella', 'lala widy', 'alvi ananta',
    'putri kristya', 'rita sugiarto', 'mansyur s', 'evie tamala',
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
    'bernadya', 'nadin amizah', 'sal priadi', 'hindia', 'feby putri',
    'tri suaka', 'zinidin zidan', 'andra respati', 'pamungkas',
    'ziva magnolya', 'fabio asher', 'arsy widianto', 'anggi marito',
    'ghea indrawari', 'ardhito pramono', 'reality club', 'hivi', 'kahitna',
    'juicy luicy', 'adera', 'fiersa besari', 'barasuara',
    'efek rumah kaca', 'gigi', 'slank', 'padi', 'kerispatih', 'd masiv',
    'st12', 'hijau daun', 'radja', 'vierra', 'repvblik', 'stinky', 'jamrud', 'base jam', 'iwan fals', 'god bless',
    'chrisye', 'krisdayanti', 'agnez mo', 'anji', 'virgoun', 'glenn fredly',
    'naff', 'seurieus', 'edane', 'young lex', 'ecko show',
    'saykoji', 'iwa k', 'shinta arsinta', 'yeni inka', 'anggun pramudita',
    'vita alvia', 'safira inema', 'arya galih', 'fendik adella',
    'lala widy', 'alvi ananta', 'putri kristya', 'mahesa', 'wandra',
    'abah lala', 'sasya arkhisna', 'nazia marwiana', 'shepin misa',
    'arlida putri', 'esa risty', 'kalia siska', 'syahiba saufa',
    'cak sodiq', 'pendhoza', 'dike sabrina',
  };

  static const Set<String> _koreanArtists = <String>{
    'blackpink', 'stray kids', 'newjeans', 'seventeen', 'twice', 'exo',
    'bts', 'aespa', 'ive', 'le sserafim', 'red velvet', 'nct', 'iu',
    'psy', 'bigbang', 'girls generation', 'itzy', 'enhypen', 'txt',
    'babymonster', 'illit', 'riize', 'zerobaseone', 'ateez', 'jennie',
    'jisoo', 'g dragon', 'taeyeon', 'jungkook', 'jimin', 'mamamoo', 'shinee', 'super junior', 'kep1er', 'nmixx', 'g i dle',
    'tomorrow x together', 'day6', 'akmu', 'zico', 'sunmi',
    'chungha', 'hwasa', 'heize', 'paul kim', '2ne1', 'wonder girls',
  };

  static const Set<String> _japaneseArtists = <String>{
    'yoasobi', 'ado', 'kenshi yonezu', 'official hige dandism', 'aimyon',
    'one ok rock', 'king gnu', 'radwimps', 'yorushika', 'fujii kaze',
    'zutomayo', 'vaundy', 'mrs green apple', 'back number',
    'bump of chicken', 'spitz', 'utada hikaru', 'hikaru utada',
    'creepy nuts', 'kana boon', 'sekai no owari',
  };

  // Artis dengan genre yang jelas bukan pop. Tanpa ini semua artis Barat
  // dianggap pop, sehingga radio rapper ikut memutar lagu pop.
  static const Set<String> _hipHopArtists = <String>{
    'eminem', 'drake', 'kendrick lamar', 'travis scott', 'jay z',
    '21 savage', 'j cole', 'lil wayne', 'nicki minaj', 'cardi b', '50 cent',
    'snoop dogg', 'kanye west', 'juice wrld', 'xxxtentacion', 'tyga',
    'young lex', 'ecko show', 'saykoji', 'iwa k',
  };

  static const Set<String> _rockArtists = <String>{
    'linkin park', 'nirvana', 'green day', 'metallica', 'guns n roses',
    'ac dc', 'foo fighters', 'red hot chili peppers', 'bon jovi',
    'scorpions', 'my chemical romance', 'paramore', 'fall out boy',
    'blink 182', 'sum 41', 'slank', 'god bless', 'jamrud', 'seurieus',
    'edane',
  };

  static final Set<String> _allKnownArtists = <String>{
    ..._englishArtists,
    ..._indonesianArtists,
    ..._javaneseArtists,
    ..._dangdutArtists,
    ..._koreanArtists,
    ..._japaneseArtists,
    ..._hipHopArtists,
    ..._rockArtists,
  };

  static bool _isKnownArtist(String normalizedText) =>
      normalizedText.isNotEmpty &&
      _containsAnyPhrase(normalizedText, _allKnownArtists);

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
    // Genre khusus dicek lebih dulu; pop hanya jadi default untuk artis umum.
    if (_containsAnyPhrase(text, _javaneseArtists)) return 'jawa';
    if (_containsAnyPhrase(text, _dangdutArtists)) return 'dangdut';
    if (_containsAnyPhrase(text, _hipHopArtists)) return 'hip_hop';
    if (_containsAnyPhrase(text, _rockArtists)) return 'rock';
    if (_containsAnyPhrase(text, _koreanArtists)) return 'kpop';
    if (_containsAnyPhrase(text, _englishArtists)) return 'pop';
    if (_containsAnyPhrase(text, _indonesianArtists)) return 'pop';

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
    if (_containsAnyPhrase(text, _indonesianArtists) ||
        _containsAnyPhrase(text, _javaneseArtists) ||
        _containsAnyPhrase(text, _dangdutArtists)) {
      return 'indonesian';
    }

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

  // ---------------------------------------------------------------------------
  // SEED RADIO
  //
  // Cara kerja (mirip Radio lagu di Spotify, tetapi memakai pencarian YouTube):
  //   1. Seed utama  = artis lagu yang sedang diputar + label genre.
  //      Contoh: "denny caknan lagu jawa". Hasilnya lagu lain dari artis yang
  //      sama, bukan unggahan ulang/cover dari judul yang sama.
  //   2. Seed cadangan = artis sejenis (satu kelompok genre) lalu pencarian
  //      "terpopuler" untuk genre itu. RadioService memakainya bergantian di
  //      setiap isi ulang, jadi daftar putar bercampur antar artis.
  // Semua kandidat tetap disaring oleh isCompatible/rankForRadio.
  // ---------------------------------------------------------------------------

  static final math.Random _random = math.Random();

  /// Label yang ditambahkan ke seed. Setiap label HARUS terbaca kembali sebagai
  /// genre yang sama oleh [styleFromText], karena RadioService menurunkan genre
  /// target dari teks seed.
  static const Map<String, String> _seedStyleLabels = <String, String>{
    'jawa': 'lagu jawa',
    'sunda': 'lagu sunda',
    'kpop': 'kpop',
    'pop_dj': 'pop dj remix',
    'dj_remix': 'dj remix',
    'religi': 'lagu religi',
    'dangdut': 'dangdut',
    'hip_hop': 'hip hop',
    'rnb': 'r&b',
    'rock': 'rock',
    'reggae': 'reggae',
    'ska': 'ska',
    'jazz': 'jazz',
    'blues': 'blues',
    'country': 'country',
    'acoustic': 'akustik',
    'indie': 'indie',
    'instrumental': 'instrumental',
    'melayu': 'lagu melayu',
    'pop': 'pop',
  };

  /// Kelompok artis yang saling mirip. Dipakai untuk "artis sejenis" dan
  /// sebagai daftar artis yang paling sering dicari per genre.
  static const Map<String, List<String>> _peerGroups = <String, List<String>>{
    'jawa': <String>[
      'denny caknan', 'happy asmara', 'guyon waton', 'ndarboy genk',
      'gilga sahid', 'niken salindry', 'farel prayoga', 'difarina indra',
      'mahesa', 'sasya arkhisna', 'nazia marwiana', 'shepin misa',
      'arlida putri', 'didi kempot', 'woro widowati', 'jihan audy',
    ],
    'dangdut': <String>[
      'nella kharisma', 'lesti kejora', 'tasya rosmala', 'via vallen',
      'shinta arsinta', 'yeni inka', 'vita alvia', 'safira inema',
      'ayu ting ting', 'siti badriah', 'rhoma irama', 'dewi perssik',
      'zaskia gotik', 'elvy sukaesih',
    ],
    'pop_id': <String>[
      'tulus', 'raisa', 'mahalini', 'tiara andini', 'lyodra',
      'rizky febian', 'bernadya', 'nadin amizah', 'sal priadi', 'hindia',
      'juicy luicy', 'pamungkas', 'ghea indrawari', 'yura yunita',
      'isyana sarasvati', 'afgan', 'andmesh kamaleng', 'ardhito pramono',
      'fiersa besari', 'hivi', 'adera', 'keisya levronka',
    ],
    'band_id': <String>[
      'sheila on 7', 'dewa 19', 'noah', 'peterpan', 'ungu', 'kotak',
      'armada', 'letto', 'nidji', 'd masiv', 'kerispatih', 'st12',
      'hijau daun', 'slank', 'gigi', 'padi', 'naff', 'radja', 'vierra',
      'repvblik', 'geisha', 'fourtwnty', 'payung teduh',
    ],
    'pop_en': <String>[
      'taylor swift', 'sabrina carpenter', 'olivia rodrigo', 'dua lipa',
      'billie eilish', 'ariana grande', 'harry styles', 'ed sheeran',
      'bruno mars', 'the weeknd', 'charlie puth', 'shawn mendes',
      'selena gomez', 'gracie abrams', 'benson boone', 'teddy swims',
      'lewis capaldi', 'chappell roan', 'tate mcrae', 'justin bieber',
    ],
    'kpop': <String>[
      'blackpink', 'newjeans', 'aespa', 'stray kids', 'seventeen', 'twice',
      'bts', 'ive', 'le sserafim', 'itzy', 'enhypen', 'txt', 'nmixx',
      'illit', 'babymonster', 'red velvet', 'iu', 'exo',
    ],
    'jpop': <String>[
      'yoasobi', 'ado', 'kenshi yonezu', 'official hige dandism', 'aimyon',
      'king gnu', 'radwimps', 'one ok rock', 'yorushika', 'fujii kaze',
    ],
    'rock_en': <String>[
      'linkin park', 'nirvana', 'green day', 'foo fighters', 'metallica',
      'red hot chili peppers', 'bon jovi', 'my chemical romance',
      'paramore', 'fall out boy', 'blink 182', 'sum 41',
    ],
    'hip_hop_en': <String>[
      'eminem', 'drake', 'kendrick lamar', 'travis scott', 'post malone',
      'j cole', 'nicki minaj', 'cardi b', 'juice wrld', '50 cent',
    ],
    'hip_hop_id': <String>['young lex', 'ecko show', 'saykoji', 'iwa k'],
  };

  /// Kelompok yang pendengarnya biasanya tumpang tindih. Radio menyisipkan
  /// satu artis terkenal dari kelompok terkait supaya tidak berputar di
  /// lingkaran artis yang sama.
  static const Map<String, List<String>> _relatedGroups = <String, List<String>>{
    'pop_id': <String>['band_id'],
    'band_id': <String>['pop_id'],
    'jawa': <String>['dangdut'],
    'dangdut': <String>['jawa'],
    'pop_en': <String>['rock_en'],
    'rock_en': <String>['pop_en'],
    'hip_hop_en': <String>['pop_en'],
    'kpop': <String>['jpop'],
    'jpop': <String>['kpop'],
  };

  static String? _groupOfArtist(String artistKey) {
    if (artistKey.isEmpty) return null;
    final padded = ' $artistKey ';
    for (final entry in _peerGroups.entries) {
      if (entry.value.any((peer) => padded.contains(' $peer '))) {
        return entry.key;
      }
    }
    return null;
  }

  /// Kelompok bawaan untuk genre/bahasa tertentu ketika artisnya tidak dikenal.
  static String? _groupForContext(String? style, String? language) {
    switch (style) {
      case 'jawa':
        return 'jawa';
      case 'dangdut':
        return 'dangdut';
      case 'kpop':
        return 'kpop';
      case 'hip_hop':
        return language == 'indonesian' ? 'hip_hop_id' : 'hip_hop_en';
      case 'rock':
        return language == 'indonesian' ? 'band_id' : 'rock_en';
    }
    switch (language) {
      case 'korean':
        return 'kpop';
      case 'japanese':
        return 'jpop';
      case 'english':
        return 'pop_en';
      case 'indonesian':
        return 'pop_id';
    }
    return null;
  }

  static final RegExp _collabSplit = RegExp(
    r'\s+(?:ft\.?|feat\.?|featuring|x)\s+|\s*,\s*',
    caseSensitive: false,
  );
  static final RegExp _titleSplit = RegExp(r'\s+[-–—|]\s+');
  static final RegExp _labelChannel = RegExp(
    r'\b(?:production|productions|prod|studio|studios|records?|recordings?|'
    r'music|musik|entertainment|media|network|labels?|tv|distribution|lirik|'
    r'lyrics?|lagu|songs?|hits|group|digital)\b',
  );

  /// Nama channel yang seluruh katanya generik ("Remix Channel", "Lagu Pop
  /// Terbaru") jelas bukan nama artis.
  static const Set<String> _genericChannelWords = <String>{
    'remix', 'dj', 'cover', 'karaoke', 'playlist', 'mix', 'nonstop',
    'terbaru', 'populer', 'viral', 'trending', 'pop', 'indonesia', 'lirik',
    'lyrics', 'lyric', 'lagu', 'musik', 'music', 'tv', 'video', 'audio',
  };

  static bool _isGenericChannel(String channelKey) => channelKey
      .split(' ')
      .where((word) => word.isNotEmpty)
      .every(_genericChannelWords.contains);

  static String _firstArtist(String raw) {
    final parts = raw.split(_collabSplit);
    return parts.isEmpty ? raw.trim() : parts.first.trim();
  }

  /// Artis utama lagu. Judul YouTube bisa "Artis - Judul" atau "Judul - Artis",
  /// dan channel bisa berupa label/pengunggah ulang, jadi beberapa sumber
  /// dicek berurutan dari yang paling dapat diandalkan.
  static String _seedArtistFor(YoutubeSearchResult video) {
    final channel = _firstArtist(_radioSeedArtist(video.channelTitle));
    final channelKey = normalize(channel);
    final title = _radioSeedTitle(video.title);
    final parts = title
        .split(_titleSplit)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    // 1. Nama artis yang sudah dikenal di salah satu sisi judul.
    if (parts.length >= 2) {
      for (final part in parts) {
        final artist = _firstArtist(part);
        if (_isKnownArtist(normalize(artist))) return artist;
      }
    }
    // 2. Channel yang dikenal sebagai artis, atau channel yang bukan label.
    if (channelKey.isNotEmpty) {
      if (_isKnownArtist(channelKey)) return channel;
      if (!_labelChannel.hasMatch(channelKey) && !_isGenericChannel(channelKey)) {
        return channel;
      }
    }
    // 3. Channel label: unggahan label umumnya berformat "Artis - Judul".
    if (parts.length >= 2) {
      final candidate = _firstArtist(parts.first);
      if (candidate.split(' ').length <= 4) return candidate;
    }
    return '';
  }

  static String _composeSeed(String artist, String? style) {
    final label = style == null ? '' : (_seedStyleLabels[style] ?? '');
    final artistKey = normalize(artist);
    final labelKey = normalize(label);
    final alreadyHasLabel =
        labelKey.isEmpty || ' $artistKey '.contains(' $labelKey ');
    return <String>[artist.trim(), if (!alreadyHasLabel) label]
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Seed Radio: artis yang sedang diputar + genre. Bila artis tidak bisa
  /// dikenali, kembali ke seed lama berbasis judul.
  static String recommendationSeedFor(YoutubeSearchResult video) {
    final artist = _seedArtistFor(video);
    if (artist.isNotEmpty) {
      return _composeSeed(artist, styleFromVideo(video));
    }
    return _titleSeedFor(video);
  }

  /// Seed cadangan untuk dipakai bergantian oleh RadioService: beberapa artis
  /// sejenis, lalu pencarian terpopuler untuk genre/bahasa lagu ini.
  static List<String> alternateSeedsFor(
    YoutubeSearchResult video, {
    int maxPeers = 3,
  }) {
    final artist = _seedArtistFor(video);
    final artistKey = normalize(artist);
    final style = styleFromVideo(video);
    final language = languageFromVideo(video);
    final groupKey = _groupOfArtist(artistKey) ?? _groupForContext(style, language);

    final seeds = <String>[];
    final group = groupKey == null ? null : _peerGroups[groupKey];
    if (group != null) {
      final padded = ' $artistKey ';
      final peers = group
          .where((peer) => artistKey.isEmpty || !padded.contains(' $peer '))
          .toList()
        ..shuffle(_random);
      // Satu slot dicadangkan untuk artis terkenal dari kelompok terkait.
      final related = _relatedGroups[groupKey];
      final relatedGroup = related == null || related.isEmpty
          ? null
          : _peerGroups[related[_random.nextInt(related.length)]];
      final sameGroupCount =
          relatedGroup == null ? maxPeers : (maxPeers > 1 ? maxPeers - 1 : 1);
      for (final peer in peers.take(sameGroupCount)) {
        seeds.add(_composeSeed(peer, style));
      }
      if (relatedGroup != null && relatedGroup.isNotEmpty) {
        final crossPeer = relatedGroup[_random.nextInt(relatedGroup.length)];
        // Tanpa label gaya: gaya artis terkait bisa berbeda, dan kecocokan
        // genre tetap disaring oleh MusicStyleMatcher.isCompatible.
        if (!padded.contains(' $crossPeer ')) seeds.add(crossPeer);
      }
    }
    seeds.add(_popularQueryFor(style, language));
    return seeds;
  }

  /// Pencarian "terpopuler" yang tetap spesifik ke genre, sebagai pengganti
  /// chart global yang tidak nyambung.
  static String _popularQueryFor(String? style, String? language) {
    switch (style) {
      case 'jawa':
        return 'lagu jawa terpopuler';
      case 'sunda':
        return 'lagu sunda terpopuler';
      case 'dangdut':
        return 'dangdut koplo terpopuler';
      case 'dj_remix':
        return 'dj remix terpopuler';
      case 'pop_dj':
        return 'pop dj remix terpopuler';
      case 'kpop':
        return 'kpop popular songs';
      case 'religi':
        return 'lagu religi terpopuler';
      case 'melayu':
        return 'lagu melayu terpopuler';
      case 'hip_hop':
        return language == 'indonesian'
            ? 'rap indonesia terpopuler'
            : 'hip hop popular songs';
      case 'rnb':
        return 'r&b popular songs';
      case 'rock':
        return language == 'indonesian'
            ? 'lagu rock indonesia terpopuler'
            : 'rock popular songs';
      case 'indie':
        return 'lagu indie indonesia populer';
      case 'acoustic':
        return 'lagu akustik populer';
      case 'reggae':
        return 'lagu reggae populer';
      case 'ska':
        return 'lagu ska populer';
      case 'jazz':
        return 'jazz popular songs';
      case 'blues':
        return 'blues popular songs';
      case 'country':
        return 'country popular songs';
      case 'instrumental':
        return 'instrumental popular songs';
    }
    switch (language) {
      case 'english':
        return 'english pop hits';
      case 'korean':
        return 'kpop popular songs';
      case 'japanese':
        return 'japanese pop popular songs';
      case 'indonesian':
        return 'lagu pop indonesia terpopuler';
    }
    return 'lagu populer indonesia';
  }

  /// Seed lama: judul + artis + "similar songs". Hanya cadangan.
  static String _titleSeedFor(YoutubeSearchResult video) {
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