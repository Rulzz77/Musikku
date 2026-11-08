import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as ytex;

import '../models/youtube_search_result.dart';
import 'disk_cache.dart';
import 'youtube_search_query.dart';
import 'youtube_music_policy.dart';
import 'youtube_music_metadata_parser.dart';
import 'youtube_search_response_parser.dart';
import 'youtube_search_metadata.dart';
import 'youtube_search_api_errors.dart';
import 'youtube_api_request_guard.dart';
import 'music_style_matcher.dart';

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
  static final Map<String, YoutubeSearchResult> _musicDetailCache =
      <String, YoutubeSearchResult>{};

  // Biaya kuota per endpoint (search.list jauh lebih mahal daripada
  // videos.list) dan batas hariannya ditentukan Google dan bisa berubah.
  // Cek dokumentasi resmi YouTube Data API dan halaman Quotas di Cloud Console.
  // Cache dan deduplikasi di bawah mengurangi request berulang.

  static const int _cacheLimit = 60;
  static const Duration _cacheTtl = Duration(hours: 6);
  // Cache katalog pencarian disimpan lama di perangkat agar query berulang,
  // termasuk setelah aplikasi dibuka ulang, tidak meminta search.list lagi.
  static const Duration _catalogSearchDiskTtl = Duration(days: 14);
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

  /// Konversi metadata Video dari youtube_explode_dart menjadi model app.
  /// Properti dibaca defensif karena metadata video YouTube bisa tidak lengkap.
  /// "3 months ago" / "5 hari yang lalu" -> perkiraan tanggal. Perkiraan kasar
  /// (bulan = 30 hari, tahun = 365 hari), cukup untuk menilai baru atau lama.
  static DateTime? _approximateDateFromRelative(String raw) =>
      YoutubeSearchMetadata.parseRelativeUploadDate(raw);

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
    final releaseMetadata = YoutubeMusicMetadataParser.parse(
      title: title,
      description: description,
    );

    String thumbnailUrl = readString(() => video.thumbnails.maxResUrl);
    if (thumbnailUrl.isEmpty) {
      thumbnailUrl = readString(() => video.thumbnails.highResUrl);
    }
    if (thumbnailUrl.isEmpty) {
      thumbnailUrl = readString(() => video.thumbnails.mediumResUrl);
    }
    // SearchVideo exposes a List<Thumbnail>, while a full Video exposes a
    // ThumbnailSet. Read the actual highest-resolution list item as well.
    if (thumbnailUrl.isEmpty) {
      try {
        final dynamic thumbnails = video.thumbnails;
        if (thumbnails is Iterable) {
          var bestArea = -1;
          for (final dynamic thumbnail in thumbnails) {
            final candidateUrl = readString(() => thumbnail.url);
            final width = int.tryParse(readString(() => thumbnail.width, '0')) ?? 0;
            final height = int.tryParse(readString(() => thumbnail.height, '0')) ?? 0;
            final area = width * height;
            if (candidateUrl.isNotEmpty && area >= bestArea) {
              bestArea = area;
              thumbnailUrl = candidateUrl;
            }
          }
        }
      } catch (_) {}
    }
    if (thumbnailUrl.isEmpty && videoId.isNotEmpty) {
      thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }

    DateTime? publishedAt;
    try {
      final dynamic date = video.publishDate ?? video.uploadDate;
      if (date is DateTime) publishedAt = date;
    } catch (_) {}
    // SearchVideo.uploadDate is relative text (e.g. "3 months ago"); the full
    // Video model instead exposes DateTime uploadDate and uploadDateRaw.
    final rawUploadDate = readString(
      () => video.uploadDateRaw,
      readString(() => video.uploadDate),
    );
    final approxPublishedAt = publishedAt == null
        ? _approximateDateFromRelative(rawUploadDate)
        : null;

    // SearchVideo.duration is a String such as MM:SS / HH:MM:SS, not Duration.
    // Parse both shapes so Shorts and 15-minute compilation filters work.
    double? durationSeconds;
    try {
      durationSeconds = YoutubeSearchMetadata.parseDurationSeconds(video.duration);
    } catch (_) {}

    // SearchVideo.viewCount is a direct int. Only the full Video model nests it
    // under engagement.viewCount. Read both to avoid losing popularity data.
    int? viewCount;
    try {
      viewCount = YoutubeSearchMetadata.parseViewCount(video.viewCount);
    } catch (_) {}
    if (viewCount == null) {
      try {
        viewCount = YoutubeSearchMetadata.parseViewCount(video.engagement.viewCount);
      } catch (_) {}
    }

    bool live = false;
    try {
      live = video.isLive == true;
    } catch (_) {}

    return YoutubeSearchResult(
      videoId: videoId,
      title: title,
      description: description,
      channelTitle: channelTitle,
      artistName: releaseMetadata.artistName,
      album: releaseMetadata.album,
      thumbnailUrl: thumbnailUrl,
      viewCount: viewCount,
      publishedAt: publishedAt,
      approxPublishedAt: approxPublishedAt,
      durationSeconds: live ? null : durationSeconds,
      liveStatus: live ? 'live' : '',
      channelId: channelId,
      // youtube_explode_dart tidak mengembalikan categoryId resmi untuk hasil
      // pencarian. Filter katalog MusikKu tetap memakai metadata/judul/channel.
      categoryId: '',
    );
  }

  /// Fetches full Video details for a short candidate list. youtube_explode's
  /// lightweight SearchVideo has direct viewCount + text duration, while the
  /// full Video adds structured MusicData (song / artist / album). Call this
  /// only for the best few Spotify-import candidates, not for every search hit.
  Future<List<YoutubeSearchResult>> enrichMusicMetadata(
    List<YoutubeSearchResult> candidates,
  ) async {
    return Future.wait(candidates.map((candidate) async {
      if (candidate.isLocal || candidate.videoId.isEmpty) return candidate;
      final cached = _musicDetailCache[candidate.videoId];
      if (cached != null) return cached;

      try {
        final dynamic detail = await _youtubeExplode.videos
            .get(candidate.videoId)
            .timeout(const Duration(seconds: 12));
        String readString(dynamic Function() read) {
          try {
            final value = read();
            return value == null ? '' : value.toString().trim();
          } catch (_) {
            return '';
          }
        }

        final fullTitle = readString(() => detail.title);
        final fullDescription = readString(() => detail.description);
        final fullDuration = YoutubeSearchMetadata.parseDurationSeconds(
          () {
            try {
              return detail.duration;
            } catch (_) {
              return null;
            }
          }(),
        );
        int? fullViews;
        try {
          fullViews = YoutubeSearchMetadata.parseViewCount(
            detail.engagement.viewCount,
          );
        } catch (_) {}

        var musicDataTitle = '';
        var musicDataArtist = '';
        var musicDataAlbum = '';
        var bestMusicTitleScore = 0.0;
        try {
          final dynamic musicRows = detail.musicData;
          if (musicRows is Iterable) {
            for (final dynamic row in musicRows) {
              final rowTitle = readString(() => row.song);
              final rowArtist = readString(() => row.artist);
              final rowAlbum = readString(() => row.album);
              if (rowTitle.isEmpty || rowArtist.isEmpty) continue;
              final score = _simpleTitleOverlap(candidate.title, rowTitle);
              if (score > bestMusicTitleScore) {
                bestMusicTitleScore = score;
                musicDataTitle = rowTitle;
                musicDataArtist = rowArtist;
                musicDataAlbum = rowAlbum;
              }
            }
          }
        } catch (_) {}

        String fullThumbnail = '';
        try {
          fullThumbnail = readString(() => detail.thumbnails.maxResUrl);
          if (fullThumbnail.isEmpty) {
            fullThumbnail = readString(() => detail.thumbnails.highResUrl);
          }
        } catch (_) {}

        final parsedDescription = YoutubeMusicMetadataParser.parse(
          title: fullTitle.isEmpty ? candidate.title : fullTitle,
          description: fullDescription.isEmpty
              ? candidate.description
              : fullDescription,
        );
        final enriched = candidate.copyWith(
          description: fullDescription.isEmpty
              ? candidate.description
              : fullDescription,
          artistName: musicDataArtist.isNotEmpty
              ? musicDataArtist
              : (parsedDescription.artistName.isNotEmpty
                  ? parsedDescription.artistName
                  : candidate.artistName),
          album: musicDataAlbum.isNotEmpty
              ? musicDataAlbum
              : (parsedDescription.album.isNotEmpty
                  ? parsedDescription.album
                  : candidate.album),
          musicDataTitle: musicDataTitle,
          musicDataArtist: musicDataArtist,
          durationSeconds: candidate.durationSeconds ?? fullDuration,
          viewCount: (candidate.viewCount ?? 0) > 0
              ? candidate.viewCount
              : fullViews,
          thumbnailUrl: fullThumbnail.isNotEmpty
              ? fullThumbnail
              : candidate.thumbnailUrl,
        );
        _musicDetailCache[candidate.videoId] = enriched;
        if (_musicDetailCache.length > 240) {
          _musicDetailCache.remove(_musicDetailCache.keys.first);
        }
        return enriched;
      } catch (error) {
        debugPrint('YOUTUBE MUSIC DETAIL SKIPPED [${candidate.videoId}]: $error');
        return candidate;
      }
    }));
  }

  static double _simpleTitleOverlap(String first, String second) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'\b(?:official|audio|video|lyrics?|visualizer|hd|4k)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final a = normalize(first).split(' ').where((part) => part.isNotEmpty).toSet();
    final b = normalize(second).split(' ').where((part) => part.isNotEmpty).toSet();
    if (a.isEmpty || b.isEmpty) return 0;
    return a.intersection(b).length / a.length;
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

  static int _channelSearchMatchScore(String channelTitle, String query) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'\b(?:official(?:\s+music)?(?:\s+channel)?|vevo|topic|music\s+channel|channel)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final wanted = normalize(query);
    final found = normalize(channelTitle);
    if (wanted.isEmpty || found.isEmpty) return 0;
    if (wanted == found) return 100;
    if (found.startsWith('$wanted ') || wanted.startsWith('$found ')) return 85;
    final tokens = wanted.split(' ').where((token) => token.length > 1).toSet();
    final channelTokens = found.split(' ').toSet();
    if (tokens.isNotEmpty && tokens.every(channelTokens.contains)) return 70;
    return 0;
  }

  static List<YoutubeSearchResult> _rankSearchCandidates(
    String query,
    Iterable<YoutubeSearchResult> candidates,
  ) {
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(
          RegExp(r'\b(?:official|audio|video|music|songs?|song|lyrics?|visualizer|channel|latest|terbaru)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final queryTokens = normalize(query)
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toSet();
    if (queryTokens.isEmpty) return candidates.toList(growable: false);

    double score(YoutubeSearchResult video) {
      final titleTokens = normalize(video.title).split(' ').toSet();
      final channelTokens = normalize(video.channelTitle).split(' ').toSet();
      final descriptionTokens = normalize(video.description).split(' ').toSet();
      final identityTokens = <String>{...titleTokens, ...channelTokens};
      final identityCoverage =
          queryTokens.intersection(identityTokens).length / queryTokens.length;
      final titleCoverage =
          queryTokens.intersection(titleTokens).length / queryTokens.length;
      final channelCoverage =
          queryTokens.intersection(channelTokens).length / queryTokens.length;
      final descriptionCoverage = queryTokens
              .intersection(descriptionTokens)
              .length /
          queryTokens.length;
      final views = (video.viewCount ?? 0).clamp(0, 1000000000).toInt();
      // Exact title/artist match stays far ahead; popularity only breaks close
      // ties so a viral unrelated upload cannot outrank the requested track.
      final popularityTieBreak = views <= 0
          ? 0.0
          : (math.log(views + 1) / math.ln10 * 0.55)
              .clamp(0.0, 4.4)
              .toDouble();
      return identityCoverage * 75 +
          titleCoverage * 16 +
          channelCoverage * 8 +
          descriptionCoverage * 1 +
          popularityTieBreak;
    }

    final ranked = candidates.toList(growable: false)
      ..sort((a, b) {
        final byScore = score(b).compareTo(score(a));
        if (byScore != 0) return byScore;
        return (b.viewCount ?? 0).compareTo(a.viewCount ?? 0);
      });
    return ranked;
  }

  Future<List<YoutubeSearchResult>> search(String query) =>
      _search(query, spotifyImportMode: false);

  /// Broader candidate collection exclusively for Spotify import. The normal
  /// manual search still uses query-scoped artist filtering; Spotify import
  /// collects plausible music candidates so its next stage can inspect the
  /// structured Video.musicData credit before deciding whether the performer
  /// really matches. Karaoke, cover, AI, compilation, and duration filters
  /// remain active in both modes.
  Future<List<YoutubeSearchResult>> searchForSpotifyImport(String query) =>
      _search(query, spotifyImportMode: true);

  /// Low-latency Spotify first pass: one relevance page, no popularity page,
  /// and no metadata enrichment. The importer calls the deeper method only
  /// when the first-pass candidates do not contain a corroborated match.
  Future<List<YoutubeSearchResult>> searchForSpotifyImportFast(String query) =>
      _search(
        query,
        spotifyImportMode: true,
        spotifyFastMode: true,
      );

  static bool _matchesStructuredMusicDataQuery(
    String query,
    YoutubeSearchResult video,
  ) {
    final structured = '${video.musicDataArtist} ${video.musicDataTitle}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (structured.isEmpty) return false;

    const ignored = <String>{
      'official', 'audio', 'video', 'music', 'song', 'songs', 'lagu',
      'terbaru', 'latest', 'channel', 'vevo', 'topic', '2024', '2025', '2026',
    };
    final queryTokens = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length > 1 && !ignored.contains(token))
        .toSet();
    if (queryTokens.isEmpty || queryTokens.length > 6) return false;
    final structuredTokens = structured.split(' ').toSet();
    return queryTokens.every(structuredTokens.contains) &&
        YoutubeMusicPolicy.isMusicCandidate(video);
  }

  Future<List<YoutubeSearchResult>> _search(
    String query, {
    required bool spotifyImportMode,
    bool spotifyFastMode = false,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const [];

    bool acceptsCandidate(YoutubeSearchResult video) => spotifyImportMode
        ? YoutubeMusicPolicy.isSpotifyImportCandidate(video)
        : (YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
                video,
                query: keyword,
              ) ||
              _matchesStructuredMusicDataQuery(keyword, video));

    final intent = interpretSearch(keyword);
    final effectiveQuery = intent.apiQuery;
    // Versioned cache separates Spotify's deeper candidate collection from
    // older, shorter/filtered result sets. Raw results are retained so a later
    // matcher improvement does not inherit an already-truncated candidate list.
    final modeKey = spotifyFastMode
        ? 'spotify-fast'
        : (spotifyImportMode ? 'spotify-deep' : 'catalog');
    final cacheKey =
        'explodeSearchV13StagedSpotifyImport|$modeKey|${keyword.toLowerCase()}|${effectiveQuery.toLowerCase()}|${intent.latest ? 'date' : 'relevance'}';
    final resultLimit = spotifyImportMode ? 60 : 30;
    final cached = _cache[cacheKey];

    if (cached != null) {
      final age = DateTime.now().difference(cached.time);
      final ttl = cached.results.isEmpty ? _emptyResultTtl : _cacheTtl;
      if (age < ttl && cached.results.isNotEmpty) {
        debugPrint('EXPLODE SEARCH CACHE HIT (memory): $effectiveQuery');
        return _rankSearchCandidates(
          keyword,
          cached.results.where(acceptsCandidate),
        ).take(resultLimit).toList(growable: false);
      }
    }

    final diskRaw = await _disk.get(
      'q|$cacheKey',
      maxAge: intent.latest ? _latestSearchDiskTtl : _catalogSearchDiskTtl,
    );
    final diskResults = _resultsFromJson(diskRaw);
    // Cache kosong tidak pernah dianggap hasil final: query perlu dicoba lagi.
    if (diskRaw is List && diskResults.isNotEmpty) {
      debugPrint('EXPLODE SEARCH CACHE HIT (disk): $effectiveQuery');
      _putCache(cacheKey, _CacheEntry(DateTime.now(), diskResults));
      return _rankSearchCandidates(
        keyword,
        diskResults.where(acceptsCandidate),
      ).take(resultLimit).toList(growable: false);
    }

    debugPrint('EXPLODE SEARCH NETWORK REQUEST: $effectiveQuery');
    try {
      final sort = intent.latest
          ? ytex.SortFilters.uploadDate
          : ytex.SortFilters.relevance;
      final dynamic firstPage = await _youtubeExplode.search.search(
        effectiveQuery,
        filter: sort,
      );

      final rawResults = <YoutubeSearchResult>[];
      final seenIds = <String>{};
      void appendPage(dynamic sourcePage) {
        if (sourcePage is! Iterable) return;
        for (final item in sourcePage.cast<dynamic>()) {
          final video = _fromExplodeVideo(item);
          if (video.videoId.isNotEmpty && seenIds.add(video.videoId)) {
            rawResults.add(video);
          }
        }
      }

      appendPage(firstPage);
      List<YoutubeSearchResult> accepted() => rawResults
          .where((video) => !video.isLive && !video.isUpcoming)
          .where((video) {
            final seconds = video.durationSeconds;
            if (seconds != null && seconds <= 30) return false;
            return acceptsCandidate(video);
          })
          .toList(growable: false);

      // The first relevance page can be dominated by remixes, fan mirrors, or
      // similarly named songs. Spotify import inspects up to three relevance
      // pages; ordinary search keeps its lighter one-page fallback behavior.
      dynamic pageCursor = firstPage;
      final maxRelevancePages = spotifyFastMode
          ? 1
          : (spotifyImportMode ? 3 : 2);
      for (var pageNumber = 1; pageNumber < maxRelevancePages; pageNumber++) {
        final acceptedCount = accepted().length;
        final enoughCandidates = spotifyImportMode
            ? acceptedCount >= 45
            : acceptedCount >= 12;
        if (enoughCandidates) break;
        try {
          final beforeCount = rawResults.length;
          final dynamic nextPage = await pageCursor.nextPage();
          if (nextPage == null) break;
          appendPage(nextPage);
          pageCursor = nextPage;
          if (rawResults.length == beforeCount) break;
        } catch (paginationError) {
          debugPrint('EXPLODE SEARCH NEXT PAGE SKIPPED: $paginationError');
          break;
        }
      }

      // A second ranking often surfaces original releases from channels that
      // are not the artist's own. Spotify import always inspects one view-count
      // page; view count only adds candidates and never authenticates a match.
      final beforePopular = accepted();
      final hasWidelyViewed = beforePopular.any(
        (video) => (video.viewCount ?? 0) >= 100000,
      );
      if (!spotifyFastMode &&
          !intent.latest &&
          (spotifyImportMode || beforePopular.length < 12 || !hasWidelyViewed)) {
        try {
          final dynamic popularPage = await _youtubeExplode.search.search(
            effectiveQuery,
            filter: ytex.SortFilters.viewCount,
          );
          appendPage(popularPage);
        } catch (popularError) {
          debugPrint('EXPLODE SEARCH VIEW-COUNT FALLBACK SKIPPED: $popularError');
        }
      }

      // Ordinary search can enrich a tiny popular shortlist. Spotify import
      // performs a track-aware detail lookup after combining its query variants.
      if (!spotifyImportMode && !intent.latest && accepted().length < 12) {
        final acceptedIds = accepted().map((video) => video.videoId).toSet();
        final metadataCandidates = rawResults
            .where((video) =>
                !acceptedIds.contains(video.videoId) &&
                (video.viewCount ?? 0) >= 100000 &&
                YoutubeMusicPolicy.isMusicCandidate(video))
            .toList(growable: false);
        // Relevance decides which popular candidates deserve a detail lookup;
        // view count is only a tie-breaker. Otherwise unrelated viral uploads
        // can consume all three metadata slots before the matching track is
        // inspected for its structured YouTube Music artist/title credit.
        final shortlist = _rankSearchCandidates(keyword, metadataCandidates)
            .take(3)
            .toList(growable: false);
        if (shortlist.isNotEmpty) {
          final enriched = await enrichMusicMetadata(shortlist);
          final enrichedById = {
            for (final item in enriched) item.videoId: item,
          };
          for (var index = 0; index < rawResults.length; index++) {
            final replacement = enrichedById[rawResults[index].videoId];
            if (replacement != null) rawResults[index] = replacement;
          }
        }
      }

      final acceptedResults = accepted();
      final results = _rankSearchCandidates(keyword, acceptedResults)
          .take(resultLimit)
          .toList(growable: false);
      if (spotifyImportMode) {
        final acceptedIds = acceptedResults.map((video) => video.videoId).toSet();
        final rejectedSamples = rawResults
            .where((video) => !acceptedIds.contains(video.videoId))
            .take(6)
            .map((video) => '${video.title} [${video.channelTitle}]')
            .join(' | ');
        debugPrint(
          'SPOTIFY SEARCH POOL [$keyword]: raw=${rawResults.length}, '
          'eligible=${acceptedResults.length}, returned=${results.length}, '
          'filteredSamples=${rejectedSamples.isEmpty ? '-' : rejectedSamples}',
        );
      }

      // Persist kandidat mentah, bukan hanya lagu yang lolos policy hari ini.
      // Jangan simpan daftar kosong agar hasil kosong sementara tidak menetap.
      if (rawResults.isNotEmpty) {
        _putCache(cacheKey, _CacheEntry(DateTime.now(), rawResults));
        await _disk.put(
          'q|$cacheKey',
          rawResults.map((video) => video.toJson()).toList(),
        );
      }
      debugPrint(
        'EXPLODE SEARCH RESULT: raw=${rawResults.length}, accepted=${results.length}, query=$effectiveQuery',
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

    final cacheKey = 'channelExplodeV3ArtistTitleAware|${keyword.toLowerCase()}';
    final cached = _channelCache[cacheKey];
    if (cached != null &&
        cached.results.isNotEmpty &&
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
      if (restored.isNotEmpty) {
        _putChannelCache(cacheKey, restored);
        debugPrint('EXPLODE CHANNEL CACHE HIT (disk): $keyword');
        return restored;
      }
      // Hasil channel kosong bisa sementara; jangan jadikan cache final.
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

      final orderedCandidates = candidates.entries.toList()
        ..sort((a, b) => _channelSearchMatchScore(
              _explodeVideoAuthor(b.value), keyword,
            ).compareTo(
              _channelSearchMatchScore(_explodeVideoAuthor(a.value), keyword),
            ));
      final tasks = orderedCandidates.take(12).map((entry) async {
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

      if (channels.isNotEmpty) {
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
      }
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
  // Bukan melanjutkan judul video yang sedang diputar. Radio mengikuti artis,
  // genre, dan bahasa seed; tidak boleh otomatis mengubah semua pencarian
  // menjadi konteks Indonesia karena itu mencampur hasil lagu Barat/lokal.
  //
  // Setiap halaman search.list menghabiskan kuota search. videos.list memakai
  // kuota umum dan dapat mengembalikan detail sampai 50 video per panggilan;
  // hasil radio sengaja di-cache.

  // Shorts bisa sampai 3 menit, sementara Data API tidak memberi flag isShort.
  // Filter lokal memakai label metadata dan durasi untuk membatasi kandidat.
  static const int _radioMinSeconds = 31;
  static const int _radioMaxSeconds =
      YoutubeMusicPolicy.maxStandaloneTrackDurationSeconds;

  Future<RadioPage> searchLatest(
    String query, {
    String? pageToken,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return const RadioPage(results: []);

    final normalized = keyword.toLowerCase();
    // Versi cache berubah karena query Radio sekarang menjaga bahasa seed;
    // hasil lama yang mungkin sudah tercampur konteks Indonesia tidak dipakai.
    final cacheKey =
        'radioExplodeV10TypedSearchMetadata|$normalized|${pageToken ?? ''}';
    final cached = _cache[cacheKey];
    if (cached != null) {
      final age = DateTime.now().difference(cached.time);
      final ttl = cached.results.isEmpty ? _emptyResultTtl : _radioCacheTtl;
      if (age < ttl) {
        final filtered = _rankRadio(_filterAiMusicCandidates(
          _filterNonMusicCandidates(_filterShortFormCandidates(cached.results)),
        ).where(YoutubeMusicPolicy.isMusicCandidate).toList());
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
        ).where(YoutubeMusicPolicy.isMusicCandidate).toList());
        _putCache(cacheKey, _CacheEntry(DateTime.now(), filtered, token));
        return RadioPage(results: filtered, nextPageToken: token);
      }
    }

    final lowerKeyword = keyword.toLowerCase();
    final isSongSimilarityQuery = RegExp(
      r'\b(?:similar songs?|songs? like|similar music)\b',
      caseSensitive: false,
    ).hasMatch(lowerKeyword);
    final alreadyMusicWord = RegExp(
      r'\b(?:lagu|musik|music|songs?|audio|remix|dj|dangdut|pop|rock|jazz|hip\s*hop|kpop|metal|indie|akustik|nostalgia|karaoke|cover|mix|album)\b',
      caseSensitive: false,
    ).hasMatch(lowerKeyword);

    // Artis yang dikenal memberi petunjuk bahasa meski query tidak menulis
    // "English" atau "Indonesia" (misalnya "Billie Eilish pop"). Tambahkan
    // bahasa hasil inferensi, bukan negara default. Jika bahasa tak diketahui,
    // biarkan YouTube relevansi menentukan hasil tanpa bias negara.
    final inferredLanguage = MusicStyleMatcher.languageFromText(keyword);
    final explicitLanguage = MusicStyleMatcher.hasExplicitLanguageHint(keyword);
    final languageQualifier = explicitLanguage
        ? null
        : switch (inferredLanguage) {
            'english' => 'English',
            'indonesian' => 'Indonesia',
            'korean' => 'Korean',
            'japanese' => 'Japanese',
            'spanish' => 'Spanish',
            'hindi' => 'Hindi',
            'arabic' => 'Arabic',
            'thai' => 'Thai',
            'mandarin' => 'Mandarin',
            'javanese' => 'Javanese',
            'sundanese' => 'Sundanese',
            _ => null,
          };
    final songQualifier = switch (inferredLanguage) {
      'indonesian' || 'javanese' || 'sundanese' => 'lagu',
      _ => 'song',
    };
    final radioKeyword = [
      keyword,
      if (!alreadyMusicWord && !isSongSimilarityQuery) songQualifier,
      ?languageQualifier,
    ].join(' ');
    // Jangan menambahkan kata 'official' secara paksa: banyak single asli dari
    // channel artis/label independen tidak memakai marker itu di YouTube.
    final radioSearchQuery = radioKeyword;
    final pageSourceKey = radioSearchQuery.toLowerCase();

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
          radioSearchQuery,
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
      final relevancePageCount = rawItems.length;
      final seenRadioIds = <String>{
        for (final dynamic item in rawItems)
          _fromExplodeVideo(item).videoId,
      };

      List<YoutubeSearchResult> parseRadioItems() => rawItems
          .map(_fromExplodeVideo)
          .where((video) => video.videoId.isNotEmpty)
          .where((video) {
            if (video.isLive || video.isUpcoming) return false;
            final seconds = video.durationSeconds;
            if (seconds == null) return true;
            return seconds >= _radioMinSeconds && seconds <= _radioMaxSeconds;
          })
          .toList(growable: false);

      var results = parseRadioItems();
      // Radio normally follows relatedness/relevance. If that page is mostly
      // filtered or lacks any popular match, add a single view-sorted page as
      // a fallback pool. Keep the relevance page's pagination cursor intact.
      if (requestedPage == 1 &&
          (results.where(YoutubeMusicPolicy.isMusicCandidate).length < 8 ||
              results.every((video) => (video.viewCount ?? 0) < 100000))) {
        try {
          final dynamic popularPage = await _youtubeExplode.search.search(
            radioSearchQuery,
            filter: ytex.SortFilters.viewCount,
          );
          if (popularPage is Iterable) {
            for (final dynamic item in popularPage.cast<dynamic>()) {
              final candidate = _fromExplodeVideo(item);
              if (candidate.videoId.isNotEmpty &&
                  seenRadioIds.add(candidate.videoId)) {
                rawItems.add(item);
              }
            }
          }
          results = parseRadioItems();
        } catch (popularError) {
          debugPrint('EXPLODE RADIO VIEW-COUNT FALLBACK SKIPPED: $popularError');
        }
      }

      results = _filterShortFormCandidates(results);
      results = await removeShorts(results);
      results = _filterNonMusicCandidates(results);
      results = _filterAiMusicCandidates(results);
      results = results
          .where(YoutubeMusicPolicy.isMusicCandidate)
          .toList(growable: false);
      results = _rankRadio(results);

      final nextToken = relevancePageCount >= 20 && page != null
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
      // JANGAN di-cache: satu error sesaat (jaringan / parsing) sebelumnya
      // tersimpan sebagai "kosong" selama 30 menit, sehingga setiap Next untuk
      // seed yang sama ikut gagal menemukan lagu sampai cache itu kedaluwarsa.
      // Sumber halaman juga dibuang supaya percobaan berikutnya mulai bersih.
      _radioExplodePageSources.remove(pageSourceKey);
      _radioExplodePageNumbers.remove(pageSourceKey);
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
    final cacheKey = 'mostPopularMusicPolicyV8|$musicCategoryId';
    final cached = _cache[cacheKey];
    if (cached != null) {
      final age = DateTime.now().difference(cached.time);
      if (age < _feedTtl || (force && age < _forcedFeedRefreshFloor)) {
        return cached.results
            .where(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate)
            .take(maxResults)
            .toList(growable: false);
      }
    }
    if (!force) {
      final diskHit = await _disk.get(cacheKey, maxAge: _feedTtl);
      final fromDisk = _resultsFromJson(diskHit);
      if (diskHit is List && (diskHit.isEmpty || fromDisk.isNotEmpty)) {
        final officialFromDisk = fromDisk
            .where(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate)
            .toList(growable: false);
        _putCache(cacheKey, _CacheEntry(DateTime.now(), officialFromDisk));
        return officialFromDisk.take(maxResults).toList(growable: false);
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
    final results = parsed
        .where(isMusicCatalogItem)
        .where(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate)
        .toList(growable: false);

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

    const cacheKey = 'recentMusicPolicyV10SingleTrackOnly';
    final cached = _cache[cacheKey];
    if (cached != null) {
      final age = DateTime.now().difference(cached.time);
      if (age < _feedTtl || (force && age < _forcedFeedRefreshFloor)) {
        return cached.results
            .where(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate)
            .take(maxResults)
            .toList(growable: false);
      }
    }
    if (!force) {
      final diskHit = await _disk.get(cacheKey, maxAge: _feedTtl);
      final fromDisk = _resultsFromJson(diskHit);
      if (diskHit is List && (diskHit.isEmpty || fromDisk.isNotEmpty)) {
        final officialFromDisk = fromDisk
            .where(YoutubeMusicPolicy.isOfficialMusicReleaseCandidate)
            .toList(growable: false);
        _putCache(cacheKey, _CacheEntry(DateTime.now(), officialFromDisk));
        return officialFromDisk.take(maxResults).toList(growable: false);
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

  /// Resource videos.list -> model; buang durasi sangat pendek di parser.
  /// Penyaringan Shorts tanpa hashtag dan video pendek non-musik ada di policy.
  List<YoutubeSearchResult> _parseVideoResources(List items) =>
      YoutubeSearchResponseParser.parseVideoResources(items);

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

  static bool isLikelyUnofficialMusicVersion(YoutubeSearchResult video) =>
      YoutubeMusicPolicy.isLikelyUnofficialMusicVersion(video);

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