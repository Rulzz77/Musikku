import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/youtube_search_result.dart';
import 'disk_cache.dart';
import 'music_style_matcher.dart';

class YoutubeSearchException implements Exception {
  final String message;

  const YoutubeSearchException(this.message);

  @override
  String toString() => message;
}

class _CacheEntry {
  final DateTime time;
  final List<YoutubeSearchResult> results;
  final String? nextPageToken;

  _CacheEntry(this.time, this.results, [this.nextPageToken]);
}

class _ChannelCacheEntry {
  final DateTime time;
  final List<YoutubeChannelSearchResult> results;

  _ChannelCacheEntry(this.time, this.results);
}

/// Satu halaman hasil lagu terbaru yang masih relevan dengan konteks pencarian untuk autoplay.
class RadioPage {
  final List<YoutubeSearchResult> results;
  final String? nextPageToken;

  const RadioPage({
    required this.results,
    this.nextPageToken,
  });
}

class SmartSearchIntent {
  final String originalQuery;
  final String apiQuery;
  final String label;
  final bool latest;
  final bool musicContext;

  const SmartSearchIntent({
    required this.originalQuery,
    required this.apiQuery,
    required this.label,
    required this.latest,
    required this.musicContext,
  });
}

class YoutubeSearchService {
  bool dataSaver = false;
  int dataSaverLevel = 0;

  void setDataSaver(bool value) => setDataSaverMode(value ? 1 : 0);

  void setDataSaverMode(int level) {
    dataSaverLevel = level.clamp(0, 2).toInt();
    dataSaver = dataSaverLevel > 0;
  }

  /// API key TIDAK lagi ditulis di dalam kode.
  ///
  /// Jalankan dengan:
  ///   flutter run --dart-define=YOUTUBE_API_KEY=KUNCI_KAMU
  /// Build rilis:
  ///   flutter build apk --dart-define=YOUTUBE_API_KEY=KUNCI_KAMU
  static const String _apiKey = String.fromEnvironment('YOUTUBE_API_KEY');

  static const String _baseUrl =
      'https://www.googleapis.com/youtube/v3/search';

  // Satu request search = 100 unit dari kuota harian 10.000 unit.
  // Cache membuat pencarian yang sama tidak menghabiskan kuota lagi.
  static const int _cacheLimit = 20;
  static const Duration _cacheTtl = Duration(minutes: 30);
  static const Duration _radioCacheTtl = Duration(minutes: 10);

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, _ChannelCacheEntry> _channelCache = {};

  /// Cache di HP: pencarian yang sama tidak menghabiskan kuota lagi
  /// walaupun aplikasi sudah ditutup dan dibuka ulang.
  static const DiskCache _disk = DiskCache(
    namespace: 'search',
    maxEntries: 20,
    ttl: Duration(hours: 12),
  );

