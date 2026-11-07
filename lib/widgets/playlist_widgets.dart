import 'package:flutter/material.dart';

import '../models/playlist.dart';
import 'unified_artwork.dart';
import 'playlist_artwork.dart';
import '../models/youtube_search_result.dart';
import 'music_design.dart';
import 'song_lists.dart';

// ============================================================
// DIALOG NAMA PLAYLIST
// ============================================================

/// Menampilkan dialog input nama. Mengembalikan nama (sudah di-trim)
/// atau null kalau dibatalkan / kosong.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String confirmLabel = 'Simpan',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PlaylistNameDialog(
      title: title,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({
    required this.title,
    required this.initial,
    required this.confirmLabel,
  });

  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();

    Navigator.pop(context, name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.7))),
      title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.35)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Nama playlist'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

// ============================================================
// SHEET "TAMBAH KE PLAYLIST"
// ============================================================

/// Sheet tetap terbuka setelah satu playlist diketuk, jadi lagu bisa
/// ditambahkan ke beberapa playlist sekaligus. Playlist yang sudah berisi
/// lagu ini diberi centang; mengetuknya lagi menghapus lagu dari playlist itu.
void showAddToPlaylistSheet(
  BuildContext context, {
  required YoutubeSearchResult video,
  required List<Playlist> playlists,
  required void Function(Playlist playlist) onToggle,
  required VoidCallback onCreateNew,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (innerContext, setSheetState) {
          final scheme = Theme.of(sheetContext).colorScheme;
          final addedCount = playlists.where((playlist) => playlist.containsTrack(video)).length;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.78),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 18, 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SIMPAN LAGU', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
                            const SizedBox(height: 5),
                            Text('Masukkan ke koleksi', style: TextStyle(color: scheme.onSurface, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                            const SizedBox(height: 3),
                            Text(addedCount == 0 ? 'Pilih playlist untuk menyimpan lagu ini.' : 'Sudah tersimpan di $addedCount playlist.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Selesai',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.58)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: UnifiedArtwork(track: video, width: 58, height: 58),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 12.5, fontWeight: FontWeight.w900, height: 1.2)),
                              const SizedBox(height: 4),
                              Text(video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      onCreateNew();
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Buat playlist baru'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46), alignment: Alignment.centerLeft),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                  child: Row(
                    children: [
                      Text('PLAYLIST KAMU', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                      const Spacer(),
                      Text('${playlists.length} koleksi', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Flexible(
                  child: playlists.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.library_music_outlined, size: 36, color: scheme.onSurfaceVariant),
                              const SizedBox(height: 8),
                              Text('Belum ada playlist', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text('Buat playlist baru untuk mulai mengumpulkan lagu.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
                          itemCount: playlists.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            final playlist = playlists[index];
                            final contains = playlist.containsTrack(video);
                            return Material(
                              color: contains ? scheme.primary.withValues(alpha: 0.10) : scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(15),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(15),
                                onTap: () {
                                  onToggle(playlist);
                                  setSheetState(() {});
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(9),
                                  child: Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(10),
                                        child: SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: PlaylistArtwork(
                                            playlist: playlist,
                                            width: 48,
                                            height: 48,
                                            iconSize: 22,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 12.5, fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 4),
                                            Text('${playlist.songs.length} lagu${contains ? ' · lagu ini sudah ada' : ''}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(contains ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: contains ? scheme.primary : scheme.onSurfaceVariant, size: 22),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

// ============================================================
// DAFTAR PLAYLIST
// ============================================================

class PlaylistsView extends StatelessWidget {
  const PlaylistsView({
    super.key,
    required this.playlists,
    required this.onOpen,
    required this.onCreate,
  });

  final List<Playlist> playlists;
  final ValueChanged<Playlist> onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: MusicPageHeader(
            icon: Icons.queue_music_rounded,
            eyebrow: 'KOLEKSI PRIBADI',
            title: 'Playlist kamu',
            subtitle: '${playlists.length} playlist · susun lagu sesuai suasana',
            trailing: IconButton.filledTonal(
              tooltip: 'Playlist baru',
              onPressed: onCreate,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
            child: MusicEmptyState(
              icon: Icons.queue_music_rounded,
              title: 'Belum ada playlist',
              message: 'Buat playlist pertama, lalu tahan lagu untuk menambahkannya.',
              actionLabel: 'Buat playlist',
              onAction: onCreate,
            ),
          ),
        for (var index = 0; index < playlists.length; index++)
          Builder(
            builder: (context) {
              final playlist = playlists[index];
              final scheme = Theme.of(context).colorScheme;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 9),
                child: Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => onOpen(playlist),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: PlaylistArtwork(playlist: playlist, width: 68, height: 68, iconSize: 28),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 5),
                                Text('${playlist.songs.length} lagu · Koleksi pribadi', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5)),
                                const SizedBox(height: 8),
                                Container(width: 34, height: 3, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4))),
                              ],
                            ),
                          ),
                          const SizedBox(width: 7),
                          Icon(Icons.arrow_forward_rounded, color: scheme.primary, size: 19),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

// ============================================================
// ISI SATU PLAYLIST
// ============================================================

enum _PlaylistAction { rename, delete }

class PlaylistDetailView extends StatelessWidget {
  const PlaylistDetailView({
    super.key,
    required this.playlist,
    required this.cardBuilder,
    required this.onBack,
    required this.onPlayAll,
    required this.onRename,
    required this.onDelete,
  });

  final Playlist playlist;
  final SongCardBuilder cardBuilder;
  final VoidCallback onBack;
  final VoidCallback onPlayAll;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final songs = playlist.songs;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: songs.isEmpty ? 2 : songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: MusicGlassPanel(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
              radius: 20,
              child: Row(
              children: [
                IconButton(
                  tooltip: 'Kembali',
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                Expanded(
                  child: Text(
                    '${playlist.name} (${songs.length})',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (songs.isNotEmpty)
                  TextButton.icon(
                    onPressed: onPlayAll,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Putar'),
                  ),
                PopupMenuButton<_PlaylistAction>(
                  color: Theme.of(context).colorScheme.surface,
                  onSelected: (action) {
                    switch (action) {
                      case _PlaylistAction.rename:
                        onRename();
                      case _PlaylistAction.delete:
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _PlaylistAction.rename,
                      child: Text('Ubah nama'),
                    ),
                    PopupMenuItem(
                      value: _PlaylistAction.delete,
                      child: Text('Hapus playlist'),
                    ),
                  ],
                ),
              ],
            ),
            ),
          );
        }

        if (songs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
            child: MusicEmptyState(
              icon: Icons.library_music_outlined,
              title: 'Playlist masih kosong',
              message: 'Tahan sebuah lagu, lalu pilih "Tambah ke playlist".',
            ),
          );
        }

        return cardBuilder(songs[index - 1]);
      },
    );
  }
}
