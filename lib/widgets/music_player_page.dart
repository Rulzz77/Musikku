import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/loop_mode.dart';
import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';

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
    required this.onCycleLoop,
    required this.onToggleFavorite,
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
  final VoidCallback onCycleLoop;
  final VoidCallback onToggleFavorite;

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
    final artwork = widget.video.coverUrl;

    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surfaceContainerHighest.withValues(alpha: 0.82),
              scheme.surface,
              scheme.surface,
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
                          SizedBox(height: 2),
                          Text('MusikKu', style: TextStyle(fontSize: 12)),
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
                        final heightBasedArt = (constraints.maxHeight * 0.36).clamp(170.0, 280.0).toDouble();
                        final artSize = math.min(widthBasedArt, heightBasedArt).toDouble();
                        return SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight - 28),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 8),
                                Center(
                                  child: Container(
                                    width: artSize,
                                    height: artSize,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      color: scheme.surfaceContainerHighest,
                                      border: Border.all(
                                        color: scheme.outlineVariant.withValues(alpha: 0.42),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.primary.withValues(alpha: 0.08),
                                          blurRadius: 34,
                                          spreadRadius: 1,
                                          offset: const Offset(0, 16),
                                        ),
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.16),
                                          blurRadius: 18,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: artwork.isNotEmpty
                                        ? Image.network(
                                            artwork,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => _artworkFallback(scheme),
                                            loadingBuilder: (context, child, progress) => progress == null
                                                ? child
                                                : _artworkFallback(scheme, loading: true),
                                          )
                                        : _artworkFallback(scheme),
                                  ),
                                ),
                                const SizedBox(height: 28),
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
                                const SizedBox(height: 14),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    // YouTube-style buffer bar:
                                    // red = already played, light gray = buffered ahead,
                                    // dark gray = not buffered yet.
                                    trackHeight: 4,
                                    activeTrackColor: const Color(0xFFFF0033),
                                    secondaryActiveTrackColor: scheme.onSurface.withValues(alpha: 0.46),
                                    inactiveTrackColor: scheme.onSurface.withValues(alpha: 0.18),
                                    thumbColor: const Color(0xFFFF0033),
                                    overlayColor: const Color(0x22FF0033),
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
                                          tooltip: ui.isShuffle ? 'Matikan shuffle' : 'Aktifkan shuffle',
                                          onPressed: widget.onToggleShuffle,
                                          icon: Icon(Icons.shuffle_rounded, color: ui.isShuffle ? scheme.primary : scheme.onSurfaceVariant),
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
    );
  }

  Widget _artworkFallback(ColorScheme scheme, {bool loading = false}) {
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: loading
            ? const CircularProgressIndicator()
            : Icon(Icons.music_note_rounded, size: 84, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
