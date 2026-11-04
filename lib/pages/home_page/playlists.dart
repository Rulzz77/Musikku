part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Playlist buatan sendiri (buat, ubah nama, hapus, putar).
extension _HomePlaylists on _HomePageState {
  void _savePlaylists() {
    unawaited(_storage.savePlaylists(_playlists));
  }

  void _openCustomPlaylistsPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomPlaylistsPage(
          playlists: _playlists,
          playerUiState: _playerUiState,
          availableSongs: <YoutubeSearchResult>[
            ..._favorites,
            ..._recentlyPlayed,
            ..._searchResults,
            ..._activeList,
          ],
          onChanged: _handleCustomPlaylistsChanged,
          onPlayPlaylist: _playCustomPlaylist,
          onPlayOfflinePlaylist: _playOfflineCustomPlaylist,
          onPlaySong: _playCustomPlaylistSong,
          onShufflePlaylist: _playShuffledCustomPlaylist,
          currentVideo: _currentVideo,
          nativeState: _nativeStateNotifier,
          onOpenCurrentPlayer: _openYoutubeWatchFromPlayer,
          onMiniPlayPause: () => _routeListenTogetherAction('play_pause', _togglePlayPause),
          onMiniNext: () => _routeListenTogetherAction('next', () => _next()),
          onSelectTab: _hubController.selectTab,
        ),
      ),
    );
  }

  Future<void> _playCustomPlaylist(Playlist playlist) async {
    if (playlist.songs.isEmpty) {
      _toast('Playlist ini masih kosong');
      return;
    }
    await _playCustomPlaylistSong(playlist, playlist.songs.first);
  }

  /// Putar salinan offline dari lagu online yang sudah diunduh.
  /// Gunakan ID lokal stabil untuk sinkronisasi state Media3. Entri online
  /// asli tetap disimpan di playlist, lengkap dengan path file unduhannya.
  YoutubeSearchResult _asDownloadedLocalTrack(YoutubeSearchResult song) {
    return song.copyWith(
      videoId: 'local:offline_${song.videoId}',
      sourceType: 'local',
      mediaUri: Uri.file(song.offlinePath).toString(),
      localMediaId: 'offline_${song.videoId}',
    );
  }

  YoutubeSearchResult _asPlayablePlaylistTrack(YoutubeSearchResult song) {
    if (song.isLocal) return song;
    if (song.isOfflineDownloaded && File(song.offlinePath).existsSync()) {
      return _asDownloadedLocalTrack(song);
    }
    return song;
  }

  Future<void> _playOfflineCustomPlaylist(Playlist playlist) async {
    final offlineSongs = playlist.songs
        .where((song) => song.isLocal ||
            (song.isOfflineDownloaded && File(song.offlinePath).existsSync()))
        .map((song) => song.isLocal ? song : _asDownloadedLocalTrack(song))
        .toList(growable: false);
    if (offlineSongs.isEmpty) {
      _toast('Belum ada lagu yang selesai diunduh di playlist ini');
      return;
    }

    _activeList = PlaybackSourcePolicy.explicitPlaylistItems(offlineSongs);
    _activeSource = _ListSource.playlist;
    _activePlaylistId = playlist.id;
    _activePlaylistOfflineOnly = true;
    final firstSong = offlineSongs.first;
    if (_playerUiState.value.isShuffle) {
      _prepareShufflePool(excludeCurrent: true, sourceVideo: firstSong);
    }
    await _openYoutubeVideo(firstSong, preserveListContext: true);
  }

  Future<void> _playShuffledCustomPlaylist(Playlist playlist) async {
    if (playlist.songs.isEmpty) {
      _toast('Playlist ini masih kosong');
      return;
    }
    final shuffledSongs = playlist.songs
        .map(_asPlayablePlaylistTrack)
        .toList(growable: true)
      ..shuffle();
    _activeList = PlaybackSourcePolicy.explicitPlaylistItems(shuffledSongs);
    _activeSource = _ListSource.playlist;
    _activePlaylistId = playlist.id;
    _activePlaylistOfflineOnly = false;
    final firstSong = shuffledSongs.first;
    if (_playerUiState.value.isShuffle) {
      _prepareShufflePool(excludeCurrent: true, sourceVideo: firstSong);
    }
    await _openYoutubeVideo(firstSong, preserveListContext: true);
  }

  Future<void> _playCustomPlaylistSong(
    Playlist playlist,
    YoutubeSearchResult video,
  ) async {
    if (playlist.songs.isEmpty ||
        !playlist.songs.any((song) => song.videoId == video.videoId)) {
      return;
    }
    // A user's playlist is the playback contract. Prefer a saved local copy
    // for entries already downloaded; keep the online source for the rest.
    final playableSongs = playlist.songs
        .map(_asPlayablePlaylistTrack)
        .toList(growable: false);
    final selectedSong = _asPlayablePlaylistTrack(video);
    _activeList = PlaybackSourcePolicy.explicitPlaylistItems(playableSongs);
    _activeSource = _ListSource.playlist;
    _activePlaylistId = playlist.id;
    _activePlaylistOfflineOnly = false;
    if (_playerUiState.value.isShuffle) {
      _prepareShufflePool(excludeCurrent: true, sourceVideo: selectedSong);
    }
    await _openYoutubeVideo(selectedSong, preserveListContext: true);
  }

  /// Buat playlist baru. Kalau [thenAdd] diisi, lagu itu langsung dimasukkan.
  Future<void> _createPlaylist({YoutubeSearchResult? thenAdd}) async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Playlist baru',
      confirmLabel: 'Buat',
    );

    if (name == null || !mounted) {
      return;
    }

    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      songs: thenAdd == null ? null : [thenAdd],
    );

    setState(() {
      _playlists.insert(0, playlist);
    });

    _savePlaylists();

    _toast(
      thenAdd == null
          ? 'Playlist "$name" dibuat'
          : 'Ditambahkan ke "$name"',
      duration: const Duration(seconds: 1),
    );
  }

  void _showAddToPlaylist(YoutubeSearchResult video) {
    showAddToPlaylistSheet(
      context,
      video: video,
      playlists: _playlists,
      onCreateNew: () => unawaited(_createPlaylist(thenAdd: video)),
      onToggle: (playlist) {
        final index = playlist.songs.indexWhere(
          (song) => song.videoId == video.videoId,
        );

        setState(() {
          if (index == -1) {
            playlist.songs.add(video);
          } else {
            playlist.songs.removeAt(index);
          }
        });

        _savePlaylists();
        _refreshActivePlaylist(playlist);

        _toast(
          index == -1
              ? 'Ditambahkan ke "${playlist.name}"'
              : 'Dihapus dari "${playlist.name}"',
          duration: const Duration(seconds: 1),
        );
      },
    );
  }

  void _removeFromPlaylist(Playlist playlist, YoutubeSearchResult video) {
    setState(() {
      playlist.songs.removeWhere((song) => song.videoId == video.videoId);
    });

    _savePlaylists();
    _refreshActivePlaylist(playlist);

    _toast(
      'Dihapus dari "${playlist.name}"',
      duration: const Duration(seconds: 1),
    );
  }

  /// Kalau playlist yang sedang diputar diedit, perbarui daftar aktif
  /// dan shuffle pool supaya Next tidak memutar lagu yang sudah dihapus.
  void _refreshActivePlaylist(Playlist playlist) {
    if (_activeSource != _ListSource.playlist ||
        _activePlaylistId != playlist.id) {
      return;
    }

    final seenIds = <String>{};
    // Keep the playlist exactly as edited. PlaybackSourcePolicy.sameSourceAs
    // inserts the current track if absent, which is useful for a new context
    // but wrong when a user removes that track from the active playlist.
    final sourceSongs = _activePlaylistOfflineOnly
        ? playlist.songs
            .where((song) => song.isLocal ||
                (song.isOfflineDownloaded && File(song.offlinePath).existsSync()))
            .map((song) => song.isLocal ? song : _asDownloadedLocalTrack(song))
        : playlist.songs.map(_asPlayablePlaylistTrack);
    final songsForCurrentSource = sourceSongs.where((song) {
      // Do not silently remove local or remote entries from a custom playlist.
      // The explicit playlist remains fixed even when its sources are mixed.
      final id = song.videoId.trim();
      if (id.isEmpty) return false;
      return seenIds.add(id);
    }).toList(growable: false);
    final ids = songsForCurrentSource.map((song) => song.videoId).toSet();
    final known = _activeList.map((song) => song.videoId).toSet();

    _activeList = List<YoutubeSearchResult>.from(songsForCurrentSource);

    _shufflePool.removeWhere((song) => !ids.contains(song.videoId));

    for (final song in songsForCurrentSource) {
      if (!known.contains(song.videoId) &&
          song.videoId != _currentVideo?.videoId) {
        _shufflePool.add(song);
      }
    }
    if (_playerUiState.value.isShuffle) {
      _prepareShufflePool(excludeCurrent: true, sourceVideo: _currentVideo);
    }
  }
}
