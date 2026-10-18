import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../models/playlist.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
import '../widgets/playlist_widgets.dart' show showPlaylistNameDialog;
import '../widgets/unified_artwork.dart';

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
      body: playlist == null
          ? _buildPlaylistList(scheme)
          : _buildPlaylistSongs(playlist, scheme),
    );
  }

  Widget _buildPlaylistList(ColorScheme scheme) {
    if (widget.playlists.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.queue_music_rounded, size: 60, color: scheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('Belum ada playlist MusikKu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Buat playlist sendiri, lalu tambahkan lagu lewat menu lagu.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => unawaited(_createPlaylist()),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Buat playlist'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: widget.playlists.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final playlist = widget.playlists[index];
        final first = playlist.songs.isEmpty ? null : playlist.songs.first;
        return Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: 54,
                height: 54,
                child: first == null
                    ? ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.queue_music_rounded),
                      )
                    : UnifiedArtwork(track: first, width: 54, height: 54, fit: BoxFit.cover),
              ),
            ),
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${playlist.songs.length} lagu'),
            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            onTap: () => setState(() => _selectedPlaylistId = playlist.id),
          ),
        );
      },
    );
  }

  Widget _buildPlaylistSongs(Playlist playlist, ColorScheme scheme) {
    if (playlist.songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.library_music_outlined, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 10),
              const Text('Playlist masih kosong', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 6),
              Text('Tambahkan lagu dari favorit, riwayat, atau daftar yang baru dimuat.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => unawaited(_showAddSongsSheet(playlist)),
                icon: const Icon(Icons.playlist_add_rounded),
                label: const Text('Tambah lagu'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
