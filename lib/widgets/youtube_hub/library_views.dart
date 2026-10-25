part of '../youtube_hub.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _YoutubeHubLibraryViews on _YoutubeHubState {
  Widget _libraryCard(String title, String subtitle, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(15)),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 3),
                Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, height: 1.25)),
              ])),
              const SizedBox(width: 8),
              Container(width: 32, height: 32, decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.72), shape: BoxShape.circle), child: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant, size: 20)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _libraryView() {
    final scheme = Theme.of(context).colorScheme;
    Widget spacedCard(String title, String subtitle, IconData icon, VoidCallback onTap) =>
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: _libraryCard(title, subtitle, icon, onTap)));

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 10, 14, 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 8, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primary.withValues(alpha: 0.19), scheme.secondary.withValues(alpha: 0.08), scheme.surfaceContainerHighest.withValues(alpha: 0.72)]),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
            ),
            child: Row(children: [
              Container(width: 50, height: 50, decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.82), borderRadius: BorderRadius.circular(17), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.48))), alignment: Alignment.center, child: Icon(Icons.library_music_rounded, color: scheme.onSurface, size: 28)),
              const SizedBox(width: 12),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('RUANG MUSIKMU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
                SizedBox(height: 3),
                Text('Koleksi kamu', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.55)),
                SizedBox(height: 3),
                Text('Favorit, riwayat, dan playlist lokal', style: TextStyle(fontSize: 11.5)),
              ])),
              IconButton(tooltip: 'Pembaruan aplikasi', onPressed: () => unawaited(AppUpdateSheet.show(context)), visualDensity: VisualDensity.compact, icon: const Icon(Icons.system_update_alt_rounded)),
            ]),
          ),
        ),
      ),
      spacedCard('Playlist MusikKu', '${widget.customPlaylistCount} playlist buatan sendiri · bisa diurutkan dan diedit', Icons.queue_music_rounded, widget.onOpenCustomPlaylists ?? () {}),
      spacedCard('Playlist pintar', 'Mix kamu dibuat dari lagu yang sering diputar, ditambah favorit dan riwayat', Icons.auto_awesome_rounded, _showSmartPlaylistPicker),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 9),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Pintasan koleksi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                  ),
                ),
              ),
              Text(
                'Akses cepat',
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GridView.count(
            crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.48, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            children: [
              _libraryQuickTile(title: 'Riwayat dengar', subtitle: '${widget.recentlyPlayed.length} lagu terakhir', icon: Icons.history_rounded, onTap: _openRecentHistory),
              _libraryQuickTile(title: 'Favorit MusikKu', subtitle: '${widget.favorites.length} lagu tersimpan', icon: Icons.favorite_rounded, onTap: _openFavoritesList),
              _libraryQuickTile(title: 'Musik lokal', subtitle: 'File di perangkat', icon: Icons.library_music_rounded, onTap: _openLocalMusic),
              _libraryQuickTile(title: 'Radio otomatis', subtitle: 'Putar lagu serupa', icon: Icons.radio_rounded, onTap: _startRadioFromCollection),
            ],
          ),
        ),
      ),
      spacedCard('Statistik mendengarkan', 'Ringkasan waktu dengar, lagu, dan kebiasaan musik', Icons.insights_outlined, () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StatsPage(storage: _storage)))),
      spacedCard('Pengaturan MusikKu', 'Tema, tampilan pemutar, dan preferensi jaringan', Icons.tune_rounded, _showAppSettings),
    ];
  }

  Widget _libraryQuickTile({required String title, required String subtitle, required IconData icon, required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.38))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(13)), alignment: Alignment.center, child: Icon(icon, color: scheme.onPrimaryContainer, size: 21)),
        const SizedBox(height: 9),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
        const SizedBox(height: 3),
        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
      ]))),
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
