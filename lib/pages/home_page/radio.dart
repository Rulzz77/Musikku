part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Radio / autoplay: bibit radio, pengisian antrean, dan pemilihan lagu berikutnya.
extension _HomeRadio on _HomePageState {
  String _radioSeedFor(YoutubeSearchResult video) {
    // Jangan gunakan _lastSearchQuery untuk seed karena nilainya dapat berasal
    // dari pencarian lama. Radio harus mengikuti track yang sedang diputar.
    return RadioService.songRadioSearchSeedFor(video);
  }

  String? _radioPreferredLanguageFor(YoutubeSearchResult video) =>
      MusicStyleMatcher.languageFromVideo(video);

  /// Prime recommendations from the track explicitly selected by the user.
  /// This prevents a previous Radio seed/pool from leaking into a new song.
  void _prepareRadioForTrack(YoutubeSearchResult video) {
    if (video.isLocal) return;
    final seed = _radioSeedFor(video);
    if (seed.isEmpty) return;
    _radioOriginVideoId = video.videoId;
    _radioPickedIds.clear();
    _radio.start(
      seed,
      preferredLanguage: _radioPreferredLanguageFor(video),
      lockLanguage: false,
      alternateSeeds: MusicStyleMatcher.alternateSeedsFor(video),
      seedArtist: MusicStyleMatcher.seedArtistKeyFor(video),
    );
  }

  /// True bila lagu aktif bukan asal konteks Radio dan bukan hasil pilihan
  /// Radio sendiri, artinya pengguna pindah lagu lewat jalur yang tidak
  /// me-reset Radio.
  bool _isRadioContextStale(YoutubeSearchResult current) {
    if (!_radio.hasSeed || current.isLocal) return false;
    return current.videoId != _radioOriginVideoId &&
        !_radioPickedIds.contains(current.videoId);
  }

  Future<void> _startRadioFromVideo(YoutubeSearchResult video) async {
    final seed = _radioSeedFor(video);
    if (seed.isEmpty) {
      _toast('Tidak menemukan konteks radio untuk lagu ini.');
      return;
    }

    // Starting Radio is an explicit source change. Never keep the old playlist,
    // search list, shuffle pool or Previous history as a hidden fallback.
    _activeSource = _ListSource.radio;
    _activePlaylistId = null;
    _activeList = <YoutubeSearchResult>[];
    _shufflePool = <YoutubeSearchResult>[];
    _playHistory.clear();
    _radioOriginVideoId = video.videoId;
    _radioPickedIds.clear();
    _radio.start(
      seed,
      preferredLanguage: _radioPreferredLanguageFor(video),
      lockLanguage: false,
      // Artis sejenis + terpopuler di genre yang sama, dipakai bergantian
      // dengan seed utama supaya lagu berikutnya tidak hanya dari satu artis.
      alternateSeeds: MusicStyleMatcher.alternateSeedsFor(video),
      seedArtist: MusicStyleMatcher.seedArtistKeyFor(video),
    );

    // Start the selected song as the radio seed. Recommendations stay in the
    // RadioService pool instead of being mixed into the user's explicit queue;
    // this prevents unrelated/stale queue entries from hijacking Next.
    if (_currentVideo?.videoId != video.videoId) {
      await _playVideo(video);
    }
    await _radio.refill();
    if (mounted) {
      setState(() {});
      _toast('Radio aktif · lagu berikutnya akan dipilih otomatis.');
    }
  }

