import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import '../services/local_media_service.dart';

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

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant UnifiedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.videoId != widget.track.videoId) {
      _prepare();
    }
  }

  void _prepare() {
    if (!widget.track.isLocal) {
      _future = null;
      return;
    }

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

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary.withValues(alpha: 0.22), scheme.surfaceContainerHighest, scheme.secondary.withValues(alpha: 0.14)],
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note_rounded, size: widget.iconSize, color: scheme.primary.withValues(alpha: 0.88)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.track.isLocal
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
        : (widget.track.coverUrl.isEmpty
            ? _fallback(context)
            : Image.network(
                widget.track.coverUrl,
                fit: widget.fit,
                cacheWidth: widget.cacheWidth?.round(),
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _fallback(context);
                },
                errorBuilder: (context, error, stackTrace) => _fallback(context),
              ));

    Widget result = child;
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
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: KeyedSubtree(
        key: ValueKey<String>(
          widget.track.isLocal
              ? 'local-${widget.track.localMediaId}'
              : 'online-${widget.track.videoId}',
        ),
        child: result,
      ),
    );
  }
}
