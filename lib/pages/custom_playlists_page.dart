import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../models/playlist.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
import '../widgets/playlist_widgets.dart' show showPlaylistNameDialog;
import '../widgets/unified_artwork.dart';
import '../widgets/flow_components.dart';
import '../widgets/music_design.dart';

/// Management screen for MusikKu's locally saved playlists.
/// The supplied playlist list is shared with HomePage; every mutation is
/// persisted through [onChanged].
class CustomPlaylistsPage extends StatefulWidget {
  const CustomPlaylistsPage({
    super.key,
    required this.playlists,
    required this.playerUiState,
    this.availableSongs = const [],
    required this.onChanged,
    required this.onPlayPlaylist,
    required this.onPlaySong,
  });

  final List<Playlist> playlists;
  final ValueListenable<PlayerUiState> playerUiState;
  final List<YoutubeSearchResult> availableSongs;
  final VoidCallback onChanged;
  final Future<void> Function(Playlist playlist) onPlayPlaylist;
  final Future<void> Function(Playlist playlist, YoutubeSearchResult song)
      onPlaySong;

  @override
  State<CustomPlaylistsPage> createState() => _CustomPlaylistsPageState();
}

class _CustomPlaylistsPageState extends State<CustomPlaylistsPage> {
  String? _selectedPlaylistId;

