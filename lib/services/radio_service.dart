import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/youtube_search_result.dart';
import 'channel_block_filter.dart';
import 'music_style_matcher.dart';
import 'youtube_search_service.dart';

/// Autoplay / "radio": menyiapkan lagu terbaru yang masih relevan dengan kata kunci
/// supaya tombol Next dan auto-next tetap punya lagu berikutnya.
class RadioService {
  RadioService(
    this._searchService, {
    required this.currentVideoId,
    Set<String> Function()? blockedIds,
    Set<String> Function()? blockedChannelKeys,
    this.onError,
  })  : _blockedIds = blockedIds ?? (() => <String>{}),
        _blockedChannelKeys = blockedChannelKeys ?? (() => <String>{});

  final YoutubeSearchService _searchService;
  final String? Function() currentVideoId;
  final Set<String> Function() _blockedIds;
  final Set<String> Function() _blockedChannelKeys;
  final void Function(String message)? onError;

  final math.Random _random = math.Random();

  String _seed = '';
  String? _preferredLanguage;
  bool _lockLanguage = false;
  final List<YoutubeSearchResult> _pool = [];
  String? _pageToken;
  Future<void>? _fetch;
  DateTime? _lastRefillStartedAt;
  static const Duration _minimumRefillInterval = Duration(seconds: 20);
  bool _disposed = false;
  // Incremented whenever the radio context is reset so an older request cannot
  // populate a new pool or clear the handle for a newer in-flight request.
  int _fetchGeneration = 0;

  /// Video yang sudah diputar sesi ini, supaya autoplay tidak mengulang ID yang sama.
  final List<String> _playedIds = <String>[];

  /// Track-family keys yang sudah diputar. Satu video bisa menghasilkan
  /// beberapa key (misalnya judul inti + variasi judul) agar cover/reupload
  /// oleh vokalis/channel berbeda tetap dianggap lagu yang sama.
  final List<String> _playedTrackKeys = <String>[];

  // Selection cooldown agar auto-next tidak mengambil judul/artist yang sama
  // berulang walaupun kandidat tersebut punya view paling tinggi.
  final List<String> _recentSelectionTrackKeys = <String>[];
  final List<String> _recentSelectionArtists = <String>[];

  static const int _maxPlayedIds = 1000;
  static const int _maxPlayedTrackKeys = 1200;
  static const int _selectionCooldownTracks = 10;
  static const int _selectionCooldownArtists = 5;

  bool get hasSeed => _seed.isNotEmpty;

  String get seed => _seed;

  /// Explicit-language searches stay in that language. Track Radio can cross.
  bool get locksLanguage => _lockLanguage;

  bool get isPoolEmpty => _pool.isEmpty;

  int get poolLength => _pool.length;

  /// Mulai (atau lanjutkan) radio dengan kata kunci [seed].
  void start(
    String seed, {
    String? preferredLanguage,
    bool lockLanguage = false,
  }) {
    final normalized = seed.trim();

    if (normalized.isEmpty) {
      return;
    }

    final changed = normalized.toLowerCase() != _seed.toLowerCase() ||
        preferredLanguage != _preferredLanguage ||
        lockLanguage != _lockLanguage;
    if (changed) {
      _fetchGeneration++;
      _seed = normalized;
      _pool.clear();
      _pageToken = null;
      _fetch = null;
      _lastRefillStartedAt = null;
    }
    _seed = normalized;
    _preferredLanguage = preferredLanguage ?? MusicStyleMatcher.languageFromText(normalized);
    _lockLanguage = lockLanguage;

    // Siapkan lagu berikutnya di belakang layar supaya Next terasa instan.
    if (_pool.isEmpty) {
      unawaited(refill());
    }
  }

  /// Paksa radio mulai ulang dari seed yang sama. Dipakai sebagai fallback
  /// ketika semua hasil halaman/cache lama habis atau terlalu banyak terfilter.
  void restart(String seed, {bool? lockLanguage}) {
    final normalized = seed.trim();
    if (normalized.isEmpty) {
      return;
    }

    _fetchGeneration++;
    _seed = normalized;
    _preferredLanguage ??= MusicStyleMatcher.languageFromText(normalized);
    if (lockLanguage != null) _lockLanguage = lockLanguage;
    _pool.clear();
    _pageToken = null;
    _fetch = null;
    _lastRefillStartedAt = null;
  }

