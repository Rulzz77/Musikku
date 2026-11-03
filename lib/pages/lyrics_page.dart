
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/lyric.dart';
import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
import '../widgets/album_artwork_image.dart';

/// Dedicated full-screen lyrics page. Playback remains owned by HomePage.
class LyricsPage extends StatefulWidget {
  const LyricsPage({
    super.key,
    required this.video,
    required this.playerUiState,
    required this.nativeState,
    required this.onSeek,
  });

  final YoutubeSearchResult video;
  final ValueListenable<PlayerUiState> playerUiState;
  final ValueListenable<NativeYoutubeState> nativeState;
  final Future<void> Function(Duration position) onSeek;

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};
  int _lastCenteredIndex = -1;
  String _trackedVideoId = '';

  int _currentLine(List<LyricLine> lyrics, Duration position) {
    if (lyrics.isEmpty) return -1;
    var low = 0;
    var high = lyrics.length - 1;
    var result = -1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      if (lyrics[middle].time <= position) {
        result = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return result;
  }

  void _centerLine(int index) {
    if (index < 0 || index == _lastCenteredIndex) return;
    _lastCenteredIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lineContext = _lineKeys[index]?.currentContext;
      if (lineContext == null) return;
      Scrollable.ensureVisible(
        lineContext,
        alignment: 0.48,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _formatTime(Duration value) {
    final seconds = value.inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: widget.playerUiState,
      builder: (context, player, _) {
        final activeVideo = player.video ?? widget.video;
        final lyrics = player.lyrics;
        if (_trackedVideoId != activeVideo.videoId || _lineKeys.length != lyrics.length) {
          final changedTrack = _trackedVideoId != activeVideo.videoId;
          _trackedVideoId = activeVideo.videoId;
          _lineKeys
            ..clear()
            ..addEntries(List.generate(lyrics.length, (index) => MapEntry(index, GlobalKey())));
          _lastCenteredIndex = -1;
          if (changedTrack) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scrollController.hasClients) {
                _scrollController.jumpTo(0);
              }
            });
          }
        }

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: ColoredBox(color: theme.scaffoldBackgroundColor)),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 16, 10),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Kembali ke pemutar',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: scheme.onSurface,
                              size: 30,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'KATA & NADA',
                              style: TextStyle(
                                color: scheme.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.1,
                              ),
                            ),
                          ),
                          ValueListenableBuilder<NativeYoutubeState>(
                            valueListenable: widget.nativeState,
                            builder: (context, state, _) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    state.isEffectivelyPlaying
                                        ? Icons.graphic_eq_rounded
                                        : Icons.pause_rounded,
                                    color: scheme.onSurfaceVariant,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    state.isEffectivelyPlaying ? 'SEDANG DIPUTAR' : 'JEDA',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 3, 22, 18),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AlbumArtworkImage(
                              track: activeVideo,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activeVideo.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  activeVideo.channelTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.7)),
                    Expanded(
                      child: ValueListenableBuilder<NativeYoutubeState>(
                        valueListenable: widget.nativeState,
                        builder: (context, native, _) {
                          final currentIndex = player.lyricsSynced
                              ? _currentLine(lyrics, native.position)
                              : -1;
                          if (currentIndex >= 0) _centerLine(currentIndex);

                          if (player.lyricsLoading && lyrics.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 25,
                                    height: 25,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: scheme.primary,
                                    ),
                                  ),
                                  SizedBox(height: 14),
                                  Text(
                                    'Mencari lirik…',
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (lyrics.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(28),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lyrics_outlined,
                                      color: scheme.onSurfaceVariant.withValues(alpha: 0.58),
                                      size: 42,
                                    ),
                                    const SizedBox(height: 13),
                                    Text(
                                      'Lirik belum tersedia',
                                      style: TextStyle(
                                        color: scheme.onSurface,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Lirik akan muncul di sini saat tersedia untuk lagu ini.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                        height: 1.45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(26, 30, 26, 104),
                            itemCount: lyrics.length,
                            itemBuilder: (context, index) {
                              final line = lyrics[index];
                              final isActive = index == currentIndex;
                              final hasCurrentLine = currentIndex >= 0;
                              final isPast = hasCurrentLine && index < currentIndex;
                              final color = isActive
                                  ? scheme.primary
                                  : isPast
                                      ? scheme.onSurface.withValues(alpha: 0.28)
                                      : scheme.onSurfaceVariant.withValues(alpha: 0.78);
                              return Padding(
                                key: _lineKeys[index],
                                padding: const EdgeInsets.symmetric(vertical: 11),
                                child: InkWell(
                                  onTap: player.lyricsSynced
                                      ? () => widget.onSeek(line.time)
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 230),
                                    curve: Curves.easeOutCubic,
                                    style: TextStyle(
                                      color: color,
                                      fontSize: isActive ? 25 : 17,
                                      height: 1.34,
                                      fontWeight: isActive
                                          ? FontWeight.w900
                                          : FontWeight.w600,
                                      letterSpacing: isActive ? -0.4 : -0.12,
                                    ),
                                    child: Text(
                                      line.text,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    ValueListenableBuilder<NativeYoutubeState>(
                      valueListenable: widget.nativeState,
                      builder: (context, state, _) {
                        final duration = state.duration.inMilliseconds;
                        final progress = duration > 0
                            ? (state.position.inMilliseconds / duration)
                                .clamp(0.0, 1.0)
                                .toDouble()
                            : 0.0;
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  minHeight: 3,
                                  value: progress,
                                  backgroundColor: scheme.outlineVariant.withValues(alpha: 0.50),
                                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                                ),
                              ),
                              const SizedBox(height: 7),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatTime(state.position),
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
                                  ),
                                  Text(
                                    _formatTime(state.duration),
                                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
