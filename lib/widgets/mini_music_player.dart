import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/native_youtube_state.dart';
import '../models/youtube_search_result.dart';
import 'album_artwork_image.dart';

/// Compact, tactile mini-player separated from the main navigation dock.
/// It deliberately uses an opaque surface instead of the previous glass stack.
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
        final rawBuffered = matchesTrack
            ? state.safeBufferedFraction.clamp(0.0, 1.0).toDouble()
            : progress;
        final buffered = rawBuffered < progress ? progress : rawBuffered;
        final artist = video.channelTitle.trim().isEmpty
            ? 'Artis tidak diketahui'
            : video.channelTitle.trim();

        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.88)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.34 : 0.10),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onOpen,
                    child: SizedBox(
                      height: 72,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
                        child: Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) => FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                              child: ClipRRect(
                                key: ValueKey<String>('mini-cover-${video.videoId}'),
                                borderRadius: BorderRadius.circular(11),
                                child: SizedBox(
                                  width: 54,
                                  height: 54,
                                  child: AlbumArtworkImage(
                                    track: video,
                                    width: 54,
                                    height: 54,
                                    fit: BoxFit.cover,
                                    iconSize: 24,
                                  ),
                                ),
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
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      if (isBuffering)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 5),
                                          child: SizedBox(
                                            width: 9,
                                            height: 9,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.6,
                                              color: scheme.primary,
                                            ),
                                          ),
                                        )
                                      else if (isPlaying)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 5),
                                          child: Icon(Icons.volume_up_rounded, size: 12, color: scheme.primary),
                                        ),
                                      Expanded(
                                        child: Text(
                                          isBuffering ? 'Menyiapkan audio…' : artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: scheme.onSurfaceVariant,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 7),
                            IconButton(
                              tooltip: isPlaying ? 'Jeda' : 'Putar',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 40, height: 42),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                backgroundColor: scheme.primary,
                                foregroundColor: scheme.onPrimary,
                              ),
                              onPressed: () => unawaited(onPlayPause()),
                              icon: Icon(
                                isBuffering
                                    ? Icons.more_horiz_rounded
                                    : isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                size: 25,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Lagu berikutnya',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 34, height: 42),
                              padding: EdgeInsets.zero,
                              onPressed: () => unawaited(onNext()),
                              icon: Icon(Icons.skip_next_rounded, size: 25, color: scheme.onSurface),
                            ),
                          ],
                        ),
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
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scheme.onSurface.withValues(alpha: 0.12),
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
          ),
        );
      },
    );
  }
}
