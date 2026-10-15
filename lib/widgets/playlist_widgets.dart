import 'package:flutter/material.dart';

import '../models/playlist.dart';
import 'unified_artwork.dart';
import '../models/youtube_search_result.dart';
import '../theme/app_colors.dart';
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Text(widget.title),
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

void showAddToPlaylistSheet(
  BuildContext context, {
  required YoutubeSearchResult video,
  required List<Playlist> playlists,
  required void Function(Playlist playlist) onToggle,
  required VoidCallback onCreateNew,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tambah ke playlist',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add, color: appGold),
                title: const Text('Playlist baru'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onCreateNew();
                },
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final playlist in playlists)
                      ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text('${playlist.songs.length} lagu'),
                        trailing: playlist.contains(video.videoId)
                            ? const Icon(Icons.check_circle, color: appGold)
                            : null,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          onToggle(playlist);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Playlist (${playlists.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Baru'),
              ),
            ],
          ),
        ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Column(
              children: [
                Icon(Icons.queue_music, size: 60, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'Belum ada playlist',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                ),
                const SizedBox(height: 5),
                Text(
                  'Buat playlist, lalu tahan lagu untuk menambahkannya.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        for (final playlist in playlists)
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: playlist.songs.isEmpty
                    ? Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.queue_music),
                      )
                    : UnifiedArtwork(
                        track: playlist.songs.first,
                        width: 56,
                        height: 56,
                        cacheWidth: 168,
                        borderRadius: BorderRadius.circular(8),
                      ),
              ),
            ),
            title: Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text('${playlist.songs.length} lagu'),
            trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
            onTap: () => onOpen(playlist),
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
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
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
          );
        }

        if (songs.isEmpty) {
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Column(
              children: [
                Icon(Icons.library_music_outlined, size: 60, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'Playlist masih kosong',
                  style: TextStyle(color: scheme.onSurface, fontSize: 16),
                ),
                const SizedBox(height: 5),
                Text(
                  'Tahan sebuah lagu, lalu pilih "Tambah ke playlist".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          );
        }

        return cardBuilder(songs[index - 1]);
      },
    );
  }
}
