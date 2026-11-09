import 'dart:io';

import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/youtube_search_result.dart';
import 'unified_artwork.dart';

/// Displays a user's custom playlist cover, falling back to its first track.
/// The custom cover is stored independently, so reordering tracks never changes it.
class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    super.key,
    required this.playlist,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.iconSize = 42,
    this.fallbackBackground,
    this.fallbackForeground,
  });

  final Playlist playlist;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double iconSize;
  final Color? fallbackBackground;
  final Color? fallbackForeground;

  @override
  Widget build(BuildContext context) {
    final customPath = playlist.artworkPath?.trim() ?? '';
    if (customPath.isNotEmpty) {
      return Image.file(
        File(customPath),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) => _trackOrFallback(context),
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _trackOrFallback(context);
        },
      );
    }
    return _trackOrFallback(context);
  }

  Widget _trackOrFallback(BuildContext context) {
    final YoutubeSearchResult? firstTrack =
        playlist.songs.isEmpty ? null : playlist.songs.first;
    if (firstTrack != null) {
      return UnifiedArtwork(
        track: firstTrack,
        width: width,
        height: height,
        fit: fit,
        iconSize: iconSize,
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fallbackBackground ?? scheme.primaryContainer,
        ),
        child: Center(
          child: Icon(
            Icons.queue_music_rounded,
            size: iconSize,
            color: fallbackForeground ?? scheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
