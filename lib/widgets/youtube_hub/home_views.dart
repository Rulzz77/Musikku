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
        _homeEmptyState(signedIn: _user != null, retry: () => _selectChip(_activeChip, force: true))
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

    // Build a YouTube-like vertical feed, alternating subscription uploads and
    // popular videos. Dedupe IDs so one video isn't shown twice.
    final subscriptionVideos = _subscriptionFeed
        .where((video) => !video.isLive && !video.isUpcoming)
        .toList(growable: false);
    final popularVideos = _trending
        .where((video) => !video.isLive && !video.isUpcoming)
        .toList(growable: false);
    final feed = <YoutubeSearchResult>[];
    final seenIds = <String>{};

    void addUnique(YoutubeSearchResult video) {
      if (video.videoId.isNotEmpty && seenIds.add(video.videoId)) {
        feed.add(video);
      }
    }

    final feedLength = subscriptionVideos.length > popularVideos.length
        ? subscriptionVideos.length
        : popularVideos.length;
    for (var index = 0; index < feedLength; index++) {
      if (index < subscriptionVideos.length) addUnique(subscriptionVideos[index]);
      if (index < popularVideos.length) addUnique(popularVideos[index]);
    }

    final recentlyPlayed = widget.recentlyPlayed.take(12).toList(growable: false);
    final smartPlaylists = _buildSmartPlaylists();

    return [
      SliverToBoxAdapter(child: _modernWelcomeHeader()),
      SliverToBoxAdapter(child: _featuredMusicBanner()),
      _chipRow(),
      _sectionHeader('Akses cepat'),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 86,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 5),
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (context, index) {
              final actions = <({String title, String subtitle, IconData icon, VoidCallback onTap})>[
                (title: 'Mix favorit', subtitle: '${widget.favorites.length} lagu tersimpan', icon: Icons.auto_awesome_rounded, onTap: _playFavoritesMix),
                (title: 'Musik lokal', subtitle: 'File di perangkat', icon: Icons.library_music_rounded, onTap: _openLocalMusic),
                (title: 'Riwayat', subtitle: '${widget.recentlyPlayed.length} lagu terakhir', icon: Icons.history_rounded, onTap: _openRecentHistory),
                (title: 'Radio', subtitle: 'Temukan lagu serupa', icon: Icons.radio_rounded, onTap: _startRadioFromCollection),
              ];
              final action = actions[index];
              return _homeQuickActionCard(
                title: action.title,
                subtitle: action.subtitle,
                icon: action.icon,
                onTap: action.onTap,
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
        _homeEmptyState(
          signedIn: _user != null,
          retry: () => _loadHome(force: true),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
  }

  List<SmartPlaylist> _buildSmartPlaylists() {
    final catalog = <YoutubeSearchResult>[
      ..._trending,
      ..._chipFeeds.values.expand((items) => items),
      ..._searchResults,
      ..._exploreResults,
      ..._subscriptionFeed,
      ..._liked,
    ];
    return SmartPlaylistService.build(
      favorites: widget.favorites,
      recentlyPlayed: widget.recentlyPlayed,
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

  void _playFavoritesMix() {
    final songs = List<YoutubeSearchResult>.from(widget.favorites);
    if (songs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada lagu favorit. Simpan lagu dulu untuk membuat Mix Favorit.')),
      );
      return;
    }
    songs.shuffle(_feedRandom);
    unawaited(widget.onPlayFromList(songs.first, songs));
  }

  void _openRecentHistory() {
    if (widget.recentlyPlayed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Riwayat masih kosong. Putar lagu dulu, nanti muncul di sini.')),
      );
      return;
    }
    _showSongList('Riwayat dengar MusikKu', widget.recentlyPlayed);
  }

  void _openFavoritesList() {
    if (widget.favorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada favorit. Tambahkan lagu ke favorit untuk menemukannya di sini.')),
      );
      return;
    }
    _showSongList('Favorit MusikKu', widget.favorites);
  }

  Widget _homeQuickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 158,
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
                colors: [Color(0xFFFF6584), Color(0xFFD91F4D), Color(0xFF7F214B)],
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
                  style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.2),
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
                  'Suara yang pas buat harimu',
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
          IconButton(
            tooltip: _user == null ? 'Hubungkan YouTube' : 'Akun YouTube',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 40),
            onPressed: _user == null ? _login : _showAccountSheet,
            icon: Container(
              width: 29,
              height: 29,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primaryContainer, border: Border.all(color: scheme.primary.withValues(alpha: 0.18))),
              child: _user == null
                  ? Icon(Icons.person_outline_rounded, size: 18, color: scheme.onPrimaryContainer)
                  : Text(
                      (_user!.displayName?.trim().isNotEmpty == true ? _user!.displayName!.trim().characters.first : '?').toUpperCase(),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: scheme.onPrimaryContainer),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featuredMusicBanner() {
    final scheme = Theme.of(context).colorScheme;
    final isCompact = MediaQuery.sizeOf(context).width < 370 || MediaQuery.textScalerOf(context).scale(14) > 18;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A101B), Color(0xFF57203E), Color(0xFFD42A54)],
            stops: [0, 0.56, 1],
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
              child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFC0D0).withValues(alpha: 0.07))),
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
                          child: const Text('MUSIK UNTUK HARI INI', style: TextStyle(color: Color(0xFFFFDCE5), fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 1.05)),
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
                              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF84203F), padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
                  if (!isCompact) ...[
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 91,
                      height: 132,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(width: 86, height: 86, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: 0.13), width: 1.4), color: Colors.white.withValues(alpha: 0.05))),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFD9E2), Color(0xFFFF7898), Color(0xFFB61F50)]),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 15, offset: const Offset(0, 7))],
                            ),
                            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 38),
                          ),
                          Positioned(top: 8, right: 2, child: Icon(Icons.music_note_rounded, color: Colors.white.withValues(alpha: 0.94), size: 25)),
                          Positioned(
                            bottom: 10,
                            left: 0,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(color: const Color(0xFF25121F).withValues(alpha: 0.72), borderRadius: BorderRadius.circular(13), border: Border.all(color: Colors.white.withValues(alpha: 0.16))),
                              child: const Icon(Icons.headphones_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _showDataSaverSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => ValueListenableBuilder<DataSaverMode>(
        valueListenable: widget.settings.dataSaverMode,
        builder: (context, mode, _) {
          final scheme = Theme.of(context).colorScheme;
          final state = _account.isSignedIn ? 'Akun tersambung' : 'Tanpa login';
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hemat data',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Atur seberapa agresif MusikKu mengurangi request tambahan. Playback YouTube tetap ditentukan player.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const DataUsageCard(),
                    RadioGroup<DataSaverMode>(
                      groupValue: mode,
                      onChanged: (value) {
                        if (value == null) return;
                        unawaited(widget.settings.setDataSaverMode(value));
                      },
                      child: Column(
                        children: [
                          for (final choice in DataSaverMode.values)
                            RadioListTile<DataSaverMode>(
                              value: choice,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                choice.label,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(choice.description),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),
                    ValueListenableBuilder<bool>(
                      valueListenable: widget.settings.prefetchWifiOnly,
                      builder: (context, wifiOnly, _) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Prefetch hanya saat Wi-Fi',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          wifiOnly
                              ? 'Request tambahan tidak diprioritaskan saat seluler.'
                              : 'Request tambahan boleh berjalan di seluler.',
                        ),
                        value: wifiOnly,
                        onChanged: (value) =>
                            unawaited(widget.settings.setPrefetchWifiOnly(value)),
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: widget.settings.bufferAlertSeconds,
                      builder: (context, seconds, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Peringatan buffer rendah • $seconds dtk',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Slider(
                            value: seconds.toDouble(),
                            min: 3,
                            max: 30,
                            divisions: 9,
                            label: '$seconds dtk',
                            onChanged: (value) => unawaited(
                              widget.settings.setBufferAlertSeconds(value.round()),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.verified_user_outlined, size: 17, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$state • data tambahan ditunda sampai dibutuhkan.',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
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

  Widget _homeEmptyState({required bool signedIn, Future<void> Function()? retry}) {
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
              _feedError.isNotEmpty
                  ? 'Lagu belum bisa dimuat'
                  : (signedIn ? 'Belum ada lagu baru' : 'Beranda masih kosong'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _feedError.isNotEmpty
                  ? _feedError
                  : (signedIn
                      ? 'Cari lagu lewat kolom pencarian untuk mulai mendengarkan.'
                      : 'Cari lagu lewat kolom pencarian atau pilih rekomendasi musik di beranda.'),
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
                if (!signedIn)
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _login,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Masuk'),
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
