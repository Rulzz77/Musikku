import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import 'unified_artwork.dart';

import '../models/loop_mode.dart';
import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
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
          // Full-screen copy of the current artwork, blurred into the player
          // background. This is what the sharp cover fades into at its top and
          // bottom edges, so it never looks like a rounded card pasted on top.
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Transform.scale(
                scale: 1.16,
                child: UnifiedArtwork(
                  track: widget.video,
                  fit: BoxFit.cover,
                  iconSize: 220,
                ),
              ),
            ),
          ),
          // Keep the blurred layer visible under the transparent ends of the
          // full-screen artwork. A heavy opaque veil here would hide the blur.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    scheme.surface.withValues(alpha: 0.24),
                    scheme.surface.withValues(alpha: 0.38),
                    scheme.surface.withValues(alpha: 0.64),
                  ],
                  stops: const [0.0, 0.52, 1.0],
                ),
              ),
            ),
          ),
          // The key difference from a normal album-art card: the sharp cover
          // itself fills the player canvas, underneath every control. Its alpha
          // fades vertically at both ends and reveals the enlarged blurred copy
          // above. No rounded clip, border, or square card is used.
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x99FFFFFF),
                      Colors.white,
                      Colors.white,
                      Color(0x77FFFFFF),
                      Colors.transparent,
                    ],
                    stops: [0.0, 0.10, 0.20, 0.76, 0.90, 1.0],
                  ).createShader(bounds),
                  child: UnifiedArtwork(
                    track: widget.video,
                    fit: BoxFit.cover,
                    iconSize: 240,
                  ),
                ),
                // Slight vignette keeps white controls legible without hiding
                // the image or introducing rounded corners.
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
                          Colors.black.withValues(alpha: 0.26),
                        ],
                        stops: const [0.0, 0.20, 0.68, 1.0],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
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
                        final widthBasedArt = (constraints.maxWidth - 44).clamp(180.0, 330.0).toDouble();
                        final heightRatio = constraints.maxHeight < 480 ? 0.28 : constraints.maxHeight < 600 ? 0.30 : 0.33;
                        final heightBasedArt = (constraints.maxHeight * heightRatio)
                            .clamp(constraints.maxHeight < 480 ? 100.0 : 138.0, constraints.maxHeight < 480 ? 170.0 : 260.0)
                            .toDouble();
                        final artSize = math.min(widthBasedArt, heightBasedArt).toDouble();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(18, 2, 18, 4),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 8),
                                // Preserve the visual breathing room where the
                                // old album-art square sat. The cover is now one
                                // full-screen image behind this layout, not a
                                // separate centered square/card.
                                SizedBox(height: artSize),
                                SizedBox(height: constraints.maxHeight < 600 ? 10 : 18),
                                Row(
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
                                              fontWeight: FontWeight.w500,
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
                                ),
                                SizedBox(height: constraints.maxHeight < 600 ? 6 : 10),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: widget.onAddToPlaylist,
                                      icon: const Icon(Icons.playlist_add_rounded, size: 17),
                                      label: const Text('Tambah ke playlist'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _openLyrics,
                                      icon: const Icon(Icons.lyrics_rounded, size: 17),
                                      label: const Text('Lirik'),
                                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8), visualDensity: VisualDensity.compact),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: widget.onOpenQueue,
                                      icon: const Icon(Icons.queue_music_rounded, size: 17),
                                      label: const Text('Antrean'),
                                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8), visualDensity: VisualDensity.compact),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: widget.onOpenAudioSettings,
                                      icon: const Icon(Icons.equalizer_rounded, size: 17),
                                      label: const Text('Efek audio'),
                                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8), visualDensity: VisualDensity.compact),
                                    ),
                                    ValueListenableBuilder<bool>(
                                      valueListenable: widget.sleepActive,
                                      builder: (context, active, _) => OutlinedButton.icon(
                                        onPressed: widget.onOpenSleepTimer,
                                        icon: Icon(active ? Icons.timer_rounded : Icons.bedtime_outlined, size: 17, color: active ? scheme.primary : null),
                                        label: Text(active ? 'Timer aktif' : 'Timer tidur'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: active ? scheme.primary : null,
                                          side: BorderSide(color: active ? scheme.primary.withValues(alpha: 0.6) : scheme.outlineVariant),
                                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: constraints.maxHeight < 600 ? 4 : 8),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    // YouTube-style buffer bar:
                                    // red = already played, light gray = buffered ahead,
                                    // dark gray = not buffered yet.
                                    trackHeight: 4,
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
                                          icon: const Icon(Icons.skip_previous_rounded, size: 36),
                                        ),
                                        SizedBox(
                                          width: 72,
                                          height: 72,
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                                            onPressed: busy ? null : () => widget.onPlayPause(),
                                            child: Icon(
                                              busy ? Icons.hourglass_top_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                              size: 42,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Lagu berikutnya (MusikKu)',
                                          onPressed: widget.onNext,
                                          icon: const Icon(Icons.skip_next_rounded, size: 36),
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
                                if (constraints.maxHeight >= 760)
                                  ValueListenableBuilder<bool>(
                                    valueListenable: widget.showDataUsageOnPlayer,
                                    builder: (context, visible, _) => visible
                                        ? const Padding(
                                            padding: EdgeInsets.only(top: 4),
                                            child: DataUsageCard(),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                              ],
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
        ],
      ),
    );
  }

  void _openLyrics() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
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
