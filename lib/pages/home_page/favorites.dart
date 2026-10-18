part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Favorit, like/dislike, dan putar semua favorit.
extension _HomeFavorites on _HomePageState {
  bool _isFavorite(String videoId) {
    return _favorites.any((video) => video.videoId == videoId);
  }

  void _toggleFavorite(YoutubeSearchResult video) {
    final index = _favorites.indexWhere(
      (item) => item.videoId == video.videoId,
    );

    final added = index == -1;

    setState(() {
      if (added) {
        _favorites.insert(0, video);
      } else {
        _favorites.removeAt(index);
      }
    });

    unawaited(_storage.saveFavorites(_favorites));

    _refreshActiveFavorites();

    _syncFavoriteFlag();

    _toast(
      added ? 'Ditambahkan ke favorit' : 'Dihapus dari favorit',
      duration: const Duration(seconds: 1),
    );
  }

  /// Sinkronkan status hati di full player dengan lagu yang sedang diputar.
  void _syncFavoriteFlag() {
    final id = _currentVideo?.videoId;

    _playerUiState.value = _playerUiState.value.copyWith(
      isFavorite: id != null && _isFavorite(id),
    );
  }

  void _syncFeedbackFlags() {
    final id = _currentVideo?.videoId;

    _playerUiState.value = _playerUiState.value.copyWith(
      isLiked: id != null && _likedIds.contains(id),
      isDisliked: id != null && _dislikedIds.contains(id),
    );
  }

  Future<void> _toggleLike(YoutubeSearchResult video) async {
    final alreadyLiked = _likedIds.contains(video.videoId);

    setState(() {
      if (alreadyLiked) {
        _likedIds.remove(video.videoId);
      } else {
        _likedIds.add(video.videoId);
        _dislikedIds.remove(video.videoId);
      }
    });

    await Future.wait([
      _storage.saveLikedIds(_likedIds),
      _storage.saveDislikedIds(_dislikedIds),
    ]);
    _syncFeedbackFlags();
    _toast(alreadyLiked ? 'Like dibatalkan' : 'Disukai 👍', duration: const Duration(seconds: 1));
  }

  Future<void> _toggleDislike(YoutubeSearchResult video) async {
    final alreadyDisliked = _dislikedIds.contains(video.videoId);

    setState(() {
      if (alreadyDisliked) {
        _dislikedIds.remove(video.videoId);
      } else {
        _dislikedIds.add(video.videoId);
        _likedIds.remove(video.videoId);
      }
    });

    await Future.wait([
      _storage.saveLikedIds(_likedIds),
      _storage.saveDislikedIds(_dislikedIds),
    ]);
    _syncFeedbackFlags();
    _toast(
      alreadyDisliked ? 'Dislike dibatalkan' : 'Tidak akan direkomendasikan lagi',
      duration: const Duration(seconds: 1),
    );
  }

  /// Kalau playlist aktif = favorit, perbarui daftar & shuffle pool
  /// saat favorit ditambah / dihapus.
  void _refreshActiveFavorites() {
    if (_activeSource != _ListSource.favorites) {
      return;
    }

    final ids = _favorites.map((video) => video.videoId).toSet();
    final known = _activeList.map((video) => video.videoId).toSet();

    _activeList = List<YoutubeSearchResult>.from(_favorites);

    _shufflePool.removeWhere((video) => !ids.contains(video.videoId));

    for (final video in _favorites) {
      if (!known.contains(video.videoId) &&
          video.videoId != _currentVideo?.videoId) {
        _shufflePool.add(video);
      }
    }
    if (_playerUiState.value.isShuffle) {
      _prepareShufflePool(excludeCurrent: true, sourceVideo: _currentVideo);
    }
  }
}
