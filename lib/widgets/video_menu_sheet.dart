import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/youtube_search_result.dart';
import '../theme/app_colors.dart';
import 'unified_artwork.dart';

/// Menu yang muncul saat kartu lagu ditekan lama.
void showVideoMenuSheet(
  BuildContext context, {
  required YoutubeSearchResult video,
  required bool isFavorite,
  required bool isLiked,
  required bool isDisliked,
  required bool isChannelBlocked,
  required VoidCallback onLike,
  required VoidCallback onDislike,
  required VoidCallback onToggleChannelBlock,
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
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Theme.of(sheetContext).colorScheme.primary.withValues(alpha: 0.16),
                          Theme.of(sheetContext).colorScheme.surfaceContainerLow,
                          Theme.of(sheetContext).colorScheme.secondary.withValues(alpha: 0.08),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(sheetContext).colorScheme.outlineVariant.withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: UnifiedArtwork(track: video, width: 70, height: 70, iconSize: 28),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 5),
                              Text(video.channelTitle.isEmpty ? 'Artis tidak diketahui' : video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: Theme.of(sheetContext).colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 7),
                              Text('PILIH AKSI LAGU', style: TextStyle(fontSize: 9, letterSpacing: 1.0, fontWeight: FontWeight.w900, color: Theme.of(sheetContext).colorScheme.secondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!video.isLocal)
                  ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: const Text('Salin tautan lagu'),
                    subtitle: const Text('Salin tautan publik agar mudah dibagikan.'),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await Clipboard.setData(ClipboardData(text: 'https://youtu.be/${video.videoId}'));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tautan lagu disalin.')),
                        );
                      }
                    },
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
                if (!video.isLocal && video.channelTitle.trim().isNotEmpty)
                  ListTile(
                    leading: Icon(
                      isChannelBlocked ? Icons.check_circle_outline : Icons.block_rounded,
                      color: isChannelBlocked ? Theme.of(sheetContext).colorScheme.primary : null,
                    ),
                    title: Text(
                      isChannelBlocked
                          ? 'Izinkan rekomendasi channel'
                          : 'Jangan rekomendasikan channel',
                    ),
                    subtitle: Text(
                      isChannelBlocked
                          ? 'Channel ini akan bisa muncul lagi di Radio.'
                          : 'Sembunyikan ${video.channelTitle} dari Radio berikutnya.',
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onToggleChannelBlock();
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
