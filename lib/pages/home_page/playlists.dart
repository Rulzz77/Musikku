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
          availableSongs: <YoutubeSearchResult>[
            ..._favorites,
            ..._recentlyPlayed,
            ..._searchResults,
            ..._activeList,
          ],
          onChanged: () {
            _savePlaylists();
            final activeId = _activePlaylistId;
            if (activeId != null) {
              for (final playlist in _playlists) {
                if (playlist.id == activeId) {
                  _refreshActivePlaylist(playlist);
                  break;
                }
              }
            }
            if (mounted) setState(() {});
          },
          onPlayPlaylist: _playCustomPlaylist,
          onPlaySong: _playCustomPlaylistSong,
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

  Future<void> _playCustomPlaylistSong(
    Playlist playlist,
    YoutubeSearchResult video,
  ) async {
    if (playlist.songs.isEmpty ||
        !playlist.songs.any((song) => song.videoId == video.videoId)) {
      return;
    }
    _activeList = PlaybackSourcePolicy.sameSourceAs(
      playlist.songs,
      selected: video,
    );
    _activeSource = _ListSource.playlist;
    _activePlaylistId = playlist.id;
    if (_playerUiState.value.isShuffle) {
      _prepareShufflePool(excludeCurrent: true, sourceVideo: video);
    }
    await _openYoutubeVideo(video);
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

    final current = _currentVideo;
    final songsForCurrentSource = current == null
        ? List<YoutubeSearchResult>.from(playlist.songs)
        : PlaybackSourcePolicy.sameSourceAs(playlist.songs, selected: current);
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
