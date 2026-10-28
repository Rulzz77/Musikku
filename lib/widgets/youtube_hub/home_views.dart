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

    // Urutan: sapaan -> filter -> pintasan -> sorotan -> koleksi ->
    // lanjutkan -> rekomendasi.
    return [
      SliverToBoxAdapter(child: _modernWelcomeHeader()),
      _chipRow(),
      SliverToBoxAdapter(child: _homeShortcutRow(actions)),
      SliverToBoxAdapter(child: _featuredMusicBanner()),
      if (smartPlaylists.isNotEmpty) ...[
        _sectionHeader('Playlist pintar', action: 'Lihat semua', onAction: _showSmartPlaylistPicker),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 80,
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
      width: 176,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playSmartPlaylist(playlist),
          onLongPress: () => _showSongList(playlist.title, playlist.songs),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: UnifiedArtwork(track: first, width: 56, height: 56, fit: BoxFit.cover, iconSize: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        playlist.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${playlist.songs.length} lagu',
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
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
      height: 96,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _homeShortcutItem(
          title: actions[index].title,
          subtitle: actions[index].subtitle,
          icon: actions[index].icon,
          onTap: actions[index].onTap,
          highlighted: actions[index].title == 'Dengerin bareng',
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
    return Tooltip(
      message: subtitle,
      child: SizedBox(
        width: 76,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: highlighted ? scheme.primary : scheme.surfaceContainerHigh,
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 24,
                  color: highlighted ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: 72,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: TextStyle(color: scheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
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

    // Hanya sapaan dan satu tombol cari: tanpa logo, label, atau garis.
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topInset + 12, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              greeting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.9,
                height: 1.1,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cari musik',
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            style: IconButton.styleFrom(
              backgroundColor: scheme.surfaceContainerHigh,
              padding: EdgeInsets.zero,
            ),
            onPressed: _openSearch,
            icon: Icon(Icons.search_rounded, size: 24, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _featuredMusicBanner() {
    final scheme = Theme.of(context).colorScheme;
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
    final track = featuredTrack;
    final hasTrack = track != null;
    final title = hasTrack
        ? MusicTitleFormatter.clean(track.title)
        : 'Temukan musik yang kamu suka';
    final artist = track == null
        ? ''
        : MusicTitleFormatter.artistLabel(
            title: track.title,
            channelTitle: track.channelTitle,
          );
    final subtitle = hasTrack
        ? artist
        : 'Cari rilisan baru dan lanjutkan lagu favorit.';
    final fg = hasTrack ? Colors.white : scheme.onPrimaryContainer;

    Widget circleButton({
      required String tooltip,
      required IconData icon,
      required VoidCallback onTap,
      required bool filled,
    }) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: filled
              ? (hasTrack ? Colors.white : scheme.primary)
              : Colors.white.withValues(alpha: hasTrack ? 0.22 : 0.0),
          shape: CircleBorder(
            side: filled || hasTrack
                ? BorderSide.none
                : BorderSide(color: scheme.onPrimaryContainer.withValues(alpha: 0.4)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                size: filled ? 26 : 20,
                color: filled
                    ? (hasTrack ? const Color(0xFF101819) : scheme.onPrimary)
                    : fg,
              ),
            ),
          ),
        ),
      );
    }

    // Satu sampul dengan judul dan dua tombol bulat di atasnya; tanpa label
    // tambahan supaya fokus ke gambar.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: SizedBox(
        height: 188,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: scheme.primaryContainer,
            child: InkWell(
              onTap: hasTrack ? () => unawaited(widget.onPlay(track)) : _openSearch,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasTrack)
                    UnifiedArtwork(track: track, fit: BoxFit.cover, iconSize: 48),
                  if (hasTrack)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.75),
                          ],
                          stops: const [0.35, 1.0],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 16,
                    right: 14,
                    bottom: 14,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  height: 1.15,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: fg.withValues(alpha: 0.78),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        circleButton(
                          tooltip: 'Radio',
                          icon: Icons.radio_rounded,
                          filled: false,
                          onTap: hasTrack && widget.onStartRadio != null
                              ? () => unawaited(widget.onStartRadio!(track))
                              : _startRadioFromCollection,
                        ),
                        const SizedBox(width: 8),
                        circleButton(
                          tooltip: hasTrack ? 'Putar' : 'Cari musik',
                          icon: hasTrack ? Icons.play_arrow_rounded : Icons.search_rounded,
                          filled: true,
                          onTap: hasTrack ? () => unawaited(widget.onPlay(track)) : _openSearch,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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