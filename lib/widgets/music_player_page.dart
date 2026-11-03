import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

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
  static const Color _muted = Color(0xFFAAB7AA);
  static const Color _citrus = appGold;
  static const Color _coral = appSecondary;

  double? _dragPositionMs;
  double? _seekHoldMs;
  DateTime? _seekHoldAt;
  late int _volumePreview;
  bool _adjustingVolume = false;

  @override
  void initState() {
    super.initState();
    _volumePreview = widget.volumePercent.clamp(0, 100).toInt();
  }

  @override
  void didUpdateWidget(covariant MusicPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_adjustingVolume && oldWidget.volumePercent != widget.volumePercent) {
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
    return Material(
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
                  colors: [Color(0xB5101915), Color(0xE8101915), _canvas],
                  stops: [0, 0.48, 1],
                ),
              ),
            ),
          ),
          SafeArea(
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
        color: const Color(0xFFF1F1E8).withValues(alpha: 0.07),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 43, height: 43, child: Icon(icon, color: const Color(0xFFF1F1E8), size: 23)),
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
        final coverSize = math.min(width * 0.82, height * 0.29)
            .clamp(140.0, 292.0)
            .toDouble();

        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Lower the artwork block slightly for a more relaxed player composition.
              SizedBox(height: (height * 0.092).clamp(38.0, 66.0).toDouble()),
              if (widget.platformPlayer != null)
                SizedBox(
                  width: math.min(width * 0.96, 440),
                  height: math.min(math.min(width * 0.96, 440) * 9 / 16, height * 0.32),
                  child: widget.platformPlayer!,
                )
              else
                _buildAlbumCover(coverSize),
              const SizedBox(height: 19),
              _buildTrackInfo(busy),
              const SizedBox(height: 15),
              _buildSeekBar(
                context: context,
                duration: duration,
                maxMs: maxMs,
                sliderValue: sliderValue,
                bufferedTrackValue: bufferedTrackValue,
              ),
              const SizedBox(height: 3),
              _buildPlaybackModes(),
              const SizedBox(height: 5),
              _buildTransportRow(busy: busy, playing: playing),
              const SizedBox(height: 5),
              _buildVolumeSlider(),
              const SizedBox(height: 7),
              _buildBottomActions(context),
              if (matchesTrack && state.playbackState == NativePlaybackState.error)
                const Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Text(
                    'Audio gagal dimuat. Coba putar ulang atau pilih lagu berikutnya.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFFF9A91), fontSize: 10.5),
                  ),
                ),
            ],
          ),
        );
      },
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
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 38,
              offset: const Offset(0, 18),
            ),
            BoxShadow(
              color: const Color(0xFFF1F1E8).withValues(alpha: 0.055),
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
                style: const TextStyle(color: Color(0xFFF1F1E8), fontSize: 24, height: 1.06, fontWeight: FontWeight.w900, letterSpacing: -0.7),
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
            icon: Icon(ui.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: ui.isFavorite ? _coral : const Color(0xFFB5C1B5), size: 25),
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
            secondaryActiveTrackColor: const Color(0xFFF1F1E8).withValues(alpha: 0.34),
            inactiveTrackColor: const Color(0xFFF1F1E8).withValues(alpha: 0.15),
            thumbColor: _citrus,
            overlayColor: const Color(0xFFF1F1E8).withValues(alpha: 0.12),
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


  Widget _buildVolumeSlider() {
    return Row(
      children: [
        const Icon(Icons.volume_down_rounded, color: _muted, size: 20),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: _citrus,
              inactiveTrackColor: const Color(0xFFF1F1E8).withValues(alpha: 0.18),
              thumbColor: _citrus,
              overlayColor: const Color(0xFFF1F1E8).withValues(alpha: 0.10),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              min: 0,
              max: 100,
              value: _volumePreview.clamp(0, 100).toDouble(),
              onChanged: (value) {
                final next = value.round();
                setState(() {
                  _volumePreview = next;
                  _adjustingVolume = true;
                });
                unawaited(widget.onVolumeChanged(next, false));
              },
              onChangeEnd: (value) {
                final next = value.round();
                setState(() {
                  _volumePreview = next;
                  _adjustingVolume = false;
                });
                unawaited(widget.onVolumeChanged(next, true));
              },
            ),
          ),
        ),
        const Icon(Icons.volume_up_rounded, color: _muted, size: 20),
      ],
    );
  }

  Widget _buildPlaybackModes() {
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: widget.playerUiState,
      builder: (context, ui, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _transportSideButton(
            icon: ui.isSmartShuffle ? Icons.auto_awesome_rounded : Icons.shuffle_rounded,
            selected: ui.isShuffle,
            tooltip: ui.isSmartShuffle ? 'Smart Shuffle aktif • tekan lama untuk mematikan' : 'Shuffle • tekan lama untuk Smart Shuffle',
            onPressed: widget.onToggleShuffle,
            onLongPress: widget.onToggleSmartShuffle,
          ),
          const SizedBox(width: 24),
          _transportSideButton(
            icon: ui.loopMode == LoopModeCustom.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
            selected: ui.loopMode != LoopModeCustom.off,
            tooltip: switch (ui.loopMode) {
              LoopModeCustom.off => 'Aktifkan repeat',
              LoopModeCustom.all => 'Repeat semua aktif',
              LoopModeCustom.one => 'Repeat satu aktif',
            },
            onPressed: widget.onCycleLoop,
          ),
        ],
      ),
    );
  }

  Widget _buildTransportRow({required bool busy, required bool playing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Lagu sebelumnya',
          onPressed: () => widget.onPrevious(),
          icon: const Icon(Icons.skip_previous_rounded, size: 48, color: Color(0xFFF1F1E8)),
        ),
        const SizedBox(width: 23),
        SizedBox(
          width: 76,
          height: 76,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFD8F17A), Color(0xFFB6D65D)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF1F1E8).withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: IconButton(
              tooltip: playing ? 'Jeda' : 'Putar',
              onPressed: (busy && !widget.followingRoom) ? null : () => widget.onPlayPause(),
              icon: Icon(
                busy ? Icons.hourglass_top_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                size: 43,
                color: _canvas,
              ),
            ),
          ),
        ),
        const SizedBox(width: 23),
        IconButton(
          tooltip: 'Lagu berikutnya',
          onPressed: () => widget.onNext(),
          icon: const Icon(Icons.skip_next_rounded, size: 48, color: Color(0xFFF1F1E8)),
        ),
      ],
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
          child: Icon(icon, color: selected ? _citrus : const Color(0xFFB5C1B5), size: 20),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Row(
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
    );
  }

  Widget _bottomAction({required IconData icon, required String label, required VoidCallback? onPressed, bool selected = false}) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 37,
                height: 34,
                decoration: BoxDecoration(
                  color: selected ? _citrus.withValues(alpha: 0.16) : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: selected ? _citrus : const Color(0xFFB5C1B5), size: 24),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: selected ? _citrus : _muted, fontSize: 9.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

}
