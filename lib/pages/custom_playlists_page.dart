import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/playlist.dart';
import '../models/player_ui_state.dart';
import '../models/native_youtube_state.dart';
import '../models/youtube_search_result.dart';
import '../widgets/playlist_widgets.dart' show showPlaylistNameDialog;
import '../widgets/unified_artwork.dart';
import '../widgets/playlist_artwork.dart';
import '../widgets/flow_components.dart';
import '../widgets/music_design.dart';
import '../widgets/mini_music_player.dart';

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
    this.onShufflePlaylist,
    this.currentVideo,
    this.nativeState,
    this.onOpenCurrentPlayer,
    this.onMiniPlayPause,
    this.onMiniNext,
    this.onSelectTab,
  });

  final List<Playlist> playlists;
  final ValueListenable<PlayerUiState> playerUiState;
  final List<YoutubeSearchResult> availableSongs;
  final VoidCallback onChanged;
  final Future<void> Function(Playlist playlist) onPlayPlaylist;
  final Future<void> Function(Playlist playlist, YoutubeSearchResult song)
      onPlaySong;
  final Future<void> Function(Playlist playlist)? onShufflePlaylist;
  final YoutubeSearchResult? currentVideo;
  final ValueListenable<NativeYoutubeState>? nativeState;
  final VoidCallback? onOpenCurrentPlayer;
  final Future<void> Function()? onMiniPlayPause;
  final Future<void> Function()? onMiniNext;
  final ValueChanged<int>? onSelectTab;

  @override
  State<CustomPlaylistsPage> createState() => _CustomPlaylistsPageState();
}

class _CustomPlaylistsPageState extends State<CustomPlaylistsPage> {
  final ImagePicker _imagePicker = ImagePicker();
  String? _selectedPlaylistId;
  bool _changingArtwork = false;

