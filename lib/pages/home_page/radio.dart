part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Radio / autoplay: bibit radio, pengisian antrean, dan pemilihan lagu berikutnya.
extension _HomeRadio on _HomePageState {
  String _radioSeedFor(YoutubeSearchResult video) {
    final query = _lastSearchQuery.trim();
    final queryStyle = MusicStyleMatcher.styleFromText(query);
    final videoStyle = MusicStyleMatcher.styleFromVideo(video);

    // Query genre (misalnya "lagu Jawa" atau "Pop") adalah konteks utama.
    // Jangan menggantinya dengan "nama channel lagu Indonesia", karena seed
    // generik itu yang membuat radio dapat melompat ke genre lain.
    if (query.isNotEmpty && queryStyle != null) {
      return query;
    }

    if (query.isNotEmpty &&
        !RadioService.queryLooksLikeCurrentTrack(query, video)) {
      return query;
    }

    if (videoStyle != null) {
      return MusicStyleMatcher.seedForStyle(videoStyle);
    }

    return RadioService.seedFor(video);
  }

  Future<void> _startRadioFromVideo(YoutubeSearchResult video) async {
    final seed = _radioSeedFor(video);
    if (seed.isEmpty) {
      _toast('Tidak menemukan konteks radio untuk lagu ini.');
      return;
    }
    _radio.start(seed);
    await _radio.refill();
    var added = 0;
    for (var i = 0; i < (widget.settings.dataSaverLevel >= 2 ? 4 : (widget.settings.dataSaverLevel == 1 ? 6 : 12)); i++) {
      final next = _radio.take(random: false);
      if (next == null) break;
      if (_queueManager.add(next)) added++;
    }
    if (added > 0) {
      await _storage.saveQueue(_queueManager.items);
      if (mounted) setState(() {});
      _toast('Radio dari lagu ini menambahkan $added lagu.');
    } else {
      _toast('Belum menemukan lagu lain yang relevan.');
    }
  }

  /// Playlist (favorit / terakhir diputar) sudah habis → lanjut ke lagu
  /// populer dari artis yang sama, bukan berhenti.
  Future<void> _continueWithRadio(
    YoutubeSearchResult current, {
    required bool fromAutoNext,
  }) async {
    final seed = _radioSeedFor(current);

    if (seed.isEmpty) {
      if (!fromAutoNext) {
        _toast('Tidak ada lagu berikutnya');
      }

      return;
    }

    _activeSource = _ListSource.radio;

    _radio.start(seed);

    _toast(
      'Lanjut ke lagu populer yang masih sejenis 🎧',
      duration: const Duration(seconds: 1),
    );

    await _nextFromRadio(fromAutoNext: fromAutoNext);
  }

  /// Ambil kandidat dari pool radio yang BUKAN Shorts. Setiap kandidat dicek
  /// langsung ke YouTube; kalau Short langsung dibuang dan ambil berikutnya.
  Future<YoutubeSearchResult?> _takeNonShortFromRadio() async {
    for (var i = 0; i < 15; i++) {
      final candidate = _playerUiState.value.isSmartShuffle
          ? _radio.takeSmart(
              score: (video) => _smartShuffleScore(
                video,
                currentArtist: _currentVideo?.channelTitle,
              ),
            )
          : _radio.take(random: _playerUiState.value.isShuffle);

      if (candidate == null) {
        return null;
      }

      if (YoutubeSearchService.isLikelyShortForm(candidate) ||
          YoutubeSearchService.isLikelyNonMusicVideo(candidate) ||
          await _searchService.isShortVideo(candidate.videoId)) {
        continue;
      }

      return candidate;
    }

    return null;
  }

  /// Dari daftar [videos] ambil satu yang bukan Shorts (urutan/acak sesuai mode).
  Future<YoutubeSearchResult?> _pickNonShort(
    List<YoutubeSearchResult> videos, {
    required bool random,
  }) async {
    final list = List<YoutubeSearchResult>.from(videos);

    if (random) {
      list.shuffle(_random);
    }

    for (final video in list.take(15)) {
      if (YoutubeSearchService.isLikelyShortForm(video) ||
          YoutubeSearchService.isLikelyNonMusicVideo(video)) {
        continue;
      }
      if (!await _searchService.isShortVideo(video.videoId)) {
        return video;
      }
    }

    return null;
  }

