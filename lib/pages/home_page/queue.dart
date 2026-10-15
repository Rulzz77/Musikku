part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Antrean, shuffle pool, dan menu video.
extension _HomeQueue on _HomePageState {
  String? get _shuffleMusicStyle {
    if (_activeSource == _ListSource.favorites ||
        _activeSource == _ListSource.playlist) {
      return null; // Hormati urutan playlist/favorit buatan pengguna.
    }

    final query = _activeSource == _ListSource.radio && _radio.hasSeed
        ? _radio.seed
        : _lastSearchQuery;
    return MusicStyleMatcher.styleForContext(
      query: query,
      currentVideo: _currentVideo,
    );
  }

  void _prepareShufflePool({bool excludeCurrent = true}) {
    final style = _shuffleMusicStyle;
    _shufflePool = _activeList
        .where((video) => MusicStyleMatcher.isCompatible(
              video: video,
              targetStyle: style,
            ))
        .toList();

    if (excludeCurrent && _currentVideo != null) {
      _shufflePool.removeWhere(
        (video) => video.videoId == _currentVideo!.videoId,
      );
    }
  }

  double _smartShuffleScore(
    YoutubeSearchResult video, {
    String? currentArtist,
  }) {
    final stat = _listeningStatsById[video.videoId];
    var score = 10.0;

    if (_likedIds.contains(video.videoId)) {
      score += 10.0;
    }
    if (_dislikedIds.contains(video.videoId)) {
      score -= 100.0;
    }

    if (stat != null) {
      score += (stat.playCount.clamp(0, 8) as num).toDouble() * 1.8;
      score += (stat.listenedSeconds / 600.0).clamp(0.0, 4.0);
      score -= (stat.skipCount.clamp(0, 6) as num).toDouble() * 4.5;

      final lastPlayed = stat.lastPlayedAt;
      if (lastPlayed != null) {
        final hours = DateTime.now().difference(lastPlayed).inMinutes / 60.0;
        if (hours < 24) {
          score -= (24.0 - hours).clamp(0.0, 24.0) / 3.0;
        }
      }
    }

    // Variasi artis: Smart Shuffle sengaja memberi penalti ke artis yang sama
    // dengan lagu aktif agar hasilnya tidak terasa seperti album yang berulang.
    if (currentArtist != null &&
        currentArtist.isNotEmpty &&
        video.channelTitle.trim().toLowerCase() == currentArtist.trim().toLowerCase()) {
      score -= 9.0;
    }

    // Sedikit jitter membuat urutannya tetap bervariasi tanpa kehilangan sinyal
    // personalisasi. Ini bukan random murni.
    score += _random.nextDouble() * 2.5;
    return score;
  }

  YoutubeSearchResult? _takeShuffleVideo() {
    final style = _shuffleMusicStyle;
    _shufflePool.removeWhere((video) => !MusicStyleMatcher.isCompatible(
          video: video,
          targetStyle: style,
        ));
    if (_shufflePool.isEmpty) {
      return null;
    }

    // Kandidat yang label genrenya cocok didahulukan; lagu tanpa label genre
    // baru menjadi fallback setelah kandidat yang dikenali habis.
    final preferred = MusicStyleMatcher.prioritizeStyle(_shufflePool, style);
    final candidatesPool = preferred.isNotEmpty ? preferred : _shufflePool;

    if (!_playerUiState.value.isSmartShuffle) {
      final selected = candidatesPool[_random.nextInt(candidatesPool.length)];
      _shufflePool.removeWhere((video) => video.videoId == selected.videoId);
      return selected;
    }

    final currentArtist = _currentVideo?.channelTitle;
    final scored = candidatesPool
        .map(
          (video) => (
            video: video,
            score: _smartShuffleScore(video, currentArtist: currentArtist),
          ),
        )
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // Ambil dari beberapa kandidat teratas supaya tetap terasa acak, tetapi
    // tidak kehilangan preferensi user.
    final topCount = scored.length < 6 ? scored.length : 6;
    final top = scored.take(topCount).map((item) => item.video).toList();
    final differentArtist = currentArtist == null
        ? top
        : top
            .where(
              (video) => video.channelTitle.trim().toLowerCase() !=
                  currentArtist.trim().toLowerCase(),
            )
            .toList();

    final candidates = differentArtist.isNotEmpty ? differentArtist : top;
    final selected = candidates[_random.nextInt(candidates.length)];
    _shufflePool.removeWhere((video) => video.videoId == selected.videoId);
    return selected;
  }

  void _addToQueue(YoutubeSearchResult video) {
    final added = _queueManager.add(video);

    if (added) {
      unawaited(_storage.saveQueue(_queueManager.items));
    }

    if (!mounted) {
      return;
    }

    setState(() {});

    _toast(
      added
          ? '"${video.title}" ditambahkan ke antrean'
          : '"${video.title}" sudah ada di antrean',
    );
  }

  void _playNext(YoutubeSearchResult video) {
    _queueManager.addNext(video);
    unawaited(_storage.saveQueue(_queueManager.items));

    if (!mounted) {
      return;
    }

    setState(() {});

    _toast('"${video.title}" akan diputar berikutnya');
  }

  void _showVideoMenu(YoutubeSearchResult video, {Playlist? fromPlaylist}) {
    showVideoMenuSheet(
      context,
      video: video,
      isFavorite: _isFavorite(video.videoId),
      isLiked: _likedIds.contains(video.videoId),
      isDisliked: _dislikedIds.contains(video.videoId),
      onLike: () => _toggleLike(video),
      onDislike: () => _toggleDislike(video),
      onOpenArtist: () => _openArtist(video.channelTitle),
      onPlayNext: () => _playNext(video),
      onAddToQueue: () => _addToQueue(video),
      onToggleFavorite: () => _toggleFavorite(video),
      onAddToPlaylist: () => _showAddToPlaylist(video),
      onStartRadio: () => _startRadioFromVideo(video),
      onRemoveFromPlaylist: fromPlaylist == null
          ? null
          : () => _removeFromPlaylist(fromPlaylist, video),
    );
  }
}
