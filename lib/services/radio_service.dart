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
  final List<YoutubeSearchResult> _pool = [];
  String? _pageToken;
  Future<void>? _fetch;
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

  bool get isPoolEmpty => _pool.isEmpty;

  int get poolLength => _pool.length;

  /// Mulai (atau lanjutkan) radio dengan kata kunci [seed].
  void start(String seed) {
    final normalized = seed.trim();

    if (normalized.isEmpty) {
      return;
    }

    if (normalized.toLowerCase() != _seed.toLowerCase()) {
      _fetchGeneration++;
      _seed = normalized;
      _pool.clear();
      _pageToken = null;
      _fetch = null;
    }

    // Siapkan lagu berikutnya di belakang layar supaya Next terasa instan.
    if (_pool.isEmpty) {
      unawaited(refill());
    }
  }

  /// Paksa radio mulai ulang dari seed yang sama. Dipakai sebagai fallback
  /// ketika semua hasil halaman/cache lama habis atau terlalu banyak terfilter.
  void restart(String seed) {
    final normalized = seed.trim();
    if (normalized.isEmpty) {
      return;
    }

    _fetchGeneration++;
    _seed = normalized;
    _pool.clear();
    _pageToken = null;
    _fetch = null;
  }

  /// Isi ulang pool. Kalau sedang berjalan, pemanggil ikut menunggu yang sama.
  Future<void> refill() {
    if (_disposed) return Future<void>.value();

    final running = _fetch;
    if (running != null) {
      return running;
    }

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
    _pool.removeWhere((video) =>
        _blockedIds().contains(video.videoId) ||
        ChannelBlockFilter.isBlocked(video, _blockedChannelKeys()) ||
        !MusicStyleMatcher.isCompatible(video: video, targetStyle: targetStyle));

    if (_pool.isEmpty) {
      return null;
    }

    final styleCandidates = MusicStyleMatcher.prioritizeStyle(_pool, targetStyle);
    final candidatesPool = styleCandidates.isNotEmpty ? styleCandidates : _pool;
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
          value += _random.nextDouble() * 3.5;
          return (video: video, score: value);
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final topCount = scored.length < 10 ? scored.length : 10;
    final candidates = scored.take(topCount).map((item) => item.video).toList();

    // Dari kandidat bagus, pilih secara acak supaya urutan tidak selalu identik.
    // Namun track/artist yang baru muncul tetap sudah diberi penalti.
    final selected = candidates[_random.nextInt(candidates.length)];
    _pool.removeWhere((video) => video.videoId == selected.videoId);
    _rememberSelection(selected);
    return selected;
  }

  /// Ambil satu lagu dari pool. Shuffle biasa tetap acak, sedangkan mode normal
  /// memakai pemilihan berbasis keragaman agar tidak selalu mengambil hasil
  /// paling populer pertama.
  YoutubeSearchResult? take({required bool random}) {
    final targetStyle = MusicStyleMatcher.styleFromText(_seed);
    _pool.removeWhere((video) =>
        _blockedIds().contains(video.videoId) ||
        ChannelBlockFilter.isBlocked(video, _blockedChannelKeys()) ||
        !MusicStyleMatcher.isCompatible(video: video, targetStyle: targetStyle));

    if (_pool.isEmpty) {
      return null;
    }

    final styleCandidates = MusicStyleMatcher.prioritizeStyle(_pool, targetStyle);
    final candidatesPool = styleCandidates.isNotEmpty ? styleCandidates : _pool;

    if (random) {
      final eligible = candidatesPool
          .where((video) => !_recentlySelected(video))
          .toList();
      final source = eligible.isNotEmpty ? eligible : candidatesPool;
      final selected = source[_random.nextInt(source.length)];
      _pool.removeWhere((video) => video.videoId == selected.videoId);
      _rememberSelection(selected);
      return selected;
    }

    final currentArtist = _recentSelectionArtists.isEmpty
        ? ''
        : _recentSelectionArtists.last;

    // Kandidat utama: hindari judul yang baru diputar dan artist yang sama
    // berturut-turut. Tetap batasi ke 12 teratas agar popularitas tetap punya
    // pengaruh.
    final diverse = candidatesPool.where((video) {
      if (_recentlySelected(video)) return false;
      final artist = _artistKey(video);
      if (currentArtist.isNotEmpty && artist == currentArtist) return false;
      return true;
    }).take(12).toList();

    final sameArtistAllowed = candidatesPool
        .where((video) => !_recentlySelected(video))
        .take(12)
        .toList();

    final source = diverse.isNotEmpty
        ? diverse
        : (sameArtistAllowed.isNotEmpty ? sameArtistAllowed : candidatesPool.take(12).toList());

    final topCount = source.length < 5 ? source.length : 5;
    final selected = source[_random.nextInt(topCount)];
    _pool.removeWhere((video) => video.videoId == selected.videoId);
    _rememberSelection(selected);
    return selected;
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

    if (_disposed || seed.isEmpty) {
      return;
    }

    final targetStyle = MusicStyleMatcher.styleFromText(seed);

    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        final page = await _searchService.searchLatest(
          seed,
          pageToken: _pageToken,
        );

        // Seed sudah ganti (atau service sudah dibuang) selama menunggu.
        if (_disposed ||
            generation != _fetchGeneration ||
            seed != _seed) {
          return;
        }

        _pageToken = page.nextPageToken;

        final currentId = currentVideoId();
        final knownIds = _pool.map((video) => video.videoId).toSet();
        final knownTrackKeys = <String>{};
        for (final pooledVideo in _pool) {
          knownTrackKeys.addAll(trackKeysFor(pooledVideo));
        }

        for (final video in page.results) {
          if (!MusicStyleMatcher.isCompatible(
                video: video,
                targetStyle: targetStyle,
              ) ||
              video.videoId == currentId ||
              _playedIds.contains(video.videoId) ||
              _blockedIds().contains(video.videoId) ||
              ChannelBlockFilter.isBlocked(video, _blockedChannelKeys()) ||
              knownIds.contains(video.videoId)) {
            continue;
          }

          final candidateKeys = trackKeysFor(video);
          if (candidateKeys.any(_playedTrackKeys.contains) ||
              candidateKeys.any(knownTrackKeys.contains)) {
            continue;
          }

          _pool.add(video);
          knownIds.add(video.videoId);
          knownTrackKeys.addAll(candidateKeys);
        }

        if (_pool.isNotEmpty) {
          return;
        }

        if (page.nextPageToken == null) {
          // Semua halaman yang tersedia sudah habis dan semua kandidat yang
          // ditemukan sudah pernah diputar. Lepaskan sebagian ID PALING LAMA,
          // bukan seluruh history, lalu mulai dari halaman pertama lagi.
          // Dengan begitu radio tetap jalan tetapi tidak cepat mengulang.
          _pageToken = null;

          if (_pool.isEmpty && _playedIds.isNotEmpty) {
            final current = currentId;
            if (current != null) {
              _playedIds.remove(current);
            }

            final keepIds = (_playedIds.length / 2).ceil();
            if (_playedIds.length > keepIds) {
              _playedIds.removeRange(0, _playedIds.length - keepIds);
            }

            if (_playedTrackKeys.isNotEmpty) {
              final keepKeys = (_playedTrackKeys.length / 2).ceil();
              if (_playedTrackKeys.length > keepKeys) {
                _playedTrackKeys.removeRange(0, _playedTrackKeys.length - keepKeys);
              }
            }

            if (current != null) {
              _playedIds.add(current);
            }
          }
        }
      }
    } catch (e) {
      // Ignore failures from a stale request just like stale successful
      // responses. They must not reset the current page token or show errors
      // for a newer radio context.
      if (_disposed || generation != _fetchGeneration || seed != _seed) {
        return;
      }

      debugPrint('RADIO ERROR: $e');

      // Token halaman bisa basi; mulai dari halaman pertama di percobaan
      // berikutnya.
      _pageToken = null;

      if (e is YoutubeSearchException) {
        onError?.call(e.message);
      }
    }
  }

  /// Nama artis / kata kunci dari sebuah lagu, dipakai sebagai benih radio
  /// saat playlist favorit habis.
  static String seedFor(YoutubeSearchResult video) {
    var channel = video.channelTitle.trim();

    channel = channel
        .replaceAll(RegExp(r'\s*[-|]\s*Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*VEVO$', caseSensitive: false), '')
        .replaceAll(
          RegExp(
            r'\s*(Official|Official Artist Channel)$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Untuk autoplay dari lagu tunggal, gunakan artis/channel sebagai seed,
    // bukan judul lagu. Ini mencegah kasus "Pelanggaran" -> "Pelanggaran"
    // versi vokalis lain.
    if (channel.length >= 3) {
      return '$channel lagu Indonesia';
    }

    return trackKeyFor(video);
  }

}

