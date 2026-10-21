import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import 'flow_components.dart';

/// Membangun satu kartu lagu. Diberikan oleh halaman induk supaya aksi
/// (putar, antrean, favorit) tetap diurus di sana.
typedef SongCardBuilder = Widget Function(YoutubeSearchResult video);

/// Daftar "Terakhir diputar".
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
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: FlowSectionHeader(icon: Icons.history_rounded, title: 'Terakhir diputar'),
          );
        }

        return cardBuilder(songs[index - 1]);
      },
    );
  }
}

/// Daftar riwayat kata kunci pencarian.
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
    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
          child: FlowSectionHeader(
            icon: Icons.manage_search_rounded,
            title: 'Pencarian terakhir',
            trailing: TextButton(onPressed: onClearAll, child: const Text('Hapus')),
          ),
        ),
        for (final query in queries)
          ListTile(
            leading: Icon(Icons.history, color: Theme.of(context).colorScheme.onSurfaceVariant),
            title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onSelect(query),
            trailing: IconButton(
              tooltip: 'Hapus',
              onPressed: () => onRemove(query),
              icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 20),
            ),
          ),
      ],
    );
  }
}

/// Daftar lagu favorit (termasuk tampilan kosong).
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
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite_rounded, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'Belum ada lagu favorit',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
            ),
            const SizedBox(height: 5),
            Text(
              'Ketuk ikon hati pada lagu untuk menyimpannya.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
            child: FlowSectionHeader(
              icon: Icons.favorite_rounded,
              title: 'Favorit (${songs.length})',
              trailing: TextButton.icon(
                onPressed: onPlayAll,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Putar semua'),
              ),
            ),
          );
        }

        return cardBuilder(songs[index - 1]);
      },
    );
  }
}
