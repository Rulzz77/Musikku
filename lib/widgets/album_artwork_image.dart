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
    final old = oldWidget.track;
    final current = widget.track;
    if (old.videoId != current.videoId ||
        old.title != current.title ||
        old.channelTitle != current.channelTitle) {
      _prepare();
    }
  }

  void _prepare() {
    _coverFuture = AlbumArtworkService.resolveCoverUrl(widget.track);
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
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
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
        track: track,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        iconSize: widget.iconSize,
      );
    }

    final thumbnail = track.coverUrl;
    return FutureBuilder<String>(
      future: _coverFuture,
      builder: (context, snapshot) {
        // Tampilkan thumbnail YouTube dulu; ganti ke sampul album persegi
        // begitu MusicBrainz/Cover Art Archive selesai, supaya player tidak
        // sempat kosong. Jika future gagal, snapshot.data null dan thumbnail
        // tetap dipakai.
        final resolved = snapshot.data;
        final url = (resolved != null && resolved.isNotEmpty) ? resolved : thumbnail;
        if (url.isEmpty) return _placeholder(context);
        return _networkImage(context, url);
      },
    );
  }
}