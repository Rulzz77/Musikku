import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

import '../models/youtube_search_result.dart';
import 'disk_cache.dart';
import 'music_style_matcher.dart';
import 'youtube_search_query.dart';
import 'youtube_music_policy.dart';
import 'youtube_search_response_parser.dart';
import 'youtube_search_api_errors.dart';
import 'youtube_api_request_guard.dart';

export 'youtube_search_query.dart' show SmartSearchIntent;

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

class _VideoDetailCacheEntry {
  final DateTime time;
  final YoutubeSearchResult result;

  _VideoDetailCacheEntry(this.time, this.result);
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

  static const YoutubeSearchApiErrors _apiErrors = YoutubeSearchApiErrors();

  // search.list memakai 1 unit per panggilan di bucket terpisah yang defaultnya
  // 100 panggilan/hari. Endpoint data lain memakai bucket umum 10.000 unit/hari.
  // Cache dan deduplikasi mengurangi request berulang; lihat dokumentasi Google.

  static const int _cacheLimit = 40;
  static const Duration _cacheTtl = Duration(hours: 6);
  // Radio kandidat tidak perlu diperbarui setiap beberapa menit. TTL yang lebih
  // panjang mengurangi permintaan halaman yang sama saat lagu berpindah.
  static const Duration _radioCacheTtl = Duration(hours: 6);
  // Feed populer juga stabil; refresh manual yang terlalu cepat memakai cache.
  static const Duration _feedTtl = Duration(hours: 6);
  static const Duration _forcedFeedRefreshFloor = Duration(minutes: 2);

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, _ChannelCacheEntry> _channelCache = {};
  static final Map<String, Future<http.Response>> _inFlightHttp =
      <String, Future<http.Response>>{};

  /// Cache di HP: pencarian yang sama tidak menghabiskan kuota lagi
  /// walaupun aplikasi sudah ditutup dan dibuka ulang.
  static const DiskCache _disk = DiskCache(
    namespace: 'search',
    maxEntries: 80,
    ttl: Duration(hours: 24),
  );

  // Pencarian channel bersifat opsional dan disimpan lintas sesi supaya query
  // yang sama tidak kembali menghabiskan bucket search.list setelah app dibuka ulang.
  static const DiskCache _channelDisk = DiskCache(
    namespace: 'channel_search',
    maxEntries: 30,
    ttl: Duration(hours: 12),
  );

  // Detail metadata for video IDs reused across queries, radio, and the home
  // feed. This cache shares snippets/statistics/durations locally so a new
  // query that returns familiar songs does not need another videos.list call.
  static const Duration _videoDetailTtl = Duration(hours: 24);
  static const DiskCache _videoDetailDisk = DiskCache(
    namespace: 'video_detail',
    maxEntries: 250,
    ttl: _videoDetailTtl,
  );
  static final Map<String, _VideoDetailCacheEntry> _videoDetailCache =
      <String, _VideoDetailCacheEntry>{};
  static Future<void> _videoDetailWriteQueue = Future<void>.value();

  static List<YoutubeSearchResult> _resultsFromJson(Object? raw) =>
      YoutubeSearchResponseParser.resultsFromJson(raw);

  SmartSearchIntent interpretSearch(String query) =>
      YoutubeSearchQueryParser.interpret(query);

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
    // V6: invalidasi cache agar hasil lama melewati filter katalog musik terbaru.
    final safeFilter = switch (filter) {
      'music' => 'music',
      _ => 'music',
    };
    final cacheKey = 'smartV7|${intent.apiQuery.toLowerCase()}|${intent.latest ? 'date' : 'relevance'}|$safeFilter';
    final cached = _cache[cacheKey];

    if (cached != null &&
        DateTime.now().difference(cached.time) < _cacheTtl) {
      return cached.results;
    }

