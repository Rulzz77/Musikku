part of '../youtube_hub.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _YoutubeHubLibraryViews on _YoutubeHubState {
  /// Satu baris daftar: ikon bulat lembut, judul, keterangan, dan panah.
  /// Dipakai di dalam blok `_libraryGroup`, jadi tanpa kartu atau garis tepi.
  Widget _libraryCard(String title, String subtitle, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          child: Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 21),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5)),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5, height: 1.25)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, color: scheme.onSurfaceVariant, size: 18),
            ],
          ),
        ),
      ),
    );
  }


  /// Blok lembut tanpa garis tepi; baris di dalamnya dipisah garis tipis.
  Widget _libraryGroup(List<Widget> rows) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 69, endIndent: 12, color: scheme.outlineVariant.withValues(alpha: 0.56)),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }


  Widget _librarySectionLabel(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(19, 20, 19, 9),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  List<Widget> _libraryView() {
    final scheme = Theme.of(context).colorScheme;

    Widget stat(String value, String label) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(color: scheme.primary, fontSize: 24, height: 1, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
              const SizedBox(height: 5),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            ],
          ),
        ),
      );
    }

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 13, 18, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FlowPageHero(
                icon: Icons.library_music_rounded,
                eyebrow: 'RUANG PRIBADI',
                title: 'Koleksi musikmu.',
                subtitle: 'Playlist, favorit, riwayat, dan lagu di HP.',
                trailing: IconButton(
                  tooltip: 'Pembaruan aplikasi',
                  onPressed: () => unawaited(AppUpdateSheet.show(context)),
                  icon: const Icon(Icons.system_update_alt_rounded),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                child: Row(
                  children: [
                    stat('${widget.customPlaylistCount}', 'PLAYLIST'),
                    stat('${widget.favorites.length}', 'FAVORIT'),
                    stat('${widget.recentlyPlayed.length}', 'RIWAYAT'),
                  ],
                ),
              ),
              Divider(color: scheme.outlineVariant.withValues(alpha: 0.65), height: 1),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(child: _librarySectionLabel('Playlist')),
      SliverToBoxAdapter(
        child: _libraryGroup([
          _libraryCard('Playlist saya', '${widget.customPlaylistCount} playlist · buat, susun, dan putar lagu', Icons.queue_music_rounded, widget.onOpenCustomPlaylists ?? () {}),
        ]),
      ),
      if (widget.customPlaylists.isNotEmpty) ...[
        SliverToBoxAdapter(child: _librarySectionLabel('Playlist terbarumu')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 190,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: widget.customPlaylists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final playlist = widget.customPlaylists[index];
                return SizedBox(
                  width: 142,
                  child: Material(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(17),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        final open = widget.onOpenCustomPlaylist;
                        if (open != null) {
                          open(playlist);
                        } else {
                          widget.onOpenCustomPlaylists?.call();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: PlaylistArtwork(playlist: playlist, fit: BoxFit.cover, iconSize: 30),
                                  ),
                                  Positioned(
                                    right: 6,
                                    bottom: 6,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.68), borderRadius: BorderRadius.circular(7)),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                        child: Text('${playlist.songs.length} lagu', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 11.5, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text('${playlist.offlineSongCount} offline · ${playlist.folderName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(child: _librarySectionLabel('Lagu & aktivitas')),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 116,
            ),
            children: [
              for (final tile in <({String title, String subtitle, IconData icon, VoidCallback action})>[
                (title: 'Favorit', subtitle: '${widget.favorites.length} lagu disimpan', icon: Icons.favorite_rounded, action: _openFavoritesList),
                (title: 'Riwayat dengar', subtitle: '${widget.recentlyPlayed.length} lagu terakhir', icon: Icons.history_rounded, action: _openRecentHistory),
                (title: 'Musik di perangkat', subtitle: 'Lagu yang ada di HP-mu', icon: Icons.library_music_rounded, action: _openLocalMusic),
                (title: 'Statistik', subtitle: 'Waktu dan kebiasaan mendengar', icon: Icons.insights_outlined, action: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StatsPage(storage: _storage)))),
              ].indexed)
                TweenAnimationBuilder<double>(
                  key: ValueKey<String>('library-shortcut-${tile.$1}'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : Duration(milliseconds: 240 + tile.$1 * 55),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value,
                    child: Transform.translate(offset: Offset(0, 10 * (1 - value)), child: child),
                  ),
                  child: _libraryQuickTile(
                    title: tile.$2.title,
                    subtitle: tile.$2.subtitle,
                    icon: tile.$2.icon,
                    onTap: tile.$2.action,
                  ),
                ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(child: _librarySectionLabel('Fitur tambahan')),
      SliverToBoxAdapter(
        child: _libraryGroup([
          _libraryCard(
            'MusikKu Studio',
            'Kenali selera musik, buat mix sesuai suasana, dan gunakan timer fokus.',
            Icons.auto_awesome_rounded,
            _openMusicStudio,
          ),
        ]),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 18)),
    ];
  }


  /// Ubin pintasan: warna lembut tanpa garis tepi, ikon polos di kiri atas,
  /// judul dan keterangan di bawahnya.
  Widget _libraryQuickTile({required String title, required String subtitle, required IconData icon, required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(17),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: scheme.primary, size: 23),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  void _openLocalMusic() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LocalMusicPage(
        onPlayFromList: widget.onPlayFromList,
        onAddToQueue: widget.onAddToQueue,
        nativeState: widget.nativeState,
        onPlayPause: widget.onPlayPause,
        playlists: widget.customPlaylists,
        onPlaylistsChanged: () {
          widget.onCustomPlaylistsChanged?.call();
          if (mounted) setState(() {});
        },
      ),
    ));
  }

  void _openMusicStudio() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MusicStudioPage(
      storage: _storage,
      recentlyPlayed: widget.recentlyPlayed,
      currentVideo: widget.currentVideo,
      onPlayFromList: widget.onPlayFromList,
      onPlayPause: widget.onPlayPause,
      onNext: widget.onNext,
      onPrevious: widget.onPrevious,
      onOpenLyrics: widget.onOpenCurrentLyrics,
      isPlaying: widget.isPlaying,
    )));
  }

  void _showAppSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AppSettingsPage(
        settings: widget.settings,
        onOpenAudioSettings: widget.onOpenAudioSettings,
      ),
    ));
  }

  void _openAlbumDetail(String title, List<YoutubeSearchResult> songs) {
    final validTracks = songs
        .where((track) => track.videoId.isNotEmpty && YoutubeSearchService.isMusicCandidate(track))
        .toList(growable: false);
    if (validTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Track album belum tersedia untuk diputar.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlbumDetailPage(
          albumTitle: title,
          tracks: validTracks,
          onPlayFromList: widget.onPlayFromList,
        ),
      ),
    );
  }

  void _showSongList(String title, List<YoutubeSearchResult> songs) {
    final musicSongs = songs.where(YoutubeSearchService.isMusicCandidate).toList(growable: false);
    if (musicSongs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belum ada lagu yang cocok dengan filter musik.')));
      return;
    }
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(expand: false, initialChildSize: 0.85, maxChildSize: 0.95, builder: (_, controller) => SafeArea(child: ListView.builder(
        controller: controller, itemCount: musicSongs.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
              child: MusicGlassPanel(
                radius: 21,
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MusicSheetHeading(
                      icon: Icons.queue_music_rounded,
                      title: title,
                      subtitle: '${musicSongs.length} lagu musik · pilih lagu untuk mulai mendengarkan.',
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          unawaited(widget.onPlayFromList(musicSongs.first, musicSongs));
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Putar semua'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final video = musicSongs[index - 1];
          final isCurrent = widget.currentVideoId == video.videoId;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Material(
              color: isCurrent
                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.54)
                  : Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(17),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
            selected: isCurrent,
            selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
            leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Stack(alignment: Alignment.center, children: [
              UnifiedArtwork(track: video, width: 96, height: 54, fit: BoxFit.cover, iconSize: 24),
              if (isCurrent) Container(width: 96, height: 54, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.38), child: const Icon(Icons.graphic_eq_rounded, color: Colors.white)),
            ])),
            title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: isCurrent ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900) : null),
            subtitle: Text(isCurrent ? 'SEDANG DIPUTAR • ${video.channelTitle}' : video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: isCurrent ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700) : null),
            trailing: isCurrent ? Icon(Icons.graphic_eq_rounded, color: Theme.of(context).colorScheme.primary) : null,
            onTap: () { Navigator.pop(context); unawaited(widget.onPlayFromList(video, musicSongs)); },
              ),
            ),
          );
        },
      ))),
    );
  }
}