  static List<YoutubeSearchResult> _resultsFromJson(Object? raw) {
    if (raw is! List) {
      return <YoutubeSearchResult>[];
    }

    final list = raw
        .whereType<Map>()
        .map((item) => YoutubeSearchResult.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((video) => video.videoId.isNotEmpty)
        .toList();

    // Cache lama (sebelum ada channelId) bikin foto channel tidak pernah
    // muncul. Anggap cache seperti itu kedaluwarsa supaya diambil ulang.
    if (list.any((v) => !v.isLocal && v.channelId.isEmpty)) {
      return <YoutubeSearchResult>[];
    }
    return list;
  }

  SmartSearchIntent interpretSearch(String query) {
    final original = query.trim();
    final lower = original.toLowerCase();

    final latestWords = <String>[
      'terbaru',
      'terkini',
      'baru',
      'new',
      'latest',
      'rilis',
    ];
    final latest = latestWords.any(lower.contains);

    final musicWords = <String>[
      'dj',
      'pop',
      'rock',
      'dangdut',
      'remix',
      'disco',
      'jazz',
      'hip hop',
      'hiphop',
      'kpop',
      'k-pop',
      'metal',
      'indie',
      'akustik',
      'galau',
      'nostalgia',
      'lagu',
      'musik',
      'song',
    ];
    final musicContext = musicWords.any(lower.contains);

    final era = RegExp(r'\b(19[5-9]0|20(?:0|1|2)0)[sS]?\b').firstMatch(lower);
    final eraLabel = era?.group(1);
    final hasIndonesia = lower.contains('indonesia') ||
        RegExp(r'(^|\s)indo($|\s)').hasMatch(lower);

    final labels = <String>[];
    if (musicContext) labels.add('musik');
    if (latest) labels.add('terbaru');
    if (eraLabel != null) labels.add('${eraLabel}s');
    if (!hasIndonesia && musicContext) labels.add('Indonesia');

    final extra = <String>[];
    if (musicContext && !hasIndonesia) extra.add('Indonesia');

    final apiQuery = [
      original,
      ...extra,
    ].join(' ').trim();

    return SmartSearchIntent(
      originalQuery: original,
      apiQuery: apiQuery,
      label: labels.isEmpty ? 'pencarian biasa' : labels.join(' • '),
      latest: latest,
      musicContext: musicContext,
    );
  }

  String describeSearch(String query) => interpretSearch(query).label;

  Future<List<YoutubeSearchResult>> search(
    String query, {
    String filter = 'music',
  }) async {
    final keyword = query.trim();

    if (keyword.isEmpty) {
      return [];
    }

    if (_apiKey.isEmpty) {
      throw const YoutubeSearchException(
        'API key YouTube belum diatur. Jalankan aplikasi dengan '
        '--dart-define=YOUTUBE_API_KEY=KUNCI_KAMU',
      );
    }

    final intent = interpretSearch(keyword);
    // V2: hasil cache lama belum membawa durasi.
    final safeFilter = switch (filter) {
      'music' => 'music',
      _ => 'music',
    };
    final cacheKey = 'smartV5|${intent.apiQuery.toLowerCase()}|${intent.latest ? 'date' : 'relevance'}|$safeFilter';
    final cached = _cache[cacheKey];

    if (cached != null &&
        DateTime.now().difference(cached.time) < _cacheTtl) {
      return cached.results;
    }

    final diskResults = _resultsFromJson(await _disk.get('q|$cacheKey'));

    if (diskResults.isNotEmpty) {
      _cache[cacheKey] = _CacheEntry(DateTime.now(), diskResults);
      return diskResults;
    }

    final params = <String, String>{
      'part': 'snippet',
      'q': intent.apiQuery,
      'type': 'video',
      'maxResults': dataSaverLevel >= 2 ? '6' : (dataSaverLevel == 1 ? '10' : '16'),
      'relevanceLanguage': 'id',
      'key': _apiKey,
      if (safeFilter == 'live') 'eventType': 'live',
      if (safeFilter == 'music') 'videoCategoryId': '10',
    };

    if (intent.latest) {
      params['order'] = 'date';
    }

    // MusikKu mode audio-only: katalog dan pencarian selalu dibatasi ke
    // kategori Musik. Tidak memakai filter embeddable karena kita tidak
    // menampilkan player video tertanam.
    if (intent.musicContext || safeFilter == 'music') {
      params['regionCode'] = 'ID';
      params['videoCategoryId'] = '10';
    }

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);

    final response = await _getWithRetry(uri);

    if (response.statusCode != 200) {
      throw YoutubeSearchException(_errorMessage(response));
    }

    final data = jsonDecode(response.body);
    final items = data is Map ? data['items'] : null;

    if (items is! List) {
      return [];
    }

    var results = <YoutubeSearchResult>[];

    for (final item in items) {
      if (item is! Map) {
        continue;
      }

      final id = item['id'];
      final snippet = item['snippet'];

      if (id is! Map || snippet is! Map) {
        continue;
      }

      final videoId = id['videoId']?.toString() ?? '';

      if (videoId.isEmpty) {
        continue;
      }

      results.add(
        YoutubeSearchResult(
          videoId: videoId,
          title: _decodeHtml(snippet['title']?.toString() ?? 'Tanpa judul'),
          channelTitle: _decodeHtml(
            snippet['channelTitle']?.toString() ?? 'Unknown',
          ),
          thumbnailUrl: _pickThumbnail(snippet['thumbnails']),
          publishedAt: DateTime.tryParse(snippet['publishedAt']?.toString() ?? ''),
          channelId: snippet['channelId']?.toString() ?? '',
          categoryId: snippet['categoryId']?.toString() ?? '',
        ),
      );
    }

    // Lengkapi durasi, jumlah tonton, dan status live (1 unit kuota).
    results = await _withDetails(results);
    // Audio-only catalog: omit active/upcoming broadcasts and known Shorts.
    // These are frequent causes of unavailable/unstable direct audio streams
    // and should not appear as normal songs in the queue.
    results = results.where((video) {
      if (video.isLive || video.isUpcoming) return false;
      final seconds = video.durationSeconds;
      if (seconds != null && seconds <= 60) return false;
      return isMusicCatalogItem(video);
    }).toList(growable: false);

    _cache[cacheKey] = _CacheEntry(DateTime.now(), results);

    if (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }

    if (results.isNotEmpty) {
      unawaited(_disk.put(
        'q|$cacheKey',
        results.map((video) => video.toJson()).toList(),
      ));
    }

    return results;
  }

  Future<List<YoutubeChannelSearchResult>> searchChannels(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty || _apiKey.isEmpty) return const [];

