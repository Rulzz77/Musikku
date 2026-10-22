import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/loop_mode.dart';
import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
import 'album_artwork_image.dart';
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
              opacity: 0.48,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: AlbumArtworkImage(track: widget.video, fit: BoxFit.cover, iconSize: 100),
              ),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: scheme.surface.withValues(alpha: 0.44)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.primary.withValues(alpha: 0.10),
                  scheme.secondary.withValues(alpha: 0.035),
                  scheme.surface.withValues(alpha: 0.40),
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
                    const Expanded(
                      child: Column(
                        children: [
                          Text(
                            'SEDANG DIPUTAR',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                          ),
                          SizedBox(height: 3),
                          Text('MusikKu • Pemutar audio', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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
                        final isWideLayout = constraints.maxWidth >= 760;
                        // Near-full-width square artwork on phones, and a larger
                        // immersive cover on tablets/landscape layouts.
                        // Full-bleed cover on phones: sharp art dissolves at both top and bottom
                        // into a soft blurred layer, rather than ending like a card.
                        // Wide layouts keep a framed hero to preserve balanced spacing.
                        final artWidth = isWideLayout
                            ? ((constraints.maxWidth - 68) / 2).clamp(280.0, 560.0).toDouble()
                            : constraints.maxWidth;
                        final artHeight = isWideLayout
                            ? (constraints.maxHeight * 0.72).clamp(300.0, 560.0).toDouble()
                            : (constraints.maxHeight * 0.68).clamp(320.0, 560.0).toDouble();
                        final artworkPanel = SizedBox(
                          width: artWidth,
                          height: artHeight,
                          child: AnimatedSwitcher(
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
                        );
                        final trackInfoPanel = Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.video.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      height: 1.18,
                                      letterSpacing: -0.35,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.video.channelTitle.isEmpty ? 'Artis tidak diketahui' : widget.video.channelTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (busy)
                              Padding(
                                padding: const EdgeInsets.only(left: 10),
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary),
                                ),
                              ),
                          ],
                        );
                        return SingleChildScrollView(
                          padding: EdgeInsets.zero,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight - 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (isWideLayout)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Expanded(child: artworkPanel),
                                        const SizedBox(width: 28),
                                        Expanded(child: trackInfoPanel),
                                      ],
                                    ),
                                  )
                                else
                                  artworkPanel,
                                Padding(
                                  padding: EdgeInsets.fromLTRB(22, isWideLayout ? 14 : 0, 22, 28),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (!isWideLayout) ...[
                                        trackInfoPanel,
                                        const SizedBox(height: 13),
                                      ],
                                    const SizedBox(height: 7),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 10,
                                      runSpacing: 4,
                                      children: [
                                        _actionIcon(
                                          context: context,
                                          icon: Icons.playlist_add_rounded,
                                          tooltip: 'Tambah ke playlist',
                                          onPressed: widget.onAddToPlaylist,
                                        ),
                                        _actionIcon(
                                          context: context,
                                          icon: Icons.lyrics_rounded,
                                          tooltip: 'Buka lirik karaoke',
                                          onPressed: _openLyrics,
                                        ),
                                        _actionIcon(
                                          context: context,
                                          icon: Icons.queue_music_rounded,
                                          tooltip: 'Buka antrean',
                                          onPressed: widget.onOpenQueue,
                                        ),
                                        _actionIcon(
                                          context: context,
                                          icon: Icons.equalizer_rounded,
                                          tooltip: 'Efek audio dan equalizer',
                                          onPressed: widget.onOpenAudioSettings,
                                        ),
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
                                    ),
                                    const SizedBox(height: 5),
                                    SliderTheme(
                                      data: SliderTheme.of(context).copyWith(
                                        // YouTube-style buffer bar:
                                        // red = already played, light gray = buffered ahead,
                                        // dark gray = not buffered yet.
                                        trackHeight: 3,
                                        activeTrackColor: scheme.primary,
                                        secondaryActiveTrackColor: scheme.onSurface.withValues(alpha: 0.46),
                                        inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.18),
                                        thumbColor: scheme.primary,
                                        overlayColor: scheme.primary.withValues(alpha: 0.12),
                                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                      ),
                                      child: Slider(
                                        min: 0,
                                        max: maxMs,
                                        value: sliderValue,
                                        secondaryTrackValue: bufferedTrackValue,
                                        onChanged: duration <= Duration.zero
                                            ? null
                                            : (value) => setState(() {
                                                  _dragPositionMs = value;
                                                }),
                                        onChangeEnd: duration <= Duration.zero
                                            ? null
                                            : (value) async {
                                                setState(() {
                                                  _dragPositionMs = null;
                                                });
                                                await widget.onSeek(Duration(milliseconds: value.round()));
                                              },
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_time(Duration(milliseconds: sliderValue.round())), style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                          Text(_time(duration), style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    ValueListenableBuilder<PlayerUiState>(
                                      valueListenable: widget.playerUiState,
                                      builder: (context, ui, _) {
                                        return Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            IconButton(
                                              tooltip: ui.isSmartShuffle
                                                  ? 'Smart Shuffle aktif • tekan lama untuk mematikan'
                                                  : 'Shuffle • tekan lama untuk Smart Shuffle',
                                              onPressed: widget.onToggleShuffle,
                                              onLongPress: widget.onToggleSmartShuffle,
                                              icon: Icon(
                                                ui.isSmartShuffle
                                                    ? Icons.auto_awesome_rounded
                                                    : Icons.shuffle_rounded,
                                                color: ui.isShuffle
                                                    ? scheme.primary
                                                    : scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Lagu sebelumnya (MusikKu)',
                                              onPressed: widget.onPrevious,
                                              icon: const Icon(Icons.skip_previous_rounded, size: 31),
                                            ),
                                            SizedBox(
                                              width: 64,
                                              height: 64,
                                              child: FilledButton(
                                                style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                                                onPressed: busy ? null : () => widget.onPlayPause(),
                                                child: Icon(
                                                  busy ? Icons.hourglass_top_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                                  size: 36,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Lagu berikutnya (MusikKu)',
                                              onPressed: widget.onNext,
                                              icon: const Icon(Icons.skip_next_rounded, size: 31),
                                            ),
                                            IconButton(
                                              tooltip: switch (ui.loopMode) {
                                                LoopModeCustom.off => 'Aktifkan repeat',
                                                LoopModeCustom.all => 'Repeat semua aktif',
                                                LoopModeCustom.one => 'Repeat satu aktif',
                                              },
                                              onPressed: widget.onCycleLoop,
                                              icon: Icon(
                                                ui.loopMode == LoopModeCustom.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                                                color: ui.loopMode == LoopModeCustom.off ? scheme.onSurfaceVariant : scheme.primary,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    if (stateMatchesTrack && state.playbackState == NativePlaybackState.error)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          'Lagu ini gagal dimuat dari sumber audio. Tekan Putar ulang atau pilih lagu berikutnya.',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                                        ),
                                      ),
                                    ValueListenableBuilder<bool>(
                                      valueListenable: widget.showDataUsageOnPlayer,
                                      builder: (context, visible, _) => visible
                                          ? const Padding(
                                              padding: EdgeInsets.only(top: 12),
                                              child: DataUsageCard(),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  /// Renders a sharp cover over a softly blurred copy of itself. A vertical
  /// alpha mask dissolves the sharp layer at the top and bottom so it feels
  /// continuous with the player background instead of looking like a rounded
  /// card pasted onto the page.
  Widget _buildImmersiveArtwork({
    required Key key,
    required bool isWideLayout,
    required YoutubeSearchResult track,
    required Color surfaceColor,
  }) {
    final artwork = Stack(
      fit: StackFit.expand,
      children: [
        // The same artwork is blurred beneath the hero. It is revealed at the
        // edges by the alpha mask and adds a natural soft halo to the cover.
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Opacity(
            opacity: 0.86,
            child: AlbumArtworkImage(track: track, fit: BoxFit.cover, iconSize: 88),
          ),
        ),
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
            stops: [0.0, 0.19, 0.76, 1.0],
          ).createShader(bounds),
          child: AlbumArtworkImage(track: track, fit: BoxFit.cover, iconSize: 88),
        ),
        // The top and bottom veils blend into the page surface. There are no
        // rounded phone-card corners, so the cover dissolves rather than ends.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                surfaceColor.withValues(alpha: 0.78),
                surfaceColor.withValues(alpha: 0.26),
                Colors.transparent,
                Colors.transparent,
                surfaceColor.withValues(alpha: 0.28),
                surfaceColor.withValues(alpha: 0.96),
              ],
              stops: const [0.0, 0.10, 0.25, 0.62, 0.88, 1.0],
            ),
          ),
        ),
        if (isWideLayout)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
      ],
    );

    // Wide layouts keep a gently framed composition. On phones the artwork is
    // clipped only to its bounds; no border radius makes a visible card shape.
    return isWideLayout
        ? ClipRRect(key: key, borderRadius: BorderRadius.circular(28), child: artwork)
        : ClipRect(key: key, child: artwork);
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