  Playlist? get _selectedPlaylist {
    final id = _selectedPlaylistId;
    if (id == null) return null;
    for (final playlist in widget.playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  void _selectMainTab(int index) {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    widget.onSelectTab?.call(index);
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

  Future<void> _changePlaylistArtwork(Playlist playlist) async {
    if (_changingArtwork) return;
    setState(() => _changingArtwork = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null || !mounted) return;

      final documents = await getApplicationDocumentsDirectory();
      final coverDirectory = Directory('${documents.path}/musikku_playlist_covers');
      await coverDirectory.create(recursive: true);
      final safeId = playlist.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final pickedName = picked.name;
      final extension = pickedName.contains('.')
          ? '.${pickedName.split('.').last.toLowerCase()}'
          : '.jpg';
      final destination = File(
        '${coverDirectory.path}/${safeId}_${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      await File(picked.path).copy(destination.path);
      if (!mounted) return;

      final oldPath = playlist.artworkPath;
      setState(() => playlist.artworkPath = destination.path);
      widget.onChanged();
      _deleteManagedArtwork(oldPath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto cover playlist berhasil diganti.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Foto cover belum bisa disimpan: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _changingArtwork = false);
    }
  }

  Future<void> _removePlaylistArtwork(Playlist playlist) async {
    final oldPath = playlist.artworkPath;
    if (oldPath == null || oldPath.isEmpty) return;
    setState(() => playlist.artworkPath = null);
    widget.onChanged();
    _deleteManagedArtwork(oldPath);
  }

  void _deleteManagedArtwork(String? path) {
    if (path == null || path.isEmpty) return;
    unawaited(() async {
      try {
        final documents = await getApplicationDocumentsDirectory();
        final managedDirectory = '${documents.path}/musikku_playlist_covers/';
        if (path.startsWith(managedDirectory)) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      } catch (_) {
        // A stale cover file must never block a playlist edit.
      }
    }());
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
    final oldArtworkPath = playlist.artworkPath;
    setState(() {
      widget.playlists.removeWhere((item) => item.id == playlist.id);
      if (_selectedPlaylistId == playlist.id) _selectedPlaylistId = null;
    });
    widget.onChanged();
    _deleteManagedArtwork(oldArtworkPath);
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: MusicGlassPanel(
                    padding: const EdgeInsets.all(14),
                    radius: 21,
                    child: Row(
                      children: [
                        const Expanded(
                          child: MusicSheetHeading(
                            icon: Icons.playlist_add_rounded,
                            title: 'Tambah lagu',
                            subtitle: 'Pilih lagu untuk koleksi ini.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${selectedIds.length}',
                            style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
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

  Future<void> _shufflePlaylistAndReturn(Playlist playlist) async {
    final action = widget.onShufflePlaylist;
    if (action == null || playlist.songs.isEmpty) return;
    try {
      final playback = action(playlist);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await playback;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playlist belum bisa diacak. Coba lagi ya.')),
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
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.94),
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
                if (value == 'cover') unawaited(_changePlaylistArtwork(playlist));
                if (value == 'reset_cover') unawaited(_removePlaylistArtwork(playlist));
                if (value == 'rename') unawaited(_renamePlaylist(playlist));
                if (value == 'delete') unawaited(_deletePlaylist(playlist));
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'cover', child: Text('Ganti foto cover')),
                if (playlist.artworkPath != null && playlist.artworkPath!.isNotEmpty)
                  const PopupMenuItem(value: 'reset_cover', child: Text('Pakai cover lagu pertama')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'rename', child: Text('Ubah nama')),
                const PopupMenuItem(value: 'delete', child: Text('Hapus playlist')),
              ],
            ),
        ],
      ),
      body: MusicBackdrop(
        child: Stack(
          children: [
            Positioned.fill(
              child: MusicPageEntrance(
                child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0.035, 0), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: playlist == null
                ? KeyedSubtree(key: const ValueKey<String>('playlist-library'), child: _buildPlaylistList(scheme))
                : KeyedSubtree(key: ValueKey<String>('playlist-${playlist.id}'), child: _buildPlaylistSongs(playlist, scheme)),
                ),
              ),
            ),
            if (widget.currentVideo != null &&
                widget.nativeState != null &&
                widget.onOpenCurrentPlayer != null &&
                widget.onMiniPlayPause != null &&
                widget.onMiniNext != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: MediaQuery.paddingOf(context).bottom + 66 + 18,
                child: MiniMusicPlayer(
                  video: widget.currentVideo!,
                  nativeState: widget.nativeState!,
                  onOpen: widget.onOpenCurrentPlayer!,
                  onPlayPause: widget.onMiniPlayPause!,
                  onNext: widget.onMiniNext!,
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: MediaQuery.paddingOf(context).bottom + 8,
              child: _PlaylistDock(onSelect: _selectMainTab),
            ),
          ],
        ),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 184),
        children: [
          hero,
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.72)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(22),
                      topRight: Radius.circular(22),
                      bottomRight: Radius.circular(22),
                      bottomLeft: Radius.circular(6),
                    ),
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 184),
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
    return Material(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.72)),
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
                  PlaylistArtwork(
                    playlist: playlist,
                    fit: BoxFit.cover,
                    iconSize: 42,
                  ),
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


  Widget _playlistDetailArtwork(Playlist playlist, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 2),
      child: Column(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PlaylistArtwork(
                        playlist: playlist,
                        fit: BoxFit.cover,
                        iconSize: 68,
                      ),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.58),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _changingArtwork
                                ? null
                                : () => unawaited(_changePlaylistArtwork(playlist)),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: _changingArtwork
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.edit_rounded,
                                      color: Colors.white,
                                      size: 21,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 17),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 27,
                height: 1.05,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Playlist pribadi  ·  ${playlist.songs.length} lagu',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistActionRow(Playlist playlist, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: OutlinedButton(
              onPressed: playlist.songs.isEmpty || widget.onShufflePlaylist == null
                  ? null
                  : () => unawaited(_shufflePlaylistAndReturn(playlist)),
              style: OutlinedButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.42)),
                foregroundColor: scheme.primary,
              ),
              child: const Icon(Icons.shuffle_rounded, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: playlist.songs.isEmpty
                    ? null
                    : () => unawaited(_playPlaylistAndReturn(playlist)),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text('Play', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton.filledTonal(
              tooltip: 'Tambah lagu',
              onPressed: () => unawaited(_showAddSongsSheet(playlist)),
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.78),
                foregroundColor: scheme.onSecondaryContainer,
              ),
              icon: const Icon(Icons.add_rounded, size: 25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistSongs(Playlist playlist, ColorScheme scheme) {
    return Column(
      children: [
        _playlistDetailArtwork(playlist, scheme),
        _playlistActionRow(playlist, scheme),
        Padding(
          padding: const EdgeInsets.fromLTRB(23, 2, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Daftar lagu',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: scheme.onSurface),
                ),
              ),
              Text(
                '${playlist.songs.length} lagu',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: playlist.songs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_note_rounded, size: 44, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                        const SizedBox(height: 9),
                        const Text('Playlist masih kosong', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        Text(
                          'Tambahkan lagu dari favorit, riwayat, atau hasil pencarian.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 184),
                  itemCount: playlist.songs.length,
                  onReorderItem: (oldIndex, newIndex) => _reorderSongs(playlist, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final song = playlist.songs[index];
                    return ValueListenableBuilder<PlayerUiState>(
                      key: ValueKey<String>('${playlist.id}:${song.videoId}'),
                      valueListenable: widget.playerUiState,
                      builder: (context, playerState, _) {
                        final isCurrent = playerState.video?.videoId == song.videoId;
                        return Material(
                          color: isCurrent ? scheme.primaryContainer.withValues(alpha: 0.22) : Colors.transparent,
                          child: InkWell(
                            onTap: () => unawaited(_playSongAndReturn(playlist, song)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42))),
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          UnifiedArtwork(track: song, width: 52, height: 52, fit: BoxFit.cover),
                                          if (isCurrent)
                                            ColoredBox(
                                              color: Colors.black.withValues(alpha: 0.34),
                                              child: const Icon(Icons.equalizer_rounded, color: Colors.white, size: 24),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 14, fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700, color: isCurrent ? scheme.primary : scheme.onSurface),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          song.channelTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCurrent)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 2),
                                      child: Icon(Icons.volume_up_rounded, color: scheme.primary, size: 18),
                                    ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Opsi lagu',
                                    onSelected: (value) {
                                      if (value == 'remove') unawaited(_removeSong(playlist, song));
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'remove', child: Text('Hapus dari playlist')),
                                    ],
                                    icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Icon(Icons.drag_handle_rounded, color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
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

class _PlaylistDock extends StatelessWidget {
  const _PlaylistDock({required this.onSelect});

  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget destination(int index, String label, IconData icon, IconData activeIcon) {
      final selected = index == 3;
      return Expanded(
        child: InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? activeIcon : icon, size: 20, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(height: 3),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: selected ? FontWeight.w900 : FontWeight.w600, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      height: 60,
      decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(15), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7))),
      child: Row(children: [
        destination(0, 'Beranda', Icons.home_outlined, Icons.home_rounded),
        destination(1, 'Jelajah', Icons.explore_outlined, Icons.explore_rounded),
        destination(2, 'Radio', Icons.radio_outlined, Icons.radio_rounded),
        destination(3, 'Koleksi', Icons.library_music_outlined, Icons.library_music_rounded),
      ]),
    );
  }
}