    final diskRaw = await _disk.get('q|$cacheKey');
    final diskResults = _resultsFromJson(diskRaw);
    if (diskRaw is List && (diskRaw.isEmpty || diskResults.isNotEmpty)) {
      _cache[cacheKey] = _CacheEntry(DateTime.now(), diskResults);
      for (final video in diskResults) {
        if (video.durationSeconds != null || video.isLive || video.isUpcoming) {
          _rememberVideoDetail(video);
        }
      }
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
          description: _decodeHtml(snippet['description']?.toString() ?? ''),
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
    // Katalog audio saja: buang siaran aktif, video sangat pendek, Shorts yang
    // terdeteksi dari metadata, dan video pendek yang tidak punya sinyal musik.
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

    // Cache juga hasil kosong: typo atau query yang memang tidak punya hasil
    // tidak boleh menghabiskan search.list lagi setelah aplikasi dibuka ulang.
    unawaited(_disk.put(
      'q|$cacheKey',
      results.map((video) => video.toJson()).toList(),
    ));

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

    final diskHit = await _channelDisk.get('q|$cacheKey');
    if (diskHit is List) {
      final restored = diskHit
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => (item['channelId']?.toString() ?? '').isNotEmpty)
          .map((item) => YoutubeChannelSearchResult(
                channelId: item['channelId'].toString(),
                title: item['title']?.toString() ?? 'Channel',
                description: item['description']?.toString() ?? '',
                thumbnailUrl: item['thumbnailUrl']?.toString() ?? '',
              ))
          .toList(growable: false);
      _channelCache[cacheKey] = _ChannelCacheEntry(DateTime.now(), restored);
      return restored;
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
    unawaited(_channelDisk.put('q|$cacheKey', channels.map((channel) => {
          'channelId': channel.channelId,
          'title': channel.title,
          'description': channel.description,
          'thumbnailUrl': channel.thumbnailUrl,
        }).toList(growable: false)));
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
  // Setiap halaman search.list memakai 1 panggilan pada bucket 100/hari yang
  // terpisah. videos.list memakai bucket umum dan dapat mengembalikan detail
  // sampai 50 video per panggilan; hasil radio sengaja di-cache.

  // Shorts bisa sampai 3 menit, sementara Data API tidak memberi flag isShort.
  // Filter lokal memakai label metadata dan durasi untuk membatasi kandidat.
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

    final cacheKey = 'radioPopularV37|${keyword.toLowerCase()}|${pageToken ?? ''}';
    final cached = _cache[cacheKey];

    if (cached != null &&
        DateTime.now().difference(cached.time) < _radioCacheTtl) {
      if (cached.results.isEmpty) {
        return RadioPage(results: const <YoutubeSearchResult>[], nextPageToken: cached.nextPageToken);
      }
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
      final rawDiskResults = diskHit['results'];
      final diskResults = _resultsFromJson(rawDiskResults);
      final diskToken = diskHit['next']?.toString();

      if (rawDiskResults is List && rawDiskResults.isEmpty) {
        _cache[cacheKey] = _CacheEntry(DateTime.now(), const <YoutubeSearchResult>[], diskToken);
        return RadioPage(results: const <YoutubeSearchResult>[], nextPageToken: diskToken);
      }

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
    final isSongSimilarityQuery = RegExp(
      r'\b(?:similar songs?|songs? like|similar music)\b',
      caseSensitive: false,
    ).hasMatch(lowerKeyword);
    final alreadyMusicWord = RegExp(
      r'\b(?:lagu|musik|music|songs?|audio|remix|dj|dangdut|pop|rock|jazz|hip\s*hop|kpop|metal|indie|akustik|nostalgia|karaoke|cover|mix|album)\b',
      caseSensitive: false,
    ).hasMatch(lowerKeyword);

    // Song Radio harus tetap mencari lagu/artis yang menjadi seed. Jangan
    // menambahkan "lagu Indonesia" ke query track-specific, karena itu bisa
    // menggeser hasil dari lagu asing atau gaya yang sedang diputar.
    final radioKeyword = [
      keyword,
      if (!alreadyMusicWord && !isSongSimilarityQuery) 'lagu',
      if (!hasIndonesia && !isSongSimilarityQuery) 'Indonesia',
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

    // Filter Shorts memakai metadata lokal tanpa request tambahan ke halaman YouTube.
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
        !isSongSimilarityQuery &&
        !keyword.toLowerCase().contains('lagu indonesia') &&
        MusicStyleMatcher.styleFromText(keyword) == null) {
      final fallback = await _searchPopularMusicFallback();
      if (fallback.isNotEmpty) {
        results = fallback;
      }
    }

    final token = data['nextPageToken']?.toString();

    _cache[cacheKey] = _CacheEntry(DateTime.now(), results, token);

    unawaited(_disk.put(cacheKey, {
      'results': results.map((video) => video.toJson()).toList(),
      'next': token,
    }));

    if (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }

    return RadioPage(results: results, nextPageToken: token);
  }

  Future<List<YoutubeSearchResult>> _searchPopularMusicFallback() async {
    // Jangan membuat search.list kedua hanya untuk fallback radio. Gunakan
    // katalog videos.list chart=mostPopular yang sudah dipakai feed beranda.
    // Ini tidak mengonsumsi bucket search.list yang lebih kecil.
    const cacheKey = 'radioPopularFallbackV38';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.time) < _radioCacheTtl) {
      return cached.results;
    }
    final diskFallback = await _disk.get(cacheKey, maxAge: _radioCacheTtl);
    if (diskFallback is List) {
      final restored = _resultsFromJson(diskFallback);
      if (diskFallback.isEmpty || restored.isNotEmpty) {
        _cache[cacheKey] = _CacheEntry(DateTime.now(), restored);
        return restored;
      }
    }

