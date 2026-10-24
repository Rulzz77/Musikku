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
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).top + 8),
        ),
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

    return [
      SliverToBoxAdapter(child: _modernWelcomeHeader()),
      SliverToBoxAdapter(child: _featuredMusicBanner()),
      _chipRow(),
      _sectionHeader('Langsung putar'),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 620 ? 4 : 2;
              final openListeningRoom = widget.onOpenListeningRoom;
              final actions = <({String title, String subtitle, IconData icon, VoidCallback onTap})>[
                if (openListeningRoom != null)
                  (
                    title: 'Dengerin bareng',
                    subtitle: 'Buat / gabung pakai kode',
                    icon: Icons.headphones_rounded,
                    onTap: openListeningRoom,
                  ),
                (
                  title: 'Mix kamu',
                  subtitle: frequentMix == null
                      ? 'Belum ada lagu berulang'
                      : '${frequentMix.songs.length} lagu sering diputar',
                  icon: Icons.graphic_eq_rounded,
                  onTap: () => _playFrequentMix(frequentMix),
                ),
                (title: 'Musik lokal', subtitle: 'File di perangkat', icon: Icons.library_music_rounded, onTap: _openLocalMusic),
                (title: 'Riwayat', subtitle: '${widget.recentlyPlayed.length} lagu terakhir', icon: Icons.history_rounded, onTap: _openRecentHistory),
                (title: 'Radio', subtitle: 'Lagu yang nyambung', icon: Icons.radio_rounded, onTap: _startRadioFromCollection),
              ];
              return GridView.count(
                crossAxisCount: columns,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
                childAspectRatio: columns == 2 ? 2.14 : 1.95,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final action in actions)
                    _homeQuickActionCard(
                      title: action.title,
                      subtitle: action.subtitle,
                      icon: action.icon,
                      onTap: action.onTap,
                    ),
                ],
              );
            },
          ),
        ),
      ),
      if (smartPlaylists.isNotEmpty) ...[
        _sectionHeader('Playlist pintar', action: 'Lihat semua', onAction: _showSmartPlaylistPicker),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 88,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              scrollDirection: Axis.horizontal,
              itemCount: smartPlaylists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
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
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
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
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
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
          return const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_rounded, size: 42),
                SizedBox(height: 10),
                Text('Playlist pintar belum tersedia', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 6),
                Text('Simpan lagu ke favorit atau dengarkan beberapa lagu dulu.'),
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
                child: Text('Playlist pintar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              ),
              for (final playlist in playlists)
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(_smartPlaylistIcon(playlist.id), color: scheme.onPrimaryContainer),
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
      width: 186,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.36)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playSmartPlaylist(playlist),
          onLongPress: () => _showSongList(playlist.title, playlist.songs),
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: UnifiedArtwork(track: first, width: 60, height: 60, fit: BoxFit.cover, iconSize: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(playlist.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('${playlist.songs.length} lagu', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.play_circle_fill_rounded, color: scheme.primary, size: 27),
              ],
            ),
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

  Widget _homeQuickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.36)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: scheme.onPrimaryContainer, size: 21),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.2, height: 1.15, color: scheme.onSurfaceVariant)),
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

  Widget _modernWelcomeHeader() {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;
    final hour = DateTime.now().hour;
    final greeting = hour < 11
        ? 'Selamat pagi'
        : hour < 15
            ? 'Selamat siang'
            : hour < 18
                ? 'Selamat sore'
                : 'Selamat malam';

    return Padding(
      padding: EdgeInsets.fromLTRB(18, topInset + 10, 12, 17),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF55DCCB), Color(0xFF087F79), Color(0xFF55DCCB)],
              ),
              borderRadius: BorderRadius.circular(17),
              boxShadow: [
                BoxShadow(color: scheme.primary.withValues(alpha: 0.26), blurRadius: 18, offset: const Offset(0, 7)),
              ],
            ),
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 46,
                height: 46,
                fit: BoxFit.cover,
                semanticLabel: 'Logo MusikKu',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  greeting.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.secondary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.35),
                ),
                const SizedBox(height: 3),
                Text(
                  appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurface, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.85, height: 1.0),
                ),
                const SizedBox(height: 4),
                Text(
                  'Temukan suara yang cocok buat harimu',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 3),
          IconButton.filledTonal(
            tooltip: 'Cari musik',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 39, height: 39),
            style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.82), padding: EdgeInsets.zero),
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _featuredMusicBanner() {
    final scheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 370 || MediaQuery.textScalerOf(context).scale(14) > 18;
    final featuredTrack = _trending.isNotEmpty
        ? _trending.first
        : (widget.recentlyPlayed.isNotEmpty ? widget.recentlyPlayed.first : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF141C1D), Color(0xFF153E39), Color(0xFF1B8F8B)],
            stops: [0, 0.58, 1],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.19), blurRadius: 25, offset: const Offset(0, 11))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -58,
              top: -70,
              child: Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.075), width: 27)),
              ),
            ),
            Positioned(
              right: 76,
              bottom: -88,
              child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF55DCCB).withValues(alpha: 0.10))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 21, 17, 19),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white.withValues(alpha: 0.16))),
                          child: const Text('MUSIK UNTUK HARI INI', style: TextStyle(color: Color(0xFFC7FFF4), fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 1.05)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Mood kamu.\nMusik kamu.',
                          maxLines: 2,
                          style: TextStyle(color: Colors.white, fontSize: isCompact ? 24 : 27, fontWeight: FontWeight.w900, letterSpacing: -0.95, height: 1.04),
                        ),
                        const SizedBox(height: 8),
                        Text('Temukan lagu baru atau putar lagi yang kamu suka.', maxLines: 2, style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 11, height: 1.35, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 15),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: () {
                                setState(() => _section = _YoutubeSection.explore);
                                unawaited(_loadExploreCategory(_exploreCategory));
                              },
                              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF104E4A), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                              icon: const Icon(Icons.explore_rounded, size: 17),
                              label: const Text('Jelajahi musik', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5)),
                            ),
                            OutlinedButton.icon(
                              onPressed: _startRadioFromCollection,
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withValues(alpha: 0.40)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                              icon: const Icon(Icons.radio_rounded, size: 16),
                              label: const Text('Radio', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (featuredTrack != null) ...[
                    const SizedBox(width: 10),
                    Semantics(
                      button: true,
                      label: 'Putar ${featuredTrack.title}',
                      child: InkWell(
                        onTap: () => unawaited(widget.onPlay(featuredTrack)),
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          width: isCompact ? 66 : 100,
                          height: isCompact ? 94 : 132,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              UnifiedArtwork(track: featuredTrack, fit: BoxFit.cover, iconSize: 28),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.black.withValues(alpha: 0.02), Colors.black.withValues(alpha: 0.62)],
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 7),
                                  child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: isCompact ? 27 : 35),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else if (!isCompact) ...[
                    const SizedBox(width: 5),
                    Container(
                      width: 91,
                      height: 112,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                      ),
                      child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 46),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _homeEmptyState({Future<void> Function()? retry}) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 56, 28, 24),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.video_library_rounded, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              _feedError.isNotEmpty ? 'Lagu belum bisa dimuat' : 'Beranda masih kosong',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _feedError.isNotEmpty
                  ? _feedError
                  : 'Cari lagu lewat kolom pencarian atau pilih rekomendasi musik di beranda.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 18),
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
