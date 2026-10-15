import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import '../services/youtube_search_service.dart';
import '../theme/app_colors.dart';
import '../widgets/unified_artwork.dart';

class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.artist,
    required this.searchService,
    required this.onPlay,
    this.onLongPress,
  });

  final String artist;
  final YoutubeSearchService searchService;
  final ValueChanged<YoutubeSearchResult> onPlay;
  final ValueChanged<YoutubeSearchResult>? onLongPress;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late Future<List<YoutubeSearchResult>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<YoutubeSearchResult>> _load() async {
    final results = await widget.searchService.search(
      '${widget.artist} songs',
    );
    return results
        .where((video) => video.videoId.isNotEmpty)
        .take(30)
        .toList();
  }

  String _formatViews(int views) {
    if (views >= 1000000000) {
      return '${(views / 1000000000).toStringAsFixed(1)} M';
    }
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)} jt';
    }
    if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)} rb';
    }
    return views.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.artist)),
      body: FutureBuilder<List<YoutubeSearchResult>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: snapshot.error.toString(),
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final songs = snapshot.data ?? const <YoutubeSearchResult>[];
          if (songs.isEmpty) {
            return _ErrorState(
              message: 'Belum menemukan lagu dari artis/channel ini.',
              onRetry: () => setState(() => _future = _load()),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: songs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final video = songs[index];
              return Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => widget.onPlay(video),
                  onLongPress: widget.onLongPress == null
                      ? null
                      : () => widget.onLongPress!(video),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: UnifiedArtwork(
                            track: video,
                            width: 92,
                            height: 58,
                            cacheWidth: 276,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                video.channelTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              if (video.viewCount != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  '${_formatViews(video.viewCount!)} ditonton',
                                  style: const TextStyle(
                                    color: appGold,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(Icons.play_circle_fill, color: appGold),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search, size: 60, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      ),
    );
  }
}
