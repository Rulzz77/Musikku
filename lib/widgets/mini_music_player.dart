import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/native_youtube_state.dart';
import '../models/youtube_search_result.dart';
import 'album_artwork_image.dart';

/// Floating glass mini-player. It stays visually separate from the navigation
/// dock while sharing the app's current theme and playback state.
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
        final artist = video.channelTitle.trim().isEmpty
            ? 'Artis tidak diketahui'
            : video.channelTitle.trim();

        return ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surface.withValues(alpha: 0.90),
                    scheme.surfaceContainerHigh.withValues(alpha: 0.84),
                    scheme.surface.withValues(alpha: 0.94),
                  ],
                ),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: theme.brightness == Brightness.dark ? 0.15 : 0.72,
                  ),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.27 : 0.09,
                    ),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              scheme.primary.withValues(alpha: 0.07),
                              Colors.transparent,
                              scheme.secondary.withValues(alpha: 0.035),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onOpen,
                      child: SizedBox(
                        height: 76,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 280),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) => FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                                child: ClipRRect(
                                  key: ValueKey<String>('mini-cover-${video.videoId}'),
                                  borderRadius: BorderRadius.circular(14),
                                  child: SizedBox(
                                    width: 56,
                                    height: 56,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        AlbumArtworkImage(
                                          track: video,
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          iconSize: 25,
                                        ),
                                        if (isPlaying)
                                          Align(
                                            alignment: Alignment.bottomCenter,
                                            child: Container(
                                              height: 17,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [
                                                    Colors.transparent,
                                                    Colors.black.withValues(alpha: 0.64),
                                                  ],
                                                ),
                                              ),
                                              child: const Center(
                                                child: Icon(
                                                  Icons.graphic_eq_rounded,
                                                  color: Colors.white,
                                                  size: 14,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
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
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.18,
                                        height: 1.15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        if (isBuffering) ...[
                                          SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.6,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                        Expanded(
                                          child: Text(
                                            isBuffering ? 'Menyiapkan audio…' : artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 5),
                              IconButton.filled(
                                tooltip: isPlaying ? 'Jeda' : 'Putar',
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  backgroundColor: scheme.primary,
                                  foregroundColor: scheme.onPrimary,
                                  minimumSize: const Size(42, 42),
                                  maximumSize: const Size(42, 42),
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
                                constraints: const BoxConstraints.tightFor(width: 35, height: 42),
                                padding: EdgeInsets.zero,
                                onPressed: () => unawaited(onNext()),
                                icon: Icon(
                                  Icons.skip_next_rounded,
                                  size: 28,
                                  color: scheme.onSurface,
                                ),
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
                                scheme.onSurface.withValues(alpha: 0.16),
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
          ),
        );
      },
    );
  }
}