  Future<void> _nextFromRadio({required bool fromAutoNext}) async {
    YoutubeSearchResult? next;

    // Cari kandidat radio sampai beberapa halaman. Setelah filter Shorts,
    // anti-repeat, dislike, dan track fingerprint, satu halaman bisa kosong.
    for (var attempt = 0; attempt < 8 && next == null; attempt++) {
      if (_radio.isPoolEmpty) {
        if (!fromAutoNext && attempt == 0) {
          _toast(
            'Mencari lagu berikutnya…',
            duration: const Duration(seconds: 1),
          );
        }

        await _radio.refill();
      }

      if (_radio.isPoolEmpty) {
        continue;
      }

      next = await _takeNonShortFromRadio();
    }

    // Fallback 1: pakai hasil pencarian aktif yang sudah ada di memory.
    // Ini menjamin auto-next tidak mati hanya karena request radio gagal.
    if (next == null && _activeList.isNotEmpty) {
      final currentId = _currentVideo?.videoId;
      final targetStyle = MusicStyleMatcher.styleForContext(
        query: _radio.seed,
        currentVideo: _currentVideo,
      );
      final candidates = _activeList.where((video) {
        if (video.videoId == currentId) return false;
        if (_dislikedIds.contains(video.videoId)) return false;
        if (YoutubeSearchService.isLikelyShortForm(video)) return false;
        if (YoutubeSearchService.isLikelyNonMusicVideo(video)) return false;
        if (!MusicStyleMatcher.isCompatible(
          video: video,
          targetStyle: targetStyle,
        )) {
          return false;
        }
        return RadioService.trackKeyFor(video).isNotEmpty;
      }).toList();

      if (candidates.isNotEmpty) {
        final preferred = MusicStyleMatcher.prioritizeStyle(candidates, targetStyle);
        final styleCandidates = preferred.isNotEmpty ? preferred : candidates;
        if (_playerUiState.value.isSmartShuffle) {
          styleCandidates.sort((a, b) => _smartShuffleScore(
                b,
                currentArtist: _currentVideo?.channelTitle,
              ).compareTo(
                _smartShuffleScore(
                  a,
                  currentArtist: _currentVideo?.channelTitle,
                ),
              ));
        }

        next = await _pickNonShort(
          styleCandidates,
          random: _playerUiState.value.isShuffle &&
              !_playerUiState.value.isSmartShuffle,
        );
      }
    }

    // Fallback 2: paksa radio reset dari seed awal. Ini menangani pool/cache
    // lama yang terlalu ketat setelah perubahan filter Shorts/fingerprint.
    if (next == null && _radio.hasSeed) {
      _radio.restart(_radio.seed);
      await _radio.refill();
      if (!_radio.isPoolEmpty) {
        next = await _takeNonShortFromRadio();
      }
    }

    // Fallback 4: kuota/API habis atau offline → jangan diam. Putar dari
    // favorit / terakhir diputar (bukan lagu yang sedang diputar).
    if (next == null) {
      final currentId = _currentVideo?.videoId;
      final targetStyle = MusicStyleMatcher.styleForContext(
        query: _radio.seed,
        currentVideo: _currentVideo,
      );
      final local = <YoutubeSearchResult>[
        ..._favorites,
        ..._recentlyPlayed,
      ].where((video) {
        return video.videoId != currentId &&
            !_dislikedIds.contains(video.videoId) &&
            !YoutubeSearchService.isLikelyShortForm(video) &&
            !YoutubeSearchService.isLikelyNonMusicVideo(video) &&
            MusicStyleMatcher.isCompatible(
              video: video,
              targetStyle: targetStyle,
            );
      }).toList();

      if (local.isNotEmpty) {
        final preferred = MusicStyleMatcher.prioritizeStyle(local, targetStyle);
        next = await _pickNonShort(
          preferred.isNotEmpty ? preferred : local,
          random: true,
        );
      }
    }

    if (next == null) {
      debugPrint(
        'AUTO NEXT: no candidate | seed=${_radio.seed} | source=$_activeSource | activeList=${_activeList.length}',
      );
      if (!fromAutoNext) {
        _toast(
          'Belum menemukan lagu berikutnya. Coba lagi.',
          duration: const Duration(seconds: 1),
        );
      }
      return;
    }

    await _playVideo(next);

    if (_radio.poolLength <= 6) {
      unawaited(_radio.refill());
    }
  }
}
