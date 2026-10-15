import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';

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
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              'Terakhir diputar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
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
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Pencarian terakhir',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: onClearAll,
                child: const Text('Hapus semua'),
              ),
            ],
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
            Icon(Icons.favorite_border, size: 60, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Favorit (${songs.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onPlayAll,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Putar semua'),
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
