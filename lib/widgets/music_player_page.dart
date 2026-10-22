import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/loop_mode.dart';
import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
import 'unified_artwork.dart';
import 'data_usage_card.dart';
import 'lyrics_panel.dart';

/// Audio-only full player. No YouTube video surface is mounted here; Media3
/// owns the stream so artwork, seek, next/previous, and background state all
/// refer to the same audio source.
class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({
    super.key,
    required this.video,
    required this.nativeState,
    required this.playerUiState,
    required this.onBack,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    required this.onToggleShuffle,
    required this.onToggleSmartShuffle,
    required this.onCycleLoop,
    required this.onToggleFavorite,
    required this.onAddToPlaylist,
    required this.onOpenQueue,
    required this.onOpenAudioSettings,
    required this.onOpenSleepTimer,
    required this.sleepActive,
    required this.showDataUsageOnPlayer,
  });

  final YoutubeSearchResult video;
  final ValueListenable<NativeYoutubeState> nativeState;
  final ValueListenable<PlayerUiState> playerUiState;
  final VoidCallback onBack;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onNext;
  final Future<void> Function() onPrevious;
  final Future<void> Function(Duration position) onSeek;
  final VoidCallback onToggleShuffle;
  final VoidCallback onToggleSmartShuffle;
  final VoidCallback onCycleLoop;
  final VoidCallback onToggleFavorite;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenAudioSettings;
  final VoidCallback onOpenSleepTimer;
  final ValueListenable<bool> sleepActive;
  final ValueListenable<bool> showDataUsageOnPlayer;

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  double? _dragPositionMs;

  @override
  void didUpdateWidget(covariant MusicPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.videoId != widget.video.videoId) {
      _dragPositionMs = null;
    }
  }

  String _time(Duration value) {
    final seconds = value.inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    if (minutes >= 60) {
      return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
    }
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Album art fills the page behind the controls, softly blurred so the
          // cover feels immersive without reducing text/control contrast.
          Positioned.fill(
            child: Opacity(
              opacity: 0.64,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: UnifiedArtwork(track: widget.video, fit: BoxFit.cover, iconSize: 100),
              ),
            ),
          ),
          // Darken the artwork just enough for legible controls while keeping
          // its colours visibly present behind the entire player page.
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                    scheme.surface.withValues(alpha: 0.48),
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primary.withValues(alpha: 0.08),
                  scheme.secondary.withValues(alpha: 0.02),
                  scheme.surface.withValues(alpha: 0.18),
                ],
              ),
            ),
            child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Kembali ke beranda',
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'SEDANG DIPUTAR',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.7,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.video.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<PlayerUiState>(
                      valueListenable: widget.playerUiState,
                      builder: (context, ui, _) => IconButton(
                        tooltip: ui.isFavorite ? 'Hapus dari favorit' : 'Tambah ke favorit',
                        onPressed: widget.onToggleFavorite,
                        icon: Icon(
                          ui.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: ui.isFavorite ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<NativeYoutubeState>(
                  valueListenable: widget.nativeState,
                  builder: (context, state, _) {
                    final stateMatchesTrack = state.videoId.isEmpty || state.videoId == widget.video.videoId;
                    final position = stateMatchesTrack ? state.position : Duration.zero;
                    final duration = stateMatchesTrack && state.duration > Duration.zero
                        ? state.duration
                        : Duration(milliseconds: ((widget.video.durationSeconds ?? 0) * 1000).round());
                    final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
                    final sliderValue = (_dragPositionMs ?? position.inMilliseconds.toDouble()).clamp(0.0, maxMs).toDouble();
                    // Buffer position is reported as a fraction of the whole track.
                    // Keep the buffered endpoint at/after the playhead so the
                    // light-gray secondary track is the audio already downloaded ahead.
                    final rawBufferedMs = stateMatchesTrack
                        ? (state.safeBufferedFraction * maxMs).clamp(0.0, maxMs).toDouble()
                        : sliderValue;
                    final bufferedTrackValue = math.max(sliderValue, rawBufferedMs).clamp(0.0, maxMs).toDouble();
                    final busy = stateMatchesTrack && state.isBuffering;
                    final playing = stateMatchesTrack && state.isEffectivelyPlaying;

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isWideLayout = constraints.maxWidth >= 760 && constraints.maxHeight >= 520;
                        // Near-full-width square artwork on phones, and a larger
                        // immersive cover on tablets/landscape layouts.
                        // Full-bleed cover on phones: sharp art dissolves at both top and bottom
                        // into a soft blurred layer, rather than ending like a card.
                        // Wide layouts keep a framed hero to preserve balanced spacing.
                        // Restore the large, immersive cover from the reference
                        // layout. The previous 0.42 ratio left too much empty space
                        // around a small-looking square. Controls remain in the
                        // fixed lower viewport; no page-level vertical scroll is added.
                        final maxArtHeight = (constraints.maxHeight * (isWideLayout ? 0.56 : 0.66))
                            .clamp(1.0, 720.0)
                            .toDouble();
                        final minArtHeight = math.min(constraints.maxHeight * (constraints.maxHeight < 560 ? 0.36 : 0.50), maxArtHeight);
                        final artRatio = isWideLayout
                            ? 0.48
                            : constraints.maxHeight < 460
                                ? 0.42
                                : constraints.maxHeight < 620
                                    ? 0.53
                                    : 0.60;
                        final artHeight = (constraints.maxHeight * artRatio)
                            .clamp(minArtHeight, maxArtHeight)
                            .toDouble();
                        final artWidth = isWideLayout
                            ? ((constraints.maxWidth - 68) / 2).clamp(280.0, 560.0).toDouble()
                            : constraints.maxWidth;
                        final artworkPanel = SizedBox(
                          width: artWidth,
                          height: artHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 520),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) => FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(begin: 1.025, end: 1).animate(
                                      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                                    ),
                                    child: child,
                                  ),
                                ),
                                child: _buildImmersiveArtwork(
                                  key: ValueKey<String>('art-${widget.video.videoId}'),
                                  isWideLayout: isWideLayout,
                                  track: widget.video,
                                  surfaceColor: scheme.surface,
                                ),
                              ),
                              if (!isWideLayout)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 2,
                                  child: _buildCurrentLyricGlass(textTheme: theme.textTheme),
                                ),
                            ],
                          ),
                        );
                        final trackInfoPanel = Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.video.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      height: 1.12,
                                      letterSpacing: -0.35,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.video.channelTitle.isEmpty ? 'Artis tidak diketahui' : widget.video.channelTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.only(left: 10),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.2),
                                ),
                              ),
                          ],
                        );
                        final actionButtons = Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 9,
                          runSpacing: 0,
                          children: [
                            _actionIcon(context: context, icon: Icons.playlist_add_rounded, tooltip: 'Tambah ke playlist', onPressed: widget.onAddToPlaylist),
                            _actionIcon(context: context, icon: Icons.lyrics_rounded, tooltip: 'Buka lirik karaoke', onPressed: _openLyrics),
                            _actionIcon(context: context, icon: Icons.queue_music_rounded, tooltip: 'Buka antrean', onPressed: widget.onOpenQueue),
                            _actionIcon(context: context, icon: Icons.equalizer_rounded, tooltip: 'Efek audio dan equalizer', onPressed: widget.onOpenAudioSettings),
                            ValueListenableBuilder<bool>(
                              valueListenable: widget.sleepActive,
                              builder: (context, active, _) => _actionIcon(
                                context: context,
                                icon: active ? Icons.timer_rounded : Icons.bedtime_outlined,
                                tooltip: active ? 'Timer tidur aktif' : 'Timer tidur',
                                onPressed: widget.onOpenSleepTimer,
                                selected: active,
                              ),
                            ),
                          ],
                        );
                        final seekControls = Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                activeTrackColor: scheme.primary,
                                secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.45),
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.20),
                                thumbColor: Colors.white,
                                overlayColor: scheme.primary.withValues(alpha: 0.12),
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
                              ),
                              child: Slider(
                                min: 0,
                                max: maxMs,
                                value: sliderValue,
                                secondaryTrackValue: bufferedTrackValue,
                                onChanged: duration <= Duration.zero ? null : (value) => setState(() => _dragPositionMs = value),
                                onChangeEnd: duration <= Duration.zero
                                    ? null
                                    : (value) async {
                                        setState(() => _dragPositionMs = null);
                                        await widget.onSeek(Duration(milliseconds: value.round()));
                                      },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 5),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_time(Duration(milliseconds: sliderValue.round())), style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
                                  Text(_time(duration), style: theme.textTheme.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
                                ],
                              ),
                            ),
                          ],
                        );
                        final playbackControls = ValueListenableBuilder<PlayerUiState>(
                          valueListenable: widget.playerUiState,
                          builder: (context, ui, _) => Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                tooltip: ui.isSmartShuffle ? 'Smart Shuffle aktif • tekan lama untuk mematikan' : 'Shuffle • tekan lama untuk Smart Shuffle',
                                visualDensity: VisualDensity.compact,
                                onPressed: widget.onToggleShuffle,
                                onLongPress: widget.onToggleSmartShuffle,
                                icon: Icon(ui.isSmartShuffle ? Icons.auto_awesome_rounded : Icons.shuffle_rounded, color: ui.isShuffle ? Colors.white : Colors.white70),
                              ),
                              IconButton(
                                tooltip: 'Lagu sebelumnya (MusikKu)',
                                visualDensity: VisualDensity.compact,
                                onPressed: widget.onPrevious,
                                icon: const Icon(Icons.skip_previous_rounded, size: 30, color: Colors.white),
                              ),
                              SizedBox(
                                width: 60,
                                height: 60,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    shape: const CircleBorder(),
                                    padding: EdgeInsets.zero,
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black87,
                                  ),
                                  onPressed: busy ? null : () => widget.onPlayPause(),
                                  child: Icon(busy ? Icons.hourglass_top_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded), size: 32),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Lagu berikutnya (MusikKu)',
                                visualDensity: VisualDensity.compact,
                                onPressed: widget.onNext,
                                icon: const Icon(Icons.skip_next_rounded, size: 30, color: Colors.white),
                              ),
                              IconButton(
                                tooltip: switch (widget.playerUiState.value.loopMode) {
                                  LoopModeCustom.off => 'Aktifkan repeat',
                                  LoopModeCustom.all => 'Repeat semua aktif',
                                  LoopModeCustom.one => 'Repeat satu aktif',
                                },
                                visualDensity: VisualDensity.compact,
                                onPressed: widget.onCycleLoop,
                                icon: Icon(
                                  widget.playerUiState.value.loopMode == LoopModeCustom.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                  color: widget.playerUiState.value.loopMode == LoopModeCustom.off ? Colors.white70 : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        );

                        // Fixed viewport: this player intentionally has no vertical scroll.
                        // Art and controls resize to available height on compact phones/landscape.
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isWideLayout)
                              Expanded(
                                flex: 5,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(22, 5, 22, 0),
                                  child: Row(
                                    children: [
                                      Expanded(child: artworkPanel),
                                      const SizedBox(width: 22),
                                      Expanded(child: Align(alignment: Alignment.centerLeft, child: trackInfoPanel)),
                                    ],
                                  ),
                                ),
                              )
                            else
                              SizedBox(width: double.infinity, height: artHeight, child: artworkPanel),
                            Expanded(
                              flex: isWideLayout ? 5 : 6,
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(isWideLayout ? 24 : 18, isWideLayout ? 7 : 3, isWideLayout ? 24 : 18, 5),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (!isWideLayout) trackInfoPanel,
                                    actionButtons,
                                    seekControls,
                                    playbackControls,
                                    if (stateMatchesTrack && state.playbackState == NativePlaybackState.error)
                                      Text(
                                        'Lagu gagal dimuat. Coba putar ulang atau pilih lagu berikutnya.',
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.88)),
                                      ),
                                    // Keep the optional usage card off very short screens so controls never scroll/overflow.
                                    if (constraints.maxHeight >= 760)
                                      ValueListenableBuilder<bool>(
                                        valueListenable: widget.showDataUsageOnPlayer,
                                        builder: (context, visible, _) => visible
                                            ? const Padding(padding: EdgeInsets.only(top: 3), child: DataUsageCard())
                                            : const SizedBox.shrink(),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      ],
      ),
    );
  }

  /// Places sharp album art over the blurred full-page artwork in the root
  /// Stack. The alpha mask dissolves the top and bottom edges into that shared
  /// background, so the image never reads as a rectangular card.
  Widget _buildImmersiveArtwork({
    required Key key,
    required bool isWideLayout,
    required YoutubeSearchResult track,
    required Color surfaceColor,
  }) {
    final art = Stack(
      fit: StackFit.expand,
      children: [
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.15, 0.79, 1.0],
          ).createShader(bounds),
          child: UnifiedArtwork(track: track, fit: BoxFit.cover, iconSize: 88),
        ),
        // A very light vignette gently hides the fade boundary without putting
        // an opaque surface-colour band over the cover.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.12),
                  Colors.transparent,
                  Colors.transparent,
                  surfaceColor.withValues(alpha: 0.07),
                ],
                stops: const [0.0, 0.20, 0.76, 1.0],
              ),
            ),
          ),
        ),
      ],
    );

    // On phones the art touches the screen edges and fades vertically into the
    // full-page blurred art. Wide layouts retain a restrained rounded frame.
    return isWideLayout
        ? ClipRRect(key: key, borderRadius: BorderRadius.circular(28), child: art)
        : ClipRect(key: key, child: art);
  }

  /// Small glass lyric pill floating over the soft edge of the full-bleed art.
  /// It is displayed only for real timestamped lyrics; unsynced text must not
  /// pretend to follow playback position.
  Widget _buildCurrentLyricGlass({
    required TextTheme textTheme,
  }) {
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: widget.playerUiState,
      builder: (context, playerState, _) {
        if (playerState.video?.videoId != widget.video.videoId ||
            !playerState.lyricsSynced ||
            playerState.lyrics.isEmpty) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<NativeYoutubeState>(
          valueListenable: widget.nativeState,
          builder: (context, state, _) {
            final matchesTrack = state.videoId.isEmpty || state.videoId == widget.video.videoId;
            final position = matchesTrack ? state.position : Duration.zero;
            var lineIndex = 0;
            for (var i = 0; i < playerState.lyrics.length; i++) {
              if (playerState.lyrics[i].time <= position) {
                lineIndex = i;
              } else {
                break;
              }
            }
            final lyric = playerState.lyrics[lineIndex].text.trim();
            if (lyric.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.105),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.10),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        lyric,
                        key: ValueKey<String>('lyric-$lineIndex-$lyric'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                          shadows: [
                            Shadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _actionIcon({
    required BuildContext context,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton.filledTonal(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        maximumSize: const Size(44, 44),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
        backgroundColor: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        foregroundColor: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
    );
  }

  void _openLyrics() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          // Keep the lyrics card inside the sheet and let it fill the available
          // height; a shrink-wrapped SingleChildScrollView left a dark empty
          // block below the lyrics on tall screens.
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: ValueListenableBuilder<PlayerUiState>(
            valueListenable: widget.playerUiState,
            builder: (context, ui, _) => LyricsPanel(
              lyrics: ui.video?.videoId == widget.video.videoId ? ui.lyrics : const [],
              loading: ui.video?.videoId == widget.video.videoId && ui.lyricsLoading,
              synced: ui.video?.videoId == widget.video.videoId && ui.lyricsSynced,
              nativeState: widget.nativeState,
              onSeek: widget.onSeek,
              expandToAvailableHeight: true,
            ),
          ),
        ),
      ),
    );
  }

}
