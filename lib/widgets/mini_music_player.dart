import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/native_youtube_state.dart';
import '../models/youtube_search_result.dart';
import 'album_artwork_image.dart';

/// Persistent compact player above MusikKu's navigation dock.
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
        final progress = durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0).toDouble() : 0.0;
        final buffered = math.max(progress, matchesTrack ? state.safeBufferedFraction : progress).clamp(0.0, 1.0).toDouble();
        final artist = video.channelTitle.trim().isEmpty ? 'Artis tidak diketahui' : video.channelTitle.trim();

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: theme.brightness == Brightness.dark
                  ? const [Color(0xFF1B3046), Color(0xFF101D2D)]
                  : [scheme.surface, scheme.surfaceContainerLow],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: scheme.primary.withValues(alpha: 0.25), width: 1),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.28 : 0.09), blurRadius: 25, offset: const Offset(0, 9)),
              BoxShadow(color: scheme.primary.withValues(alpha: 0.06), blurRadius: 20, spreadRadius: -6),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Stack(
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onOpen,
                    child: SizedBox(
                      height: 76,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(9, 9, 7, 9),
                        child: Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 360),
                              switchInCurve: Curves.easeOutBack,
                              transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child)),
                              child: ClipRRect(
                                key: ValueKey<String>('mini-cover-${video.videoId}'),
                                borderRadius: BorderRadius.circular(13),
                                child: SizedBox(
                                  width: 57,
                                  height: 57,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      AlbumArtworkImage(track: video, width: 57, height: 57, fit: BoxFit.cover, iconSize: 24),
                                      if (isPlaying)
                                        DecoratedBox(
                                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.17)),
                                          child: const Center(child: _MiniEqualizer()),
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
                                  Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.25, height: 1.1)),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: [
                                      if (isBuffering)
                                        const Padding(padding: EdgeInsets.only(right: 5), child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.6, color: Color(0xFF67E5F2))))
                                      else if (isPlaying)
                                        const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.volume_up_rounded, size: 12, color: Color(0xFF67E5F2))),
                                      Expanded(child: Text(isBuffering ? 'Menyiapkan audio…' : artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w600))),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 5),
                            IconButton(
                              tooltip: 'Lagu berikutnya',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(width: 36, height: 44),
                              padding: EdgeInsets.zero,
                              onPressed: () => unawaited(onNext()),
                              icon: Icon(Icons.skip_next_rounded, size: 25, color: scheme.onSurface),
                            ),
                            const SizedBox(width: 2),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: 43,
                              height: 43,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.24), blurRadius: 13, offset: const Offset(0, 4))],
                              ),
                              child: IconButton(
                                tooltip: isPlaying ? 'Jeda' : 'Putar',
                                padding: EdgeInsets.zero,
                                onPressed: () => unawaited(onPlayPause()),
                                icon: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 170),
                                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                                  child: Icon(
                                    isBuffering ? Icons.more_horiz_rounded : (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                    key: ValueKey<String>(isBuffering ? 'loading' : isPlaying ? 'pause' : 'play'),
                                    size: 25,
                                    color: scheme.onPrimary,
                                  ),
                                ),
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
                      height: 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          LinearProgressIndicator(value: buffered, minHeight: 3, backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation<Color>(scheme.onSurface.withValues(alpha: 0.12))),
                          LinearProgressIndicator(value: progress, minHeight: 3, backgroundColor: Colors.transparent, valueColor: AlwaysStoppedAnimation<Color>(scheme.primary)),
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

class _MiniEqualizer extends StatefulWidget {
  const _MiniEqualizer();

  @override
  State<_MiniEqualizer> createState() => _MiniEqualizerState();
}

class _MiniEqualizerState extends State<_MiniEqualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 780))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(4, (index) {
            final wave = (math.sin((_controller.value * math.pi * 2) + (index * 0.9)) + 1) / 2;
            return Container(
              width: 3,
              height: 7 + (wave * 13),
              margin: const EdgeInsets.symmetric(horizontal: 1.4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3)),
            );
          }),
        ),
      );
}
