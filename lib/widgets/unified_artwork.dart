import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import '../services/album_artwork_service.dart';
import '../services/local_media_service.dart';
import '../services/track_artwork_service.dart';

class UnifiedArtwork extends StatefulWidget {
  final YoutubeSearchResult track;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double? cacheWidth;
  final double? width;
  final double? height;
  final double iconSize;

  const UnifiedArtwork({
    super.key,
    required this.track,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheWidth,
    this.width,
    this.height,
    this.iconSize = 44,
  });

  @override
  State<UnifiedArtwork> createState() => _UnifiedArtworkState();
}

class _UnifiedArtworkState extends State<UnifiedArtwork> {
  static final LocalMediaService _localMedia = LocalMediaService();
  static final Map<String, Uint8List> _artworkCache = <String, Uint8List>{};
  static final Map<String, Future<Uint8List?>> _pending = <String, Future<Uint8List?>>{};

  Future<Uint8List?>? _future;
  Future<String?>? _customArtworkFuture;
  Future<String>? _albumArtworkFuture;

  @override
  void initState() {
    super.initState();
    TrackArtworkService.revision.addListener(_onCustomArtworkChanged);
    _prepare();
  }

  void _onCustomArtworkChanged() {
    _prepare();
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant UnifiedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.videoId != widget.track.videoId ||
        oldWidget.track.title != widget.track.title ||
        oldWidget.track.channelTitle != widget.track.channelTitle ||
        oldWidget.track.artistName != widget.track.artistName ||
        oldWidget.track.album != widget.track.album ||
        oldWidget.track.thumbnailUrl != widget.track.thumbnailUrl) {
      _prepare();
    }
  }

  void _prepare() {
    _customArtworkFuture = TrackArtworkService.pathFor(widget.track.videoId);
    if (!widget.track.isLocal) {
      _future = null;
      _albumArtworkFuture =
          AlbumArtworkService.resolveCoverUrl(widget.track);
      return;
    }
    _albumArtworkFuture = null;

    final id = widget.track.localMediaId;
    if (id.isEmpty) {
      _future = Future<Uint8List?>.value(null);
      return;
    }

    final cached = _artworkCache[id];
    if (cached != null) {
      _future = Future<Uint8List?>.value(cached);
      return;
    }

    _future = _pending[id] ??= _load(id);
  }

  Future<Uint8List?> _load(String id) async {
    try {
      final bytes = await _localMedia.getArtwork(id);
      if (bytes != null && bytes.isNotEmpty) {
        _artworkCache[id] = bytes;
      }
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _pending.remove(id);
    }
  }

  @override
  void dispose() {
    TrackArtworkService.revision.removeListener(_onCustomArtworkChanged);
    super.dispose();
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded, size: widget.iconSize, color: scheme.primary.withValues(alpha: 0.88)),
      ),
    );
  }

  Widget _originalArtwork(BuildContext context) {
    return widget.track.isLocal
        ? FutureBuilder<Uint8List?>(
            future: _future,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null || bytes.isEmpty) {
                return _fallback(context);
              }
              return Image.memory(
                bytes,
                fit: widget.fit,
                gaplessPlayback: true,
                filterQuality: FilterQuality.low,
              );
            },
          )
        : FutureBuilder<String>(
            future: _albumArtworkFuture,
            builder: (context, snapshot) {
              final verifiedUrl = snapshot.data?.trim() ?? '';
              final url = verifiedUrl.isNotEmpty
                  ? verifiedUrl
                  : widget.track.coverUrl;
              if (url.isEmpty) return _fallback(context);
              return Image.network(
                url,
                fit: widget.fit,
                cacheWidth: widget.cacheWidth?.round(),
                gaplessPlayback: true,
                filterQuality: FilterQuality.high,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _fallback(context);
                },
                errorBuilder: (context, error, stackTrace) {
                  final fallback = widget.track.coverUrl;
                  if (fallback.isNotEmpty && fallback != url) {
                    return Image.network(
                      fallback,
                      fit: widget.fit,
                      cacheWidth: widget.cacheWidth?.round(),
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallback(context),
                    );
                  }
                  return _fallback(context);
                },
              );
            },
          );
  }

  @override
  Widget build(BuildContext context) {
    Widget result = FutureBuilder<String?>(
      future: _customArtworkFuture,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path != null && path.isNotEmpty) {
          return Image.file(
            File(path),
            fit: widget.fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => _originalArtwork(context),
          );
        }
        return _originalArtwork(context);
      },
    );
    if (widget.borderRadius != null) {
      result = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: result,
      );
    }
    if (widget.width != null || widget.height != null) {
      result = SizedBox(
        width: widget.width,
        height: widget.height,
        child: result,
      );
    }
    return AnimatedSwitcher(
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey<String>(
          '${widget.track.videoId}-${widget.track.localMediaId}',
        ),
        child: result,
      ),
    );
  }

}
