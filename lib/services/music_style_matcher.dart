import '../models/youtube_search_result.dart';

/// Heuristik genre/konteks untuk menjaga radio dan shuffle tetap sejenis.
/// YouTube Data API hanya memberi kategori umum "Music", bukan genre lagu,
/// jadi matcher ini sengaja memakai tag judul/channel yang bisa dikenali.
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

  /// Gaya yang eksplisit di query atau metadata. Urutan penting: "pop Jawa"
  /// harus diperlakukan sebagai Jawa agar radio tidak berpindah ke Pop umum.
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

    if (_matches(text, r'\b(?:hip hop|hiphop|rap|rap indonesia)\b')) {
      return 'hip_hop';
    }

    if (_matches(text, r'\b(?:r&b|rnb|rhythm and blues|soul music)\b')) {
      return 'rnb';
    }

    if (_matches(text, r'\b(?:rock|hard rock|alternative rock|metal|heavy metal|punk rock)\b')) {
      return 'rock';
    }

    if (_matches(text, r'\b(?:reggae|ska)\b')) return 'reggae';
    if (_matches(text, r'\b(?:jazz|smooth jazz|bebop)\b')) return 'jazz';
    if (_matches(text, r'\b(?:blues)\b')) return 'blues';
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

    // Fallback artist hints apply only when the title/channel has no explicit
    // genre marker above. This avoids classifying a DJ remix as Jawa merely
    // because the original singer is known for Javanese songs.
    if (_containsAny(text, const [
      'denny caknan',
      'ndarboy genk',
      'guyon waton',
      'aftershine',
      'happy asmara',
      'gilga sahid',
      'niken salindry',
      'jihan audy',
      'difarina indra',
      'farel prayoga',
      'woro widowati',
      'hendra kumbara',
      'didi kempot',
    ])) {
      return 'jawa';
    }

    if (_containsAny(text, const [
      'tulus',
      'raisa',
      'rossa',
      'mahalini',
      'tiara andini',
      'rizky febian',
      'judika',
      'afgan',
      'andmesh kamaleng',
      'lyodra',
      'keisya levronka',
      'yura yunita',
      'isyana sarasvati',
      'vidi aldiano',
      'bunga citra lestari',
      'sabrina carpenter',
      'taylor swift',
      'ed sheeran',
      'bruno mars',
    ])) {
      return 'pop';
    }

    if (_containsAny(text, const [
      'nella kharisma',
      'siti badriah',
      'lesti kejora',
      'rhoma irama',
      'elvy sukaesih',
      'tasya rosmala',
      'via vallen',
      'dewi perssik',
      'inul daratista',
      'zaskia gotik',
      'ayu ting ting',
    ])) {
      return 'dangdut';
    }

    if (_containsAny(text, const [
      'blackpink',
      'stray kids',
      'newjeans',
      'seventeen',
      'twice',
      'exo',
      'iu korean',
    ])) {
      return 'kpop';
    }

    return null;
  }

  static String? styleFromVideo(YoutubeSearchResult? video) {
    if (video == null) return null;
    return styleFromText('${video.title} ${video.channelTitle} ${video.album}');
  }

  /// Query eksplisit menang dari inferensi berdasarkan judul lagu.
  static String? styleForContext({
    String query = '',
    YoutubeSearchResult? currentVideo,
  }) {
    final queryStyle = styleFromText(query);
    final currentStyle = styleFromVideo(currentVideo);

    // Query eksplisit adalah pilihan pengguna; jangan menimpanya hanya karena
    // judul track punya label subgenre tambahan (mis. "Pop Jawa").
    return queryStyle ?? currentStyle;
  }

  /// Metadata tanpa tag genre dianggap belum diketahui (bukan otomatis genre
  /// lain). Track yang jelas bertag genre berbeda akan ditahan dari radio.
  static bool isCompatible({
    required YoutubeSearchResult video,
    required String? targetStyle,
  }) {
    if (targetStyle == null) return true;
    final candidateStyle = styleFromVideo(video);
    return candidateStyle == null || candidateStyle == targetStyle;
  }

  /// Kalau ada kandidat yang secara eksplisit satu gaya, gunakan mereka lebih
  /// dulu; kandidat tak berlabel baru dipakai ketika kandidat sejenis habis.
  static List<YoutubeSearchResult> prioritizeStyle(
    Iterable<YoutubeSearchResult> videos,
    String? targetStyle,
  ) {
    final compatible = videos
        .where((video) => isCompatible(video: video, targetStyle: targetStyle))
        .toList();

    if (targetStyle == null) return compatible;

    final exact = compatible
        .where((video) => styleFromVideo(video) == targetStyle)
        .toList();
    return exact.isNotEmpty
        ? exact
        : compatible.where((video) => styleFromVideo(video) == null).toList();
  }

  static String seedForStyle(String style) => switch (style) {
        'jawa' => 'lagu Jawa Indonesia',
        'sunda' => 'lagu Sunda Indonesia',
        'kpop' => 'K-pop songs',
        'dj_remix' => 'DJ remix Indonesia',
        'religi' => 'lagu religi Indonesia',
        'dangdut' => 'lagu dangdut Indonesia',
        'hip_hop' => 'hip hop Indonesia',
        'rnb' => 'R&B music',
        'rock' => 'lagu rock Indonesia',
        'reggae' => 'lagu reggae Indonesia',
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
