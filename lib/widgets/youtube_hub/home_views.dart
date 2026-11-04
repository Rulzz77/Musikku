part of '../youtube_hub.dart';

// The state extensions share private UI logic; State.setState is used by this library.
// ignore_for_file: invalid_use_of_protected_member

extension _YoutubeHubHomeViews on _YoutubeHubState {
  /// Beranda musik: lagu populer kategori Music di Indonesia.
  /// Trending memakai API key, jadi TIDAK perlu login.
  Future<void> _loadHome({bool force = false}) async {
    if (!mounted) return;
    final requestSequence = ++_homeRequestSequence;
    setState(() {
      _feedLoading = true;
      _feedError = '';
    });
    try {
      final videos = await _searchService.mostPopular(
        categoryId: '10',
        maxResults: widget.settings.dataSaverLevel >= 2 ? 12 : (widget.settings.dataSaverLevel == 1 ? 20 : 30),
        force: force,
      );
      if (!mounted || requestSequence != _homeRequestSequence) return;
      final freshVideos = List<YoutubeSearchResult>.from(videos);
      if (force && freshVideos.length > 1) {
        freshVideos.shuffle(_feedRandom);
      }
      setState(() => _trending = freshVideos);
    } catch (e) {
      if (!mounted || requestSequence != _homeRequestSequence) return;
      debugPrint('YOUTUBE TRENDING ERROR: $e');
      setState(() {
        _feedError = e is YoutubeSearchException
            ? e.message
            : 'Tidak bisa memuat lagu. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      if (mounted && requestSequence == _homeRequestSequence) {
        setState(() => _feedLoading = false);
      }
    }
  }

  /// Chip beranda hanya menampilkan katalog musik dan lagu terbaru.
  Future<void> _selectChip(int index, {bool force = false}) async {
    final requestSequence = ++_chipRequestSequence;
    _homeRequestSequence++;
    _searchRequestId++; // batalkan pencarian yang masih berjalan
    _searchController.clear();
    setState(() {
      _activeChip = index;
      _query = '';
      _searchMode = 'music';
      _searchResults = const [];
      _searchChannels = const [];
      _section = _YoutubeSection.home;
      _loading = false;
      _error = '';
      _feedError = '';
    });
    if (!force && (_chipFeeds[index]?.isNotEmpty ?? false)) {
      if (mounted && _chipLoading) setState(() => _chipLoading = false);
      return;
    }

    setState(() => _chipLoading = true);
    try {
      final List<YoutubeSearchResult> videos;
      switch (index) {
        case 1:
          videos = await _searchService.mostPopular(
            categoryId: '10',
            maxResults: widget.settings.dataSaverLevel >= 2 ? 12 : (widget.settings.dataSaverLevel == 1 ? 20 : 30),
            force: force,
          );
          break;
        case 2:
        default:
          videos = await _searchService.recentPopular(
            maxResults: widget.settings.dataSaverLevel >= 2 ? 12 : (widget.settings.dataSaverLevel == 1 ? 20 : 30),
            force: force,
          );
          break;
      }
      if (!mounted ||
          requestSequence != _chipRequestSequence ||
          _activeChip != index) {
        return;
      }
      final freshVideos = List<YoutubeSearchResult>.from(videos);
      if (force && freshVideos.length > 1) {
        freshVideos.shuffle(_feedRandom);
      }
      setState(() => _chipFeeds[index] = freshVideos);
    } catch (e) {
      if (!mounted ||
          requestSequence != _chipRequestSequence ||
          _activeChip != index) {
        return;
      }
      debugPrint('YOUTUBE CHIP ERROR: $e');
      setState(() {
        _feedError = e is YoutubeSearchException
            ? e.message
            : 'Tidak bisa memuat lagu. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      if (mounted && requestSequence == _chipRequestSequence) {
        setState(() => _chipLoading = false);
      }
    }
  }

  List<Widget> _chipSections() {
    final videos = _chipFeeds[_activeChip] ?? const <YoutubeSearchResult>[];
    return [
      _sectionHeader(_YoutubeHubState._chipTitles[_activeChip] ?? 'Musik'),
      if (videos.isEmpty && _chipLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (videos.isEmpty)
        _homeEmptyState(retry: () => _selectChip(_activeChip, force: true))
      else
        SliverList.builder(
          itemCount: videos.length,
          itemBuilder: (context, index) => _videoCard(videos[index]),
        ),
    ];
  }

  List<Widget> _homeSections() {
    // Filter views reuse the same search and feed pipeline as before.
    if (_activeChip >= 1 && _activeChip <= 3) {
      return [
        SliverToBoxAdapter(child: _modernWelcomeHeader()),
        _chipRow(),
        ..._chipSections(),
      ];
    }

    // Music-only public feed; no signed-in subscription uploads are used.
    final feed = <YoutubeSearchResult>[];
    final seenFeedIds = <String>{};
    for (final video in _trending) {
      if (video.isLive ||
          video.isUpcoming ||
          !YoutubeSearchService.isMusicCatalogItem(video) ||
          video.videoId.isEmpty ||
          !seenFeedIds.add(video.videoId)) {
        continue;
      }
      feed.add(video);
    }

    final recentlyPlayed = widget.recentlyPlayed
        .where((video) => YoutubeSearchService.isMusicCandidate(video))
        .take(12)
        .toList(growable: false);
    final smartPlaylists = _buildSmartPlaylists();
    final frequentMix = _findFrequentMix(smartPlaylists);
    final openListeningRoom = widget.onOpenListeningRoom;
    final actions = <({String title, String subtitle, IconData icon, VoidCallback onTap})>[
      if (frequentMix != null)
        (
          title: 'Mix untukmu',
          subtitle: '${frequentMix.songs.length} lagu dari kebiasaanmu',
          icon: Icons.auto_awesome_rounded,
          onTap: () => _playFrequentMix(frequentMix),
        ),
      if (openListeningRoom != null)
        (
          title: 'Dengar bareng',
          subtitle: 'Buat ruang atau gabung teman',
          icon: Icons.headphones_rounded,
          onTap: openListeningRoom,
        ),
    ];
    final isFirstTime = recentlyPlayed.isEmpty &&
        widget.favorites.isEmpty &&
        widget.customPlaylists.isEmpty;

    // Beranda hanya berisi jalur utama: cari musik, mulai mendengarkan,
    // kelola playlist, lanjutkan lagu, lalu rekomendasi. Fitur sekunder
    // dipindahkan ke Koleksi atau Pengaturan agar tidak tersebar.
    return [
      SliverToBoxAdapter(child: _modernWelcomeHeader()),
      _chipRow(),
      if (isFirstTime)
        SliverToBoxAdapter(child: _firstTimeGuide()),
      if (actions.isNotEmpty)
        SliverToBoxAdapter(child: _homeShortcutRow(actions)),
      ..._customPlaylistSection(),
      if (smartPlaylists.isNotEmpty) ...[
        _sectionHeader('Playlist pintar', action: 'Lihat semua', onAction: _showSmartPlaylistPicker),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 118,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              scrollDirection: Axis.horizontal,
              itemCount: smartPlaylists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _smartPlaylistCard(smartPlaylists[index]),
            ),
          ),
        ),
      ],
      if (recentlyPlayed.isNotEmpty) ...[
        _sectionHeader(
          'Lanjutkan mendengarkan',
          action: recentlyPlayed.length > 1 ? 'Putar semua' : null,
          onAction: recentlyPlayed.length > 1
              ? () => unawaited(widget.onPlayFromList(recentlyPlayed.first, recentlyPlayed))
              : null,
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 204,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              scrollDirection: Axis.horizontal,
              itemCount: recentlyPlayed.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _quickPickCard(recentlyPlayed[index]),
            ),
          ),
        ),
      ],
      if (feed.isNotEmpty) ...[
        _sectionHeader('Pilihan musik untukmu'),
        SliverList.builder(
          itemCount: feed.length,
          itemBuilder: (context, index) => _videoCard(feed[index]),
        ),
      ] else if (_feedLoading || _inlineLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else
        _homeEmptyState(retry: () => _loadHome(force: true)),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
    ];
  }

  /// Playlist buatan sendiri, tampil langsung di beranda supaya mudah diputar.
  List<Widget> _customPlaylistSection() {
    final playlists = widget.customPlaylists;
    final open = widget.onOpenCustomPlaylists;
    if (playlists.isEmpty && open == null) return const <Widget>[];
    final shown = playlists.take(12).toList(growable: false);
    return [
      _sectionHeader(
        'Playlist kamu',
        action: open == null ? null : (playlists.isEmpty ? 'Buat' : 'Lihat semua'),
        onAction: open,
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 118,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            scrollDirection: Axis.horizontal,
            itemCount: playlists.isEmpty ? 1 : shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => playlists.isEmpty
                ? _createPlaylistCard(open!)
                : _customPlaylistCard(shown[index]),
          ),
        ),
      ),
    ];
  }

  Widget _createPlaylistCard(VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 190,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(19),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline_rounded, size: 30, color: scheme.primary),
              const SizedBox(height: 8),
              Text(
                'Buat playlist pertamamu',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customPlaylistCard(Playlist playlist) {
    final scheme = Theme.of(context).colorScheme;
    final first = playlist.songs.isEmpty ? null : playlist.songs.first;
    final play = widget.onPlayCustomPlaylist;
    final open = widget.onOpenCustomPlaylists;
    final canPlay = first != null && play != null;
    return SizedBox(
      width: 190,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(19),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Playlist kosong / tanpa handler putar: buka halaman playlist.
          onTap: canPlay ? () => unawaited(play(playlist)) : open,
          onLongPress: open,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (first != null)
                PlaylistArtwork(playlist: playlist, fit: BoxFit.cover, iconSize: 30)
              else
                ColoredBox(
                  color: scheme.surfaceContainerHighest,
                  child: Center(
                    child: Icon(Icons.queue_music_rounded, size: 34, color: scheme.onSurfaceVariant),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x12000000), Color(0xD9000000)],
                    stops: [0.05, 1],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 10,
                bottom: 11,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            playlist.name.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            playlist.songs.isEmpty ? 'Kosong' : '${playlist.songs.length} lagu',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canPlay)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.play_arrow_rounded, color: scheme.onPrimary, size: 22),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<SmartPlaylist> _buildSmartPlaylists() {
    final catalog = <YoutubeSearchResult>[
      ..._trending,
      ..._chipFeeds.values.expand((items) => items),
      ..._searchResults,
      ..._exploreResults,
    ].where(YoutubeSearchService.isMusicCandidate).toList(growable: false);
    return SmartPlaylistService.build(
      favorites: widget.favorites.where(YoutubeSearchService.isMusicCandidate).toList(growable: false),
      recentlyPlayed: widget.recentlyPlayed.where(YoutubeSearchService.isMusicCandidate).toList(growable: false),
      listeningStats: widget.listeningStats,
      catalog: catalog,
    );
  }

  void _playSmartPlaylist(SmartPlaylist playlist) {
    if (playlist.songs.isEmpty) return;
    unawaited(widget.onPlayFromList(playlist.songs.first, playlist.songs));
  }

  void _showSmartPlaylistPicker() {
    final playlists = _buildSmartPlaylists();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        if (playlists.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 40, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                const Text('Playlist pintar belum tersedia', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'Simpan lagu ke favorit atau dengarkan beberapa lagu dulu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text('Playlist pintar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              for (final playlist in playlists)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.surfaceContainerHigh,
                    child: Icon(_smartPlaylistIcon(playlist.id), color: scheme.onSurface),
                  ),
                  title: Text(playlist.title),
                  subtitle: Text('${playlist.songs.length} lagu · ${playlist.subtitle}'),
                  trailing: const Icon(Icons.play_arrow_rounded),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _playSmartPlaylist(playlist);
                  },
                  onLongPress: () {
                    Navigator.pop(sheetContext);
                    _showSongList(playlist.title, playlist.songs);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _smartPlaylistIcon(String id) {
    return switch (id) {
      'smart_favorites' => Icons.favorite_rounded,
      'smart_recent' => Icons.history_rounded,
      'smart_most_played' => Icons.trending_up_rounded,
      _ => Icons.replay_rounded,
    };
  }

  Widget _smartPlaylistCard(SmartPlaylist playlist) {
    final scheme = Theme.of(context).colorScheme;
    final first = playlist.songs.first;
    return SizedBox(
      width: 190,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(19),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playSmartPlaylist(playlist),
          onLongPress: () => _showSongList(playlist.title, playlist.songs),
          child: Stack(
            fit: StackFit.expand,
            children: [
              UnifiedArtwork(track: first, fit: BoxFit.cover, iconSize: 30),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x12000000), Color(0xD9000000)],
                    stops: [0.05, 1],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 10,
                bottom: 11,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            playlist.title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${playlist.songs.length} lagu',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.play_arrow_rounded, color: scheme.onPrimary, size: 22),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  SmartPlaylist? _findFrequentMix(List<SmartPlaylist> playlists) {
    for (final playlist in playlists) {
      if (playlist.id == 'smart_most_played' && playlist.songs.isNotEmpty) {
        return playlist;
      }
    }
    return null;
  }

  void _playFrequentMix(SmartPlaylist? playlist) {
    if (playlist == null || playlist.songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mix kamu akan muncul setelah beberapa lagu diputar berulang kali.'),
        ),
      );
      return;
    }
    // Keep the listening-frequency ranking; do not shuffle it into a random mix.
    unawaited(widget.onPlayFromList(playlist.songs.first, playlist.songs));
  }

  void _openRecentHistory() {
    final songs = widget.recentlyPlayed
        .where(YoutubeSearchService.isMusicCandidate)
        .toList(growable: false);
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada riwayat lagu yang cocok dengan filter musik.')),
      );
      return;
    }
    _showSongList('Riwayat dengar MusikKu', songs);
  }

  void _openFavoritesList() {
    final songs = widget.favorites
        .where(YoutubeSearchService.isMusicCandidate)
        .toList(growable: false);
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada favorit yang cocok dengan filter musik.')),
      );
      return;
    }
    _showSongList('Favorit MusikKu', songs);
  }

  /// Pintasan: ikon bulat dengan satu baris label. Keterangan tambahan
  /// (jumlah lagu, dll.) tampil sebagai tooltip saat ditekan lama.
  Widget _homeShortcutRow(
    List<({String title, String subtitle, IconData icon, VoidCallback onTap})> actions,
  ) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 1, 16, 7),
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _homeShortcutItem(
          title: actions[index].title,
          subtitle: actions[index].subtitle,
          icon: actions[index].icon,
          onTap: actions[index].onTap,
          highlighted: actions[index].title == 'Dengar bareng',
        ),
      ),
    );
  }

  Widget _homeShortcutItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool highlighted = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accent = highlighted ? scheme.secondary : scheme.primary;
    return Tooltip(
      message: subtitle,
      child: SizedBox(
        width: 148,
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: Icon(icon, size: 17, color: accent),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_outward_rounded, size: 13, color: scheme.onSurfaceVariant.withValues(alpha: 0.65)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 11.5, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modernWelcomeHeader() {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, topInset + 10, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SELAMAT DATANG',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                    Text(
                      'MusikKu',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Pengaturan',
                onPressed: _showAppSettings,
                style: IconButton.styleFrom(
                  fixedSize: const Size(42, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(Icons.settings_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            'Mau dengar apa hari ini?',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 22,
              height: 1.08,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.65,
            ),
          ),
          const SizedBox(height: 9),
          Material(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _openSearch,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 52,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: scheme.primary, size: 21),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cari lagu, artis, atau album',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: scheme.onSurfaceVariant,
                        size: 17,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _firstTimeGuide() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.waving_hand_rounded, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Baru pertama kali di MusikKu?',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '1. Cari lagu lewat kolom di atas.  2. Ketuk lagu untuk memutar.  3. Tekan ikon hati untuk menyimpan favorit.',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 11),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _selectDockDestination(_YoutubeSection.explore.index),
                  icon: const Icon(Icons.explore_outlined, size: 17),
                  label: const Text('Jelajahi genre musik'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeEmptyState({Future<void> Function()? retry}) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 24),
        child: Column(
          children: [
            Icon(Icons.library_music_rounded, size: 44, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              _feedError.isNotEmpty ? 'Lagu belum bisa dimuat' : 'Beranda masih kosong',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _feedError.isNotEmpty
                  ? _feedError
                  : 'Cari lagu lewat kolom pencarian atau pilih rekomendasi musik di beranda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (retry != null)
                  FilledButton.icon(
                    onPressed: () => unawaited(retry()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Coba lagi'),
                  ),
                OutlinedButton.icon(
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Telusuri'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}