  /// Isi ulang pool. Kalau sedang berjalan, pemanggil ikut menunggu yang sama.
  Future<void> refill() {
    if (_disposed) return Future<void>.value();

    final running = _fetch;
    if (running != null) {
      return running;
    }

    // Jangan meminta halaman baru berkali-kali saat pengguna menekan Next
    // beruntun dan semua kandidat lama tersaring. Pool lokal/fallback tetap
    // dipakai; request berikutnya baru boleh dimulai setelah jeda singkat.
    final now = DateTime.now();
    final lastStarted = _lastRefillStartedAt;
    if (lastStarted != null && now.difference(lastStarted) < _minimumRefillInterval) {
      return Future<void>.value();
    }
    _lastRefillStartedAt = now;

    final generation = _fetchGeneration;
    late final Future<void> future;
    future = _fetchPage(generation).whenComplete(() {
      // A fetch invalidated by restart may finish after a newer fetch starts.
      // It must never clear the newer fetch's in-flight handle.
      if (identical(_fetch, future)) {
        _fetch = null;
      }
    });

    _fetch = future;
    return future;
  }

  /// Ambil satu lagu secara berbobot. Dipakai Shuffle Pintar supaya radio
  /// tetap acak tetapi juga menghindari judul/artist yang baru diputar.
  YoutubeSearchResult? takeSmart({required double Function(YoutubeSearchResult) score}) {
    final targetStyle = MusicStyleMatcher.styleFromText(_seed);
    final targetLanguage = _preferredLanguage ?? MusicStyleMatcher.languageFromText(_seed);
    _pool.removeWhere((video) =>
        _blockedIds().contains(video.videoId) ||
        ChannelBlockFilter.isBlocked(video, _blockedChannelKeys()) ||
        !MusicStyleMatcher.isCompatible(
          video: video,
          targetStyle: targetStyle,
          targetLanguage: targetLanguage,
          allowCrossLanguage: !_lockLanguage,
        ));

    if (_pool.isEmpty) {
      return null;
    }

    final candidatesPool = MusicStyleMatcher.rankForRadio(
      _pool,
      targetStyle: targetStyle,
      targetLanguage: targetLanguage,
      allowCrossLanguage: !_lockLanguage,
    );
    final scored = candidatesPool
        .map((video) {
          final key = trackKeyFor(video);
          final artist = _artistKey(video);
          var value = score(video);
          if (key.isNotEmpty && _recentSelectionTrackKeys.contains(key)) {
            value -= 80.0;
          }
          if (artist.isNotEmpty && _recentSelectionArtists.contains(artist)) {
            value -= 24.0;
          }
          if (artist.isNotEmpty &&
              _recentSelectionArtists.isNotEmpty &&
              artist == _recentSelectionArtists.last) {
            value -= 36.0;
          }
          value += MusicStyleMatcher.radioSimilarityScore(
                video: video,
                targetStyle: targetStyle,
                targetLanguage: targetLanguage,
              ) * 0.35;
          value += _random.nextDouble() * 3.5;
          return (video: video, score: value);
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final topCount = scored.length < 20 ? scored.length : 20;
    final candidates = scored.take(topCount).map((item) => item.video).toList();

    // Pilih acak dari kumpulan kandidat bagus yang lebih beragam.
    // Track/artist yang baru muncul tetap sudah diberi penalti.
    final selected = candidates[_random.nextInt(candidates.length)];
    _pool.removeWhere((video) => video.videoId == selected.videoId);
    _rememberSelection(selected);
    return selected;
  }

  /// Ambil satu lagu dari pool.
  /// Radio biasa memilih secara acak berbobot: lagu dengan gaya yang cocok dan
  /// cukup populer lebih mungkin terpilih, tetapi urutannya tidak dikunci ke
  /// kandidat teratas. Shuffle aktif tetap memilih secara acak merata.
  YoutubeSearchResult? take({required bool random}) {
    final targetStyle = MusicStyleMatcher.styleFromText(_seed);
    final targetLanguage = _preferredLanguage ?? MusicStyleMatcher.languageFromText(_seed);
    _pool.removeWhere((video) =>
        _blockedIds().contains(video.videoId) ||
        ChannelBlockFilter.isBlocked(video, _blockedChannelKeys()) ||
        !MusicStyleMatcher.isCompatible(
          video: video,
          targetStyle: targetStyle,
          targetLanguage: targetLanguage,
          allowCrossLanguage: !_lockLanguage,
        ));

    if (_pool.isEmpty) return null;

    final candidates = MusicStyleMatcher.rankForRadio(
      _pool,
      targetStyle: targetStyle,
      targetLanguage: targetLanguage,
      allowCrossLanguage: !_lockLanguage,
    );
    if (candidates.isEmpty) return null;

    // Utamakan lagu yang belum baru dipilih dan artis berbeda dari pilihan
    // sebelumnya. Kalau kandidat terlalu sedikit, longgarkan aturan artis.
    final fresh = candidates.where((video) => !_recentlySelected(video)).toList();
    final currentArtist = _recentSelectionArtists.isEmpty
        ? ''
        : _recentSelectionArtists.last;
    final diverse = fresh.where((video) {
      final artist = _artistKey(video);
      return currentArtist.isEmpty || artist.isEmpty || artist != currentArtist;
    }).toList();
    final source = diverse.isNotEmpty
        ? diverse
        : (fresh.isNotEmpty ? fresh : candidates);

    final selected = random
        ? source[_random.nextInt(source.length)]
        : _weightedRadioPick(
            source,
            targetStyle: targetStyle,
            targetLanguage: targetLanguage,
          );

    _pool.removeWhere((video) => video.videoId == selected.videoId);
    _rememberSelection(selected);
    return selected;
  }

  /// Pengambilan acak berbobot, bukan sort lalu selalu memilih dari 5 lagu
  /// teratas. Gaya yang sama mendapat bobot terbesar; subgenre terkait masih
  /// berpeluang terpilih. Bahasa hanya bonus kecil selama bukan filter eksplisit.
  YoutubeSearchResult _weightedRadioPick(
    List<YoutubeSearchResult> candidates, {
    required String? targetStyle,
    required String? targetLanguage,
  }) {
    if (candidates.length == 1) return candidates.single;

    final scored = candidates.map((video) {
      var score = MusicStyleMatcher.radioSimilarityScore(
        video: video,
        targetStyle: targetStyle,
        targetLanguage: targetLanguage,
      );
      final artist = _artistKey(video);
      if (artist.isNotEmpty && _recentSelectionArtists.contains(artist)) {
        score -= 8.0;
      }
      if (artist.isNotEmpty &&
          _recentSelectionArtists.isNotEmpty &&
          artist == _recentSelectionArtists.last) {
        score -= 18.0;
      }
      // Jitter kecil membuat urutan kandidat dengan nilai serupa ikut berubah.
      score += _random.nextDouble() * 6.0;
      return (video: video, score: score);
    }).toList();

    final maxScore = scored
        .map((item) => item.score)
        .reduce((a, b) => a > b ? a : b);
    final weights = scored.map((item) {
      final relative = ((item.score - maxScore) / 12.0)
          .clamp(-6.0, 0.0)
          .toDouble();
      return math.exp(relative);
    }).toList();
    final totalWeight = weights.fold<double>(0.0, (sum, weight) => sum + weight);
    var roll = _random.nextDouble() * totalWeight;
    for (var i = 0; i < scored.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return scored[i].video;
    }
    return scored.last.video;
  }

  bool _recentlySelected(YoutubeSearchResult video) {
    final key = trackKeyFor(video);
    return key.isNotEmpty && _recentSelectionTrackKeys.contains(key);
  }

  static String _artistKey(YoutubeSearchResult video) {
    return normalizePhrase(
      video.channelTitle
          .replaceAll(RegExp(r'\b(?:official|artist|channel|topic|vevo)\b', caseSensitive: false), ' ')
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim(),
    );
  }

  void _rememberSelection(YoutubeSearchResult video) {
    final key = trackKeyFor(video);
    final artist = _artistKey(video);

    if (key.isNotEmpty) {
      _recentSelectionTrackKeys.remove(key);
      _recentSelectionTrackKeys.add(key);
      if (_recentSelectionTrackKeys.length > _selectionCooldownTracks) {
        _recentSelectionTrackKeys.removeRange(
          0,
          _recentSelectionTrackKeys.length - _selectionCooldownTracks,
        );
      }
    }

    if (artist.isNotEmpty) {
      _recentSelectionArtists.remove(artist);
      _recentSelectionArtists.add(artist);
      if (_recentSelectionArtists.length > _selectionCooldownArtists) {
        _recentSelectionArtists.removeRange(
          0,
          _recentSelectionArtists.length - _selectionCooldownArtists,
        );
      }
    }
  }

  /// Catat lagu yang diputar agar tidak muncul lagi di radio.
  /// Selain videoId, simpan fingerprint judul supaya cover/reupload/penyanyi
  /// berbeda dari lagu yang sama tetap dianggap track yang sama.
  void markPlayed(YoutubeSearchResult video) {
    final videoId = video.videoId.trim();
    if (videoId.isEmpty) {
      return;
    }

    _playedIds.remove(videoId);
    _playedIds.add(videoId);

    for (final key in trackKeysFor(video)) {
      _playedTrackKeys.remove(key);
      _playedTrackKeys.add(key);
    }

    if (_playedIds.length > _maxPlayedIds) {
      _playedIds.removeRange(0, _playedIds.length - _maxPlayedIds);
    }
    if (_playedTrackKeys.length > _maxPlayedTrackKeys) {
      _playedTrackKeys.removeRange(0, _playedTrackKeys.length - _maxPlayedTrackKeys);
    }
  }

  /// Normalisasi teks untuk membandingkan judul/query tanpa mempedulikan
  /// kapitalisasi dan tanda baca.
  static String normalizePhrase(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _cleanTitle(String raw) {
    var title = raw.toLowerCase();

    title = title
        .replaceAll(RegExp(r'https?://\S+'), ' ')
        .replaceAll(
          RegExp(
            r'\((?:(?:official|music\s*video|official\s*audio|official\s*video|lyrics?|lyric\s*video|visualizer|topic|4k|hd|full\s*hd|live|performance|mv|cover|versi|version|vocal|vocals|singer)[^)]*)\)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\[(?:(?:official|music\s*video|official\s*audio|official\s*video|lyrics?|lyric\s*video|visualizer|topic|4k|hd|full\s*hd|live|performance|mv|cover|versi|version|vocal|vocals|singer)[^\]]*)\]',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(?:official\s+music\s+video|official\s+video|official\s+audio|music\s+video|lyric\s+video|official\s+lyric\s+video|visualizer|lyrics?|audio|topic|4k|full\s*hd|hd|live|performance|mv|cover|cover\s+version|versi\s+(?:cover|vocal)|version|vocal|vocals|singer|karaoke|instrumental|remix|remastered|remaster|radio\s+edit|extended\s+mix|official\s+visualizer)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'\s+(?:ft\.?|feat\.?|featuring)\s+[^|\-â€“â€”]+$', caseSensitive: false),
          ' ',
        );

    return title
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s_-]+|[\s_-]+$'), '')
        .trim();
  }

  static Set<String> trackKeysFor(YoutubeSearchResult video) {
    final title = _cleanTitle(video.title);
    final channel = normalizePhrase(
      video.channelTitle
          .replaceAll(RegExp(r'\s*[-|]\s*'), ' ')
          .replaceAll(
            RegExp(r'\b(?:official|artist|channel|topic|vevo)\b', caseSensitive: false),
            ' ',
          )
          .replaceAll(RegExp(r'\s+'), ' '),
    );

    if (title.isEmpty) {
      return <String>{};
    }

    final rawParts = title
        .split(RegExp(r'\s*[-â€“â€”|â€¢:]\s*'))
        .map(normalizePhrase)
        .where((part) => part.length >= 3)
        .toList();

    bool looksLikeChannel(String part) {
      if (part.isEmpty || channel.isEmpty) return false;
      if (part == channel) return true;

      final partWords = part.split(' ').where((w) => w.length >= 3).toSet();
      final channelWords = channel.split(' ').where((w) => w.length >= 3).toSet();
      if (partWords.isEmpty || channelWords.isEmpty) return false;

      final overlap = partWords.intersection(channelWords).length;
      final ratio = overlap / partWords.length;
      return ratio >= 0.75 || (partWords.length == 1 && overlap == 1);
    }

    final keys = <String>{};

    // Judul utuh setelah nama channel dibuang.
    var withoutChannel = title;
    if (channel.isNotEmpty) {
      withoutChannel = withoutChannel.replaceAll(channel, ' ');
    }
    withoutChannel = normalizePhrase(withoutChannel);
    if (withoutChannel.length >= 3) {
      keys.add(withoutChannel);
    }

    // Tangkap judul inti baik formatnya "Judul - Artis" maupun
    // "Artis - Judul".
    final usefulParts = rawParts.where((part) => !looksLikeChannel(part)).toList();
    for (final part in usefulParts) {
      if (part.length >= 4 && part.split(' ').length <= 8) {
        keys.add(part);
      }
    }

    // Jangan jadikan istilah generik sebagai fingerprint.
    keys.removeWhere(
      (key) => <String>{
        'lagu',
        'musik',
        'song',
        'audio',
        'video',
        'official',
        'remix',
        'cover',
        'live',
        'karaoke',
        'mix',
        'indonesia',
        'terbaru',
      }.contains(key),
    );

    return keys;
  }

  static String trackKeyFor(YoutubeSearchResult video) {
    final keys = trackKeysFor(video);
    if (keys.isEmpty) return '';

    final sorted = keys.toList()
      ..sort((a, b) {
        final wordCount = a.split(' ').length.compareTo(b.split(' ').length);
        if (wordCount != 0) return wordCount;
        return a.length.compareTo(b.length);
      });

    return sorted.first;
  }

  static bool isSameTrackFamily(
    YoutubeSearchResult a,
    YoutubeSearchResult b,
  ) {
    if (a.videoId == b.videoId) return true;
    return trackKeysFor(a).intersection(trackKeysFor(b)).isNotEmpty;
  }

  static bool queryLooksLikeCurrentTrack(
    String query,
    YoutubeSearchResult current,
  ) {
    final normalizedQuery = normalizePhrase(query);
    if (normalizedQuery.length < 3) return false;

    final keys = trackKeysFor(current);

    if (keys.contains(normalizedQuery)) return true;

    for (final key in keys) {
      if (normalizedQuery == key ||
          normalizedQuery.contains(key) ||
          key.contains(normalizedQuery)) {
        return true;
      }
    }

    final queryWords = normalizedQuery
        .split(' ')
        .where((word) => word.length >= 3)
        .toSet();
    if (queryWords.isEmpty) return false;

    for (final key in keys) {
      final keyWords = key
          .split(' ')
          .where((word) => word.length >= 3)
          .toSet();
      if (keyWords.isEmpty) continue;

      final overlap = queryWords.intersection(keyWords).length;
      if (overlap / queryWords.length >= 0.75) {
        return true;
      }
    }

    return false;
  }

  void dispose() {
    _disposed = true;
    _fetchGeneration++;
    _fetch = null;
    _pool.clear();
  }

  Future<void> _fetchPage(int generation) async {
    final seed = _seed;
    if (_disposed || seed.isEmpty) return;

    final targetStyle = MusicStyleMatcher.styleFromText(seed);
    final targetLanguage = _preferredLanguage ?? MusicStyleMatcher.languageFromText(seed);

    bool isCurrentRequest() =>
        !_disposed && generation == _fetchGeneration && seed == _seed;

    bool eligible(YoutubeSearchResult video, {bool enforceContext = true}) {
      if (video.videoId.isEmpty ||
          video.videoId == currentVideoId() ||
          video.isLive ||
          video.isUpcoming ||
          _playedIds.contains(video.videoId) ||
          _blockedIds().contains(video.videoId) ||
          ChannelBlockFilter.isBlocked(video, _blockedChannelKeys()) ||
          YoutubeSearchService.isLikelyShortForm(video) ||
          YoutubeSearchService.isLikelyNonMusicVideo(video)) {
        return false;
      }

      final candidateKeys = trackKeysFor(video);
      if (candidateKeys.isEmpty || candidateKeys.any(_playedTrackKeys.contains)) {
        return false;
      }
      if (_pool.any((pooled) =>
          pooled.videoId == video.videoId ||
          trackKeysFor(pooled).any(candidateKeys.contains))) {
        return false;
      }

      if (!enforceContext) return true;
      return MusicStyleMatcher.isCompatible(
        video: video,
        targetStyle: targetStyle,
        targetLanguage: targetLanguage,
        allowCrossLanguage: !_lockLanguage,
      );
    }

    void addCandidates(
      Iterable<YoutubeSearchResult> videos, {
      bool enforceContext = true,
    }) {
      for (final video in videos) {
        if (!eligible(video, enforceContext: enforceContext)) continue;
        _pool.add(video);
      }
    }

    // Prioritas pertama adalah katalog musik populer yang dapat digunakan ulang
    // dari cache (videos.list, kuota umum), bukan Search API setiap kali Next.
    // Jika kandidat satu bahasa/genre tersedia, antrean diisi dari sini dulu.
    try {
      final popular = await _searchService.mostPopular(
        categoryId: '10',
        maxResults: 50,
      );
      if (!isCurrentRequest()) return;

      final scoped = popular.where((video) => eligible(video)).toList();
      final preferred = MusicStyleMatcher.rankForRadio(
        scoped,
        targetStyle: targetStyle,
        targetLanguage: targetLanguage,
        allowCrossLanguage: !_lockLanguage,
      );
      // Keep a generous candidate pool so subsequent Next presses can produce
      // variety across languages without issuing a new search on each click.
      addCandidates((preferred.isNotEmpty ? preferred : scoped).take(40));

      // Kalau chart lokal tidak punya style yang cocok, coba genre/subgenre
      // berdekatan dari chart yang sama; Radio boleh lintas bahasa.
      if (_pool.isEmpty && targetStyle != null && !_lockLanguage) {
        final relatedAcrossLanguages = popular.where((video) {
          if (!eligible(video, enforceContext: false)) return false;
          final candidateStyle = MusicStyleMatcher.styleFromVideo(video);
          return candidateStyle == null ||
              MusicStyleMatcher.isRelatedStyle(candidateStyle, targetStyle);
        }).toList();
        final relatedPreferred = MusicStyleMatcher.prioritizeStyle(
          relatedAcrossLanguages,
          targetStyle,
        );
        addCandidates(
          relatedPreferred.isNotEmpty ? relatedPreferred : relatedAcrossLanguages,
          enforceContext: false,
        );
      }

      // Terakhir, bila katalog kategori Musik tidak punya kandidat yang cukup
      // relevan, gunakan lagu populer lain supaya Next tidak langsung berhenti.
      if (_pool.isEmpty) {
        // Broad fallback may relax genre, but it must not bypass an explicit
        // language request. Unknown language metadata is allowed as a fallback.
        addCandidates(
          popular.where((video) {
            if (!eligible(video, enforceContext: false)) return false;
            if (!_lockLanguage || targetLanguage == null) return true;
            final language = MusicStyleMatcher.languageFromVideo(video);
            return language == null || language == targetLanguage;
          }),
          enforceContext: false,
        );
      }

      if (_pool.isNotEmpty) return;
    } catch (e) {
      // Katalog populer gagal/offline? Search API tetap tersedia sebagai fallback.
      debugPrint('RADIO POPULAR CATALOG: $e');
    }

    if (!isCurrentRequest()) return;

    // Fallback terakhir: satu halaman Search API. Tidak ada pengulangan halaman
    // di satu tindakan Next; searchLatest punya cache hasil agar query yang sama
    // dapat dipakai ulang selama masa cache.
    try {
      final page = await _searchService.searchLatest(seed, pageToken: _pageToken);
      if (!isCurrentRequest()) return;
      _pageToken = page.nextPageToken;

      final newCandidates = page.results.where((video) => eligible(video)).toList();
      final preferred = MusicStyleMatcher.rankForRadio(
        newCandidates,
        targetStyle: targetStyle,
        targetLanguage: targetLanguage,
        allowCrossLanguage: !_lockLanguage,
      );
      addCandidates(preferred.isNotEmpty ? preferred : newCandidates);

      if (_pool.isEmpty && page.nextPageToken == null) {
        // Ketika semua halaman telah habis, lupakan hanya bagian history yang
        // paling lama agar radio dapat bersiklus kembali tanpa cepat mengulang.
        final current = currentVideoId();
        if (current != null) _playedIds.remove(current);
        final keepIds = (_playedIds.length / 2).ceil();
        if (_playedIds.length > keepIds) {
          _playedIds.removeRange(0, _playedIds.length - keepIds);
        }
        final keepKeys = (_playedTrackKeys.length / 2).ceil();
        if (_playedTrackKeys.length > keepKeys) {
          _playedTrackKeys.removeRange(0, _playedTrackKeys.length - keepKeys);
        }
        if (current != null && !_playedIds.contains(current)) _playedIds.add(current);
        _pageToken = null;
      }
    } catch (e) {
      if (!isCurrentRequest()) return;
      debugPrint('RADIO ERROR: $e');
      _pageToken = null;
      if (e is YoutubeSearchException) onError?.call(e.message);
    }
  }

  /// Nama artis / kata kunci dari sebuah lagu, dipakai sebagai benih radio
  /// saat playlist favorit habis.
  static String seedFor(YoutubeSearchResult video) {
    // Recomendasi berasal dari genre dan bahasa yang terdeteksi. Jangan selalu
    // mengunci ke channel artis yang sedang diputar.
    return MusicStyleMatcher.recommendationSeedFor(video);
  }

}

