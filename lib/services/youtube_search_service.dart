import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as ytex;

import '../models/youtube_search_result.dart';
import 'disk_cache.dart';
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
  ///
  /// Kunci ini ikut tertanam di APK. Batasi di Google Cloud Console ke
  /// package name + SHA-1 sertifikat aplikasi dan ke YouTube Data API v3 saja.
  static const String _apiKey = String.fromEnvironment('YOUTUBE_API_KEY');

  static const YoutubeSearchApiErrors _apiErrors = YoutubeSearchApiErrors();

  // Search video dan channel memakai youtube_explode_dart, bukan endpoint
  // YouTube Data API search.list. Client dibuat sekali untuk seluruh sesi app.
  static final ytex.YoutubeExplode _youtubeExplode = ytex.YoutubeExplode();
  static final Map<String, dynamic> _radioExplodePageSources =
      <String, dynamic>{};
  static final Map<String, int> _radioExplodePageNumbers = <String, int>{};

  // Biaya kuota per endpoint (search.list jauh lebih mahal daripada
  // videos.list) dan batas hariannya ditentukan Google dan bisa berubah.
  // Cek dokumentasi resmi YouTube Data API dan halaman Quotas di Cloud Console.
  // Cache dan deduplikasi di bawah mengurangi request berulang.

  static const int _cacheLimit = 60;
  static const Duration _cacheTtl = Duration(hours: 6);
  // Cache katalog pencarian disimpan lama di perangkat agar query berulang,
  // termasuk setelah aplikasi dibuka ulang, tidak meminta search.list lagi.
  static const Duration _catalogSearchDiskTtl = Duration(days: 90);
  static const Duration _latestSearchDiskTtl = Duration(hours: 6);
  // Radio pages stabil cukup lama untuk dipakai ulang lintas sesi. Next tetap
  // dilarang mengambil halaman jaringan baru; TTL ini berlaku saat Radio dimulai.
  static const Duration _radioCacheTtl = Duration(days: 30);
  // Hasil Radio yang kosong biasanya karena filter terlalu ketat atau metadata
  // sementara tidak lengkap, jadi jangan ditahan selama 6 jam.
  static const Duration _emptyResultTtl = Duration(minutes: 30);
  // Feed populer juga stabil; refresh manual yang terlalu cepat memakai cache.
  static const Duration _feedTtl = Duration(hours: 6);
  static const Duration _forcedFeedRefreshFloor = Duration(minutes: 2);

  final Map<String, _CacheEntry> _cache = {};
  final Map<String, _ChannelCacheEntry> _channelCache = {};
  static final Map<String, Future<http.Response>> _inFlightHttp =
      <String, Future<http.Response>>{};

  // Satu client dipakai ulang agar koneksi (keep-alive) tidak dibuat ulang
  // setiap request. Hidup selama proses aplikasi.
  static final http.Client _client = http.Client();

  /// Cache di HP: pencarian yang sama tidak menghabiskan kuota lagi
  /// walaupun aplikasi sudah ditutup dan dibuka ulang.
  static const DiskCache _disk = DiskCache(
    namespace: 'search',
    maxEntries: 180,
    ttl: Duration(days: 180),
  );

  // Terpisah dari katalog biasa agar penulisan feed/search tidak mengusir
  // kandidat Radio yang bisa dipakai untuk autoplay pada sesi berikutnya.
  static const DiskCache _radioDisk = DiskCache(
    namespace: 'radio_search_pages',
    maxEntries: 50,
    ttl: Duration(days: 30),
  );

  // Pencarian channel bersifat opsional dan disimpan lintas sesi supaya query
  // yang sama tidak kembali menghabiskan kuota search.list setelah app dibuka ulang.
  static const DiskCache _channelDisk = DiskCache(
    namespace: 'channel_search',
    maxEntries: 50,
    ttl: Duration(days: 30),
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

  /// Simpan ke cache memori dengan urutan LRU dan batas ukuran. Dipakai di
  /// semua jalur (termasuk saat hasil datang dari disk) supaya cache memori
  /// tidak tumbuh tanpa batas.
  void _putCache(String key, _CacheEntry entry) {
    _cache.remove(key); // pindah ke posisi paling baru
    _cache[key] = entry;
    while (_cache.length > _cacheLimit) {
      _cache.remove(_cache.keys.first);
    }
  }

  SmartSearchIntent interpretSearch(String query) =>
      YoutubeSearchQueryParser.interpret(query);

  String describeSearch(String query) => interpretSearch(query).label;

  /// Konversi metadata Video dari youtube_explode_dart menjadi model app.
  /// Properti dibaca defensif karena metadata video YouTube bisa tidak lengkap.
  static YoutubeSearchResult _fromExplodeVideo(dynamic video) {
    String readString(dynamic Function() read, [String fallback = '']) {
      try {
        final value = read();
        if (value == null) return fallback;
        final text = value.toString().trim();
        return text.isEmpty ? fallback : text;
      } catch (_) {
        return fallback;
      }
    }

    String videoId = readString(() => video.id.value);
    if (videoId.isEmpty) videoId = readString(() => video.id);

    String channelId = readString(() => video.channelId.value);
    if (channelId.isEmpty) channelId = readString(() => video.channelId);

    final title = _decodeHtml(readString(() => video.title, 'Tanpa judul'));
    final description = _decodeHtml(readString(() => video.description));
    final channelTitle = _decodeHtml(readString(() => video.author, 'Unknown'));

    String thumbnailUrl = readString(() => video.thumbnails.maxResUrl);
    if (thumbnailUrl.isEmpty) {
      thumbnailUrl = readString(() => video.thumbnails.highResUrl);
    }
    if (thumbnailUrl.isEmpty) {
      thumbnailUrl = readString(() => video.thumbnails.mediumResUrl);
    }
    if (thumbnailUrl.isEmpty && videoId.isNotEmpty) {
      thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }

    DateTime? publishedAt;
    try {
      final dynamic date = video.publishDate ?? video.uploadDate;
      if (date is DateTime) publishedAt = date;
    } catch (_) {}

    double? durationSeconds;
    try {
      final dynamic duration = video.duration;
      if (duration is Duration) durationSeconds = duration.inMilliseconds / 1000.0;
    } catch (_) {}

    int? viewCount;
    try {
      final dynamic value = video.engagement.viewCount;
      if (value is num) viewCount = value.toInt();
    } catch (_) {}

    bool live = false;
    try {
      live = video.isLive == true;
    } catch (_) {}

    return YoutubeSearchResult(
      videoId: videoId,
      title: title,
      description: description,
      channelTitle: channelTitle,
      thumbnailUrl: thumbnailUrl,
      viewCount: viewCount,
      publishedAt: publishedAt,
      durationSeconds: live ? null : durationSeconds,
      liveStatus: live ? 'live' : '',
      channelId: channelId,
      // youtube_explode_dart tidak mengembalikan categoryId resmi untuk hasil
      // pencarian. Filter katalog MusikKu tetap memakai metadata/judul/channel.
      categoryId: '',
    );
  }

  static String _explodeChannelId(dynamic video) {
    try {
      return video.channelId.value.toString();
    } catch (_) {
      try {
        return video.channelId.toString();
      } catch (_) {
        return '';
      }
    }
  }


  static String _explodeVideoAuthor(dynamic video) {
    try {
      return video.author.toString();
    } catch (_) {
      return 'Channel';
    }
  }

  static String _explodeVideoDescription(dynamic video) {
    try {
      return video.description.toString();
    } catch (_) {
      return '';
    }
  }

  Future<List<YoutubeSearchResult>> search(
    String query, {
    String filter = 'music',
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];

    final intent = interpretSearch(keyword);
    final safeFilter = 'music';
    final cacheKey =
        'explodeSearchV1|${intent.apiQuery.toLowerCase()}|${intent.latest ? 'date' : 'relevance'}|$safeFilter';
    final cached = _cache[cacheKey];

    if (cached != null &&
        DateTime.now().difference(cached.time) < _cacheTtl) {
      debugPrint('EXPLODE SEARCH CACHE HIT (memory): ${intent.apiQuery}');
      return cached.results;
    }

    final diskRaw = await _disk.get(
      'q|$cacheKey',
      maxAge: intent.latest ? _latestSearchDiskTtl : _catalogSearchDiskTtl,
    );
    final diskResults = _resultsFromJson(diskRaw);
    if (diskRaw is List && (diskRaw.isEmpty || diskResults.isNotEmpty)) {
      debugPrint('EXPLODE SEARCH CACHE HIT (disk): ${intent.apiQuery}');
      _putCache(cacheKey, _CacheEntry(DateTime.now(), diskResults));
      _rememberVideoDetails(diskResults);
      return diskResults;
    }

    debugPrint('EXPLODE SEARCH NETWORK REQUEST: ${intent.apiQuery}');
    try {
      final sort = intent.latest
          ? ytex.SortFilters.uploadDate
          : ytex.SortFilters.relevance;
      final dynamic page = await _youtubeExplode.search.search(
        intent.apiQuery,
        filter: sort,
      );
      final rawItems = (page as Iterable).cast<dynamic>().toList();
      var results = rawItems
          .map(_fromExplodeVideo)
          .where((video) => video.videoId.isNotEmpty)
          .take(dataSaverLevel >= 2 ? 6 : (dataSaverLevel == 1 ? 10 : 16))
          .toList(growable: false);

      results = results.where((video) {
        if (video.isLive || video.isUpcoming) return false;
        final seconds = video.durationSeconds;
        if (seconds != null && seconds <= 60) return false;
        return isMusicCatalogItem(video);
      }).toList(growable: false);

      _putCache(cacheKey, _CacheEntry(DateTime.now(), results));
      _rememberVideoDetails(results);
      await _disk.put(
        'q|$cacheKey',
        results.map((video) => video.toJson()).toList(),
      );
      return results;
    } catch (error) {
      debugPrint('EXPLODE SEARCH ERROR: $error');
      throw YoutubeSearchException(
        'Pencarian YouTube sedang tidak tersedia. Coba lagi nanti. ($error)',
      );
    }
  }

  Future<List<YoutubeChannelSearchResult>> searchChannels(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];

    final cacheKey = 'channelExplodeV1|${keyword.toLowerCase()}';
    final cached = _channelCache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.time) < _cacheTtl) {
      debugPrint('EXPLODE CHANNEL CACHE HIT (memory): $keyword');
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
      _putChannelCache(cacheKey, restored);
      debugPrint('EXPLODE CHANNEL CACHE HIT (disk): $keyword');
      return restored;
    }

    try {
      // Ambil kandidat video melalui youtube_explode_dart, lalu deduplikasi
      // channelId. Ini tidak memanggil endpoint Data API search.list.
      final dynamic searchPage = await _youtubeExplode.search.search(
        keyword,
        filter: ytex.SortFilters.relevance,
      );
      final rawItems = (searchPage as Iterable).cast<dynamic>().take(20);
      final candidates = <String, dynamic>{};
      for (final item in rawItems) {
        final channelId = _explodeChannelId(item).trim();
        if (channelId.isNotEmpty) candidates.putIfAbsent(channelId, () => item);
      }

      final tasks = candidates.entries.take(8).map((entry) async {
        final fallback = entry.value;
        var title = _decodeHtml(_explodeVideoAuthor(fallback));
        var description = _decodeHtml(_explodeVideoDescription(fallback));
        var thumbnail = '';
        try {
          final channel = await _youtubeExplode.channels.get(entry.key);
          if (channel.title.trim().isNotEmpty) title = channel.title.trim();
          if (channel.logoUrl.trim().isNotEmpty) thumbnail = channel.logoUrl.trim();
        } catch (_) {
          // Tetap tampilkan kandidat channel dari metadata hasil pencarian.
        }
        return YoutubeChannelSearchResult(
          channelId: entry.key,
          title: title.isEmpty ? 'Channel' : title,
          description: description,
          thumbnailUrl: thumbnail,
        );
      });
      final channels = (await Future.wait(tasks))
          .where((channel) => channel.channelId.isNotEmpty)
          .toList(growable: false);

      _putChannelCache(cacheKey, channels);
      await _channelDisk.put(
        'q|$cacheKey',
        channels
            .map((channel) => {
                  'channelId': channel.channelId,
                  'title': channel.title,
                  'description': channel.description,
                  'thumbnailUrl': channel.thumbnailUrl,
                })
            .toList(growable: false),
      );
      return channels;
    } catch (error) {
      debugPrint('EXPLODE CHANNEL SEARCH ERROR: $error');
      throw YoutubeSearchException(
        'Pencarian artis/channel sedang tidak tersedia. Coba lagi nanti. ($error)',
      );
    }
  }

  void _putChannelCache(
    String key,
    List<YoutubeChannelSearchResult> results,
  ) {
    _channelCache.remove(key);
    _channelCache[key] = _ChannelCacheEntry(DateTime.now(), results);
    while (_channelCache.length > _cacheLimit) {
      _channelCache.remove(_channelCache.keys.first);
    }
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
  // Setiap halaman search.list menghabiskan kuota search. videos.list memakai
  // kuota umum dan dapat mengembalikan detail sampai 50 video per panggilan;
  // hasil radio sengaja di-cache.

  // Shorts bisa sampai 3 menit, sementara Data API tidak memberi flag isShort.
  // Filter lokal memakai label metadata dan durasi untuk membatasi kandidat.
  static const int _radioMinSeconds = 61;
  static const int _radioMaxSeconds = 30 * 60;

  Future<RadioPage> searchLatest(
    String query, {
    String? pageToken,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const RadioPage(results: []);

    final normalized = keyword.toLowerCase();
    final cacheKey =
        'radioExplodeV1|$normalized|${pageToken ?? ''}';
    final cached = _cache[cacheKey];
    if (cached != null) {
      final age = DateTime.now().difference(cached.time);
      final ttl = cached.results.isEmpty ? _emptyResultTtl : _radioCacheTtl;
      if (age < ttl) {
        final filtered = _rankRadio(_filterAiMusicCandidates(
          _filterNonMusicCandidates(_filterShortFormCandidates(cached.results)),
        ));
        return RadioPage(results: filtered, nextPageToken: cached.nextPageToken);
      }
    }

    final diskHit = await _radioDisk.get(cacheKey, maxAge: _radioCacheTtl);
    if (diskHit is Map) {
      final restored = _resultsFromJson(diskHit['results']);
      final token = diskHit['next']?.toString();
      if (restored.isNotEmpty) {
        final filtered = _rankRadio(_filterAiMusicCandidates(
          _filterNonMusicCandidates(_filterShortFormCandidates(restored)),
        ));
        _putCache(cacheKey, _CacheEntry(DateTime.now(), filtered, token));
        return RadioPage(results: filtered, nextPageToken: token);
      }
    }

    final lowerKeyword = keyword.toLowerCase();
    final hasIndonesia = lowerKeyword.contains('indonesia') ||
        RegExp(r'(^|\s)indo($|\s)').hasMatch(lowerKeyword);
    final isSongSimilarityQuery = RegExp(
      r'\b(?:similar songs?|songs? like|similar music)\b',
      caseSensitive: false,
    ).hasMatch(lowerKeyword);
    final alreadyMusicWord = RegExp(
      r'\b(?:lagu|musik|music|songs?|audio|remix|dj|dangdut|pop|rock|jazz|hip\s*hop|kpop|metal|indie|akustik|nostalgia|karaoke|cover|mix|album)\b',
      caseSensitive: false,
    ).hasMatch(lowerKeyword);
    final radioKeyword = [
      keyword,
      if (!alreadyMusicWord && !isSongSimilarityQuery) 'lagu',
      if (!hasIndonesia && !isSongSimilarityQuery) 'Indonesia',
    ].join(' ');
    final pageSourceKey = radioKeyword.toLowerCase();

    int requestedPage = 1;
    if (pageToken != null && pageToken.startsWith('explode:page:')) {
      requestedPage = int.tryParse(pageToken.substring('explode:page:'.length)) ?? 1;
      if (requestedPage < 1) requestedPage = 1;
    }

    try {
      dynamic page;
      var sourcePageNumber = _radioExplodePageNumbers[pageSourceKey] ?? 0;
      var source = _radioExplodePageSources[pageSourceKey];

      // Memulai Radio baru selalu mulai dari halaman pertama meskipun sesi
      // Radio sebelumnya sudah mencapai halaman berikutnya.
      if (requestedPage == 1 || source == null) {
        source = await _youtubeExplode.search.search(
          radioKeyword,
          filter: ytex.SortFilters.relevance,
        );
        sourcePageNumber = 1;
        _radioExplodePageSources[pageSourceKey] = source;
        _radioExplodePageNumbers[pageSourceKey] = 1;
      }

      // YoutubeExplode menyimpan sumber halaman untuk pagination; ketika app
      // hidup kembali dan sumbernya belum ada, ulangi query dan maju ke halaman
      // yang diminta. Pagination ini juga tidak memakai Data API search.list.
      page = source;
      while (sourcePageNumber < requestedPage) {
        final dynamic nextPage = await page.nextPage();
        if (nextPage == null) {
          page = null;
          break;
        }
        page = nextPage;
        sourcePageNumber += 1;
        _radioExplodePageSources[pageSourceKey] = page;
        _radioExplodePageNumbers[pageSourceKey] = sourcePageNumber;
      }

      final rawItems = page == null
          ? <dynamic>[]
          : (page as Iterable).cast<dynamic>().toList();
      var results = rawItems
          .map(_fromExplodeVideo)
          .where((video) => video.videoId.isNotEmpty)
          .toList(growable: false);

      final wantsLong = lowerKeyword.contains('mix') ||
          lowerKeyword.contains('nonstop') ||
          lowerKeyword.contains('non stop') ||
          lowerKeyword.contains('album');
      if (!wantsLong) {
        results = results.where((video) {
          if (video.isLive || video.isUpcoming) return false;
          final seconds = video.durationSeconds;
          // Durasi yang tidak disediakan hasil pencarian dipertahankan agar
          // Radio tidak melakukan request videos.list untuk melengkapinya.
          if (seconds == null) return true;
          return seconds >= _radioMinSeconds && seconds <= _radioMaxSeconds;
        }).toList(growable: false);
      }

      results = _filterShortFormCandidates(results);
      results = await removeShorts(results);
      results = _filterNonMusicCandidates(results);
      results = _filterAiMusicCandidates(results);
      results = _rankRadio(results);

      final nextToken = rawItems.length >= 20 && page != null
          ? 'explode:page:${sourcePageNumber + 1}'
          : null;
      _putCache(cacheKey, _CacheEntry(DateTime.now(), results, nextToken));
      if (results.isNotEmpty) {
        await _radioDisk.put(cacheKey, {
          'results': results.map((video) => video.toJson()).toList(),
          'next': nextToken,
        });
      }
      return RadioPage(results: results, nextPageToken: nextToken);
    } catch (error) {
      debugPrint('EXPLODE RADIO SEARCH ERROR: $error');
      // Jangan fallback ke Data API search.list karena itu justru menghidupkan
      // kembali batas 100 pencarian/hari. Error terlihat dengan hasil kosong.
      _putCache(cacheKey, _CacheEntry(DateTime.now(), const []));
      return const RadioPage(results: []);
    }
  }

  /// Musik yang sedang trending. Kategori 10 dipakai sebagai default agar
  /// beranda tidak menampilkan upload dari kategori video lain.
  /// Memakai videos.list chart=mostPopular: biaya kuotanya rendah
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
        _putCache(cacheKey, _CacheEntry(DateTime.now(), fromDisk));
        _rememberVideoDetails(fromDisk);
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
    _rememberVideoDetails(parsed);
    final results = parsed.where(isMusicCatalogItem).toList(growable: false);

    _putCache(cacheKey, _CacheEntry(DateTime.now(), results));
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
    if (!force) {
      final diskHit = await _disk.get(cacheKey, maxAge: _feedTtl);
      final fromDisk = _resultsFromJson(diskHit);
      if (diskHit is List && (diskHit.isEmpty || fromDisk.isNotEmpty)) {
        _putCache(cacheKey, _CacheEntry(DateTime.now(), fromDisk));
        return fromDisk.take(maxResults).toList(growable: false);
      }
    }

    // search.list punya kuota yang jauh lebih mahal. Jangan pakai endpoint itu
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
        .where((video) =>
            video.publishedAt != null &&
            video.publishedAt!.toUtc().isAfter(cutoff))
        .toList(growable: false);
    final results =
        List<YoutubeSearchResult>.from(recent.isNotEmpty ? recent : candidates)
          ..sort((a, b) {
            final ap = a.publishedAt?.millisecondsSinceEpoch ?? 0;
            final bp = b.publishedAt?.millisecondsSinceEpoch ?? 0;
            if (bp != ap) return bp.compareTo(ap);
            return (b.viewCount ?? 0).compareTo(a.viewCount ?? 0);
          });

    _putCache(cacheKey, _CacheEntry(DateTime.now(), results));
    unawaited(_disk.put(
      cacheKey,
      results.map((video) => video.toJson()).toList(),
    ));
    return results.take(maxResults).toList(growable: false);
  }

  static String _videoDetailDiskKey(String videoId) =>
      'video|${sha256.convert(utf8.encode(videoId))}';

  /// Simpan detail video ke cache memori (LRU) dan ke disk dalam satu batch.
  /// Hanya video yang punya durasi atau status live/upcoming yang disimpan.
  static void _rememberVideoDetails(Iterable<YoutubeSearchResult> details) {
    final toDisk = <String, Object>{};

    for (final detail in details) {
      if (detail.videoId.isEmpty ||
          detail.isLocal ||
          (detail.durationSeconds == null &&
              !detail.isLive &&
              !detail.isUpcoming)) {
        continue;
      }

      _videoDetailCache.remove(detail.videoId); // pindah ke posisi terbaru
      _videoDetailCache[detail.videoId] =
          _VideoDetailCacheEntry(DateTime.now(), detail);

      try {
        toDisk[_videoDetailDiskKey(detail.videoId)] = detail.toJson();
      } catch (_) {
        // Entri yang tidak bisa diserialisasi cukup dilewati.
      }
    }

    while (_videoDetailCache.length > 300) {
      _videoDetailCache.remove(_videoDetailCache.keys.first);
    }

    if (toDisk.isEmpty) return;
    // DiskCache sudah menyerialkan penulisan per namespace dan tidak pernah
    // melempar error; catchError di sini hanya sebagai pengaman tambahan.
    _videoDetailWriteQueue = _videoDetailWriteQueue
        .then((_) => _videoDetailDisk.putAll(toDisk))
        .catchError((_) {});
  }

  /// Resource videos.list -> model; buang durasi sangat pendek di parser.
  /// Penyaringan Shorts tanpa hashtag dan video pendek non-musik ada di policy.
  List<YoutubeSearchResult> _parseVideoResources(List items) =>
      YoutubeSearchResponseParser.parseVideoResources(items);

  /// Alias untuk source lama. Semua radio baru memakai [searchLatest].
  Future<RadioPage> searchPopular(
    String query, {
    String? pageToken,
  }) =>
      searchLatest(query, pageToken: pageToken);

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
        final response = await _client.get(uri).timeout(timeout);
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


  List<YoutubeSearchResult> _rankRadio(List<YoutubeSearchResult> videos) {
    // searchLatest requests order=relevance. Preserve that order rather than
    // sorting by view count or freshness; Radio is related-song discovery,
    // not a popularity chart. Defer a third item from the same channel only.
    final result = <YoutubeSearchResult>[];
    final channelCount = <String, int>{};
    final deferred = <YoutubeSearchResult>[];

    for (final video in videos) {
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
  ) =>
      YoutubeMusicPolicy.filterAiMusicCandidates(videos);

  static bool isMusicCandidate(YoutubeSearchResult video) =>
      YoutubeMusicPolicy.isMusicCandidate(video);

  static bool isMusicCatalogItem(
    YoutubeSearchResult video, {
    bool requireCategoryId = false,
  }) =>
      YoutubeMusicPolicy.isMusicCatalogItem(
        video,
        requireCategoryId: requireCategoryId,
      );

  /// Inclusive channel/subscription filter for cover songs and non-official uploads.
  static bool isMusicChannelUpload(
    YoutubeSearchResult video, {
    String channelTitle = '',
    String channelDescription = '',
  }) =>
      YoutubeMusicPolicy.isMusicChannelUpload(
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
  @Deprecated(
      'Gunakan isLikelyShortForm(YoutubeSearchResult); ID tidak memberi status Shorts resmi.')
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

  String _errorReason(http.Response response) =>
      _apiErrors.errorReason(response);

  String _errorMessage(http.Response response) =>
      _apiErrors.errorMessage(response);

  /// YouTube API mengirim judul dengan HTML entity (&amp; &#39; &quot;).
  static String _decodeHtml(String input) =>
      YoutubeSearchResponseParser.decodeHtml(input);
}