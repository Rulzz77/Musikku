import 'dart:math' as math;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/loop_mode.dart';
import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
import '../services/music_title_formatter.dart';
import 'album_artwork_image.dart';
import 'lyrics_panel.dart';

/// Audio-only full player. No YouTube video surface is mounted here; Media3
/// owns the stream so artwork, seek, next/previous, and background state all
/// refer to the same audio source.
///
/// Layout (Spotify-style, top to bottom):
///   header  -> artwork -> title/artist + favorite -> seek bar -> transport
///   controls -> secondary actions (playlist, lyrics, queue, sleep timer).
class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({
    super.key,
    required this.video,
    this.nextVideo,
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
    required this.onOpenSleepTimer,
    required this.onOpenListeningRoom,
    required this.followingRoom,
    required this.sleepActive,
  });

  final YoutubeSearchResult video;

  /// No longer rendered (the "next up" card was removed). Kept so existing
  /// callers keep compiling; you can delete it together with the call sites.
  final YoutubeSearchResult? nextVideo;
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
  final VoidCallback onOpenSleepTimer;
  final VoidCallback onOpenListeningRoom;
  final bool followingRoom;
  final ValueListenable<bool> sleepActive;

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
          // Keep the backdrop stable when the queue changes. The album cover
          // is rendered only in its fixed square slot below, never blown up
          // as a full-screen image that changes crop between songs.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF101718),
                    Color.lerp(const Color(0xFF101718), scheme.surface, 0.10)!,
                    scheme.surface,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -90,
            child: IgnorePointer(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [scheme.primary.withValues(alpha: 0.15), scheme.primary.withValues(alpha: 0.0)],
                  ),
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
                  Colors.black.withValues(alpha: 0.12),
                  Colors.transparent,
                  scheme.surface.withValues(alpha: 0.06),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(theme),
                  Expanded(
                    child: ValueListenableBuilder<NativeYoutubeState>(
                      valueListenable: widget.nativeState,
                      builder: (context, state, _) => _buildBody(context, state),
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

  /// Header: back (left), title (centered on the whole screen), listening
  /// room (right). Favorite moved next to the song title, like Spotify.
  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 82),
                    child: Text(
                      widget.followingRoom ? 'DENGERIN BARENG' : 'SEDANG DIPUTAR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.55,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Kembali ke beranda',
                  constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                  onPressed: widget.onBack,
                  color: Colors.white,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                ),
                const Spacer(),
                IconButton(
                  tooltip: widget.followingRoom ? 'Mengikuti sesi host' : 'Dengerin bareng tanpa login',
                  constraints: const BoxConstraints.tightFor(width: 44, height: 44),
                  onPressed: widget.onOpenListeningRoom,
                  icon: Icon(
                    widget.followingRoom ? Icons.headphones_rounded : Icons.groups_2_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, NativeYoutubeState state) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

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
        // Header is 8dp shorter. Subtract that gain from the artwork
        // sizing budget so the cover remains exactly the same size.
        final artworkLayoutHeight = math.max(0.0, constraints.maxHeight - 8.0);
        final phoneArtWidth = math.min(
          300.0,
          math.max(160.0, constraints.maxWidth * 0.80),
        ).toDouble();
        // Reserved space is independent of lyrics, buffering, and optional
        // data cards so the cover never resizes mid-song.
        final reservedLowerHeight = isWideLayout ? 300.0 : 400.0;
        final heightLimitedArt = (artworkLayoutHeight - reservedLowerHeight)
            .clamp(145.0, 300.0)
            .toDouble();
        final artWidth = isWideLayout
            ? math.min(
                300.0,
                math.min(
                  ((constraints.maxWidth - 68) / 2).clamp(180.0, 300.0).toDouble(),
                  (artworkLayoutHeight * 0.54).clamp(145.0, 300.0).toDouble(),
                ),
              ).toDouble()
            : math.min(phoneArtWidth, heightLimitedArt).toDouble();
        final artHeight = artWidth;

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
                // Fade the pixels only. Scale animation made the
                // cover appear to jump/zoom whenever the song changed.
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: _buildImmersiveArtwork(
                  key: ValueKey<String>('art-${widget.video.videoId}'),
                  track: widget.video,
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: _buildCurrentLyricText(textTheme: theme.textTheme),
              ),
            ],
          ),
        );

        final trackInfoPanel = _buildTrackInfo(theme, scheme, busy);

        final controlsPanel = Padding(
          padding: EdgeInsets.fromLTRB(22, isWideLayout ? 6 : 0, 22, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isWideLayout) trackInfoPanel,
              const Spacer(flex: 2),
              _buildSeekBar(
                context: context,
                theme: theme,
                scheme: scheme,
                duration: duration,
                maxMs: maxMs,
                sliderValue: sliderValue,
                bufferedTrackValue: bufferedTrackValue,
              ),
              const Spacer(flex: 2),
              _buildTransportRow(
                scheme: scheme,
                busy: busy,
                playing: playing,
              ),
              const Spacer(flex: 3),
              _buildBottomActions(context),
              if (stateMatchesTrack && state.playbackState == NativePlaybackState.error)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Lagu ini gagal dimuat dari sumber audio. Tekan Putar ulang atau pilih lagu berikutnya.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );

        return SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isWideLayout)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(child: Center(child: artworkPanel)),
                      const SizedBox(width: 28),
                      Expanded(child: trackInfoPanel),
                    ],
                  ),
                )
              else
                Padding(
                  // Real layout space (not a paint-only transform) so the
                  // title stays below the cover.
                  padding: const EdgeInsets.only(top: 14, bottom: 10),
                  child: Center(child: artworkPanel),
                ),
              Expanded(child: controlsPanel),
            ],
          ),
        );
      },
    );
  }

  /// Title + artist on the left, buffering spinner and favorite on the right.
  Widget _buildTrackInfo(ThemeData theme, ColorScheme scheme, bool busy) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 52,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    MusicTitleFormatter.clean(widget.video.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.18,
                      letterSpacing: -0.35,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                height: 21,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.video.channelTitle.isEmpty ? 'Artis tidak diketahui' : widget.video.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
        ValueListenableBuilder<PlayerUiState>(
          valueListenable: widget.playerUiState,
          builder: (context, ui, _) => IconButton(
            tooltip: ui.isFavorite ? 'Hapus dari favorit' : 'Tambah ke favorit',
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: widget.onToggleFavorite,
            icon: Icon(
              ui.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 26,
              color: ui.isFavorite ? scheme.primary : Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekBar({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme scheme,
    required Duration duration,
    required double maxMs,
    required double sliderValue,
    required double bufferedTrackValue,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
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
              Text(
                _time(Duration(milliseconds: sliderValue.round())),
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Text(
                _time(duration),
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Shuffle - previous - play/pause - next - repeat.
  Widget _buildTransportRow({
    required ColorScheme scheme,
    required bool busy,
    required bool playing,
  }) {
    return ValueListenableBuilder<PlayerUiState>(
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
                ui.isSmartShuffle ? Icons.auto_awesome_rounded : Icons.shuffle_rounded,
                color: ui.isShuffle ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            IconButton(
              tooltip: 'Lagu sebelumnya (MusikKu)',
              onPressed: widget.onPrevious,
              icon: const Icon(Icons.skip_previous_rounded, size: 36),
            ),
            SizedBox(
              width: 68,
              height: 68,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero),
                onPressed: (busy && !widget.followingRoom) ? null : () => widget.onPlayPause(),
                child: Icon(
                  busy ? Icons.hourglass_top_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  size: 40,
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
    );
  }

  /// Secondary actions along the bottom edge, like Spotify's device/queue row.
  Widget _buildBottomActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: _actionIcon(
              context: context,
              icon: Icons.playlist_add_rounded,
              label: 'Playlist',
              tooltip: 'Tambah ke playlist',
              onPressed: widget.onAddToPlaylist,
            ),
          ),
          Expanded(
            child: _actionIcon(
              context: context,
              icon: Icons.lyrics_rounded,
              label: 'Lirik',
              tooltip: 'Buka lirik karaoke',
              onPressed: _openLyrics,
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.sleepActive,
              builder: (context, active, _) => _actionIcon(
                context: context,
                icon: active ? Icons.timer_rounded : Icons.bedtime_outlined,
                label: 'Timer',
                tooltip: active ? 'Timer tidur aktif' : 'Timer tidur',
                onPressed: widget.followingRoom ? null : widget.onOpenSleepTimer,
                selected: active,
              ),
            ),
          ),
          Expanded(
            child: _actionIcon(
              context: context,
              icon: Icons.queue_music_rounded,
              label: 'Antrean',
              tooltip: 'Buka antrean',
              onPressed: widget.onOpenQueue,
            ),
          ),
        ],
      ),
    );
  }

  /// Shows the complete square cover in a fixed-size slot. The slot size comes
  /// from the device width and remains the same when the active song changes.
  Widget _buildImmersiveArtwork({
    required Key key,
    required YoutubeSearchResult track,
  }) {
    return Container(
      key: key,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 22, offset: const Offset(0, 10)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AlbumArtworkImage(
        track: track,
        fit: BoxFit.cover,
        iconSize: 64,
      ),
    );
  }

  /// Current timestamped lyric displayed directly over artwork without a card.
  /// It only appears after the first timestamp and after the native player has
  /// confirmed that the active track matches this player.
  Widget _buildCurrentLyricText({
    required TextTheme textTheme,
  }) {
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: widget.playerUiState,
      builder: (context, playerState, _) {
        final lyrics = playerState.lyrics;
        if (playerState.video?.videoId != widget.video.videoId ||
            !playerState.lyricsSynced ||
            lyrics.isEmpty) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder<NativeYoutubeState>(
          valueListenable: widget.nativeState,
          builder: (context, state, _) {
            if (state.videoId != widget.video.videoId) {
              return const SizedBox.shrink();
            }

            // Binary search is cheaper than a full scan on every position tick
            // and prevents showing the first lyric before its actual timestamp.
            var low = 0;
            var high = lyrics.length - 1;
            var lineIndex = -1;
            while (low <= high) {
              final mid = (low + high) >> 1;
              if (lyrics[mid].time <= state.position) {
                lineIndex = mid;
                low = mid + 1;
              } else {
                high = mid - 1;
              }
            }
            if (lineIndex < 0) return const SizedBox.shrink();
            final lyric = lyrics[lineIndex].text.trim();
            if (lyric.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.08),
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
                    height: 1.24,
                    fontWeight: FontWeight.w800,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 10, offset: Offset(0, 1)),
                      Shadow(color: Colors.black87, blurRadius: 3, offset: Offset(0, 1)),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Plain icon with a short label underneath. Each action takes an equal
  /// share of the row width so the four labels never get cramped or clipped.
  Widget _actionIcon({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = onPressed == null
        ? scheme.onSurfaceVariant.withValues(alpha: 0.38)
        : (selected ? scheme.primary : scheme.onSurfaceVariant);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
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