import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/youtube_search_result.dart';
import 'unified_artwork.dart';
import 'music_design.dart';

/// Menu yang muncul saat kartu lagu ditekan lama.
///
/// Semua callback dipanggil setelah sheet ditutup. Kalau callback membuka
/// dialog/sheet lain, gunakan `context` halaman pemanggil, bukan context sheet.
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
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).colorScheme;
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.88;
      final isRemote = !video.isLocal;
      final hasChannel = video.channelTitle.trim().isNotEmpty;

      void closeThen(VoidCallback action) {
        Navigator.pop(sheetContext);
        action();
      }

      Widget actionTile({
        required IconData icon,
        required String title,
        String? subtitle,
        Color? accent,
        required VoidCallback onTap,
      }) {
        final tone = accent ?? colors.primary;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          child: Material(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(17),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 13, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(icon, color: tone, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.25,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.7),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: MusicGlassPanel(
                    padding: const EdgeInsets.all(13),
                    radius: 22,
                    accent: colors.primary,
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: UnifiedArtwork(
                            track: video,
                            width: 76,
                            height: 76,
                            iconSize: 28,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.2,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                video.channelTitle.isEmpty
                                    ? 'Artis tidak diketahui'
                                    : video.channelTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  isRemote ? 'YOUTUBE' : 'MUSIK LOKAL',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    letterSpacing: 0.8,
                                    fontWeight: FontWeight.w900,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isRemote)
                  actionTile(
                    icon: Icons.link_rounded,
                    title: 'Salin tautan lagu',
                    subtitle: 'Salin tautan publik agar mudah dibagikan.',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await Clipboard.setData(
                        ClipboardData(text: 'https://youtu.be/${video.videoId}'),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Tautan lagu disalin.')),
                        );
                      }
                    },
                  ),
                actionTile(
                  icon: isLiked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                  title: isLiked ? 'Batal suka' : 'Saya suka',
                  accent: isLiked ? colors.primary : null,
                  onTap: () => closeThen(onLike),
                ),
                actionTile(
                  icon: isDisliked
                      ? Icons.thumb_down_rounded
                      : Icons.thumb_down_outlined,
                  title: isDisliked ? 'Batal tidak suka' : 'Jangan rekomendasikan',
                  subtitle: 'Bantu sesuaikan lagu yang muncul berikutnya.',
                  accent: isDisliked ? colors.error : null,
                  onTap: () => closeThen(onDislike),
                ),
                if (isRemote && hasChannel)
                  actionTile(
                    icon: isChannelBlocked
                        ? Icons.check_circle_outline_rounded
                        : Icons.block_rounded,
                    title: isChannelBlocked
                        ? 'Izinkan rekomendasi channel'
                        : 'Jangan rekomendasikan channel',
                    subtitle: isChannelBlocked
                        ? 'Channel ini akan bisa muncul lagi di Radio.'
                        : 'Sembunyikan ${video.channelTitle} dari Radio berikutnya.',
                    accent: isChannelBlocked ? colors.primary : colors.error,
                    onTap: () => closeThen(onToggleChannelBlock),
                  ),
                if (isRemote)
                  actionTile(
                    icon: Icons.person_search_rounded,
                    title: 'Lihat artis / channel',
                    onTap: () => closeThen(onOpenArtist),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 15, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'ATUR PEMUTARAN',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 9,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                actionTile(
                  icon: Icons.skip_next_rounded,
                  title: 'Putar berikutnya',
                  onTap: () => closeThen(onPlayNext),
                ),
                actionTile(
                  icon: Icons.playlist_add_rounded,
                  title: 'Tambah ke antrean',
                  onTap: () => closeThen(onAddToQueue),
                ),
                actionTile(
                  icon: isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  title: isFavorite
                      ? 'Hapus dari favorit'
                      : 'Tambah ke favorit',
                  accent: isFavorite ? colors.tertiary : null,
                  onTap: () => closeThen(onToggleFavorite),
                ),
                if (isRemote)
                  actionTile(
                    icon: Icons.radio_rounded,
                    title: 'Radio dari lagu ini',
                    subtitle: 'Buat antrean lagu yang masih relevan dengan lagu ini.',
                    onTap: () => closeThen(onStartRadio),
                  ),
                actionTile(
                  icon: Icons.library_add_rounded,
                  title: 'Tambah ke playlist',
                  onTap: () => closeThen(onAddToPlaylist),
                ),
                if (onRemoveFromPlaylist != null)
                  actionTile(
                    icon: Icons.remove_circle_outline_rounded,
                    title: 'Hapus dari playlist ini',
                    accent: colors.error,
                    onTap: () => closeThen(onRemoveFromPlaylist),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