  /// Playlist (favorit / terakhir diputar) habis → lanjut ke lagu populer
  /// dengan genre/style yang nyambung, tanpa mengunci bahasa atau artis.
  Future<void> _continueWithRadio(
    YoutubeSearchResult current, {
    required bool fromAutoNext,
  }) async {
    // Safety net: playlist mode may never be converted into Radio by auto-next.
    if (_isFixedPlaybackList) {
      await _stopPlayback();
      if (!fromAutoNext) _toast('Playlist selesai. Pilih Repeat Semua untuk mengulang.');
      return;
    }

    if (current.isLocal) {
      await _stopPlayback();
      if (!fromAutoNext) {
        _toast('Tidak ada lagu lokal berikutnya. Pilih lagu lain dari Musik Lokal.');
      }
      return;
    }

    // Next/auto-next must work even when the user never tapped the Radio button.
    // Start the recommendation engine silently from the current song, then use
    // the same related-track pool that explicit Radio uses. The UI does not need
    // to switch screens or show the "Radio aktif" toast.
    final seed = _radioSeedFor(current);
    if (seed.isNotEmpty) {
      final sameRadioSeed = _radio.hasSeed &&
          RadioService.normalizePhrase(_radio.seed) ==
              RadioService.normalizePhrase(seed);
      if (_activeSource != _ListSource.radio || !sameRadioSeed) {
        _activeSource = _ListSource.radio;
        _activePlaylistId = null;
        _activeList = <YoutubeSearchResult>[];
        _shufflePool = <YoutubeSearchResult>[];
        _prepareRadioForTrack(current);
      }

      // start() may already be fetching; refill() joins that request. The
      // search service uses youtube_explode_dart rather than Data API search.list.
      await _radio.refill(allowNetwork: true);
      if (_radio.poolLength > 0) {
        await _nextFromRadio(fromAutoNext: fromAutoNext);
        return;
      }
    }

    // If discovery fails, fall back to cached related songs instead of forcing
    // the user to activate Radio manually.
    await _continueFromCachedLibrary(current, fromAutoNext: fromAutoNext);
  }

  Future<void> _continueFromCachedLibrary(
    YoutubeSearchResult current, {
    required bool fromAutoNext,
  }) async {
    final contextQuery = _activeSource == _ListSource.search ? _lastSearchQuery : '';
    final targetStyle = MusicStyleMatcher.styleForContext(
      query: contextQuery,
      currentVideo: current,
    );
    final targetLanguage = MusicStyleMatcher.languageForContext(
      query: contextQuery,
      currentVideo: current,
    );
    final seenIds = <String>{};
    final candidates = <YoutubeSearchResult>[];

    for (final video in <YoutubeSearchResult>[
      ..._activeList,
      ..._favorites,
      ..._recentlyPlayed,
    ]) {
      if (video.videoId.isEmpty ||
          !seenIds.add(video.videoId) ||
          video.videoId == current.videoId ||
          video.isLocal != current.isLocal ||
          RadioService.isSameTrackFamily(video, current) ||
          _dislikedIds.contains(video.videoId) ||
          ChannelBlockFilter.isBlocked(video, _blockedChannelKeys) ||
          YoutubeSearchService.isLikelyShortForm(video) ||
          YoutubeSearchService.isLikelyNonMusicVideo(video) ||
          video.isLive ||
          video.isUpcoming ||
          !YoutubeSearchService.isMusicCandidate(video)) {
        continue;
      }

      if (targetStyle != null) {
        final candidateStyle = MusicStyleMatcher.styleFromVideo(video);
        if (candidateStyle == null ||
            !MusicStyleMatcher.isRelatedStyle(candidateStyle, targetStyle)) {
          continue;
        }
      }
      if (!MusicStyleMatcher.isCompatible(
        video: video,
        targetStyle: targetStyle,
        targetLanguage: targetLanguage,
        allowCrossLanguage: true,
      )) {
        continue;
      }
      candidates.add(video);
    }

    // Never replay anything Radio already played; only the last 15 history
    // entries are checked by _pickNonShort, which let older songs repeat.
    final freshCandidates = _radio.filterUnplayedCandidates(candidates);
    if (freshCandidates.isNotEmpty) {
      final ranked = targetStyle == null
          ? freshCandidates
          : MusicStyleMatcher.rankForRadio(
              freshCandidates,
              targetStyle: targetStyle,
              targetLanguage: targetLanguage,
              allowCrossLanguage: true,
            );
      final varied = _radio.preferArtistVariety(ranked.toList(growable: false));
      final next = _playerUiState.value.isShuffle &&
              !_playerUiState.value.isSmartShuffle
          ? _pickNonShort(varied, random: true)
          : _pickSmartWeightedCandidate(
              varied,
              currentVideo: current,
              targetStyle: targetStyle,
              targetLanguage: targetLanguage,
            );
      if (next != null) {
        await _playVideo(next);
        return;
      }
    }

    final lastResort = _pickLastResortTrack();
    if (lastResort != null) {
      debugPrint('AUTO NEXT: last-resort pick ${lastResort.title}');
      await _playVideo(lastResort);
      return;
    }

    await _stopPlayback();
    if (!fromAutoNext) {
      _toast(
        'Lagu berikutnya belum tersedia. Periksa koneksi lalu coba lagi.',
        duration: const Duration(seconds: 3),
      );
    }
  }

