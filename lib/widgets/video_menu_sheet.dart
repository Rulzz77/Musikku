import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import '../theme/app_colors.dart';

/// Menu yang muncul saat kartu lagu ditekan lama.
void showVideoMenuSheet(
  BuildContext context, {
  required YoutubeSearchResult video,
  required bool isFavorite,
  required bool isLiked,
  required bool isDisliked,
  required VoidCallback onLike,
  required VoidCallback onDislike,
  required VoidCallback onOpenArtist,
  required VoidCallback onPlayNext,
  required VoidCallback onAddToQueue,
  required VoidCallback onToggleFavorite,
  required VoidCallback onAddToPlaylist,
  required VoidCallback onStartRadio,
  VoidCallback? onRemoveFromPlaylist,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.88;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.thumb_up_outlined),
                  title: Text(isLiked ? 'Batal suka' : 'Saya suka'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onLike();
                  },
                ),
                ListTile(
                  leading: Icon(
                    isDisliked ? Icons.thumb_down : Icons.thumb_down_outlined,
                    color: isDisliked ? Colors.redAccent : null,
                  ),
                  title: Text(
                    isDisliked ? 'Batal tidak suka' : 'Jangan rekomendasikan',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onDislike();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Lihat artis / channel'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onOpenArtist();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.playlist_play),
                  title: const Text('Putar berikutnya'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onPlayNext();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Tambah ke antrean'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onAddToQueue();
                  },
                ),
                ListTile(
                  leading: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? appGold : null,
                  ),
                  title: Text(
                    isFavorite ? 'Hapus dari favorit' : 'Tambah ke favorit',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onToggleFavorite();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Radio dari lagu ini'),
                  subtitle: const Text('Buat antrean lagu terbaru yang sejenis'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onStartRadio();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.library_add),
                  title: const Text('Tambah ke playlist'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onAddToPlaylist();
                  },
                ),
                if (onRemoveFromPlaylist != null)
                  ListTile(
                    leading: const Icon(Icons.remove_circle_outline),
                    title: const Text('Hapus dari playlist ini'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onRemoveFromPlaylist();
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
