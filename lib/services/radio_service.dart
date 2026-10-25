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

  /// Track-family keys yang sudah diputar. Fingerprint judul dinormalisasi
  /// tanpa memecah tanda hubung internal seperti Hati-Hati.
  final List<String> _playedTrackKeys = <String>[];
  final List<YoutubeSearchResult> _playedVideos = <YoutubeSearchResult>[];

  // Selection cooldown agar auto-next tidak mengulang judul/artis yang sama
  // walaupun API mengembalikan upload atau kandidat serupa berulang kali.
  final List<String> _recentSelectionTrackKeys = <String>[];
  final List<YoutubeSearchResult> _recentSelectionVideos = <YoutubeSearchResult>[];
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

    // Hindari request search.list beruntun ketika pengguna menekan Next cepat.
    // Jika tidak ada kandidat terkait, jangan mengambil chart populer sebagai
    // pengganti; pencarian berikutnya hanya memakai halaman query yang relevan.
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
        video.videoId == currentVideoId() ||
        wasPlayedRecently(video) ||
        _recentlySelected(video) ||
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

    final rankedPool = MusicStyleMatcher.rankForRadio(
      _pool,
      targetStyle: targetStyle,
      targetLanguage: targetLanguage,
      allowCrossLanguage: !_lockLanguage,
    );
    // Different YouTube IDs can be duplicate uploads of the same track. Do
    // not make recently selected tracks eligible again merely because all
    // alternatives have a lower score.
    final candidatesPool = rankedPool
        .where((video) => !_recentlySelected(video))
        .toList(growable: false);
    if (candidatesPool.isEmpty) return null;
    final currentArtist = _recentSelectionArtists.isEmpty
        ? ''
        : _recentSelectionArtists.last;
    final differentArtists = candidatesPool.where((video) {
      final artist = _artistKey(video);
      return currentArtist.isEmpty || artist.isEmpty || artist != currentArtist;
    }).toList(growable: false);
    final sourcePool = differentArtists.isNotEmpty ? differentArtists : candidatesPool;
    final scored = sourcePool
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
    if (candidates.isEmpty) return null;

    // Random di antara kandidat yang belum dipilih dan dengan variasi artis.
    final selected = candidates[_random.nextInt(candidates.length)];
    _removeTrackFamilyFromPool(selected);
    _rememberSelection(selected);
    return selected;
  }

  /// Ambil satu lagu dari pool.
  /// Radio memilih secara berbobot dari kandidat yang relevan dengan seed dan
  /// gaya musik aktif. Popularitas/view count tidak menjadi faktor pemilihan.
  /// Shuffle aktif tetap memilih secara acak merata dari pool terkait.
  YoutubeSearchResult? take({required bool random}) {
    final targetStyle = MusicStyleMatcher.styleFromText(_seed);
    final targetLanguage = _preferredLanguage ?? MusicStyleMatcher.languageFromText(_seed);
    _pool.removeWhere((video) =>
        video.videoId == currentVideoId() ||
        wasPlayedRecently(video) ||
        _recentlySelected(video) ||
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
    // Never fall back to [candidates] when [fresh] is empty. That fallback
    // reintroduced recently selected tracks and made Radio feel repetitive.
    final source = diverse.isNotEmpty ? diverse : fresh;
    if (source.isEmpty) return null;

    final selected = random
        ? source[_random.nextInt(source.length)]
        : _weightedRadioPick(
            source,
            targetStyle: targetStyle,
            targetLanguage: targetLanguage,
          );

    _removeTrackFamilyFromPool(selected);
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
    if (_recentSelectionVideos.any((selected) => isSameTrackFamily(selected, video))) {
      return true;
    }
    final keys = trackKeysFor(video);
    return keys.isNotEmpty && keys.any(_recentSelectionTrackKeys.contains);
  }

  /// Remove every cached upload belonging to the same normalized song family.
  /// Different singers/cover channels must not make the same song eligible again.
  void _removeTrackFamilyFromPool(YoutubeSearchResult selected) {
    _pool.removeWhere((candidate) => isSameTrackFamily(candidate, selected));
  }

  static String _artistKey(YoutubeSearchResult video) {
    final withoutChannelSuffix = video.channelTitle.replaceAll(
      RegExp(r'\b(?:official|artist|channel|topic|vevo|covers?)\b', caseSensitive: false),
      ' ',
    );
    return normalizePhrase(withoutChannelSuffix);
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

    _recentSelectionVideos.removeWhere((item) => isSameTrackFamily(item, video));
    _recentSelectionVideos.add(video);
    if (_recentSelectionVideos.length > _selectionCooldownTracks) {
      _recentSelectionVideos.removeRange(
        0,
        _recentSelectionVideos.length - _selectionCooldownTracks,
      );
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

  /// True jika ID atau keluarga judul lagu sudah diputar dalam sesi terbaru.
  /// Bandingkan video yang sudah diputar juga, bukan hanya exact ID, supaya
  /// variasi judul/cover tidak lolos karena metadata penyanyinya berbeda.
  bool wasPlayedRecently(YoutubeSearchResult video) {
    final id = video.videoId.trim();
    if (id.isEmpty) return false;
    if (_playedIds.contains(id)) return true;
    if (_playedVideos.any((played) => isSameTrackFamily(played, video))) return true;
    final keys = trackKeysFor(video);
    return keys.isNotEmpty && keys.any(_playedTrackKeys.contains);
  }

  /// Return only unique, never-played candidates. This is deliberately stricter
  /// than a UI history list: fallback catalogues must not re-introduce a song
  /// after the Radio pool has exhausted its fresh candidates.
  List<YoutubeSearchResult> filterUnplayedCandidates(
    Iterable<YoutubeSearchResult> candidates,
  ) {
    final result = <YoutubeSearchResult>[];
    final seenIds = <String>{};

    for (final video in candidates) {
      final id = video.videoId.trim();
      if (id.isEmpty || !seenIds.add(id)) continue;
      if (wasPlayedRecently(video) || _recentlySelected(video)) continue;
      if (result.any((existing) => isSameTrackFamily(existing, video))) continue;
      result.add(video);
    }
    return result;
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
    _playedVideos.removeWhere((item) => item.videoId == videoId);
    _playedVideos.add(video);
    if (_playedVideos.length > _maxPlayedIds) {
      _playedVideos.removeRange(0, _playedVideos.length - _maxPlayedIds);
    }

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

  /// Seed pencarian berbasis lagu aktif, bukan genre/chart global.
  /// Dipakai satu kali untuk membangun pool radio; kandidatnya lalu di-cache.
  static String songRadioSearchSeedFor(YoutubeSearchResult video) =>
      MusicStyleMatcher.recommendationSeedFor(video);

  static String _cleanTitle(String raw) {
    var title = raw
        .toLowerCase()
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'https?://\S+'), ' ');

    // Tag dalam kurung yang merupakan metadata/jenis upload, termasuk cover,
    // dibuang tanpa menghilangkan tanda baca internal judul seperti Hati-Hati.
    title = title.replaceAll(
      RegExp(
        r'[\(\[\{【][^\)\]\}】]*(?:official|music\s*video|official\s*audio|'
        r'lyrics?|lyric\s*video|visualizer|topic|4k|8k|hd|fhd|uhd|1080p|720p|'
        r'live|performance|cover|karaoke|instrumental|acoustic|remaster|remix|'
        r'version|versi|shorts)[^\)\]\}】]*[\)\]\}】]',
        caseSensitive: false,
      ),
      ' ',
    );

    // Hapus atribusi cover tanpa tanda kurung, misalnya "Judul - cover by X".
    // Ini dilakukan setelah tag berkurung dihapus agar tidak menyisakan "(".
    title = title.replaceAll(
      RegExp(
        r'\b(?:cover(?:ed)?(?:\s+version)?|cover\s+lagu|versi\s+cover)\s*'
        r'(?:by|oleh|dari|from|performed\s+by|sung\s+by|with)\s+[^|:;–—-]*',
        caseSensitive: false,
      ),
      ' ',
    );

    // Hapus dekorasi umum. Istilah yang penting untuk identitas lagu seperti
    // nama artis, feat., dan apostrof tetap dipertahankan.
    title = title
        .replaceAll(
          RegExp(
            r'\b(?:official\s+music\s+video|official\s+video|official\s+audio|'
            r'music\s+video|lyric\s+video|lyrics?|visualizer|audio\s+only|'
            r'video\s+official|high\s+definition|full\s*hd|1080p|720p|8k|4k|'
            r'fhd|uhd|hd|topic|vevo|karaoke|instrumental|cover(?:ed)?|'
            r'cover\s+version|versi\s+cover|remastered?|radio\s+edit|'
            r'official\s+visualizer)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+#(?:shorts|ytshorts|viral|trending|fyp)\b.*$', caseSensitive: false), ' ')
        .replaceAll(
          RegExp(
            r'\s*(?:[-|: ]\s*)?(?:live\s+performance|live\s+version|'
            r'acoustic\s+(?:version|cover)|remix|remastered?|radio\s+edit|'
            r'extended\s+mix|instrumental|karaoke|cover\s+version|versi\s+cover)\s*$',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Kata "cover by" di awal judul (contoh "Cover by X - Judul") telah
    // menghilangkan atribusinya; buang prefix cover yang masih tersisa.
    title = title.replaceAll(
      RegExp(r'^\s*(?:cover(?:ed)?|versi\s+cover|cover\s+lagu)\s*[-:|]*\s*', caseSensitive: false),
      '',
    );
    return title.replaceAll(RegExp(r'^[\s|•–—:_-]+|[\s|•–—:_-]+$'), '').trim();
  }

  static bool _looksLikeLabelChannel(String channelKey) => RegExp(
        r'\b(?:production|prod|studio|studios|records?|music|entertainment|'
        r'media|network|label|vevo|tv|distribution)\b',
      ).hasMatch(channelKey);

  /// Ambil nama penyanyi cover yang tertulis eksplisit di judul.
  /// Ini membantu menyingkirkan nama vokalis dari fingerprint lagu meskipun
  /// channel YouTube memakai nama label/akun lain.
  static String _coverArtistKey(String rawTitle) {
    final match = RegExp(
      r'\b(?:cover(?:ed)?(?:\s+version)?|cover\s+lagu|versi\s+cover)\s*'
      r'(?:by|oleh|dari|performed\s+by|sung\s+by|with)\s+'
      r'([^()\[\]{}|:;–—-]+)',
      caseSensitive: false,
    ).firstMatch(rawTitle);
    return normalizePhrase(match?.group(1) ?? '');
  }

  static bool _looksLikeChannelPart(String part, String channel) {
    if (part.isEmpty || channel.isEmpty) return false;
    if (part == channel) return true;

    final partWords = part.split(' ').where((word) => word.length >= 3).toSet();
    final channelWords = channel.split(' ').where((word) => word.length >= 3).toSet();
    if (partWords.isEmpty || channelWords.isEmpty) return false;
    final overlap = partWords.intersection(channelWords).length;
    return overlap / partWords.length >= 0.75 ||
        (partWords.length == 1 && overlap == 1);
  }

  /// Fingerprint berbasis judul lagu, bukan ID upload atau nama penyanyi.
  /// Separator hanya dikenali bila berdiri sendiri (" - "), sehingga judul
  /// ber-hyphen seperti "Hati-Hati di Jalan" tetap satu frasa utuh.
  static Set<String> trackKeysFor(YoutubeSearchResult video) {
    final rawTitle = video.title.trim();
    final cleaned = _cleanTitle(rawTitle);
    if (cleaned.isEmpty) return <String>{};

    final channel = _artistKey(video);
    final coverArtist = _coverArtistKey(rawTitle);
    final hadCoverCue = RegExp(
      r'\b(?:cover(?:ed)?|versi\s+cover|karaoke)\b',
      caseSensitive: false,
    ).hasMatch(rawTitle);
    final chunks = cleaned
        .split(RegExp(r'\s*(?:\||\u2022|;)\s*'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final keys = <String>{};

    for (final chunk in chunks) {
      final parts = chunk
          .split(RegExp(r'\s+(?:-|\u2013|\u2014|:)\s+'))
          .map((part) => normalizePhrase(part))
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      if (parts.isEmpty) continue;

      final performerParts = parts.where((part) =>
          _looksLikeChannelPart(part, channel) ||
          _looksLikeChannelPart(part, coverArtist)).toSet();
      List<String> songParts;
      if (parts.length == 1) {
        songParts = parts;
      } else if (performerParts.isNotEmpty) {
        // Buang segmen yang jelas merupakan nama channel/penyanyi cover.
        // Ini bekerja untuk kedua format: "Penyanyi - Judul" dan "Judul - Penyanyi".
        final remaining = parts.where((part) => !performerParts.contains(part)).toList();
        songParts = remaining.isNotEmpty ? remaining : <String>[parts.first];
      } else if (parts.length > 1 &&
          RegExp(r'\b(?:ft\.?|feat\.?|featuring)\b', caseSensitive: false)
              .hasMatch(parts.first)) {
        // Format "Artis ft. Kolaborator - Judul": sisi kanan adalah lagu.
        songParts = <String>[parts[1]];
      } else if (hadCoverCue) {
        // Jika akun yang mengunggah adalah label/produksi dan judul memakai
        // format "Penyanyi - Judul (Cover)", segmen kanan sering merupakan
        // judul lagu. Untuk judul normal "Judul - Penyanyi", tetap pilih kiri.
        // Cover artist/channel yang diketahui sudah ditangani di atas.
        final firstWords = parts.first.split(' ').length;
        final secondWords = parts[1].split(' ').length;
        songParts = <String>[
          if (_looksLikeLabelChannel(channel) && firstWords > secondWords)
            parts[1]
          else
            parts.first,
        ];
      } else if (_looksLikeLabelChannel(channel) && parts.length == 2) {
        final firstWords = parts[0].split(' ').length;
        final secondWords = parts[1].split(' ').length;
        // Label musik sering memakai format "Artis - Judul". Satu kata di
        // kiri tetap diperlakukan sebagai judul (mis. "Nemen - Gilga Sahid").
        if (firstWords == 1) {
          songParts = <String>[parts[0]];
        } else if (firstWords == 2 && secondWords == 1) {
          songParts = <String>[parts[1]];
        } else if (secondWords >= firstWords) {
          songParts = <String>[parts[1]];
        } else {
          songParts = <String>[parts[0]];
        }
      } else {
        // Default untuk hasil search: format lagu biasanya "Judul - Artis".
        songParts = <String>[parts.first];
      }

      for (var key in songParts) {
        // Sufiks versi sering diletakkan sebelum nama penyanyi: "Judul Remix - Artis".
        // Bersihkan modifier pada tiap segmen, bukan hanya di ujung keseluruhan judul.
        key = key.replaceAll(
          RegExp(
            r'\b(?:official|music\s+video|official\s+audio|lyrics?|lirik|'
            r'live|performance|acoustic|remix|remastered?|radio\s+edit|'
            r'extended\s+mix|cover|karaoke|instrumental|version|versi|topic|vevo)\b',
            caseSensitive: false,
          ),
          ' ',
        );
        if (channel.isNotEmpty) {
          key = key.replaceAll(RegExp(r'\b' + RegExp.escape(channel) + r'\b'), ' ');
        }
        key = normalizePhrase(key);
        if (key.length < 3) continue;
        if (<String>{
          'lagu', 'musik', 'song', 'songs', 'audio', 'video', 'official',
          'remix', 'cover', 'live', 'karaoke', 'instrumental', 'mix',
          'indonesia', 'terbaru', 'acoustic', 'version', 'versi',
        }.contains(key)) {
          continue;
        }
        keys.add(key);
      }
    }

    if (keys.isEmpty) {
      final fallback = normalizePhrase(cleaned);
      if (fallback.length >= 3) keys.add(fallback);
    }
    return keys;
  }

  static String trackKeyFor(YoutubeSearchResult video) {
    final keys = trackKeysFor(video).toList();
    if (keys.isEmpty) return '';
    // Gunakan fingerprint judul yang paling informatif, bukan potongan kata
    // satu kata dari tanda hubung internal.
    keys.sort((a, b) {
      final words = b.split(' ').length.compareTo(a.split(' ').length);
      if (words != 0) return words;
      return b.length.compareTo(a.length);
    });
    return keys.first;
  }

  static Set<String> _meaningfulTrackTokens(String key) {
    const stopWords = <String>{
      'the', 'a', 'an', 'and', 'dan', 'di', 'ke', 'yang', 'of', 'by', 'from',
      'ft', 'feat', 'featuring', 'official', 'music', 'video', 'audio',
      'cover', 'version', 'versi', 'lagu', 'song', 'songs', 'lyrics', 'lirik',
    };
    return normalizePhrase(key)
        .split(' ')
        .where((token) => token.length >= 2 && !stopWords.contains(token))
        .toSet();
  }

  static bool _similarTrackKey(String a, String b) {
    if (a == b) return true;
    final aTokens = _meaningfulTrackTokens(a);
    final bTokens = _meaningfulTrackTokens(b);
    if (aTokens.length < 2 || bTokens.length < 2) return false;
    final overlap = aTokens.intersection(bTokens).length;
    final shorter = aTokens.length < bTokens.length ? aTokens.length : bTokens.length;
    return overlap >= 2 && overlap / shorter >= 0.8;
  }

  static bool isSameTrackFamily(
    YoutubeSearchResult a,
    YoutubeSearchResult b,
  ) {
    if (a.videoId == b.videoId) return true;
    final aKeys = trackKeysFor(a);
    final bKeys = trackKeysFor(b);
    if (aKeys.isEmpty || bKeys.isEmpty) return false;
    for (final aKey in aKeys) {
      for (final bKey in bKeys) {
        if (_similarTrackKey(aKey, bKey)) return true;
      }
    }
    return false;
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
      if (candidateKeys.isEmpty || wasPlayedRecently(video) || _recentlySelected(video)) {
        return false;
      }
      if (_pool.any((pooled) => isSameTrackFamily(pooled, video))) {
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

    // Radio hanya memakai query berbasis lagu/artis yang sedang diputar.
    // Tidak ada fallback ke chart mostPopular. Jika tidak ada kandidat terkait,
    // jangan menggantinya dengan lagu populer yang tidak nyambung.
    try {
      final page = await _searchService.searchLatest(seed, pageToken: _pageToken);
      if (!isCurrentRequest()) return;
      _pageToken = page.nextPageToken;

      final relatedCandidates = page.results.where((video) => eligible(video)).toList();
      final rankedRelated = MusicStyleMatcher.rankForRadio(
        relatedCandidates,
        targetStyle: targetStyle,
        targetLanguage: targetLanguage,
        allowCrossLanguage: !_lockLanguage,
      );
      addCandidates(rankedRelated.isNotEmpty ? rankedRelated : relatedCandidates);

      if (_pool.isEmpty) {
        debugPrint('RADIO: no related candidates for seed="$seed"');
        if (page.nextPageToken == null || page.nextPageToken!.isEmpty) {
          onError?.call('Belum menemukan lagu yang cukup terkait dengan lagu sekarang.');
        }
      }
    } catch (e) {
      if (!isCurrentRequest()) return;
      debugPrint('RADIO RELATED SEARCH: $e');
      if (e is YoutubeSearchException) onError?.call(e.message);
    }
  }

  /// Seed radio saat daftar sumber habis; tetap berbasis track/artis yang aktif.
  static String seedFor(YoutubeSearchResult video) => songRadioSearchSeedFor(video);

}

