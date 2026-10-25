import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/native_youtube_state.dart';
import 'album_artwork_image.dart';
import '../models/youtube_search_result.dart';

/// Compact audio-only player shown above the app navigation while a track is
/// active. Tapping the surface returns to the full Now Playing page.
class MiniMusicPlayer extends StatelessWidget {
  const MiniMusicPlayer({
    super.key,
    required this.video,
    required this.nativeState,
    required this.onOpen,
    required this.onPlayPause,
    required this.onNext,
  });

  final YoutubeSearchResult video;
  final ValueListenable<NativeYoutubeState> nativeState;
  final VoidCallback onOpen;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ValueListenableBuilder<NativeYoutubeState>(
      valueListenable: nativeState,
      builder: (context, state, _) {
        final matchesTrack = state.videoId.isEmpty || state.videoId == video.videoId;
        final isPlaying = matchesTrack && state.isEffectivelyPlaying;
        final isBuffering = matchesTrack && state.isBuffering;
        final durationMs = matchesTrack ? state.duration.inMilliseconds : 0;
        final positionMs = matchesTrack ? state.position.inMilliseconds : 0;
        final progress = durationMs > 0
            ? (positionMs / durationMs).clamp(0.0, 1.0).toDouble()
            : 0.0;
        final bufferedRaw = matchesTrack
            ? state.safeBufferedFraction.clamp(0.0, 1.0).toDouble()
            : progress;
        final buffered = bufferedRaw < progress ? progress : bufferedRaw;

        return Material(
          // Permukaan lembut tanpa garis tepi; bayangan tipis saja agar tetap
          // terpisah dari konten di belakangnya.
          color: scheme.surfaceContainerHigh,
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              InkWell(
                onTap: onOpen,
                child: SizedBox(
                  height: 72,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AlbumArtworkImage(
                            track: video,
                            width: 54,
                            height: 54,
                            fit: BoxFit.cover,
                            iconSize: 28,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                video.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.1,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isBuffering
                                    ? 'Memuat audio…'
                                    : (video.channelTitle.isEmpty ? 'Artis tidak diketahui' : video.channelTitle),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          tooltip: isPlaying ? 'Jeda' : 'Putar',
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            backgroundColor: scheme.onSurface,
                            foregroundColor: scheme.surface,
                            minimumSize: const Size(40, 40),
                            maximumSize: const Size(40, 40),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: () => unawaited(onPlayPause()),
                          icon: Icon(
                            isBuffering
                                ? Icons.more_horiz_rounded
                                : isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                            size: 26,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Lagu berikutnya',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => unawaited(onNext()),
                          icon: Icon(Icons.skip_next_rounded, size: 28, color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: SizedBox(
                    height: 2.5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LinearProgressIndicator(
                          value: buffered,
                          minHeight: 2.5,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            scheme.onSurface.withValues(alpha: 0.20),
                          ),
                        ),
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 2.5,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}