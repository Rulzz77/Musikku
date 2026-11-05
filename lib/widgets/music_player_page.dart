import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/loop_mode.dart';
import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
import '../services/music_title_formatter.dart';
import '../theme/app_colors.dart';
import 'album_artwork_image.dart';

/// Full-screen MusikKu player. Native playback ownership and every callback
/// stay in HomePage; this widget is a visual-only replacement for the player.
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
    required this.volumePercent,
    required this.onVolumeChanged,
    required this.onAddToPlaylist,
    required this.onOpenLyrics,
    required this.onOpenQueue,
    required this.onOpenSleepTimer,
    required this.onOpenListeningRoom,
    required this.followingRoom,
    this.inPlaylist = false,
    required this.sleepActive,
    this.platformPlayer,
  });

  final YoutubeSearchResult video;
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
  final int volumePercent;
  final Future<void> Function(int percent, bool persist) onVolumeChanged;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onOpenLyrics;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenSleepTimer;
  final VoidCallback onOpenListeningRoom;
  final bool followingRoom;
  final bool inPlaylist;
  final ValueListenable<bool> sleepActive;
  final Widget? platformPlayer;

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  static const Color _canvas = appInk;
  static const Color _muted = Color(0xFFAAB7C8);
  static const Color _citrus = appGold;
  static const Color _coral = appSecondary;

  double? _dragPositionMs;
  double? _seekHoldMs;
  DateTime? _seekHoldAt;
  late int _volumePreview;
  bool _showVolumeControl = false;

  @override
  void initState() {
    super.initState();
    _volumePreview = widget.volumePercent.clamp(0, 100).toInt();
  }

  @override
  void didUpdateWidget(covariant MusicPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.volumePercent != widget.volumePercent) {
      _volumePreview = widget.volumePercent.clamp(0, 100).toInt();
    }
    if (oldWidget.video.videoId != widget.video.videoId) {
      _dragPositionMs = null;
      _seekHoldMs = null;
      _seekHoldAt = null;
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
    // Keep the Android status bar visible and readable above the artwork.
    // The artwork itself is laid out inside SafeArea, never behind the clock/icons.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: _canvas,
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Material(
        color: _canvas,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 38, sigmaY: 38),
                child: Opacity(
                  opacity: 0.22,
                  child: AlbumArtworkImage(track: widget.video, fit: BoxFit.cover),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xB50D1422), Color(0xE80D1422), _canvas],
                    stops: [0, 0.48, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              top: true,
              bottom: true,
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: ValueListenableBuilder<NativeYoutubeState>(
                      valueListenable: widget.nativeState,
                      builder: (context, state, _) => _buildBody(context, state),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(17, 7, 17, 4),
      child: Row(
        children: [
          _roundButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: 'Tutup pemutar',
            onPressed: widget.onBack,
          ),
          const Spacer(),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SEDANG DIPUTAR',
                style: TextStyle(color: _citrus, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2.0),
              ),
              const SizedBox(height: 4),
              Text(
                widget.followingRoom ? 'LISTENING ROOM' : 'NOW PLAYING',
                style: const TextStyle(color: _muted, fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: 1.15),
              ),
            ],
          ),
          const Spacer(),
          _roundButton(
            icon: widget.followingRoom ? Icons.headphones_rounded : Icons.groups_2_rounded,
            tooltip: widget.followingRoom ? 'Mengikuti sesi dengar bareng' : 'Dengerin bareng',
            onPressed: widget.onOpenListeningRoom,
          ),
        ],
      ),
    );
  }

  Widget _roundButton({required IconData icon, required String tooltip, required VoidCallback onPressed}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xFFEEF3FA).withValues(alpha: 0.07),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 43, height: 43, child: Icon(icon, color: const Color(0xFFEEF3FA), size: 23)),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, NativeYoutubeState state) {
    final matchesTrack = state.videoId.isEmpty || state.videoId == widget.video.videoId;
    final position = matchesTrack ? state.position : Duration.zero;
    final duration = matchesTrack && state.duration > Duration.zero
        ? state.duration
        : Duration(milliseconds: ((widget.video.durationSeconds ?? 0) * 1000).round());
    final maxMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final positionMs = position.inMilliseconds.toDouble();
    final holdMs = _seekHoldMs;
    final holdAt = _seekHoldAt;
    final holdActive = holdMs != null &&
        holdAt != null &&
        DateTime.now().difference(holdAt) < const Duration(milliseconds: 1500) &&
        (holdMs - positionMs).abs() > 1200;
    final shownMs = _dragPositionMs ?? (holdActive ? holdMs : positionMs);
    final sliderValue = shownMs.clamp(0.0, maxMs).toDouble();
    final rawBufferedMs = matchesTrack ? state.safeBufferedFraction * maxMs : sliderValue;
    final bufferedTrackValue = math.max(sliderValue, rawBufferedMs).clamp(0.0, maxMs).toDouble();
    final busy = matchesTrack && state.isBuffering;
    final playing = matchesTrack && state.isEffectivelyPlaying;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final compact = height < 640;
        // Keep text and controls comfortably inset while letting the artwork
        // run almost edge-to-edge, like the supplied player reference.
        final side = width >= 700 ? 34.0 : 20.0;
        final maxCover = math.min(width - 8.0, width >= 700 ? 460.0 : 440.0);

        // Reserve enough room for title, queue shortcut, seek bar, transport,
        // volume and the four existing actions. The cover expands on tall
        // phones but shrinks predictably on short screens instead of causing
        // the lower controls to overflow.
        final reservedForExpandedControls = _showVolumeControl ? 14.0 : 0.0;
        final reservedForPlaybackError =
            matchesTrack && state.playbackState == NativePlaybackState.error ? 20.0 : 0.0;
        final coverSize = math.min(
          maxCover,
          math.max(
            136.0,
            height - (compact ? 318.0 : 326.0) - reservedForExpandedControls - reservedForPlaybackError,
          ),
        ).toDouble();

        return Padding(
          padding: EdgeInsets.fromLTRB(side, compact ? 0 : 2, side, compact ? 0 : 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SizedBox(
                height: coverSize,
                child: LayoutBuilder(
                  builder: (context, stage) {
                    if (widget.platformPlayer != null) {
                      final playerWidth = math.min(width - 8, 480.0).toDouble();
                      final playerHeight = math.min(playerWidth * 9 / 16, stage.maxHeight * 0.86).toDouble();
                      return Center(
                        child: SizedBox(
                          width: playerWidth,
                          height: playerHeight,
                          child: widget.platformPlayer!,
                        ),
                      );
                    }
                    return Center(
                      child: OverflowBox(
                        minWidth: coverSize,
                        maxWidth: coverSize,
                        minHeight: coverSize,
                        maxHeight: coverSize,
                        alignment: Alignment.center,
                        child: _buildAlbumCover(coverSize),
                      ),
                    );
                  },
                ),
              ),
              _buildTrackInfo(busy),
              _buildNextTrack(),
              _buildSeekBar(
                context: context,
                duration: duration,
                maxMs: maxMs,
                sliderValue: sliderValue,
                bufferedTrackValue: bufferedTrackValue,
              ),
              Transform.translate(
                offset: Offset(0, compact ? -3 : -7),
                child: _buildControlDeck(busy: busy, playing: playing, compact: compact),
              ),
              _buildVolumeControl(compact: compact),
              if (matchesTrack && state.playbackState == NativePlaybackState.error)
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    'Audio gagal dimuat. Coba putar ulang atau pilih lagu berikutnya.',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFFFF9A91), fontSize: 10.5),
                  ),
                ),
              _buildBottomActions(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNextTrack() {
    final next = widget.nextVideo;
    final title = next == null ? 'Lihat antrean' : MusicTitleFormatter.clean(next.title);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onOpenQueue,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.music_note_rounded, color: _muted, size: 19),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: _muted, size: 21),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlbumCover(double size) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Container(
        key: ValueKey<String>('player-cover-frame-${widget.video.videoId}'),
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 38,
              offset: const Offset(0, 18),
            ),
            BoxShadow(
              color: const Color(0xFFEEF3FA).withValues(alpha: 0.055),
              blurRadius: 1,
              spreadRadius: 1,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: AlbumArtworkImage(
          track: widget.video,
          width: size,
          height: size,
          fit: BoxFit.cover,
          iconSize: 58,
        ),
      ),
    );
  }

  Widget _buildTrackInfo(bool busy) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                MusicTitleFormatter.clean(widget.video.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFF1F1E8), fontSize: 22, height: 1.04, fontWeight: FontWeight.w900, letterSpacing: -0.7),
              ),
              const SizedBox(height: 5),
              Text(
                widget.video.channelTitle.trim().isEmpty ? 'Artis tidak diketahui' : widget.video.channelTitle.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(left: 5),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _citrus)),
          ),
        ValueListenableBuilder<PlayerUiState>(
          valueListenable: widget.playerUiState,
          builder: (context, ui, _) => IconButton(
            tooltip: ui.isFavorite ? 'Hapus dari favorit' : 'Tambah ke favorit',
            onPressed: widget.onToggleFavorite,
            icon: Icon(ui.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: ui.isFavorite ? _coral : const Color(0xFFAAB7C8), size: 25),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekBar({
    required BuildContext context,
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
            trackHeight: 4,
            activeTrackColor: _citrus,
            secondaryActiveTrackColor: const Color(0xFFEEF3FA).withValues(alpha: 0.34),
            inactiveTrackColor: const Color(0xFFEEF3FA).withValues(alpha: 0.15),
            thumbColor: _citrus,
            overlayColor: const Color(0xFFEEF3FA).withValues(alpha: 0.12),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
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
                    setState(() {
                      _dragPositionMs = null;
                      _seekHoldMs = value;
                      _seekHoldAt = DateTime.now();
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
              Text(_time(Duration(milliseconds: sliderValue.round())), style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
              Text(_time(duration), style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }


  void _setVolumePreview(int value, {bool persist = false}) {
    final next = value.clamp(0, 100).toInt();
    if (next == _volumePreview) {
      if (persist) unawaited(widget.onVolumeChanged(next, true));
      return;
    }
    setState(() => _volumePreview = next);
    unawaited(widget.onVolumeChanged(next, persist));
  }

  Widget _buildVolumeControl({required bool compact}) {
    final expanded = _showVolumeControl;
    final sliderWidth = compact ? 116.0 : 150.0;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      child: SizedBox(
        height: expanded ? 48 : 34,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(horizontal: expanded ? 8 : 0, vertical: 1),
            decoration: BoxDecoration(
              color: expanded ? const Color(0xFF151F30).withValues(alpha: 0.92) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: expanded
                  ? Border.all(color: const Color(0xFFEEF3FA).withValues(alpha: 0.09))
                  : Border.all(color: Colors.transparent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: expanded ? 'Tutup pengatur volume' : 'Atur volume',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _showVolumeControl = !_showVolumeControl),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(
                        _volumePreview == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: expanded ? _citrus : _muted,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.centerLeft,
                  child: expanded
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: sliderWidth,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  activeTrackColor: _citrus,
                                  inactiveTrackColor: const Color(0xFFEEF3FA).withValues(alpha: 0.16),
                                  thumbColor: _citrus,
                                  overlayColor: _citrus.withValues(alpha: 0.12),
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                ),
                                child: Slider(
                                  min: 0,
                                  max: 100,
                                  divisions: 100,
                                  value: _volumePreview.toDouble(),
                                  onChanged: (value) => _setVolumePreview(value.round()),
                                  onChangeEnd: (value) => _setVolumePreview(value.round(), persist: true),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 34,
                              child: Text(
                                '$_volumePreview%',
                                textAlign: TextAlign.end,
                                style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        )
                      : const SizedBox(width: 0, height: 34),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlDeck({required bool busy, required bool playing, required bool compact}) {
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: widget.playerUiState,
      builder: (context, ui, _) {
        final sideSize = compact ? 35.0 : 39.0;
        final transportSize = compact ? 43.0 : 48.0;
        final playSize = compact ? 64.0 : 70.0;
        final gap = compact ? 2.0 : 7.0;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: sideSize,
              height: sideSize,
              child: _transportSideButton(
                icon: ui.isSmartShuffle ? Icons.auto_awesome_rounded : Icons.shuffle_rounded,
                selected: ui.isShuffle,
                tooltip: ui.isSmartShuffle ? 'Smart Shuffle aktif • tekan lama untuk mematikan' : 'Shuffle • tekan lama untuk Smart Shuffle',
                onPressed: widget.onToggleShuffle,
                onLongPress: widget.onToggleSmartShuffle,
              ),
            ),
            SizedBox(width: gap),
            IconButton(
              tooltip: 'Lagu sebelumnya',
              visualDensity: VisualDensity.compact,
              onPressed: () => widget.onPrevious(),
              icon: Icon(Icons.skip_previous_rounded, size: transportSize, color: const Color(0xFFEEF3FA)),
            ),
            SizedBox(
              width: playSize,
              height: playSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _citrus,
                  boxShadow: [
                    BoxShadow(color: _citrus.withValues(alpha: 0.20), blurRadius: 22, offset: const Offset(0, 8)),
                  ],
                ),
                child: IconButton(
                  tooltip: playing ? 'Jeda' : 'Putar',
                  onPressed: (busy && !widget.followingRoom) ? null : () => widget.onPlayPause(),
                  icon: Icon(
                    busy ? Icons.hourglass_top_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    size: compact ? 37 : 41,
                    color: _canvas,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Lagu berikutnya',
              visualDensity: VisualDensity.compact,
              onPressed: () => widget.onNext(),
              icon: Icon(Icons.skip_next_rounded, size: transportSize, color: const Color(0xFFEEF3FA)),
            ),
            SizedBox(width: gap),
            SizedBox(
              width: sideSize,
              height: sideSize,
              child: _transportSideButton(
                icon: ui.loopMode == LoopModeCustom.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                selected: ui.loopMode != LoopModeCustom.off,
                tooltip: switch (ui.loopMode) {
                  LoopModeCustom.off => 'Aktifkan repeat',
                  LoopModeCustom.all => 'Repeat semua aktif',
                  LoopModeCustom.one => 'Repeat satu aktif',
                },
                onPressed: widget.onCycleLoop,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _transportSideButton({
    required IconData icon,
    required bool selected,
    required String tooltip,
    required VoidCallback onPressed,
    VoidCallback? onLongPress,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? _citrus.withValues(alpha: 0.16) : Colors.transparent),
          child: Icon(icon, color: selected ? _citrus : const Color(0xFFAAB7C8), size: 20),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3FA).withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFEEF3FA).withValues(alpha: 0.075)),
      ),
      child: Row(
        children: [
          Expanded(child: _bottomAction(icon: widget.inPlaylist ? Icons.check_circle_rounded : Icons.playlist_add_rounded, label: 'Playlist', selected: widget.inPlaylist, onPressed: widget.onAddToPlaylist)),
          Expanded(child: _bottomAction(icon: Icons.lyrics_rounded, label: 'Lirik', onPressed: widget.onOpenLyrics)),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.sleepActive,
              builder: (context, active, _) => _bottomAction(icon: active ? Icons.timer_rounded : Icons.bedtime_outlined, label: 'Timer', selected: active, onPressed: widget.followingRoom ? null : widget.onOpenSleepTimer),
            ),
          ),
          Expanded(child: _bottomAction(icon: Icons.queue_music_rounded, label: 'Antrean', onPressed: widget.onOpenQueue)),
        ],
      ),
    );
  }

  Widget _bottomAction({required IconData icon, required String label, required VoidCallback? onPressed, bool selected = false}) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? _citrus : const Color(0xFFAAB7C8), size: 19),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: selected ? _citrus : _muted, fontSize: 9, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }


}
