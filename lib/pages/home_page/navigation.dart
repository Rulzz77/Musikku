part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Navigasi ke halaman lain, tombol Back, dan backup/restore.
extension _HomeNavigation on _HomePageState {
  /// Dipanggil saat notifikasi sistem (live / video baru) diketuk.
  void _openVideoFromNotification(Map<String, String> data) {
    if (!mounted) return;
    final id = data['videoId'] ?? '';
    if (id.isEmpty) return;
    unawaited(_openYoutubeVideo(YoutubeSearchResult(
      videoId: id,
      title: (data['title'] ?? '').isEmpty ? 'Video' : data['title']!,
      channelTitle: data['channelTitle'] ?? '',
      thumbnailUrl: '',
    )));
  }

  Future<void> _playFromCustomList(
    YoutubeSearchResult video,
    List<YoutubeSearchResult> list,
  ) async {
    if (!mounted || list.isEmpty) return;
    _activeSource = _ListSource.local;
    _activePlaylistId = null;
    _activeList = List<YoutubeSearchResult>.from(list);
    if (_playerUiState.value.isShuffle) {
      _prepareShufflePool(excludeCurrent: true);
    }
    await _openYoutubeVideo(video);
  }

  Future<void> _openYoutubeVideo(YoutubeSearchResult video) async {
    if (!mounted) return;
    final sameSong = _currentVideo?.videoId == video.videoId &&
        !_restoredNeedsLoad &&
        _nativeState.playbackState != NativePlaybackState.error &&
        (video.isLocal || _youtubeController.isUsingYoutubeAudio);
    setState(() {
      _youtubeWatchVideo = video;
      _youtubeSystemPipMode = false;
      _suppressAutoNextInPip = false;
    });

    if (sameSong) {
      if (!_nativeState.isEffectivelyPlaying) {
        try {
          await _youtubeController.playVideo();
        } catch (_) {}
      }
      return;
    }
    await _playVideo(video);
  }

  void _handleYoutubeWatchBack() {
    if (!mounted) return;
    unawaited(_closeYoutubeWatch());
  }

  /// Menutup tampilan Now Playing tanpa menghentikan musik.
  Future<void> _closeYoutubeWatch() async {
    if (!mounted) return;
    try {
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _youtubeWatchVideo = null;
      _youtubeSystemPipMode = false;
      _suppressAutoNextInPip = false;
    });
  }

  /// Buka lagi halaman tonton untuk video yang sedang diputar
  /// (dari PiP) tanpa memuat ulang videonya.
  void _openYoutubeWatchFromPlayer() {
    final video = _currentVideo;
    if (video == null || !mounted) return;
    unawaited(_youtubeController.setPlayerUiVisible(true));
    setState(() {
      _youtubeWatchVideo = video;
      _suppressAutoNextInPip = false;
    });
  }

  /// Zoom player saat "Potong tepi video" aktif.
  double get _videoCropZoom => widget.settings.cropVideoBranding.value ? 1.12 : 1.0;

  void _applyVideoCrop() {
    unawaited(_youtubeController.setVideoCrop(_videoCropZoom));
  }

  void _openArtist(String artist) {
    final name = artist.trim();
    if (name.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArtistPage(
          artist: name,
          searchService: _searchService,
          onPlay: (video) {
            _activeSource = _ListSource.radio;
            _radio.start('$name music');
            unawaited(_playVideo(video));
          },
          onLongPress: _showVideoMenu,
        ),
      ),
    );
  }

  /// Mengembalikan true kalau Back dipakai untuk "mundur" satu layar
  /// di dalam app. False = sudah di layar depan, biarkan app ke background.
  bool _handleBack() {
    // 0) Kalau layar Now Playing terbuka, Back pertama menutupnya tanpa
    // menghentikan pemutaran audio.
    if (_youtubeWatchVideo != null) {
      _handleYoutubeWatchBack();
      return true;
    }

    // 0b) Halaman channel terbuka di hub -> tutup, kembali ke hub.
    if (_hubController.handleBack()) {
      return true;
    }

    // 1) Keyboard / kolom cari sedang aktif.
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();

      return true;
    }

    // 2) Sedang membuka isi satu playlist -> kembali ke daftar playlist.
    if (_showPlaylists && _openPlaylistId != null) {
      setState(() {
        _openPlaylistId = null;
      });

      return true;
    }

    // 3) Layar favorit / playlist -> kembali ke layar depan.
    if (_showFavorites || _showPlaylists) {
      setState(() {
        _showFavorites = false;
        _showPlaylists = false;
        _openPlaylistId = null;
      });

      return true;
    }

    // 4) Hasil pencarian -> bersihkan, kembali ke layar depan.
    if (_searchResults.isNotEmpty ||
        _errorMessage.isNotEmpty ||
        _isLoading) {
      _searchController.clear();

      setState(() {
        _searchResults = [];
        _errorMessage = '';
        _isLoading = false;
      });

      return true;
    }

    return false;
  }


}
