import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import '../services/album_artwork_service.dart';
import 'unified_artwork.dart';

/// Displays album art for the active player, with local-art and YouTube
/// thumbnail fallbacks. Metadata requests are shared/cached by the service.
class AlbumArtworkImage extends StatefulWidget {
  const AlbumArtworkImage({
    super.key,
    required this.track,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.iconSize = 48,
  });

  final YoutubeSearchResult track;
  final BoxFit fit;
  final double? width;
  final double? height;
  final double iconSize;

  @override
  State<AlbumArtworkImage> createState() => _AlbumArtworkImageState();
}

class _AlbumArtworkImageState extends State<AlbumArtworkImage> {
  late Future<String> _coverFuture;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant AlbumArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.videoId != widget.track.videoId ||
        oldWidget.track.title != widget.track.title ||
        oldWidget.track.channelTitle != widget.track.channelTitle) {
      _prepare();
    }
  }

  void _prepare() {
    _coverFuture = AlbumArtworkService.resolveCoverUrl(widget.track);
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.album_rounded, size: widget.iconSize, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _networkImage(BuildContext context, String url) {
    return Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        final fallback = widget.track.coverUrl;
        if (fallback.isNotEmpty && fallback != url) {
          return Image.network(
            fallback,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _fallback(context),
          );
        }
        return _fallback(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.track.isLocal) {
      return UnifiedArtwork(
        track: widget.track,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        iconSize: widget.iconSize,
      );
    }

    final fallback = widget.track.coverUrl;
    return FutureBuilder<String>(
      future: _coverFuture,
      builder: (context, snapshot) {
        final url = snapshot.data;
        // Show YouTube's image immediately; swap to matched square album art
        // once MusicBrainz/Cover Art Archive resolves, avoiding a blank player.
        final displayUrl = url != null && url.isNotEmpty ? url : fallback;
        if (displayUrl.isEmpty) return _fallback(context);
        return _networkImage(context, displayUrl);
      },
    );
  }
}
