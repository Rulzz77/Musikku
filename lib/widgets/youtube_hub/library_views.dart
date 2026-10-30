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
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 10),
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
    final topInset = MediaQuery.paddingOf(context).top;
    final scheme = Theme.of(context).colorScheme;

    Widget stat(String value, String label) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: TextStyle(color: scheme.primary, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, topInset + 18, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'RUANG PRIBADI',
                      style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.4),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Pembaruan aplikasi',
                    onPressed: () => unawaited(AppUpdateSheet.show(context)),
                    icon: const Icon(Icons.system_update_alt_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Semua musikmu.\n'),
                    TextSpan(text: 'Satu tempat.', style: TextStyle(color: scheme.primary)),
                  ],
                ),
                style: TextStyle(color: scheme.onSurface, fontSize: 31, height: 1.0, fontWeight: FontWeight.w900, letterSpacing: -1.4),
              ),
              const SizedBox(height: 8),
              Text(
                'Simpan, susun, dan temukan lagi lagu yang pernah kamu dengarkan.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  stat('${widget.customPlaylistCount}', 'PLAYLIST'),
                  const SizedBox(width: 8),
                  stat('${widget.favorites.length}', 'FAVORIT'),
                  const SizedBox(width: 8),
                  stat('${widget.recentlyPlayed.length}', 'RIWAYAT'),
                ],
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(child: _librarySectionLabel('Playlist & mix')),
      SliverToBoxAdapter(
        child: _libraryGroup([
          _libraryCard('Playlist MusikKu', '${widget.customPlaylistCount} playlist buatan sendiri · bisa diurutkan dan diedit', Icons.queue_music_rounded, widget.onOpenCustomPlaylists ?? () {}),
          _libraryCard('Playlist pintar', 'Mix dari lagu yang sering diputar, favorit, dan riwayat', Icons.auto_awesome_rounded, _showSmartPlaylistPicker),
        ]),
      ),
      SliverToBoxAdapter(child: _librarySectionLabel('Koleksi cepat')),
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
              mainAxisExtent: 112,
            ),
            children: [
              _libraryQuickTile(title: 'Riwayat dengar', subtitle: '${widget.recentlyPlayed.length} lagu terakhir', icon: Icons.history_rounded, onTap: _openRecentHistory),
              _libraryQuickTile(title: 'Favorit MusikKu', subtitle: '${widget.favorites.length} lagu tersimpan', icon: Icons.favorite_rounded, onTap: _openFavoritesList),
              _libraryQuickTile(title: 'Musik lokal', subtitle: 'File di perangkat', icon: Icons.library_music_rounded, onTap: _openLocalMusic),
              _libraryQuickTile(title: 'Radio otomatis', subtitle: 'Putar lagu serupa', icon: Icons.radio_rounded, onTap: _startRadioFromCollection),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(child: _librarySectionLabel('Pengaturan & aktivitas')),
      SliverToBoxAdapter(
        child: _libraryGroup([
          _libraryCard('Statistik mendengarkan', 'Ringkasan waktu dengar, lagu, dan kebiasaan musik', Icons.insights_outlined, () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StatsPage(storage: _storage)))),
          _libraryCard('Pengaturan MusikKu', 'Tema, penggunaan data, dan preferensi pemutaran', Icons.tune_rounded, _showAppSettings),
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
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => LocalMusicPage(onPlayFromList: widget.onPlayFromList, onAddToQueue: widget.onAddToQueue)));
  }

  void _showAppSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AppSettingsPage(settings: widget.settings, onOpenAudioSettings: widget.onOpenAudioSettings)));
  }

  void _startRadioFromCollection() {
    final seed = widget.recentlyPlayed.isNotEmpty ? widget.recentlyPlayed.first : widget.favorites.isNotEmpty ? widget.favorites.first : _trending.isNotEmpty ? _trending.first : null;
    if (seed != null && widget.onStartRadio != null) {
      unawaited(widget.onStartRadio!(seed));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belum ada lagu untuk memulai radio. Putar lagu dulu ya.')));
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
          if (index == 0) return Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 10), child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)));
          final video = musicSongs[index - 1];
          final isCurrent = widget.currentVideoId == video.videoId;
          return ListTile(
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
          );
        },
      ))),
    );
  }
}