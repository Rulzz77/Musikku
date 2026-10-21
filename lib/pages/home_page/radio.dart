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
    // Device-local playback has no YouTube radio continuation. This guard also
    // covers a restored local track whose playlist context is empty after app
    // restart, so Next/auto-next cannot jump into remote YouTube audio.
    if (current.isLocal) {
      await _stopPlayback();
      if (!fromAutoNext) {
        _toast('Tidak ada lagu lokal berikutnya. Pilih lagu lain dari Musik Lokal.');
      }
      return;
    }

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

  /// Ambil kandidat dari pool radio yang bukan Shorts, memakai metadata lokal.
  YoutubeSearchResult? _takeNonShortFromRadio() {
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

      // Filter metadata lokal saja. isShortVideo(videoId) adalah API lama
      // yang sekarang selalu false dan tidak memberi sinyal tambahan.
      if (YoutubeSearchService.isLikelyShortForm(candidate) ||
          YoutubeSearchService.isLikelyNonMusicVideo(candidate)) {
        continue;
      }

      return candidate;
    }

    return null;
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

    for (final video in list.take(15)) {
      if (YoutubeSearchService.isLikelyShortForm(video) ||
          YoutubeSearchService.isLikelyNonMusicVideo(video)) {
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
            'Mencari lagu berikutnya…',
            duration: const Duration(seconds: 1),
          );
        }

        await _radio.refill();
      }

      if (_radio.isPoolEmpty) {
        continue;
      }

      next = _takeNonShortFromRadio();
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
        if (ChannelBlockFilter.isBlocked(video, _blockedChannelKeys)) return false;
        if (YoutubeSearchService.isLikelyShortForm(video)) return false;
        if (YoutubeSearchService.isLikelyNonMusicVideo(video)) return false;
        if (video.isLive || video.isUpcoming) return false;
        if (!MusicStyleMatcher.isCompatible(
          video: video,
          targetStyle: targetStyle,
        )) {
          return false;
        }
        return RadioService.trackKeyFor(video).isNotEmpty;
      }).toList();
      // Active search results may be stale or cached before Shorts filtering.
      // Verify them again so fallback cannot re-introduce a Short into autoplay.
      final verifiedCandidates = await _searchService.removeShorts(candidates);

      if (verifiedCandidates.isNotEmpty) {
        final preferred = MusicStyleMatcher.prioritizeStyle(verifiedCandidates, targetStyle);
        final styleCandidates = preferred.isNotEmpty ? preferred : verifiedCandidates;
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

        next = _pickNonShort(
          styleCandidates,
          random: _playerUiState.value.isShuffle &&
              !_playerUiState.value.isSmartShuffle,
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
      final local = <YoutubeSearchResult>[
        ..._favorites,
        ..._recentlyPlayed,
      ].where((video) {
        return video.videoId != currentId &&
            !_dislikedIds.contains(video.videoId) &&
            !ChannelBlockFilter.isBlocked(video, _blockedChannelKeys) &&
            !YoutubeSearchService.isLikelyShortForm(video) &&
            !YoutubeSearchService.isLikelyNonMusicVideo(video) &&
            !video.isLive &&
            !video.isUpcoming &&
            MusicStyleMatcher.isCompatible(
              video: video,
              targetStyle: targetStyle,
            );
      }).toList();
      // Favorites/history are also possible stale sources; re-verify Shorts.
      final verifiedLocal = await _searchService.removeShorts(local);

      if (verifiedLocal.isNotEmpty) {
        final preferred = MusicStyleMatcher.prioritizeStyle(verifiedLocal, targetStyle);
        next = _pickNonShort(
          preferred.isNotEmpty ? preferred : verifiedLocal,
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

    // Tidak melakukan prefetch hanya karena pool tinggal beberapa lagu.
    // Request halaman baru dilakukan saat pool benar-benar habis di Next berikutnya.
  }
}
