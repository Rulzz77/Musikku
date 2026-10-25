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
    final openListeningRoom = widget.onOpenListeningRoom;
    final actions = <({String title, String subtitle, IconData icon, VoidCallback onTap})>[
      if (openListeningRoom != null)
        (
          title: 'Dengerin bareng',
          subtitle: 'Buat / gabung kamar',
          icon: Icons.headphones_rounded,
          onTap: openListeningRoom,
        ),
      (
        title: 'Mix kamu',
        subtitle: frequentMix == null ? 'Putar favorit' : '${frequentMix.songs.length} lagu',
        icon: Icons.auto_awesome_rounded,
        onTap: () => _playFrequentMix(frequentMix),
      ),
      (title: 'Radio', subtitle: 'Lagu serupa', icon: Icons.radio_rounded, onTap: _startRadioFromCollection),
      (title: 'Musik lokal', subtitle: 'File perangkat', icon: Icons.library_music_rounded, onTap: _openLocalMusic),
      (title: 'Riwayat', subtitle: '${widget.recentlyPlayed.length} lagu', icon: Icons.history_rounded, onTap: _openRecentHistory),
    ];

    return [
      SliverToBoxAdapter(child: _modernWelcomeHeader()),
      SliverToBoxAdapter(child: _featuredMusicBanner()),
      _chipRow(),
      _sectionHeader('Akses cepat'),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 116,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            scrollDirection: Axis.horizontal,
            itemCount: actions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, index) => _homeQuickActionCard(
              title: actions[index].title,
              subtitle: actions[index].subtitle,
              icon: actions[index].icon,
              onTap: actions[index].onTap,
              highlighted: actions[index].title == 'Dengerin bareng',
            ),
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
    bool highlighted = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = highlighted ? Colors.white : scheme.onSurface;
    final secondary = highlighted ? Colors.white.withValues(alpha: 0.72) : scheme.onSurfaceVariant;
    return SizedBox(
      width: 146,
      height: 108,
      child: Material(
        color: highlighted ? const Color(0xFF14524C) : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: highlighted
                ? const Color(0xFF55DCCB).withValues(alpha: 0.42)
                : scheme.outlineVariant.withValues(alpha: 0.34),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: highlighted
                ? const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF164B46), Color(0xFF0F302D)],
                    ),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 33,
                      height: 33,
                      decoration: BoxDecoration(
                        color: highlighted
                            ? const Color(0xFF55DCCB).withValues(alpha: 0.17)
                            : scheme.primaryContainer.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        size: 19,
                        color: highlighted ? const Color(0xFF8EF0E0) : scheme.onPrimaryContainer,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_outward_rounded, size: 14, color: secondary.withValues(alpha: 0.82)),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: foreground, fontSize: 12.1, fontWeight: FontWeight.w900, letterSpacing: -0.15),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: secondary, fontSize: 9.8, fontWeight: FontWeight.w600),
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
      padding: EdgeInsets.fromLTRB(16, topInset + 6, 12, 13),
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
                  'Musik favorit, dalam satu tempat',
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
    final compact = MediaQuery.sizeOf(context).width < 370;
    YoutubeSearchResult? featuredTrack;
    for (final candidate in _trending) {
      if (!candidate.isLive &&
          !candidate.isUpcoming &&
          YoutubeSearchService.isMusicCandidate(candidate)) {
        featuredTrack = candidate;
        break;
      }
    }
    if (featuredTrack == null) {
      for (final candidate in widget.recentlyPlayed) {
        if (YoutubeSearchService.isMusicCandidate(candidate)) {
          featuredTrack = candidate;
          break;
        }
      }
    }
    final title = featuredTrack == null
        ? 'Temukan musik\nyang kamu suka'
        : MusicTitleFormatter.clean(featuredTrack.title);
    final artist = featuredTrack?.channelTitle.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF101819), Color(0xFF163B37), Color(0xFF176B65)],
            stops: [0, 0.62, 1],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.13),
              blurRadius: 22,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -46,
              top: -74,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.055),
                    width: 23,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 14 : 17, 15, 14, 15),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_awesome_rounded, size: 13, color: Color(0xFF9AF5E8)),
                            const SizedBox(width: 5),
                            Text(
                              'PILIHAN HARI INI',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 17 : 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.45,
                            height: 1.08,
                          ),
                        ),
                        if (artist.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 5),
                          Text(
                            'Temukan rilisan baru dan lanjutkan lagu favorit.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 10.5,
                              height: 1.25,
                            ),
                          ),
                        ],
                        const SizedBox(height: 11),
                        Wrap(
                          spacing: 7,
                          runSpacing: 6,
                          children: [
                            FilledButton.icon(
                              onPressed: featuredTrack == null
                                  ? _openSearch
                                  : () => unawaited(widget.onPlay(featuredTrack!)),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF9AF5E8),
                                foregroundColor: const Color(0xFF103B37),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: Icon(featuredTrack == null ? Icons.search_rounded : Icons.play_arrow_rounded, size: 17),
                              label: Text(
                                featuredTrack == null ? 'Cari musik' : 'Putar',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: featuredTrack != null && widget.onStartRadio != null
                                  ? () => unawaited(widget.onStartRadio!(featuredTrack!))
                                  : _startRadioFromCollection,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.30)),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.radio_rounded, size: 15),
                              label: const Text('Radio', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
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
                      label: 'Putar ${MusicTitleFormatter.clean(featuredTrack.title)}',
                      child: InkWell(
                        onTap: () => unawaited(widget.onPlay(featuredTrack!)),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: compact ? 82 : 104,
                          height: compact ? 116 : 132,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 14, offset: const Offset(0, 6)),
                            ],
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
                                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                                  ),
                                ),
                              ),
                              const Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: EdgeInsets.all(7),
                                  child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 27),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: 8),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                      child: const Icon(Icons.headphones_rounded, color: Color(0xFF9AF5E8), size: 30),
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
