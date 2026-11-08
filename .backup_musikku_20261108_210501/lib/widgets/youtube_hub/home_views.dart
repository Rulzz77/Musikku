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
    if (_activeChip >= 1 && _activeChip <= 3) {
      return [
        SliverToBoxAdapter(child: _modernWelcomeHeader()),
        _chipRow(),
        ..._chipSections(),
      ];
    }

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

    final recent = widget.recentlyPlayed
        .where(YoutubeSearchService.isMusicCandidate)
        .take(8)
        .toList(growable: false);
    final smartPlaylists = _buildSmartPlaylists();
    final firstFeatured = smartPlaylists.isNotEmpty
        ? smartPlaylists.first
        : null;

    return [
      SliverToBoxAdapter(child: _modernWelcomeHeader()),
      _sectionHeader('Quick Picks', action: 'Koleksi', onAction: () => _selectDockDestination(_YoutubeSection.library.index)),
      SliverToBoxAdapter(child: _quickPicksGrid(recent)),
      _sectionHeader(
        'Made For You',
        action: smartPlaylists.isNotEmpty ? 'Lihat semua' : null,
        onAction: smartPlaylists.isNotEmpty ? _showSmartPlaylistPicker : null,
      ),
      if (firstFeatured != null)
        SliverToBoxAdapter(child: _madeForYouCards(smartPlaylists))
      else if (feed.isNotEmpty)
        SliverToBoxAdapter(child: _featuredDiscoveryCard(feed.first, label: 'Pilihan untukmu'))
      else if (_feedLoading || _inlineLoading)
        const SliverToBoxAdapter(child: _HomeSectionSkeleton(height: 174)),
      if (recent.isNotEmpty) ...[
        _sectionHeader('Recently Played', action: 'Lihat semua', onAction: _openRecentHistory),
        SliverList.builder(
          itemCount: min(recent.length, 5),
          itemBuilder: (context, index) => _videoCard(recent[index]),
        ),
      ],
      _sectionHeader('Your Mixes'),
      SliverToBoxAdapter(child: _moodGrid()),
      if (recent.isNotEmpty) ...[
        _sectionHeader('Continue Listening', action: 'Lihat semua', onAction: _openRecentHistory),
        SliverList.builder(
          itemCount: min(recent.length, 4),
          itemBuilder: (context, index) => _continueListeningRow(recent[index]),
        ),
      ],
      _sectionHeader('Discover Something New'),
      if (feed.isNotEmpty) ...[
        if (feed.length > (firstFeatured == null ? 1 : 0))
          SliverToBoxAdapter(
            child: _featuredDiscoveryCard(
              feed[firstFeatured == null ? 1 : 0],
              label: 'Featured discovery',
            ),
          ),
        if (feed.length > (firstFeatured == null ? 2 : 1))
          SliverList.builder(
            itemCount: min(feed.length - (firstFeatured == null ? 2 : 1), 5),
            itemBuilder: (context, index) => _videoCard(feed[index + (firstFeatured == null ? 2 : 1)]),
          ),
      ] else if (_feedLoading || _inlineLoading)
        const SliverToBoxAdapter(child: _HomeSectionSkeleton(height: 220))
      else
        _homeEmptyState(retry: () => _loadHome(force: true)),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  Widget _quickPicksGrid(List<YoutubeSearchResult> recent) {
    final firstFavorite = widget.favorites.isEmpty ? null : widget.favorites.first;
    final firstRecent = recent.isEmpty ? null : recent.first;
    final firstPlaylist = widget.customPlaylists.isEmpty || widget.customPlaylists.first.songs.isEmpty
        ? null
        : widget.customPlaylists.first.songs.first;
    final tiles = <({String title, String subtitle, IconData icon, YoutubeSearchResult? artwork, VoidCallback onTap})>[
      (
        title: 'Lagu Disukai',
        subtitle: '${widget.favorites.length} lagu',
        icon: Icons.favorite_rounded,
        artwork: firstFavorite,
        onTap: _openFavoritesList,
      ),
      (
        title: 'Recently Played',
        subtitle: '${widget.recentlyPlayed.length} lagu terakhir',
        icon: Icons.history_rounded,
        artwork: firstRecent,
        onTap: _openRecentHistory,
      ),
      (
        title: 'Playlist Saya',
        subtitle: '${widget.customPlaylistCount} playlist',
        icon: Icons.queue_music_rounded,
        artwork: firstPlaylist,
        onTap: widget.onOpenCustomPlaylists ?? () => _selectDockDestination(_YoutubeSection.library.index),
      ),
      (
        title: 'Dengar Bareng',
        subtitle: 'Buat ruang atau gabung',
        icon: Icons.headphones_rounded,
        artwork: null,
        onTap: widget.onOpenListeningRoom ?? () {},
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 680 ? 4 : 2;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: tiles.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 9,
              mainAxisSpacing: 9,
              mainAxisExtent: 62,
            ),
            itemBuilder: (context, index) {
              final tile = tiles[index];
              return _quickPickTile(
                title: tile.title,
                subtitle: tile.subtitle,
                icon: tile.icon,
                artwork: tile.artwork,
                onTap: tile.onTap,
              );
            },
          );
        },
      ),
    );
  }

  Widget _quickPickTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required YoutubeSearchResult? artwork,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: double.infinity,
              child: artwork == null
                  ? DecoratedBox(
                      decoration: BoxDecoration(color: scheme.primaryContainer),
                      child: Icon(icon, color: scheme.onPrimaryContainer, size: 23),
                    )
                  : UnifiedArtwork(track: artwork, fit: BoxFit.cover, iconSize: 21),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 7),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 11.5, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _madeForYouCards(List<SmartPlaylist> playlists) {
    final scheme = Theme.of(context).colorScheme;
    final first = playlists.first;
    final primarySong = first.songs.first;
    return SizedBox(
      height: 186,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: min(playlists.length, 6),
        separatorBuilder: (_, _) => const SizedBox(width: 11),
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          final featured = index == 0;
          return SizedBox(
            width: featured ? MediaQuery.sizeOf(context).width * 0.76 : 164,
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(19),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _showSongList(playlist.title, playlist.songs),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    UnifiedArtwork(track: featured ? primarySong : playlist.songs.first, fit: BoxFit.cover, iconSize: 34),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x12000000), Color(0xE0000000)],
                          stops: [0.12, 1],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 12,
                      bottom: 13,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(featured ? 'MADE FOR YOU' : 'YOUR MIX', style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.35)),
                          const SizedBox(height: 5),
                          Text(playlist.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                          const SizedBox(height: 3),
                          Text('${playlist.songs.length} lagu · ${playlist.subtitle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.90), shape: BoxShape.circle),
                        child: Padding(padding: const EdgeInsets.all(9), child: Icon(Icons.play_arrow_rounded, color: scheme.onSurface, size: 20)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _moodGrid() {
    const moods = <({String name, String query, IconData icon, Color color})>[
      (name: 'Chill', query: 'Chill', icon: Icons.nightlight_round, color: Color(0xFF426A86)),
      (name: 'Sad', query: 'Sad', icon: Icons.cloud_rounded, color: Color(0xFF5B5D80)),
      (name: 'Happy', query: 'Happy', icon: Icons.wb_sunny_rounded, color: Color(0xFF9B7542)),
      (name: 'Energetic', query: 'Energetic', icon: Icons.bolt_rounded, color: Color(0xFF9B5144)),
      (name: 'Focus', query: 'Focus', icon: Icons.center_focus_strong_rounded, color: Color(0xFF3F7770)),
      (name: 'Relax', query: 'Relax', icon: Icons.spa_rounded, color: Color(0xFF6B7950)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      child: LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: moods.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: constraints.maxWidth >= 680 ? 3 : 2,
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            mainAxisExtent: 76,
          ),
          itemBuilder: (context, index) {
            final mood = moods[index];
            return Material(
              color: mood.color,
              borderRadius: BorderRadius.circular(15),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _section = _YoutubeSection.explore;
                    _exploreCategory = 'Sedang tren';
                    _exploreResults = const [];
                  });
                  unawaited(_loadExploreCategory(mood.query));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                  child: Row(
                    children: [
                      Expanded(child: Text(mood.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -0.3))),
                      Icon(mood.icon, color: Colors.white.withValues(alpha: 0.88), size: 29),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _continueListeningRow(YoutubeSearchResult video) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (widget.watchProgress[video.videoId] ?? 0).clamp(0.0, 1.0).toDouble();
    final title = MusicTitleFormatter.clean(video.title);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(widget.onPlay(video)),
          child: Row(
            children: [
              SizedBox(width: 54, height: 58, child: UnifiedArtwork(track: video, fit: BoxFit.cover)),
              const SizedBox(width: 11),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 11.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 3),
                      Text(video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9.5)),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: scheme.outlineVariant.withValues(alpha: 0.35), valueColor: AlwaysStoppedAnimation<Color>(scheme.primary)),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(onPressed: () => unawaited(widget.onPlay(video)), icon: Icon(Icons.play_arrow_rounded, color: scheme.primary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _featuredDiscoveryCard(YoutubeSearchResult video, {required String label}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: SizedBox(
        height: 218,
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => unawaited(widget.onPlay(video)),
            child: Stack(
              fit: StackFit.expand,
              children: [
                UnifiedArtwork(track: video, fit: BoxFit.cover, iconSize: 42),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x08000000), Color(0xD9000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.45)),
                            const SizedBox(height: 6),
                            Text(MusicTitleFormatter.clean(video.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -0.45)),
                            const SizedBox(height: 4),
                            Text(video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(width: 45, height: 45, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle), child: Icon(Icons.play_arrow_rounded, color: scheme.onPrimary, size: 28)),
                    ],
                  ),
                ),
              ],
            ),
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
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
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

  /// Dua pintasan utama Beranda memakai kartu yang lebih lega dan seimbang.

  Widget _modernWelcomeHeader() {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    Widget action({required String tooltip, required IconData icon, required VoidCallback onTap}) {
      return Padding(
        padding: const EdgeInsets.only(left: 7),
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: SizedBox(
              width: 41,
              height: 41,
              child: Tooltip(message: tooltip, child: Icon(icon, color: scheme.onSurface, size: 20)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(18, topInset + 10, 18, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 39,
              height: 39,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('MusikKu', style: TextStyle(color: scheme.onSurface, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.55, height: 1.0)),
                const SizedBox(height: 4),
                Text('YOUR MUSIC EXPERIENCE', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1.15)),
              ],
            ),
          ),
          action(
            tooltip: 'Listening Together',
            icon: Icons.headphones_rounded,
            onTap: widget.onOpenListeningRoom ?? () {},
          ),
          action(
            tooltip: 'Cari lagu atau artis',
            icon: Icons.search_rounded,
            onTap: _openSearch,
          ),
          action(
            tooltip: 'Pengaturan',
            icon: Icons.settings_outlined,
            onTap: _showAppSettings,
          ),
        ],
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

class _HomeSectionSkeleton extends StatelessWidget {
  const _HomeSectionSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(child: Container(decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(15)))),
                  const SizedBox(height: 10),
                  Expanded(child: Container(decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(15)))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
