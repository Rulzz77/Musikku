part of '../youtube_hub.dart';

// The state extensions share private UI logic; State.setState is used by this library.
// ignore_for_file: invalid_use_of_protected_member

extension _YoutubeHubLibraryViews on _YoutubeHubState {
  List<Widget> _subscriptionsView() {
    // Tab Langganan khusus musik: tampilkan channel dengan upload musik yang
    // lolos filter atau profil musik yang jelas (termasuk penyanyi cover).
    // Channel non-musik tanpa sinyal musik tetap tidak ditampilkan.
    final musicChannelIds = _musicSubscriptionChannelIds;
    final visibleSubscriptions = _subscriptions
        .where((channel) =>
            musicChannelIds.contains(channel.id) ||
            YoutubeSearchService.isLikelyMusicChannelProfile(
              channel.title,
              channel.description,
            ))
        .toList(growable: false);
    return <Widget>[
      _sectionHeader(
        visibleSubscriptions.isEmpty ? 'Langganan musik' : 'Langganan musik • ${visibleSubscriptions.length} channel',
      ),
      if (_user == null)
        SliverToBoxAdapter(child: _loginCard())
      else if (visibleSubscriptions.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(18), child: Text('Belum ada channel langganan dengan unggahan musik terbaru. Coba perbarui feed atau buka channel musik dari daftar langganan.')),
        )
      else ...[
        SliverToBoxAdapter(
          child: SizedBox(
            height: 82,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
              scrollDirection: Axis.horizontal,
              itemCount: visibleSubscriptions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final channel = visibleSubscriptions[index];
                return InkWell(
                  onTap: () => _openChannel(channel),
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: channel.thumbnailUrl.isNotEmpty ? NetworkImage(channel.thumbnailUrl) : null,
                          child: channel.thumbnailUrl.isEmpty ? const Icon(Icons.person_rounded) : null,
                        ),
                        const SizedBox(height: 4),
                        Text(channel.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _sectionHeader('Musik terbaru'),
        if (_subscriptionFeed.isEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(18), child: Text('Belum ada musik baru dari channel yang kamu subscribe.')))
        else
          SliverList.builder(
            itemCount: _subscriptionFeed.length,
            itemBuilder: (context, index) => _videoCard(_subscriptionFeed[index]),
          ),
      ],
    ];
  }

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
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11.5,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _libraryView() {
    final scheme = Theme.of(context).colorScheme;
    final likedCount = _user == null ? widget.favorites.length : _liked.length;
    final playlistCount = _user == null ? 0 : _playlists.length;
    final displayName = _user?.displayName?.trim();

    Widget spacedCard(String title, String subtitle, IconData icon, VoidCallback onTap) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: _libraryCard(title, subtitle, icon, onTap),
        ),
      );
    }

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 10, 14, 12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 16, 8, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.13),
                  scheme.surfaceContainerHighest.withValues(alpha: 0.76),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.48)),
                  ),
                  alignment: Alignment.center,
                  child: _user == null
                      ? Icon(Icons.person_outline_rounded, color: scheme.onSurface, size: 28)
                      : Text(
                          (displayName != null && displayName.isNotEmpty
                                  ? displayName.characters.first
                                  : '?')
                              .toUpperCase(),
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'KOLEKSI MUSIK',
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text('Pustaka kamu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                      const SizedBox(height: 3),
                      Text(
                        _user?.email ?? 'Atur dan nikmati koleksimu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Pembaruan aplikasi',
                  onPressed: () => unawaited(AppUpdateSheet.show(context)),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.system_update_alt_rounded),
                ),
                IconButton(
                  tooltip: 'Pengaturan MusikKu',
                  onPressed: _showAppSettings,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
      if (_user == null)
        SliverToBoxAdapter(child: _loginCard())
      else ...[
        spacedCard(
          'Lagu yang disukai',
          '$likedCount lagu musik di akun YouTube',
          Icons.thumb_up_alt_outlined,
          () => _showSongList('Lagu yang disukai', _liked),
        ),
        spacedCard(
          'Playlist YouTube',
          '$playlistCount playlist',
          Icons.queue_music_rounded,
          _showPlaylistPicker,
        ),
      ],
      spacedCard(
        'Playlist MusikKu',
        '${widget.customPlaylistCount} playlist buatan sendiri · bisa diurutkan dan diedit',
        Icons.queue_music_rounded,
        widget.onOpenCustomPlaylists ?? () {},
      ),
      spacedCard(
        'Playlist pintar',
        'Mix favorit, riwayat, dan lagu yang sering diputar',
        Icons.auto_awesome_rounded,
        _showSmartPlaylistPicker,
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 9),
          child: Row(
            children: [
              const Expanded(child: Text('Pintasan koleksi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.35))),
              Text('Akses cepat', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.28,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _libraryQuickTile(
                title: 'Riwayat dengar',
                subtitle: '${widget.recentlyPlayed.length} lagu terakhir',
                icon: Icons.history_rounded,
                onTap: _openRecentHistory,
              ),
              _libraryQuickTile(
                title: 'Favorit MusikKu',
                subtitle: '${widget.favorites.length} lagu tersimpan',
                icon: Icons.favorite_rounded,
                onTap: _openFavoritesList,
              ),
              _libraryQuickTile(
                title: 'Musik lokal',
                subtitle: 'File di perangkat',
                icon: Icons.library_music_rounded,
                onTap: _openLocalMusic,
              ),
              _libraryQuickTile(
                title: 'Radio otomatis',
                subtitle: 'Putar lagu serupa',
                icon: Icons.radio_rounded,
                onTap: _startRadioFromCollection,
              ),
            ],
          ),
        ),
      ),
      spacedCard(
        'Statistik mendengarkan',
        'Ringkasan waktu dengar, lagu, dan kebiasaan musik',
        Icons.insights_outlined,
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => StatsPage(storage: _storage)),
        ),
      ),
      spacedCard(
        'Hemat data',
        'Atur request tambahan dan penyegaran feed',
        Icons.data_saver_on_outlined,
        _showDataSaverSheet,
      ),
      spacedCard(
        'Pengaturan MusikKu',
        'Tema, tampilan pemutar, dan preferensi jaringan',
        Icons.tune_rounded,
        _showAppSettings,
      ),
      if (_selectedPlaylist != null) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedPlaylist!.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _selectedPlaylist = null;
                    _playlistItems = const [];
                  }),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Tutup playlist',
                ),
              ],
            ),
          ),
        ),
        if (_playlistItems.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(18), child: Text('Playlist kosong.')),
          )
        else
          SliverList.builder(
            itemCount: _playlistItems.length,
            itemBuilder: (context, index) => _videoCard(_playlistItems[index]),
          ),
      ],
    ];
  }

  Widget _libraryQuickTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.38)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(13)),
                alignment: Alignment.center,
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 21),
              ),
              const SizedBox(height: 9),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  void _openLocalMusic() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalMusicPage(
          onPlayFromList: widget.onPlayFromList,
          onAddToQueue: widget.onAddToQueue,
        ),
      ),
    );
  }

  void _showAppSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppSettingsPage(settings: widget.settings),
      ),
    );
  }

  void _startRadioFromCollection() {
    final seed = _subscriptionFeed.isNotEmpty
        ? _subscriptionFeed.first
        : widget.recentlyPlayed.isNotEmpty
            ? widget.recentlyPlayed.first
            : widget.favorites.isNotEmpty
                ? widget.favorites.first
                : _trending.isNotEmpty
                    ? _trending.first
                    : null;

    if (seed != null && widget.onStartRadio != null) {
      unawaited(widget.onStartRadio!(seed));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Belum ada lagu untuk memulai radio. Putar lagu dulu ya.')),
    );
  }

  Widget _loginCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.58),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(Icons.account_circle_rounded, size: 30, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rememberedAccountEmail.isEmpty ? 'Hubungkan akun YouTube' : 'Akun YouTube tersimpan',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.25),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _rememberedAccountEmail.isEmpty
                          ? 'Sinkronkan subscription dan playlist saat kamu membutuhkannya.'
                          : 'Akun terakhir: $_rememberedAccountEmail',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _loading ? null : _login,
              icon: Icon(_rememberedAccountEmail.isEmpty ? Icons.login_rounded : Icons.restore_rounded),
              label: Text(_rememberedAccountEmail.isEmpty ? 'Hubungkan Google' : 'Pulihkan akun'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSongList(String title, List<YoutubeSearchResult> songs) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => SafeArea(
          child: ListView.builder(
            controller: controller,
            itemCount: songs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                );
              }
              final video = songs[index - 1];
              final isCurrent = widget.currentVideoId == video.videoId;
              return ListTile(
                selected: isCurrent,
                selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.45),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      UnifiedArtwork(track: video, width: 96, height: 54, fit: BoxFit.cover, iconSize: 24),
                      if (isCurrent)
                        Container(
                          width: 96,
                          height: 54,
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.38),
                          child: const Icon(Icons.graphic_eq_rounded, color: Colors.white),
                        ),
                    ],
                  ),
                ),
                title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: isCurrent ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w900) : null),
                subtitle: Text(isCurrent ? 'SEDANG DIPUTAR • ${video.channelTitle}' : video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: isCurrent ? TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700) : null),
                trailing: isCurrent ? Icon(Icons.graphic_eq_rounded, color: Theme.of(context).colorScheme.primary) : null,
                onTap: () {
                  Navigator.pop(context);
                  // Preserve list context so Next/Previous use the selected
                  // collection rather than treating the song as an isolated tap.
                  unawaited(widget.onPlayFromList(video, songs));
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showPlaylistPicker() {
    if (_playlists.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            const ListTile(title: Text('Pilih playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            ..._playlists.map(
              (playlist) => ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text(playlist.title),
                subtitle: Text('${playlist.itemCount} item • hanya musik ditampilkan'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_openPlaylist(playlist));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(child: Text((_user?.displayName ?? '?').characters.first.toUpperCase())),
              title: Text(_user?.displayName ?? 'Akun'),
              subtitle: Text(_user?.email ?? ''),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Keluar'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_logout());
              },
            ),
          ],
        ),
      ),
    );
  }
}
