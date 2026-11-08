import 'dart:io';

import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import '../services/album_artwork_service.dart';
import '../services/track_artwork_service.dart';
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
  late Future<String?> _customArtworkFuture;

  @override
  void initState() {
    super.initState();
    TrackArtworkService.revision.addListener(_onCustomArtworkChanged);
    _prepare();
  }

  @override
  void didUpdateWidget(covariant AlbumArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.track;
    final current = widget.track;
    if (old.videoId != current.videoId ||
        old.title != current.title ||
        old.channelTitle != current.channelTitle ||
        old.artistName != current.artistName ||
        old.album != current.album ||
        old.thumbnailUrl != current.thumbnailUrl) {
      _prepare();
    }
  }

  void _onCustomArtworkChanged() {
    _prepare();
    if (mounted) setState(() {});
  }

  void _prepare() {
    _coverFuture = AlbumArtworkService.resolveCoverUrl(widget.track);
    _customArtworkFuture = TrackArtworkService.pathFor(widget.track.videoId);
  }

  @override
  void dispose() {
    TrackArtworkService.revision.removeListener(_onCustomArtworkChanged);
    super.dispose();
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: widget.iconSize,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Memuat [url]. Jika gagal, coba sekali thumbnail bawaan track
  /// (selama berbeda dari [url]), lalu terakhir placeholder.
  Widget _networkImage(BuildContext context, String url) {
    final thumbnail = widget.track.coverUrl;
    final canFallBack = thumbnail.isNotEmpty && thumbnail != url;

    return Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _placeholder(context);
      },
      errorBuilder: (context, error, stackTrace) => canFallBack
          ? _networkImage(context, thumbnail)
          : _placeholder(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    if (track.isLocal) {
      return UnifiedArtwork(
        key: ValueKey<String>('local-${track.localMediaId}-${track.videoId}'),
        track: track,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        iconSize: widget.iconSize,
      );
    }
    return FutureBuilder<String?>(
      future: _customArtworkFuture,
      builder: (context, customSnapshot) {
        final customPath = customSnapshot.data;
        if (customPath != null && customPath.isNotEmpty) {
          return Image.file(
            File(customPath),
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => _resolvedArtwork(context),
          );
        }
        return _resolvedArtwork(context);
      },
    );
  }

  Widget _resolvedArtwork(BuildContext context) {
    final thumbnail = widget.track.coverUrl;
    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: FutureBuilder<String>(
        key: ValueKey<String>('album-cover-${widget.track.videoId}'),
        future: _coverFuture,
        builder: (context, snapshot) {
          final resolved = snapshot.data;
          final url = (resolved != null && resolved.isNotEmpty) ? resolved : thumbnail;
          if (url.isEmpty) return _placeholder(context);
          return _networkImage(context, url);
        },
      ),
    );
  }
}