  /// Ambil kandidat dari pool radio yang bukan Shorts, memakai metadata lokal.
  /// Riwayat pencarian memberi sinyal ringan bahwa artis pernah dicari.
  /// Statistik play/skip/like sudah dihitung oleh SmartQueueScorer, jadi tidak
  /// digandakan di sini agar satu artis tidak mendominasi rekomendasi.
  Future<double Function(YoutubeSearchResult)> _buildRadioTasteBonus() async {
    var queries = <String>[];
    try {
      queries = (await _storage.loadHistory())
          .take(30)
          .map((query) => ' ${SmartQueueScorer.normalizeArtist(query)} ')
          .where((query) => query.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {}

    return (YoutubeSearchResult video) {
      final artistKey = MusicStyleMatcher.artistKeyFor(video);
      final normalizedArtist = SmartQueueScorer.normalizeArtist(artistKey);
      if (normalizedArtist.length < 3) return 0.0;
      final searchedRecently =
          queries.any((query) => query.contains(' $normalizedArtist '));
      return searchedRecently ? 3.0 : 0.0;
    };
  }

  YoutubeSearchResult? _takeNonShortFromRadio({
    double Function(YoutubeSearchResult)? tasteBonus,
  }) {
    for (var i = 0; i < 50; i++) {
      final isPlainShuffle = _playerUiState.value.isShuffle &&
          !_playerUiState.value.isSmartShuffle;
      final candidate = isPlainShuffle
          ? _radio.take(random: true)
          : _radio.takeSmart(
              score: (video) {
                final base = _safeQueueScore(
                  video,
                  currentArtist: _currentVideo?.channelTitle,
                );
                final bonus = tasteBonus?.call(video) ?? 0.0;
                return base + (bonus.isFinite ? bonus : 0.0);
              },
            );

      if (candidate == null) {
        return null;
      }

      // Filter metadata lokal saja. isShortVideo(videoId) adalah API lama
      // yang sekarang selalu false dan tidak memberi sinyal tambahan.
      if (!YoutubeSearchService.isMusicCandidate(candidate) ||
          YoutubeSearchService.isLikelyShortForm(candidate) ||
          YoutubeSearchService.isLikelyNonMusicVideo(candidate)) {
        continue;
      }

      // Guard lapis kedua: jika pool berisi upload lain untuk lagu yang baru
      // diputar, jangan sampai Next memantul ke lagu sebelumnya.
      if (_wasPlayedInRecentPlaybackHistory(candidate)) {
        debugPrint('RADIO NEXT: skip recent track ${candidate.videoId} | ${candidate.title}');
        continue;
      }

      return candidate;
    }

    return null;
  }

  /// Fallback paling akhir: semua jalur Radio kosong (pool habis, API gagal,
  /// genre tidak terdeteksi). Lebih baik memutar ulang lagu lama dari favorit /
  /// terakhir diputar daripada diam. Filter genre dan "sudah pernah diputar"
  /// sengaja diabaikan, tapi tetap menghormati blokir, dislike, Shorts, bukan
  /// lagu sekarang, dan bukan 15 lagu terakhir (lewat _pickNonShort).
  YoutubeSearchResult? _pickLastResortTrack() {
    final seen = <String>{};
    final pool = <YoutubeSearchResult>[
      ..._favorites,
      ..._recentlyPlayed,
    ].where((video) {
      return video.videoId.isNotEmpty &&
          !video.isLocal &&
          seen.add(video.videoId) &&
          !_dislikedIds.contains(video.videoId) &&
          !ChannelBlockFilter.isBlocked(video, _blockedChannelKeys) &&
          YoutubeSearchService.isMusicCandidate(video) &&
          !video.isLive &&
          !video.isUpcoming;
    }).toList(growable: false);
    if (pool.isEmpty) return null;
    final varied = _radio.preferArtistVariety(pool);
    if (_playerUiState.value.isShuffle &&
        !_playerUiState.value.isSmartShuffle) {
      return _pickNonShort(varied, random: true);
    }
    return _pickSmartWeightedCandidate(varied, currentVideo: _currentVideo);
  }

  /// Kandidat radio/cached fallback tidak boleh berupa lagu sekarang atau
  /// keluarga lagu yang ada di jendela Previous terbaru.
  bool _wasPlayedInRecentPlaybackHistory(YoutubeSearchResult candidate) {
    final current = _currentVideo;
    if (current != null &&
        (candidate.videoId == current.videoId ||
            RadioService.isSameTrackFamily(candidate, current))) {
      return true;
    }

    // Batasi ke 15 track terakhir supaya katalog panjang tidak ikut terkunci.
    final start = _playHistory.length > 15 ? _playHistory.length - 15 : 0;
    for (final previous in _playHistory.skip(start)) {
      if (candidate.videoId == previous.videoId ||
          RadioService.isSameTrackFamily(candidate, previous)) {
        return true;
      }
    }
    return false;
  }

  /// Dari daftar [videos] ambil satu yang bukan Shorts (urutan/acak sesuai mode).
  YoutubeSearchResult? _pickNonShort(
    List<YoutubeSearchResult> videos, {
    required bool random,
  }) {
    final list = List<YoutubeSearchResult>.from(videos);

    if (random) {
      list.shuffle(_random);
    }

    for (final video in list) {
      if (!YoutubeSearchService.isMusicCandidate(video) ||
          YoutubeSearchService.isLikelyShortForm(video) ||
          YoutubeSearchService.isLikelyNonMusicVideo(video) ||
          _wasPlayedInRecentPlaybackHistory(video)) {
        continue;
      }
      return video;
    }

    return null;
  }

  Future<void> _nextFromRadio({required bool fromAutoNext}) async {
    // Radio catalogues are YouTube-only. Do not allow a stale radio seed to
    // switch a currently playing local file into a YouTube track.
    if (_currentVideo?.isLocal == true) {
      await _stopPlayback();
      if (!fromAutoNext) {
        _toast('Shuffle/Radio lokal selesai. Pilih playlist musik lokal untuk lanjut.');
      }
      return;
    }

    YoutubeSearchResult? next;

    // Batasi satu halaman Radio per tindakan Next. Jika halaman kosong/tersaring,
    // gunakan fallback lokal alih-alih menghabiskan kuota dengan banyak halaman.
    for (var attempt = 0; attempt < 1 && next == null; attempt++) {
      if (_radio.isPoolEmpty) {
        if (!fromAutoNext && attempt == 0) {
          _toast(
            'Menyiapkan lagu berikutnya…',
            duration: const Duration(seconds: 1),
          );
        }

        await _radio.refill(allowNetwork: true);
      }

      if (_radio.isPoolEmpty) {
        continue;
      }

      next = _takeNonShortFromRadio(
        tasteBonus: await _buildRadioTasteBonus(),
      );
    }

    // Fallback 1: pakai hasil pencarian aktif yang sudah ada di memory.
    // Ini menjamin auto-next tidak mati hanya karena request radio gagal.
    if (next == null && _activeList.isNotEmpty) {
      final currentId = _currentVideo?.videoId;
      final targetStyle = MusicStyleMatcher.styleForContext(
        query: _radio.seed,
        currentVideo: _currentVideo,
      );
      final targetLanguage = MusicStyleMatcher.languageForContext(
        query: _radio.seed,
        currentVideo: _currentVideo,
      );
      final candidates = _activeList.where((video) {
        if (video.videoId == currentId ||
            (_currentVideo != null &&
                RadioService.isSameTrackFamily(video, _currentVideo!))) {
          return false;
        }
        if (_dislikedIds.contains(video.videoId)) return false;
        if (ChannelBlockFilter.isBlocked(video, _blockedChannelKeys)) return false;
        if (YoutubeSearchService.isLikelyShortForm(video)) return false;
        if (YoutubeSearchService.isLikelyNonMusicVideo(video)) return false;
        if (!YoutubeSearchService.isMusicCandidate(video)) return false;
        if (video.isLive || video.isUpcoming) return false;
        // Cached non-radio lists may only backfill a known related genre;
        // an old unclassified search result must not hijack song-specific Radio.
        if (targetStyle == null) return false;
        final candidateStyle = MusicStyleMatcher.styleFromVideo(video);
        if (candidateStyle == null ||
            !MusicStyleMatcher.isRelatedStyle(candidateStyle, targetStyle)) {
          return false;
        }
        if (!MusicStyleMatcher.isCompatible(
          video: video,
          targetStyle: targetStyle,
          targetLanguage: targetLanguage,
          allowCrossLanguage: !_radio.locksLanguage,
        )) {
          return false;
        }
        return RadioService.trackKeyFor(video).isNotEmpty;
      }).toList();
      // Only offer candidates not played in this radio history. Falling back
      // to [candidates] when freshCandidates is empty caused familiar tracks
      // to repeat immediately whenever the API/cache was exhausted.
      final freshCandidates = _radio.filterUnplayedCandidates(candidates);
      // Active search results may be stale or cached before Shorts filtering.
      final verifiedCandidates = await _searchService.removeShorts(freshCandidates);

      if (verifiedCandidates.isNotEmpty) {
        final styleCandidates = MusicStyleMatcher.rankForRadio(
          verifiedCandidates,
          targetStyle: targetStyle,
          targetLanguage: targetLanguage,
          allowCrossLanguage: !_radio.locksLanguage,
        );
        // Weighted recommendation picker ranks this whole compatible pool
        // once, then samples from its best eight candidates.
        final variedPool = _radio.preferArtistVariety(styleCandidates);
        next = _playerUiState.value.isShuffle &&
                !_playerUiState.value.isSmartShuffle
            ? _pickNonShort(variedPool, random: true)
            : _pickSmartWeightedCandidate(
                variedPool,
                currentVideo: _currentVideo,
                targetStyle: targetStyle,
                targetLanguage: targetLanguage,
              );
      }
    }

    // Jangan reset dan mengambil halaman awal lagi dalam klik Next yang sama.
    // Tidak ada request halaman tambahan dalam klik Next yang sama; percobaan baru
    // hanya dilakukan pada interaksi berikutnya setelah fallback lokal di bawah.

    // Fallback 2: kuota/API habis atau offline → jangan diam. Putar dari
    // favorit / terakhir diputar (bukan lagu yang sedang diputar).
    if (next == null) {
      final currentId = _currentVideo?.videoId;
      final targetStyle = MusicStyleMatcher.styleForContext(
        query: _radio.seed,
        currentVideo: _currentVideo,
      );
      final targetLanguage = MusicStyleMatcher.languageForContext(
        query: _radio.seed,
        currentVideo: _currentVideo,
      );
      final local = <YoutubeSearchResult>[
        ..._favorites,
        ..._recentlyPlayed,
      ].where((video) {
        final candidateStyle = MusicStyleMatcher.styleFromVideo(video);
        return video.videoId != currentId &&
            (_currentVideo == null ||
                !RadioService.isSameTrackFamily(video, _currentVideo!)) &&
            !_dislikedIds.contains(video.videoId) &&
            !ChannelBlockFilter.isBlocked(video, _blockedChannelKeys) &&
            !YoutubeSearchService.isLikelyShortForm(video) &&
            !YoutubeSearchService.isLikelyNonMusicVideo(video) &&
            YoutubeSearchService.isMusicCandidate(video) &&
            !video.isLive &&
            !video.isUpcoming &&
            targetStyle != null &&
            candidateStyle != null &&
            MusicStyleMatcher.isRelatedStyle(candidateStyle, targetStyle) &&
            MusicStyleMatcher.isCompatible(
              video: video,
              targetStyle: targetStyle,
              targetLanguage: targetLanguage,
              allowCrossLanguage: !_radio.locksLanguage,
            );
      }).toList();
      // Favorites/history are a last-resort cache, not permission to replay the
      // same tracks. When every cached item was played already, stop gracefully
      // instead of returning a song from the same history again.
      final freshLocal = _radio.filterUnplayedCandidates(local);
      final verifiedLocal = await _searchService.removeShorts(freshLocal);

      if (verifiedLocal.isNotEmpty) {
        final preferred = MusicStyleMatcher.rankForRadio(
          verifiedLocal,
          targetStyle: targetStyle,
          targetLanguage: targetLanguage,
          allowCrossLanguage: !_radio.locksLanguage,
        );
        final variedLocal = _radio.preferArtistVariety(
          preferred.isNotEmpty ? preferred : verifiedLocal,
        );
        next = _playerUiState.value.isShuffle &&
                !_playerUiState.value.isSmartShuffle
            ? _pickNonShort(variedLocal, random: true)
            : _pickSmartWeightedCandidate(
                variedLocal,
                currentVideo: _currentVideo,
                targetStyle: targetStyle,
                targetLanguage: targetLanguage,
              );
      }
    }

    // Fallback 3: genre tidak terdeteksi / semua kandidat sudah pernah diputar.
    // Fallback 1 mati di mode Radio (_activeList sengaja dikosongkan) dan
    // Fallback 2 butuh targetStyle, jadi tanpa ini lagu berhenti diam-diam.
    next ??= _pickLastResortTrack();

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

    // A cover result can be replaced with a high-confidence official/original
    // upload when the YouTube search API exposes one. The resolver is only
    // called for explicit cover titles; ambiguous or unavailable originals keep
    // the chosen result and never block playback.
    final selected = next;
    final resolved = await _originalTrackResolver.resolveIfCover(
      selected,
      allowNetwork: false,
    );
    final playable = resolved.videoId != selected.videoId &&
            !_radio.wasPlayedRecently(resolved)
        ? resolved
        : selected;
    if (playable.videoId != selected.videoId) {
      debugPrint(
        'RADIO ORIGINAL RESOLVED: ${selected.title} -> ${playable.title} (${playable.videoId})',
      );
      if (!fromAutoNext) _toast('Menemukan rekaman asli: ${playable.title}');
    }

    _radioPickedIds
      ..add(selected.videoId)
      ..add(playable.videoId);
    await _playVideo(playable);

    // Prefetch related candidates while a song is playing. This avoids needing
    // the user to activate Radio and helps keep the next transition responsive.
    // The search service uses youtube_explode_dart rather than YouTube Data API
    // search.list, although the unofficial endpoint can still be rate-limited.
    if (_radio.poolLength <= 3) {
      unawaited(_radio.refill(allowNetwork: true));
    }
  }
}