    final popular = await mostPopular(categoryId: '10', maxResults: 50);
    var results = popular.where((video) {
      final seconds = video.durationSeconds;
      return !video.isLive &&
          !video.isUpcoming &&
          (seconds == null || (seconds >= _radioMinSeconds && seconds <= _radioMaxSeconds));
    }).toList(growable: false);
    results = _filterShortFormCandidates(results);
    results = _filterNonMusicCandidates(results);
    results = _filterAiMusicCandidates(results);
    results = _rankRadio(results);

    _cache[cacheKey] = _CacheEntry(DateTime.now(), results);
    unawaited(_disk.put(
      cacheKey,
      results.map((video) => video.toJson()).toList(),
    ));
    return results;
  }

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
    final cacheKey = 'mostPopularMusicV3|$musicCategoryId';
    final cached = _cache[cacheKey];
    if (cached != null) {
      final age = DateTime.now().difference(cached.time);
      if (age < _feedTtl || (force && age < _forcedFeedRefreshFloor)) {
        return cached.results.take(maxResults).toList(growable: false);
      }
    }
    if (!force) {
      final diskHit = await _disk.get(cacheKey, maxAge: _feedTtl);
      final fromDisk = _resultsFromJson(diskHit);
      if (diskHit is List && (diskHit.isEmpty || fromDisk.isNotEmpty)) {
        _cache[cacheKey] = _CacheEntry(DateTime.now(), fromDisk);
        for (final video in fromDisk) {
          if (video.durationSeconds != null || video.isLive || video.isUpcoming) {
            _rememberVideoDetail(video);
          }
        }
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
    for (final video in parsed) {
      if (video.durationSeconds != null || video.isLive || video.isUpcoming) {
        _rememberVideoDetail(video);
      }
    }
    final results = parsed.where(isMusicCatalogItem).toList(growable: false);

    _cache[cacheKey] = _CacheEntry(DateTime.now(), results);
    unawaited(_disk.put(cacheKey, results.map((v) => v.toJson()).toList()));
    return results.take(maxResults).toList(growable: false);
  }

  /// Feed lagu baru menggunakan katalog videos.list yang sudah dicache.
  /// Ini menghindari search.list berulang hanya untuk feed kategori tetap.
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

    const cacheKey = 'recentMusicV5FromPopular';
    final cached = _cache[cacheKey];
    if (cached != null) {
      final age = DateTime.now().difference(cached.time);
      if (age < _feedTtl || (force && age < _forcedFeedRefreshFloor)) {
        return cached.results.take(maxResults).toList(growable: false);
      }
    }
    final diskHit = await _disk.get(cacheKey, maxAge: _feedTtl);
    final fromDisk = _resultsFromJson(diskHit);
    if (!force && diskHit is List && (diskHit.isEmpty || fromDisk.isNotEmpty)) {
      _cache[cacheKey] = _CacheEntry(DateTime.now(), fromDisk);
      return fromDisk.take(maxResults).toList(growable: false);
    }

    // search.list punya bucket harian 100 panggilan. Jangan pakai endpoint itu
    // untuk feed kedua: ambil kandidat dari videos.list yang sudah dipakai
    // beranda, lalu urutkan berdasarkan tanggal rilis. Jika kandidat 30 hari
    // terakhir tidak tersedia, tampilkan katalog musik populer yang tersedia.
    final popular = await mostPopular(
      categoryId: '10',
      maxResults: 50,
      force: force,
    );
    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(const Duration(days: 30));
    final candidates = popular
        .where((video) => !video.isLive && !video.isUpcoming)
        .toList(growable: false);
    final recent = candidates
        .where((video) => video.publishedAt != null && video.publishedAt!.toUtc().isAfter(cutoff))
        .toList(growable: false);
    final results = List<YoutubeSearchResult>.from(recent.isNotEmpty ? recent : candidates)
      ..sort((a, b) {
        final ap = a.publishedAt?.millisecondsSinceEpoch ?? 0;
        final bp = b.publishedAt?.millisecondsSinceEpoch ?? 0;
        if (bp != ap) return bp.compareTo(ap);
        return (b.viewCount ?? 0).compareTo(a.viewCount ?? 0);
      });

    _cache[cacheKey] = _CacheEntry(DateTime.now(), results);
    unawaited(_disk.put(
      cacheKey,
      results.map((video) => video.toJson()).toList(),
    ));
    return results.take(maxResults).toList(growable: false);
  }

  /// Melengkapi hasil pencarian dengan durasi, jumlah tonton, dan status live
  /// lewat satu panggilan videos.list (1 unit per 50 video). Kalau gagal,
  /// daftar asli dikembalikan apa adanya.
  static String _videoDetailDiskKey(String videoId) =>
      'video|${sha256.convert(utf8.encode(videoId))}';

  Future<List<YoutubeSearchResult>> _withDetails(
    List<YoutubeSearchResult> videos,
  ) async {
    if (videos.isEmpty || _apiKey.isEmpty) return videos;

    final details = <String, YoutubeSearchResult>{};
    final needDisk = <YoutubeSearchResult>[];
    final now = DateTime.now();

    for (final video in videos) {
      if (video.videoId.isEmpty || video.isLocal) continue;
      final entry = _videoDetailCache[video.videoId];
      if (entry != null && now.difference(entry.time) < _videoDetailTtl) {
        details[video.videoId] = entry.result;
      } else {
        if (entry != null) _videoDetailCache.remove(video.videoId);
        needDisk.add(video);
      }
    }

    // SharedPreferences lookups are parallelized, but API requests remain
    // batched (up to 50 IDs per videos.list call).
    final diskValues = await Future.wait(needDisk.map(
      (video) => _videoDetailDisk.get(_videoDetailDiskKey(video.videoId)),
    ));
    final missingApi = <YoutubeSearchResult>[];
    for (var i = 0; i < needDisk.length; i++) {
      final video = needDisk[i];
      final raw = diskValues[i];
      if (raw is Map) {
        try {
          final cached = YoutubeSearchResult.fromJson(
            Map<String, dynamic>.from(raw),
          );
          if (cached.videoId == video.videoId &&
              (cached.durationSeconds != null || cached.isLive || cached.isUpcoming)) {
            _videoDetailCache[cached.videoId] =
                _VideoDetailCacheEntry(DateTime.now(), cached);
            details[cached.videoId] = cached;
            continue;
          }
        } catch (_) {
          // Invalid cache entries are ignored and refreshed from the API.
        }
      }
      missingApi.add(video);
    }

    for (var i = 0; i < missingApi.length; i += 50) {
      final chunk = missingApi.sublist(i, math.min(i + 50, missingApi.length));
      try {
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
          if (detail == null) continue;
          details[detail.videoId] = detail;
          _rememberVideoDetail(detail);
        }
      } catch (_) {
        // Cached and search-snippet metadata are still usable if details fail.
      }
    }

    return videos.map((video) {
      final detail = details[video.videoId];
      if (detail == null) return video;
      return video.copyWith(
        description: detail.description.isNotEmpty
            ? detail.description
            : video.description,
        viewCount: detail.viewCount ?? video.viewCount,
        durationSeconds: detail.durationSeconds ?? video.durationSeconds,
        publishedAt: detail.publishedAt ?? video.publishedAt,
        liveStatus: detail.liveStatus.isNotEmpty
            ? detail.liveStatus
            : video.liveStatus,
        concurrentViewers: detail.concurrentViewers ?? video.concurrentViewers,
        liveStartTime: detail.liveStartTime ?? video.liveStartTime,
        channelId: detail.channelId.isNotEmpty ? detail.channelId : video.channelId,
        categoryId: detail.categoryId.isNotEmpty ? detail.categoryId : video.categoryId,
      );
    }).toList(growable: false);
  }

  static void _rememberVideoDetail(YoutubeSearchResult detail) {
    if (detail.videoId.isEmpty ||
        detail.isLocal ||
        (detail.durationSeconds == null && !detail.isLive && !detail.isUpcoming)) {
      return;
    }
    _videoDetailCache[detail.videoId] =
        _VideoDetailCacheEntry(DateTime.now(), detail);
    if (_videoDetailCache.length > 300) {
      _videoDetailCache.remove(_videoDetailCache.keys.first);
    }
    // Serialize disk writes so concurrent feed responses don't race while
    // updating DiskCache's bounded entry index.
    _videoDetailWriteQueue = _videoDetailWriteQueue.then(
      (_) => _videoDetailDisk.put(_videoDetailDiskKey(detail.videoId), detail.toJson()),
    );
  }

  /// Resource videos.list -> model; buang durasi sangat pendek di parser.
  /// Penyaringan Shorts tanpa hashtag dan video pendek non-musik ada di policy.
  List<YoutubeSearchResult> _parseVideoResources(List items) =>
      YoutubeSearchResponseParser.parseVideoResources(items);

  /// Alias untuk source lama. Semua radio baru memakai [searchLatest].
  Future<RadioPage> searchPopular(
    String query, {
    String? pageToken,
  }) => searchLatest(query, pageToken: pageToken);

  Future<http.Response> _getWithRetry(
    Uri uri, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    // Coalesce identical concurrent calls (for example a rebuild that triggers
    // the same query twice before the first response reaches the cache).
    final key = uri.toString();
    final active = _inFlightHttp[key];
    if (active != null) return active;

    late final Future<http.Response> request;
    request = _performGetWithRetry(uri, timeout: timeout).whenComplete(() {
      if (identical(_inFlightHttp[key], request)) {
        _inFlightHttp.remove(key);
      }
    });
    _inFlightHttp[key] = request;
    return request;
  }

  Future<http.Response> _performGetWithRetry(
    Uri uri, {
    required Duration timeout,
  }) async {
    final scope = uri.path.endsWith('/search') ? 'search' : 'data';
    Object? lastError;

    // Two attempts are enough for transient gateway errors; quota/rate-limit
    // errors are never retried in a tight loop.
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await YoutubeApiRequestGuard.beforeRequest(scope);
        final response = await http.get(uri).timeout(timeout);
        YoutubeApiRequestGuard.observeResponse(
          scope: scope,
          statusCode: response.statusCode,
          body: response.body,
          headers: response.headers,
        );

        final reason = _errorReason(response);
        final isRateOrQuota = response.statusCode == 429 ||
            reason == 'quotaExceeded' ||
            reason == 'dailyLimitExceeded' ||
            reason == 'rateLimitExceeded' ||
            reason == 'userRateLimitExceeded';
        if (isRateOrQuota) return response;
        if (response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503 ||
            response.statusCode == 504) {
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(seconds: 1));
            continue;
          }
        }
        return response;
      } on YoutubeApiLimitException catch (error) {
        throw YoutubeSearchException(error.message);
      } catch (error) {
        lastError = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          continue;
        }
      }
    }

    throw YoutubeSearchException(
      lastError == null
          ? 'Tidak bisa terhubung ke internet. Coba lagi.'
          : 'Koneksi ke YouTube gagal setelah satu percobaan ulang. Coba lagi nanti.',
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

  List<YoutubeSearchResult> _parseItems(List items) =>
      YoutubeSearchResponseParser.parseSearchItems(items);

  Future<List<YoutubeSearchResult>> _ensureViewCounts(
    List<YoutubeSearchResult> videos,
  ) async {
    if (videos.isEmpty || dataSaverLevel > 0) return videos;
    return _withDetails(videos);
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

  static bool isLikelyShortForm(YoutubeSearchResult video) =>
      YoutubeMusicPolicy.isLikelyShortForm(video);

  static bool isLikelyNonMusicVideo(YoutubeSearchResult video) =>
      YoutubeMusicPolicy.isLikelyNonMusicVideo(video);

  static bool isLikelyAiGeneratedMusic(YoutubeSearchResult video) =>
      YoutubeMusicPolicy.isLikelyAiGeneratedMusic(video);

  List<YoutubeSearchResult> _filterAiMusicCandidates(
    List<YoutubeSearchResult> videos,
  ) => YoutubeMusicPolicy.filterAiMusicCandidates(videos);

  static bool isMusicCandidate(YoutubeSearchResult video) =>
      YoutubeMusicPolicy.isMusicCandidate(video);

  static bool isMusicCatalogItem(
    YoutubeSearchResult video, {
    bool requireCategoryId = false,
  }) => YoutubeMusicPolicy.isMusicCatalogItem(
        video,
        requireCategoryId: requireCategoryId,
      );

  /// Inclusive channel/subscription filter for cover songs and non-official uploads.
  static bool isMusicChannelUpload(
    YoutubeSearchResult video, {
    String channelTitle = '',
    String channelDescription = '',
  }) => YoutubeMusicPolicy.isMusicChannelUpload(
        video,
        channelTitle: channelTitle,
        channelDescription: channelDescription,
      );

  static bool isLikelyMusicChannelProfile(String title, String description) =>
      YoutubeMusicPolicy.isLikelyMusicChannelProfile(title, description);

  // ============================================================
  // DETEKSI SHORTS TANPA SCRAPING HALAMAN YOUTUBE
  // ============================================================
  // YouTube Data API tidak menyediakan field resmi isShort. Versi lama
  // mengirim HEAD/GET ke youtube.com/shorts/<id> bagi hampir setiap kandidat;
  // ini menambah trafik di luar API resmi dan dapat memicu 403/429.
  // Sekarang filter memakai metadata yang sudah dimiliki aplikasi (judul,
  // deskripsi, dan nama channel), tanpa request tambahan ke halaman HTML.

  /// Kompatibilitas untuk pemanggil lama. ID saja tidak cukup untuk menentukan
  /// Short melalui Data API resmi; pakai [isLikelyShortForm] pada metadata video.
  @Deprecated('Gunakan isLikelyShortForm(YoutubeSearchResult); ID tidak memberi status Shorts resmi.')
  Future<bool> isShortVideo(String videoId) async => false;

  /// Buang kandidat yang metadata-nya secara jelas menandai Shorts.
  /// Fungsi ini sengaja tidak membuat request jaringan per video.
  Future<List<YoutubeSearchResult>> removeShorts(
    List<YoutubeSearchResult> videos,
  ) async {
    if (videos.isEmpty) return videos;
    return videos
        .where((video) => !isLikelyShortForm(video))
        .toList(growable: false);
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

    // Hasil search yang sudah diperkaya _ensureViewCounts memiliki durasi.
    // Filter secara lokal agar tidak membuat panggilan videos.list kedua.
    final allHaveDuration = videos.every(
      (video) => video.durationSeconds != null || video.isLive || video.isUpcoming,
    );
    if (allHaveDuration) {
      return videos.where((video) {
        final length = video.durationSeconds;
        return !video.isLive &&
            !video.isUpcoming &&
            length != null &&
            length >= minSeconds &&
            length <= maxSeconds;
      }).toList(growable: false);
    }

    try {
      final data = await _getJson(
        Uri.parse('https://www.googleapis.com/youtube/v3/videos').replace(
          queryParameters: {
            'part': 'contentDetails',
            'id': videos
                .where((video) => video.durationSeconds == null)
                .take(50)
                .map((video) => video.videoId)
                .join(','),
            'key': _apiKey,
          },
        ),
      );

      final items = data['items'];

      if (items is! List) {
        return videos;
      }

      final seconds = <String, int>{
        for (final video in videos)
          if (video.durationSeconds != null)
            video.videoId: video.durationSeconds!.round(),
      };

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

  String _pickThumbnail(dynamic thumbnails) =>
      YoutubeSearchResponseParser.pickThumbnail(thumbnails);

  String _errorReason(http.Response response) =>
      _apiErrors.errorReason(response);

  String _errorMessage(http.Response response) =>
      _apiErrors.errorMessage(response);

  /// YouTube API mengirim judul dengan HTML entity (&amp; &#39; &quot;).
  static String _decodeHtml(String input) =>
      YoutubeSearchResponseParser.decodeHtml(input);
}
