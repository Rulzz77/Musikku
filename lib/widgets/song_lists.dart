import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import 'music_design.dart';

/// A parent-owned song renderer keeps playback, queue and favorite actions in
/// the screen that owns the player state.
typedef SongCardBuilder = Widget Function(YoutubeSearchResult video);

class RecentSongsList extends StatelessWidget {
  const RecentSongsList({
    super.key,
    required this.songs,
    required this.cardBuilder,
  });

  final List<YoutubeSearchResult> songs;
  final SongCardBuilder cardBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 104),
      itemCount: songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('YOUR TIMELINE', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
                          const SizedBox(height: 5),
                          Text('Putar kembali', style: TextStyle(color: scheme.onSurface, fontSize: 25, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1.0)),
                        ],
                      ),
                    ),
                    _CountMark(count: songs.length, label: 'lagu'),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Lanjutkan suasana dari lagu yang terakhir kamu dengarkan.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4)),
                const SizedBox(height: 12),
                Container(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: cardBuilder(songs[index - 1]),
        );
      },
    );
  }
}

class SearchHistoryList extends StatelessWidget {
  const SearchHistoryList({
    super.key,
    required this.queries,
    required this.onSelect,
    required this.onRemove,
    required this.onClearAll,
  });

  final List<String> queries;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 110),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SEARCH MEMORY', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
                  const SizedBox(height: 5),
                  Text('Cari lagi', style: TextStyle(color: scheme.onSurface, fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -1)),
                ],
              ),
            ),
            if (queries.isNotEmpty)
              TextButton.icon(
                onPressed: onClearAll,
                icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                label: const Text('Bersihkan'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Kata kunci yang pernah kamu cari.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 18),
        if (queries.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: MusicEmptyState(
              icon: Icons.manage_search_rounded,
              title: 'Belum ada riwayat',
              message: 'Pencarian yang kamu lakukan akan muncul di sini.',
            ),
          )
        else
          for (var i = 0; i < queries.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Material(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(15),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(queries[i]),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 10, 8, 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: Text('${i + 1}'.padLeft(2, '0'), style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w900)),
                        ),
                        Container(
                          width: 35,
                          height: 35,
                          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(11)),
                          child: Icon(Icons.history_rounded, size: 18, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(queries[i], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                        IconButton(
                          tooltip: 'Hapus riwayat',
                          onPressed: () => onRemove(queries[i]),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant, size: 18),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class FavoriteSongsList extends StatelessWidget {
  const FavoriteSongsList({
    super.key,
    required this.songs,
    required this.cardBuilder,
    required this.onPlayAll,
  });

  final List<YoutubeSearchResult> songs;
  final SongCardBuilder cardBuilder;
  final VoidCallback onPlayAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (songs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: MusicEmptyState(
            icon: Icons.favorite_rounded,
            title: 'Ruang favoritmu masih kosong',
            message: 'Simpan lagu dengan ikon hati. Semua pilihanmu akan terkumpul di sini.',
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 110),
      itemCount: songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 19),
            child: Container(
              padding: const EdgeInsets.fromLTRB(17, 16, 15, 16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                  bottomLeft: Radius.circular(5),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SAVED BY YOU', style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.72), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
                        const SizedBox(height: 5),
                        Text('Favorit', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 27, height: 1, fontWeight: FontWeight.w900, letterSpacing: -1)),
                        const SizedBox(height: 7),
                        Text('${songs.length} lagu tersimpan', style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.78), fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: scheme.onPrimaryContainer,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onPlayAll,
                      child: SizedBox(width: 54, height: 54, child: Icon(Icons.play_arrow_rounded, color: scheme.primaryContainer, size: 32)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: cardBuilder(songs[index - 1]),
        );
      },
    );
  }
}

class _CountMark extends StatelessWidget {
  const _CountMark({required this.count, required this.label});
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(9)),
      child: Text('$count $label', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}