    final cacheKey = 'channel|${keyword.toLowerCase()}';
    final cached = _channelCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.time) < _cacheTtl) {
      return cached.results;
    }

    final params = <String, String>{
      'part': 'snippet',
      'q': keyword,
      'type': 'channel',
      'maxResults': '8',
      'relevanceLanguage': 'id',
      'regionCode': 'ID',
      'key': _apiKey,
    };

    final uri = Uri.parse(_baseUrl).replace(queryParameters: params);
    final response = await _getWithRetry(uri, timeout: const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw YoutubeSearchException(_errorMessage(response));
    }

    final data = jsonDecode(response.body);
    final items = data is Map ? data['items'] : null;
    if (items is! List) return const [];

    final channels = <YoutubeChannelSearchResult>[];
    for (final item in items) {
      if (item is! Map) continue;
      final id = item['id'];
      final snippet = item['snippet'];
      if (id is! Map || snippet is! Map) continue;

      final channelId = id['channelId']?.toString() ?? '';
      if (channelId.isEmpty) continue;

      channels.add(
        YoutubeChannelSearchResult(
          channelId: channelId,
          title: _decodeHtml(snippet['title']?.toString() ?? 'Channel'),
          description: _decodeHtml(snippet['description']?.toString() ?? ''),
          thumbnailUrl: _pickThumbnail(snippet['thumbnails']),
        ),
      );
    }

    _channelCache[cacheKey] = _ChannelCacheEntry(DateTime.now(), channels);
    if (_channelCache.length > _cacheLimit) {
      _channelCache.remove(_channelCache.keys.first);
    }
    return channels;
  }

  // ==========================================================
  // AUTOPLAY / RADIO
  // ==========================================================
  //
  // Dipakai untuk tombol Next / auto-next saat lagu berasal dari pencarian.
  // Bukan melanjutkan judul video yang sedang diputar. Radio tetap memakai
  // kata kunci pencarian user, lalu mencari upload TERBARU yang masih berada
  // di kategori Musik dan konteks Indonesia. Contoh: cari "dj" -> video DJ terbaru;
  // cari "pop" -> video pop terbaru; cari "lagu jadul" -> upload terbaru yang
  // masih memakai konteks "lagu jadul".
  //
  // 1 halaman search = 100 unit kuota (+1 unit statistik view dan +1 unit
  // cek durasi untuk radio normal), sehingga hasilnya sengaja di-cache.

  // Shorts bisa sampai 3 menit, jadi batas bawah durasi saja tidak cukup;
  // pengecekan URL /shorts/ (lihat isShortVideo) yang jadi penentu utama.
  static const int _radioMinSeconds = 61;
  static const int _radioMaxSeconds = 30 * 60;

  Future<RadioPage> searchLatest(
    String query, {
    String? pageToken,
  }) async {
    final keyword = query.trim();

    if (keyword.isEmpty) {
      return const RadioPage(results: []);
    }

    if (_apiKey.isEmpty) {
      throw const YoutubeSearchException(
        'API key YouTube belum diatur. Jalankan aplikasi dengan '
        '--dart-define=YOUTUBE_API_KEY=KUNCI_KAMU',
      );
    }

    final cacheKey = 'radioPopularV36|${keyword.toLowerCase()}|${pageToken ?? ''}';
    final cached = _cache[cacheKey];

    if (cached != null &&
        DateTime.now().difference(cached.time) < _radioCacheTtl) {
      final filteredCached = await removeShorts(
        _filterShortFormCandidates(_filterNonMusicCandidates(_filterAiMusicCandidates(cached.results))),
      );
      if (filteredCached.isNotEmpty) {
        return RadioPage(
          results: _rankRadio(filteredCached),
          nextPageToken: cached.nextPageToken,
        );
      }
    }

    final diskHit = await _disk.get(
      cacheKey,
      maxAge: _radioCacheTtl,
    );

    if (diskHit is Map) {
      final diskResults = _resultsFromJson(diskHit['results']);
      final diskToken = diskHit['next']?.toString();

      if (diskResults.isNotEmpty) {
        final enriched = await _ensureViewCounts(diskResults);
        final filtered = await removeShorts(
          _filterShortFormCandidates(_filterNonMusicCandidates(_filterAiMusicCandidates(enriched))),
        );
        final ranked = _rankRadio(filtered);
        if (ranked.isNotEmpty) {
          _cache[cacheKey] = _CacheEntry(DateTime.now(), ranked, diskToken);
          return RadioPage(results: ranked, nextPageToken: diskToken);
        }
      }
    }

    final normalized = keyword.toLowerCase();
    final hasIndonesia = normalized.contains('indonesia') ||
        RegExp(r'(^|\s)indo($|\s)').hasMatch(normalized);

    // Pertahankan konteks asli pencarian. Jangan tambahkan "populer" atau
    // kata yang bisa menggeser genre. Cukup arahkan ke konteks Indonesia bila
    // user belum menyebutkannya. Urutan hasil ditentukan oleh upload terbaru.
    final lowerKeyword = keyword.toLowerCase();
    final alreadyMusicWord = RegExp(
      r'\b(?:lagu|musik|music|song|audio|remix|dj|dangdut|pop|rock|jazz|hip\s*hop|kpop|metal|indie|akustik|nostalgia|karaoke|cover|mix|album)\b',
      caseSensitive: false,
    ).hasMatch(lowerKeyword);

    // Arahkan radio ke konten lagu, bukan sekadar video yang kebetulan
    // membahas artis/judul tersebut. Tetap pertahankan konteks asli dan
    // urutan upload terbaru.
    final radioKeyword = [
      keyword,
      if (!alreadyMusicWord) 'lagu',
      if (!hasIndonesia) 'Indonesia',
    ].join(' ');

    final params = <String, String>{
      'part': 'snippet',
      'q': radioKeyword,
      'type': 'video',
      'maxResults': dataSaverLevel >= 2 ? '12' : (dataSaverLevel == 1 ? '20' : '50'),
      'order': 'viewCount',
      'regionCode': 'ID',
      'relevanceLanguage': 'id',
      'videoCategoryId': '10', // Musik
      'key': _apiKey,
    };

    if (pageToken != null && pageToken.isNotEmpty) {
      params['pageToken'] = pageToken;
    }

    final data = await _getJson(
      Uri.parse(_baseUrl).replace(queryParameters: params),
    );

    final items = data['items'];
    var results = items is List
        ? _parseItems(items)
        : <YoutubeSearchResult>[];

    // Tambahkan view count untuk sinyal kualitas ringan; radio tetap tidak
    // diurutkan murni berdasarkan view. Urutan akhir menggabungkan kebaruan
    // dan engagement agar hasil terasa lebih enak tanpa kehilangan konteks genre.
    results = await _ensureViewCounts(results);

    // Kalau user memang mencari mix / nonstop, jangan buang video panjang.
    final lower = keyword.toLowerCase();
    final wantsLong = lower.contains('mix') ||
        lower.contains('nonstop') ||
        lower.contains('non stop') ||
        lower.contains('album');

    if (!wantsLong) {
      // Filter durasi utama: pilih track yang cukup panjang untuk didengar,
      // tetapi jangan sampai radio mati hanya karena halaman terbaru penuh
      // upload pendek. Kalau hasil utama kosong, gunakan fallback bertahap.
      final originalResults = results;
      results = await _filterByDuration(
        results,
        minSeconds: _radioMinSeconds,
        maxSeconds: _radioMaxSeconds,
      );

      if (results.isEmpty && originalResults.isNotEmpty) {
        results = await _filterByDuration(
          originalResults,
          minSeconds: 61,
          maxSeconds: 60 * 60,
        );
      }

      if (results.isEmpty) {
        // Jangan buang seluruh radio hanya karena endpoint duration sedang
        // gagal atau upload terbaru tidak punya metadata durasi lengkap.
        results = originalResults;
      }
    }

    // YouTube Shorts tidak punya flag eksplisit di Search API. Gunakan
    // penyaring berlapis: query exclusion + heuristik judul/channel.
    results = _filterShortFormCandidates(results);

    // Penentu utama: cek langsung ke YouTube apakah video ini Short.
    results = await removeShorts(results);
    results = _filterNonMusicCandidates(results);
    results = _filterAiMusicCandidates(results);

    // Prefer popular songs strongly, while keeping a little freshness so the
    // radio does not get stuck on an old catalog item forever.
    results = _rankRadio(results);

    // Kalau seed terlalu spesifik ke sumber AI / channel non-musik sehingga
    // semua kandidat tersaring, gunakan pool musik populer Indonesia sebagai
    // fallback. Ini lebih baik daripada memutar ulang video AI atau berhenti.
    if (results.isEmpty &&
        !keyword.toLowerCase().contains('lagu indonesia') &&
        MusicStyleMatcher.styleFromText(keyword) == null) {
      final fallback = await _searchPopularMusicFallback();
      if (fallback.isNotEmpty) {
        results = fallback;
      }
    }

    final token = data['nextPageToken']?.toString();

    _cache[cacheKey] = _CacheEntry(DateTime.now(), results, token);

    if (results.isNotEmpty) {
      unawaited(_disk.put(cacheKey, {
        'results': results.map((video) => video.toJson()).toList(),
        'next': token,
      }));
    }

    if (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }

    return RadioPage(results: results, nextPageToken: token);
  }

  Future<List<YoutubeSearchResult>> _searchPopularMusicFallback() async {
    final cacheKey = 'radioPopularFallbackV36';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.time) < _radioCacheTtl &&
        cached.results.isNotEmpty) {
      return cached.results;
    }

    final params = <String, String>{
      'part': 'snippet',
      'q': 'lagu Indonesia',
      'type': 'video',
      'maxResults': dataSaverLevel >= 2 ? '12' : (dataSaverLevel == 1 ? '20' : '50'),
      'order': 'viewCount',
      'regionCode': 'ID',
      'relevanceLanguage': 'id',
      'videoCategoryId': '10',
      'key': _apiKey,
    };

    final data = await _getJson(
      Uri.parse(_baseUrl).replace(queryParameters: params),
    );

    final items = data['items'];
    if (items is! List) return const <YoutubeSearchResult>[];

    var results = _parseItems(items);
    results = await _ensureViewCounts(results);
    results = await _filterByDuration(
      results,
      minSeconds: _radioMinSeconds,
      maxSeconds: _radioMaxSeconds,
    );
    results = _filterShortFormCandidates(results);
    results = await removeShorts(results);
    results = _filterNonMusicCandidates(results);
    results = _filterAiMusicCandidates(results);
    results = _rankRadio(results);

    _cache[cacheKey] = _CacheEntry(DateTime.now(), results);
    return results;
  }

  static const Duration _feedTtl = Duration(minutes: 20);

  /// Musik yang sedang trending. Kategori 10 dipakai sebagai default agar
  /// beranda tidak menampilkan upload dari kategori video lain.
  /// Memakai videos.list chart=mostPopular: hanya 1 unit kuota per panggilan
  /// dan TIDAK perlu login.
  Future<List<YoutubeSearchResult>> mostPopular({
    String? categoryId,
    int maxResults = 30,
    bool force = false,
  }) async {
    if (_apiKey.isEmpty) {
      throw const YoutubeSearchException(
        'API key YouTube belum diatur. Jalankan aplikasi dengan '
        '--dart-define=YOUTUBE_API_KEY=KUNCI_KAMU',
      );
    }

    final musicCategoryId = categoryId == null || categoryId.trim().isEmpty
        ? '10'
        : categoryId.trim();
    final cacheKey = 'mostPopularMusicV2|$musicCategoryId';
    if (!force) {
      final cached = _cache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.time) < _feedTtl &&
          cached.results.isNotEmpty) {
        return cached.results.take(maxResults).toList(growable: false);
      }
      final diskHit = await _disk.get(cacheKey, maxAge: _feedTtl);
      final fromDisk = _resultsFromJson(diskHit);
      if (fromDisk.isNotEmpty) {
        _cache[cacheKey] = _CacheEntry(DateTime.now(), fromDisk);
        return fromDisk.take(maxResults).toList(growable: false);
      }
    }

    final params = <String, String>{
      'part': 'snippet,statistics,contentDetails,liveStreamingDetails',
      'chart': 'mostPopular',
      'regionCode': 'ID',
      // Ambil lebih banyak dari yang ditampilkan karena Shorts disaring.
      'maxResults': '50',
      'videoCategoryId': musicCategoryId,
      'key': _apiKey,
    };

    final data = await _getJson(
      Uri.parse('https://www.googleapis.com/youtube/v3/videos')
          .replace(queryParameters: params),
    );
    final items = data['items'];
    final parsed = _parseVideoResources(items is List ? items : const []);
    final results = parsed.where(isMusicCatalogItem).toList(growable: false);

    if (results.isNotEmpty) {
      _cache[cacheKey] = _CacheEntry(DateTime.now(), results);
      unawaited(_disk.put(cacheKey, results.map((v) => v.toJson()).toList()));
    }
    return results.take(maxResults).toList(growable: false);
  }

  /// Lagu musik populer yang baru diunggah (beberapa hari terakhir).
  Future<List<YoutubeSearchResult>> recentPopular({
    int maxResults = 30,
    bool force = false,
  }) async {
    if (_apiKey.isEmpty) {
      throw const YoutubeSearchException(
        'API key YouTube belum diatur. Jalankan aplikasi dengan '
        '--dart-define=YOUTUBE_API_KEY=KUNCI_KAMU',
      );
    }

    const cacheKey = 'recentMusicV3';
    if (!force) {
      final cached = _cache[cacheKey];
      if (cached != null &&
          DateTime.now().difference(cached.time) < _feedTtl &&
          cached.results.isNotEmpty) {
        return cached.results.take(maxResults).toList(growable: false);
      }
      final diskHit = await _disk.get(cacheKey, maxAge: _feedTtl);
      final fromDisk = _resultsFromJson(diskHit);
      if (fromDisk.isNotEmpty) {
        _cache[cacheKey] = _CacheEntry(DateTime.now(), fromDisk);
        return fromDisk.take(maxResults).toList(growable: false);
      }
    }

    final since = DateTime.now().toUtc().subtract(const Duration(days: 3));
    final searchData = await _getJson(
      Uri.parse(_baseUrl).replace(queryParameters: {
        'part': 'snippet',
        'type': 'video',
        'order': 'viewCount',
        'publishedAfter': '${since.toIso8601String().split('.').first}Z',
        'regionCode': 'ID',
        'relevanceLanguage': 'id',
        'videoCategoryId': '10',
        'maxResults': '50',
        'key': _apiKey,
      }),
    );
    final found = searchData['items'];
    final ids = <String>[];
    if (found is List) {
      for (final item in found) {
        if (item is! Map) continue;
        final id = item['id'];
        final videoId = id is Map ? id['videoId']?.toString() ?? '' : '';
        if (videoId.isNotEmpty) ids.add(videoId);
      }
    }
    if (ids.isEmpty) return const [];

    final detailData = await _getJson(
      Uri.parse('https://www.googleapis.com/youtube/v3/videos').replace(
        queryParameters: {
          'part': 'snippet,statistics,contentDetails,liveStreamingDetails',
          'id': ids.join(','),
          'key': _apiKey,
        },
      ),
    );
    final items = detailData['items'];
    final parsed = _parseVideoResources(items is List ? items : const []);
    final results = parsed.where(isMusicCatalogItem).toList(growable: false)
      ..sort((a, b) => (b.viewCount ?? 0).compareTo(a.viewCount ?? 0));

    if (results.isNotEmpty) {
      _cache[cacheKey] = _CacheEntry(DateTime.now(), results);
      unawaited(_disk.put(cacheKey, results.map((v) => v.toJson()).toList()));
    }
    return results.take(maxResults).toList(growable: false);
  }

  /// Melengkapi hasil pencarian dengan durasi, jumlah tonton, dan status live
  /// lewat satu panggilan videos.list (1 unit per 50 video). Kalau gagal,
  /// daftar asli dikembalikan apa adanya.
  Future<List<YoutubeSearchResult>> _withDetails(
    List<YoutubeSearchResult> videos,
  ) async {
    if (videos.isEmpty || _apiKey.isEmpty) return videos;
    try {
      final merged = <String, YoutubeSearchResult>{};
      for (var i = 0; i < videos.length; i += 50) {
        final chunk = videos.sublist(i, math.min(i + 50, videos.length));
        final data = await _getJson(
          Uri.parse('https://www.googleapis.com/youtube/v3/videos').replace(
            queryParameters: {
              'part': 'snippet,statistics,contentDetails,liveStreamingDetails',
              'id': chunk.map((v) => v.videoId).join(','),
              'key': _apiKey,
            },
          ),
        );
        final items = data['items'];
        if (items is! List) continue;
        for (final item in items) {
          if (item is! Map) continue;
          final detail = YoutubeSearchResult.fromVideoResource(
            Map<String, dynamic>.from(item),
            pickThumbnail: _pickThumbnail,
            decode: _decodeHtml,
          );
          if (detail != null) merged[detail.videoId] = detail;
        }
      }
      return videos.map((video) {
        final d = merged[video.videoId];
        if (d == null) return video;
        return video.copyWith(
          viewCount: d.viewCount,
          durationSeconds: d.durationSeconds,
          liveStatus: d.liveStatus,
          concurrentViewers: d.concurrentViewers,
          liveStartTime: d.liveStartTime,
          channelId: d.channelId.isNotEmpty ? d.channelId : video.channelId,
          categoryId: d.categoryId.isNotEmpty ? d.categoryId : video.categoryId,
        );
      }).toList(growable: false);
    } catch (_) {
      return videos;
    }
  }

  /// Resource videos.list -> model, tanpa Shorts (<= 60 detik).
  List<YoutubeSearchResult> _parseVideoResources(List items) {
    final out = <YoutubeSearchResult>[];
    for (final item in items) {
      if (item is! Map) continue;
      final video = YoutubeSearchResult.fromVideoResource(
        Map<String, dynamic>.from(item),
        pickThumbnail: _pickThumbnail,
        decode: _decodeHtml,
      );
      if (video == null) continue;
      final seconds = video.durationSeconds;
      if (!video.isLive && !video.isUpcoming && seconds != null && seconds <= 60) {
        continue;
      }
      out.add(video);
    }
    return out;
  }

  /// Alias untuk source lama. Semua radio baru memakai [searchLatest].
  Future<RadioPage> searchPopular(
    String query, {
    String? pageToken,
  }) => searchLatest(query, pageToken: pageToken);

  Future<http.Response> _getWithRetry(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http.get(uri).timeout(timeout);

        if (response.statusCode != 429) {
          return response;
        }

        // 429 dari search.list bisa bersifat sementara. Jangan melakukan
        // retry agresif; hormati Retry-After bila server mengirimkannya.
        final reason = _errorReason(response);
        final quotaLimited = reason == 'quotaExceeded' ||
            reason == 'dailyLimitExceeded';
        if (quotaLimited || attempt == 2) {
          return response;
        }

        final retryAfterSeconds =
            int.tryParse(response.headers['retry-after'] ?? '');
        final waitMs = retryAfterSeconds != null
            ? (retryAfterSeconds * 1000).clamp(500, 8000)
            : (750 * (1 << attempt)).clamp(750, 6000);

        await Future<void>.delayed(Duration(milliseconds: waitMs));
        continue;
      } catch (e) {
        lastError = e;
        if (attempt == 2) break;
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (attempt + 1)),
        );
      }
    }

    throw YoutubeSearchException(
      lastError == null
          ? 'Tidak bisa terhubung ke internet. Coba lagi.'
          : 'Tidak bisa terhubung ke internet. Coba lagi.',
    );
  }

  Future<Map> _getJson(Uri uri) async {
    final response = await _getWithRetry(uri);

    if (response.statusCode != 200) {
      throw YoutubeSearchException(_errorMessage(response));
    }

    final decoded = jsonDecode(response.body);

    return decoded is Map ? decoded : <String, dynamic>{};
  }

  List<YoutubeSearchResult> _parseItems(List items) {
    final results = <YoutubeSearchResult>[];

    for (final item in items) {
      if (item is! Map) {
        continue;
      }

      final id = item['id'];
      final snippet = item['snippet'];

      if (id is! Map || snippet is! Map) {
        continue;
      }

      final videoId = id['videoId']?.toString() ?? '';

      if (videoId.isEmpty) {
        continue;
      }

      results.add(
        YoutubeSearchResult(
          videoId: videoId,
          title: _decodeHtml(snippet['title']?.toString() ?? 'Tanpa judul'),
          channelTitle: _decodeHtml(
            snippet['channelTitle']?.toString() ?? 'Unknown',
          ),
          thumbnailUrl: _pickThumbnail(snippet['thumbnails']),
          publishedAt: DateTime.tryParse(snippet['publishedAt']?.toString() ?? ''),
          channelId: snippet['channelId']?.toString() ?? '',
        ),
      );
    }

    return results;
  }

  Future<List<YoutubeSearchResult>> _ensureViewCounts(
    List<YoutubeSearchResult> videos,
  ) async {
    if (videos.isEmpty) return videos;

    final missing = videos.where((v) => v.viewCount == null).toList();
    if (missing.isEmpty || dataSaverLevel > 0) return videos;

    try {
      final data = await _getJson(
        Uri.parse('https://www.googleapis.com/youtube/v3/videos').replace(
          queryParameters: {
            'part': 'statistics',
            'id': missing.map((v) => v.videoId).join(','),
            'key': _apiKey,
          },
        ),
      );

      final items = data['items'];
      if (items is! List) return videos;

      final views = <String, int>{};
      for (final item in items) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        final stats = item['statistics'];
        final raw = stats is Map ? stats['viewCount']?.toString() : null;
        final count = raw == null ? null : int.tryParse(raw);
        if (id.isNotEmpty && count != null) views[id] = count;
      }

      return videos.map((video) {
        final count = views[video.videoId];
        if (count == null && video.viewCount != null) return video;
        return video.copyWith(viewCount: count ?? video.viewCount);
      }).toList();
    } catch (_) {
      return videos;
    }
  }

  List<YoutubeSearchResult> _rankRadio(List<YoutubeSearchResult> videos) {
    final now = DateTime.now();

    double score(YoutubeSearchResult video) {
      final published = video.publishedAt;
      final ageHours = published == null
          ? 240.0
          : math.max(0.0, now.difference(published).inMinutes / 60.0);

      // Popularitas menjadi sinyal utama. YouTube search.list dengan
      // order=viewCount juga sudah mengurutkan dari view terbanyak; skor ini
      // hanya menjaga sedikit bias ke konten yang relatif baru.
      final freshness = 1.0 - (ageHours / (24.0 * 90.0)).clamp(0.0, 1.0);
      final views = math.max(0, video.viewCount ?? 0);
      final popularity =
          (math.log(views + 1) / math.log(100000000)).clamp(0.0, 1.0);

      var quality = 0.0;
      final text = '${video.title} ${video.channelTitle}'.toLowerCase();
      if (RegExp(r'\b(?:official|vevo|topic|official\s+artist)\b').hasMatch(text)) {
        quality += 0.05;
      }
      if (RegExp(r'\b(?:cover|karaoke|instrumental|slowed|sped\s*up|nightcore|8d)\b')
          .hasMatch(text)) {
        quality -= 0.06;
      }

      return popularity * 0.78 + freshness * 0.17 + quality * 0.05;
    }

    final sorted = [...videos]
      ..sort((a, b) => score(b).compareTo(score(a)));

    // Hindari satu channel mendominasi radio awal.
    final result = <YoutubeSearchResult>[];
    final channelCount = <String, int>{};
    final deferred = <YoutubeSearchResult>[];

    for (final video in sorted) {
      final key = video.channelTitle.trim().toLowerCase();
      final count = channelCount[key] ?? 0;
      if (count < 2) {
        result.add(video);
        channelCount[key] = count + 1;
      } else {
        deferred.add(video);
      }
    }

    result.addAll(deferred);
    return result;
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
      'pod',
    ];

    for (final word in blocked) {
      if (combined.contains(word)) {
        return true;
      }
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

  List<YoutubeSearchResult> _filterAiMusicCandidates(
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

  // ============================================================
  // DETEKSI YOUTUBE SHORTS (akurat)
  // ============================================================
  //
  // youtube.com/shorts/<id> membalas 200 kalau video itu Short, dan
  // redirect (3xx) ke /watch kalau video biasa. Ini jauh lebih akurat
  // daripada menebak dari judul atau durasi (Shorts bisa sampai 3 menit).

  static final Map<String, bool> _shortCache = <String, bool>{};

  Future<bool> isShortVideo(String videoId) async {
    final id = videoId.trim();

    if (id.isEmpty) {
      return false;
    }

    final known = _shortCache[id];

    if (known != null) {
      return known;
    }

    final client = http.Client();

    try {
      final request = http.Request(
        'HEAD',
        Uri.parse('https://www.youtube.com/shorts/$id'),
      )
        ..followRedirects = false
        ..headers['User-Agent'] =
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36';

      final response =
          await client.send(request).timeout(const Duration(seconds: 4));

      final isShort = response.statusCode == 200;

      _shortCache[id] = isShort;

      if (_shortCache.length > 2000) {
        _shortCache.remove(_shortCache.keys.first);
      }

      return isShort;
    } catch (_) {
      // Fail closed: kalau status Shorts tidak bisa diverifikasi, jangan
      // tandai sebagai video biasa dan simpan hasil negatif ke cache.
      // Pemanggil radio akan melewati kandidat ini lalu mencoba kandidat lain.
      return true;
    } finally {
      client.close();
    }
  }

  /// Buang semua Shorts dari [videos]. Maksimum 12 URL diverifikasi paralel.
  ///
  /// Shorts yang jelas dari judul dibuang langsung. Video berdurasi lebih dari
  /// 3 menit tidak perlu melakukan request jaringan karena batas Shorts saat ini
  /// adalah 3 menit; video berdurasi <= 3 menit (atau durasinya belum diketahui)
  /// diverifikasi melalui URL Shorts. Ini mengurangi request saat memuat feed
  /// subscription tanpa meloloskan Shorts pendek yang judulnya tidak bertanda.
  Future<List<YoutubeSearchResult>> removeShorts(
    List<YoutubeSearchResult> videos,
  ) async {
    if (videos.isEmpty) {
      return videos;
    }

    final flags = List<bool>.filled(videos.length, false);
    final candidates = <int>[];

    for (var i = 0; i < videos.length; i++) {
      final video = videos[i];
      if (isLikelyShortForm(video)) {
        flags[i] = true;
        continue;
      }
      final duration = video.durationSeconds;
      if (duration != null && duration > 180) {
        // Lebih dari 3 menit tidak bisa diklasifikasikan sebagai Shorts.
        continue;
      }
      candidates.add(i);
    }

    for (var start = 0; start < candidates.length; start += 12) {
      final end = math.min(start + 12, candidates.length);
      await Future.wait([
        for (var position = start; position < end; position++)
          (() async {
            final index = candidates[position];
            flags[index] = await isShortVideo(videos[index].videoId);
          })(),
      ]);
    }

    return [
      for (var i = 0; i < videos.length; i++)
        if (!flags[i]) videos[i],
    ];
  }


  List<YoutubeSearchResult> _filterNonMusicCandidates(
    List<YoutubeSearchResult> videos,
  ) {
    return videos.where(isMusicCandidate).toList();
  }

  List<YoutubeSearchResult> _filterShortFormCandidates(
    List<YoutubeSearchResult> videos,
  ) {
    return videos.where((video) => !isLikelyShortForm(video)).toList();
  }

  /// Buang live stream, klip terlalu pendek, dan mix berjam-jam supaya
  /// "lagu berikutnya" benar-benar satu lagu. videos.list = 1 unit kuota.
  Future<List<YoutubeSearchResult>> _filterByDuration(
    List<YoutubeSearchResult> videos, {
    int minSeconds = _radioMinSeconds,
    int maxSeconds = _radioMaxSeconds,
  }) async {
    if (videos.isEmpty) {
      return videos;
    }

    try {
      final data = await _getJson(
        Uri.parse('https://www.googleapis.com/youtube/v3/videos').replace(
          queryParameters: {
            'part': 'contentDetails',
            'id': videos.map((video) => video.videoId).join(','),
            'key': _apiKey,
          },
        ),
      );

      final items = data['items'];

      if (items is! List) {
        return videos;
      }

      final seconds = <String, int>{};

      for (final item in items) {
        if (item is! Map) {
          continue;
        }

        final id = item['id']?.toString() ?? '';
        final details = item['contentDetails'];
        final raw = details is Map ? details['duration']?.toString() : null;

        if (id.isEmpty || raw == null) {
          continue;
        }

        final match = RegExp(r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$')
            .firstMatch(raw);

        if (match == null) {
          continue; // live / upcoming
        }

        seconds[id] = (int.tryParse(match.group(1) ?? '0') ?? 0) * 3600 +
            (int.tryParse(match.group(2) ?? '0') ?? 0) * 60 +
            (int.tryParse(match.group(3) ?? '0') ?? 0);
      }

      return videos.where((video) {
        final length = seconds[video.videoId];

        return length != null &&
            length >= minSeconds &&
            length <= maxSeconds;
      }).toList();
    } catch (_) {
      // Gagal cek durasi tidak boleh menggagalkan autoplay.
      return videos;
    }
  }

  String _pickThumbnail(dynamic thumbnails) {
    if (thumbnails is! Map) {
      return '';
    }

    for (final size in const ['high', 'medium', 'default']) {
      final image = thumbnails[size];

      if (image is Map) {
        final url = image['url']?.toString() ?? '';

        if (url.isNotEmpty) {
          return url;
        }
      }
    }

    return '';
  }

  String _errorReason(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final error = body is Map && body['error'] is Map
          ? body['error'] as Map
          : null;
      final errors = error?['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        return (errors.first as Map)['reason']?.toString() ?? '';
      }
      return error?['status']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _errorMessage(http.Response response) {
    final reason = _errorReason(response);

    if (reason == 'quotaExceeded' || reason == 'dailyLimitExceeded') {
      return 'Kuota YouTube API hari ini sudah habis. Coba lagi besok.';
    }

    if (response.statusCode == 429) {
      return 'YouTube sedang membatasi permintaan sementara. Coba lagi beberapa saat.';
    }

    if (reason == 'keyInvalid' || reason == 'forbidden') {
      return 'API key YouTube tidak valid atau dibatasi. Cek pengaturan key.';
    }

    return 'Gagal mencari lagu (kode ${response.statusCode}).';
  }

  /// YouTube API mengirim judul dengan HTML entity (&amp; &#39; &quot;).
  static String _decodeHtml(String input) {
    var text = input.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) {
        final code = int.tryParse(match.group(1)!);

        if (code == null || code > 0x10FFFF) {
          return match.group(0)!;
        }

        return String.fromCharCode(code);
      },
    );

    text = text.replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (match) {
        final code = int.tryParse(match.group(1)!, radix: 16);

        if (code == null || code > 0x10FFFF) {
          return match.group(0)!;
        }

        return String.fromCharCode(code);
      },
    );

    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }
}
