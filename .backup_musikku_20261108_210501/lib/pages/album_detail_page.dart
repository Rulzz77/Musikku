import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import '../services/youtube_search_service.dart';
import '../widgets/album_artwork_image.dart';
import '../widgets/music_design.dart';

/// Editorial album page. Playback remains owned by YoutubeHub/HomePage.
class AlbumDetailPage extends StatelessWidget {
  const AlbumDetailPage({
    super.key,
    required this.albumTitle,
    required this.tracks,
    required this.onPlayFromList,
  });

  final String albumTitle;
  final List<YoutubeSearchResult> tracks;
  final Future<void> Function(
    YoutubeSearchResult selected,
    List<YoutubeSearchResult> tracks,
  ) onPlayFromList;

  String _artistLabel(YoutubeSearchResult track) {
    final artist = track.artistName.trim();
    return artist.isNotEmpty ? artist : track.channelTitle;
  }

  String _durationLabel(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  String _totalDuration(List<YoutubeSearchResult> items) {
    final values = items
        .map((track) => track.durationSeconds?.round())
        .whereType<int>()
        .where((value) => value > 0)
        .toList(growable: false);
    if (values.isEmpty) return 'Durasi tidak tersedia';
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    if (hours > 0) return '$hours jam $minutes menit';
    return '$minutes menit';
  }

  Future<void> _play(List<YoutubeSearchResult> validTracks, {bool shuffle = false}) async {
    if (validTracks.isEmpty) return;
    final ordered = List<YoutubeSearchResult>.from(validTracks);
    if (shuffle) ordered.shuffle(math.Random());
    await onPlayFromList(ordered.first, ordered);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final validTracks = tracks
        .where((track) => track.videoId.isNotEmpty && YoutubeSearchService.isMusicCandidate(track))
        .toList(growable: false);
    final cover = validTracks.isEmpty ? (tracks.isEmpty ? null : tracks.first) : validTracks.first;
    final artist = cover == null ? 'Artis tidak diketahui' : _artistLabel(cover);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cover != null)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                child: Opacity(
                  opacity: isDark ? 0.20 : 0.12,
                  child: AlbumArtworkImage(track: cover, fit: BoxFit.cover),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [const Color(0xD910141B), const Color(0xF5111419)]
                      : [const Color(0xDDF5F7FA), const Color(0xF7F5F7FA)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 18, 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Kembali',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ALBUM', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.7)),
                            Text('Detail album', style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 720;
                      final hero = _buildHero(
                        context,
                        cover: cover,
                        artist: artist,
                        count: validTracks.length,
                        duration: _totalDuration(validTracks),
                        wide: wide,
                        onPlay: validTracks.isEmpty ? null : () => _play(validTracks),
                        onShuffle: validTracks.isEmpty ? null : () => _play(validTracks, shuffle: true),
                      );
                      final list = _buildTrackList(context, validTracks);
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: math.min(420.0, constraints.maxWidth * 0.42).toDouble(), child: SingleChildScrollView(child: hero)),
                            Expanded(child: list),
                          ],
                        );
                      }
                      return ListView(
                        padding: const EdgeInsets.only(bottom: 28),
                        children: [hero, SizedBox(height: 8), SizedBox(height: math.max(420.0, constraints.maxHeight * 0.56).toDouble(), child: list)],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero(
    BuildContext context, {
    required YoutubeSearchResult? cover,
    required String artist,
    required int count,
    required String duration,
    required bool wide,
    required VoidCallback? onPlay,
    required VoidCallback? onShuffle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    final imageSize = (wide ? math.min(320.0, width * 0.34) : math.min(width - 72, 310.0)).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: imageSize,
              height: imageSize,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 28, offset: const Offset(0, 14))],
              ),
              clipBehavior: Clip.antiAlias,
              child: cover == null
                  ? ColoredBox(color: scheme.primaryContainer, child: Icon(Icons.album_rounded, size: 72, color: scheme.onPrimaryContainer))
                  : AlbumArtworkImage(track: cover, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 22),
          Text('ALBUM COLLECTION', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.7)),
          const SizedBox(height: 6),
          Text(albumTitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 27, height: 1.02, fontWeight: FontWeight.w900, letterSpacing: -0.9)),
          const SizedBox(height: 7),
          Text(artist, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('$count lagu · $duration', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5)),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Putar album'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
              const SizedBox(width: 9),
              IconButton.filledTonal(
                tooltip: 'Acak album',
                onPressed: onShuffle,
                icon: const Icon(Icons.shuffle_rounded),
                style: IconButton.styleFrom(fixedSize: const Size(48, 48)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList(BuildContext context, List<YoutubeSearchResult> validTracks) {
    final scheme = Theme.of(context).colorScheme;
    if (validTracks.isEmpty) {
      return const Center(child: MusicEmptyState(icon: Icons.album_outlined, title: 'Track album belum tersedia', message: 'Belum ada daftar lagu yang bisa diputar dari album ini.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: validTracks.length + 1,
      separatorBuilder: (_, _) => Divider(height: 1, indent: 68, color: scheme.outlineVariant.withValues(alpha: 0.45)),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Row(
              children: [
                Expanded(child: Text('Daftar lagu', style: TextStyle(color: scheme.onSurface, fontSize: 17, fontWeight: FontWeight.w900))),
                Text('${validTracks.length} track', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }
        final track = validTracks[index - 1];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: AlbumArtworkImage(track: track, width: 48, height: 48, fit: BoxFit.cover),
          ),
          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
          subtitle: Text(_artistLabel(track), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Text(_durationLabel(track.durationSeconds?.round()), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w700)),
          onTap: () => unawaited(onPlayFromList(track, validTracks)),
        );
      },
    );
  }
}