  Playlist? get _selectedPlaylist {
    final id = _selectedPlaylistId;
    if (id == null) return null;
    for (final playlist in widget.playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  Future<void> _createPlaylist() async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Playlist baru',
      confirmLabel: 'Buat',
    );
    if (!mounted || name == null) return;

    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
    );
    setState(() {
      widget.playlists.insert(0, playlist);
      _selectedPlaylistId = playlist.id;
    });
    widget.onChanged();
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Ubah nama playlist',
      initial: playlist.name,
      confirmLabel: 'Simpan',
    );
    if (!mounted || name == null || name == playlist.name) return;
    setState(() => playlist.name = name);
    widget.onChanged();
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus playlist?'),
        content: Text('Playlist "${playlist.name}" akan dihapus dari MusikKu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      widget.playlists.removeWhere((item) => item.id == playlist.id);
      if (_selectedPlaylistId == playlist.id) _selectedPlaylistId = null;
    });
    widget.onChanged();
  }

  Future<void> _removeSong(Playlist playlist, YoutubeSearchResult song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus dari playlist?'),
        content: Text('"${song.title}" akan dihapus dari "${playlist.name}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => playlist.songs.removeWhere((item) => item.videoId == song.videoId));
    widget.onChanged();
  }

  Future<void> _showAddSongsSheet(Playlist playlist) async {
    final seen = <String>{};
    final candidates = widget.availableSongs
        .where((song) => song.videoId.isNotEmpty &&
            !playlist.contains(song.videoId) &&
            seen.add(song.videoId))
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada lagu dari favorit, riwayat, atau daftar yang dimuat. Putar/cari lagu dulu, lalu coba lagi.')),
      );
      return;
    }

    final selectedIds = <String>{};
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.70,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Tambah lagu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                      Text('${selectedIds.length} dipilih', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final song = candidates[index];
                      final checked = selectedIds.contains(song.videoId);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (value) => setSheetState(() {
                          if (value == true) {
                            selectedIds.add(song.videoId);
                          } else {
                            selectedIds.remove(song.videoId);
                          }
                        }),
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: UnifiedArtwork(track: song, width: 48, height: 48, fit: BoxFit.cover),
                        ),
                        title: Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(song.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Batal')),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => Navigator.pop(sheetContext, Set<String>.from(selectedIds)),
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: Text('Tambah (${selectedIds.length})'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || selected == null || selected.isEmpty) return;

    var added = 0;
    setState(() {
      for (final song in candidates) {
        if (selected.contains(song.videoId) && !playlist.contains(song.videoId)) {
          playlist.songs.add(song);
          added++;
        }
      }
    });
    if (added > 0) {
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$added lagu ditambahkan ke "${playlist.name}"')),
      );
    }
  }

  void _reorderSongs(Playlist playlist, int oldIndex, int newIndex) {
    final moved = playlist.moveSong(oldIndex, newIndex);
    if (!moved) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _playPlaylistAndReturn(Playlist playlist) async {
    try {
      // Let the parent update the active source/player before closing this route,
      // but do not keep the playlist page on screen while the native player loads.
      final playback = widget.onPlayPlaylist(playlist);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await playback;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagu belum bisa diputar. Coba lagi ya.')),
        );
      }
    }
  }

  Future<void> _playSongAndReturn(Playlist playlist, YoutubeSearchResult song) async {
    try {
      final playback = widget.onPlaySong(playlist, song);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await playback;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagu belum bisa diputar. Coba lagi ya.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _selectedPlaylist;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: playlist == null
            ? null
            : IconButton(
                tooltip: 'Kembali ke playlist',
                onPressed: () => setState(() => _selectedPlaylistId = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(playlist?.name ?? 'Playlist MusikKu'),
        actions: [
          if (playlist != null && playlist.songs.isNotEmpty)
            IconButton(
              tooltip: 'Putar semua',
              onPressed: () => unawaited(_playPlaylistAndReturn(playlist)),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          if (playlist != null)
            IconButton(
              tooltip: 'Tambah lagu ke playlist',
              onPressed: () => unawaited(_showAddSongsSheet(playlist)),
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          IconButton(
            tooltip: 'Playlist baru',
            onPressed: () => unawaited(_createPlaylist()),
            icon: const Icon(Icons.add_rounded),
          ),
          if (playlist != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rename') unawaited(_renamePlaylist(playlist));
                if (value == 'delete') unawaited(_deletePlaylist(playlist));
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Ubah nama')),
                PopupMenuItem(value: 'delete', child: Text('Hapus playlist')),
              ],
            ),
        ],
      ),
      body: MusicBackdrop(
        child: playlist == null
            ? _buildPlaylistList(scheme)
            : _buildPlaylistSongs(playlist, scheme),
      ),
    );
  }

  Widget _buildPlaylistList(ColorScheme scheme) {
    final hero = const FlowPageHero(
      icon: Icons.queue_music_rounded,
      eyebrow: 'YOUR MUSIC SPACE',
      title: 'Playlist kamu',
      subtitle: 'Simpan lagu favorit dan susun antrean sesuai suasana hati.',
      trailing: Icon(Icons.auto_awesome_rounded),
    );

    if (widget.playlists.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 34),
        children: [
          hero,
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [scheme.primary.withValues(alpha: 0.20), scheme.secondary.withValues(alpha: 0.12)]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(Icons.library_music_rounded, size: 36, color: scheme.primary),
                ),
                const SizedBox(height: 14),
                const Text('Belum ada playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.35)),
                const SizedBox(height: 7),
                Text('Buat playlist pertama kamu, lalu tambahkan lagu dari hasil pencarian atau antrean.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => unawaited(_createPlaylist()),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Buat playlist'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        hero,
        const SizedBox(height: 17),
        FlowSectionHeader(
          icon: Icons.library_music_rounded,
          title: '${widget.playlists.length} playlist tersimpan',
          trailing: IconButton.filledTonal(
            tooltip: 'Playlist baru',
            onPressed: () => unawaited(_createPlaylist()),
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 620 ? 3 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.playlists.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
              itemBuilder: (context, index) {
                final playlist = widget.playlists[index];
                return TweenAnimationBuilder<double>(
                  key: ValueKey<String>('playlist-poster-${playlist.id}'),
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 300 + (index.clamp(0, 7).toInt() * 28)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Opacity(
                    opacity: value.clamp(0.0, 1.0).toDouble(),
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - value)),
                      child: child,
                    ),
                  ),
                  child: _playlistPoster(playlist, scheme),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _playlistPoster(Playlist playlist, ColorScheme scheme) {
    final track = playlist.songs.isEmpty ? null : playlist.songs.first;
    final coverUrl = track?.coverUrl ?? '';
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.48)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _selectedPlaylistId = playlist.id),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverUrl.isNotEmpty)
                    Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 420,
                      errorBuilder: (_, _, _) => _playlistCoverFallback(scheme),
                    )
                  else
                    _playlistCoverFallback(scheme),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.04), Colors.transparent, Colors.black.withValues(alpha: 0.58)],
                        stops: const [0, 0.48, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.54), borderRadius: BorderRadius.circular(8)),
                      child: Text('${playlist.songs.length} lagu', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: IconButton.filled(
                      tooltip: 'Putar ${playlist.name}',
                      onPressed: playlist.songs.isEmpty ? null : () => unawaited(_playPlaylistAndReturn(playlist)),
                      style: IconButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 11, 9, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, height: 1.15)),
                        const SizedBox(height: 4),
                        Text(playlist.songs.isEmpty ? 'Kosong · ketuk untuk isi' : 'Playlist pribadi', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant, size: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistCoverFallback(ColorScheme scheme) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primaryContainer, scheme.secondaryContainer, scheme.surfaceContainerHighest],
          ),
        ),
        child: Center(child: Icon(Icons.queue_music_rounded, color: scheme.onPrimaryContainer, size: 44)),
      );

  Widget _buildPlaylistSongs(Playlist playlist, ColorScheme scheme) {
    if (playlist.songs.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          FlowPageHero(
            icon: Icons.queue_music_rounded,
            eyebrow: 'PLAYLIST',
            title: playlist.name,
            subtitle: 'Playlist ini siap diisi dengan lagu pilihanmu.',
            compact: true,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.library_music_outlined, size: 56, color: scheme.primary),
                const SizedBox(height: 10),
                const Text('Playlist masih kosong', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                const SizedBox(height: 6),
                Text('Tambahkan lagu dari favorit, riwayat, atau daftar yang baru dimuat.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => unawaited(_showAddSongsSheet(playlist)),
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('Tambah lagu'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: FlowPageHero(
            icon: Icons.queue_music_rounded,
            eyebrow: 'PLAYLIST AKTIF',
            title: playlist.name,
            subtitle: '${playlist.songs.length} lagu · bisa diurutkan sesuai keinginanmu.',
            compact: true,
            trailing: IconButton.filledTonal(
              tooltip: 'Putar playlist',
              onPressed: () => unawaited(_playPlaylistAndReturn(playlist)),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(
            children: [
              Expanded(child: Text('${playlist.songs.length} lagu · tahan ikon untuk mengurutkan', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))),
              TextButton.icon(
                onPressed: () => unawaited(_playPlaylistAndReturn(playlist)),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Putar'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            itemCount: playlist.songs.length,
            // onReorderItem already provides the final destination index.
            onReorderItem: (oldIndex, newIndex) =>
                _reorderSongs(playlist, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final song = playlist.songs[index];
              return ValueListenableBuilder<PlayerUiState>(
                key: ValueKey<String>('${playlist.id}:${song.videoId}'),
                valueListenable: widget.playerUiState,
                builder: (context, playerState, _) {
                  final isCurrent = playerState.video?.videoId == song.videoId;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: isCurrent ? scheme.primaryContainer.withValues(alpha: 0.72) : null,
                    child: ListTile(
                      onTap: () => unawaited(_playSongAndReturn(playlist, song)),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            UnifiedArtwork(track: song, width: 52, height: 52, fit: BoxFit.cover),
                            if (isCurrent)
                              Container(
                                width: 52,
                                height: 52,
                                color: scheme.primary.withValues(alpha: 0.42),
                                child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 24),
                              ),
                          ],
                        ),
                      ),
                      title: Text(
                        song.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: isCurrent ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w900) : null,
                      ),
                      subtitle: Text(
                        isCurrent ? 'SEDANG DIPUTAR · ${song.channelTitle}' : song.channelTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: isCurrent ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w700) : null,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCurrent) Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 20),
                          IconButton(
                            tooltip: 'Hapus dari playlist',
                            onPressed: () => unawaited(_removeSong(playlist, song)),
                            icon: const Icon(Icons.remove_circle_outline_rounded),
                          ),
                          ReorderableDragStartListener(
                            index: index,
                            child: Icon(Icons.drag_handle_rounded, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
