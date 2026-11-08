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
import 'album_artwork_image.dart';

/// Full-screen MusikKu player. Native playback ownership and every callback
/// stay in HomePage; this widget is a visual-only replacement for the player.
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
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _canvas => Theme.of(context).colorScheme.onPrimary;
  Color get _playerBackground => _isDark
      ? const Color(0xFF111419)
      : const Color(0xFFF2F5F8);
  Color get _muted => _isDark
      ? const Color(0xFFAAB7C8)
      : const Color(0xFF687482);
  Color get _mainText => _isDark
      ? const Color(0xFFF1F4F8)
      : const Color(0xFF1B222B);
  Color get _controlInk => _isDark
      ? const Color(0xFFEEF3FA)
      : const Color(0xFF283442);
  Color get _controlSurface => _controlInk.withValues(alpha: _isDark ? 0.07 : 0.055);
  Color get _controlBorder => _controlInk.withValues(alpha: _isDark ? 0.075 : 0.09);
  Color get _citrus => Theme.of(context).colorScheme.primary;
  Color get _coral => Theme.of(context).colorScheme.secondary;

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
    final isDark = _isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: _playerBackground,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Material(
        color: _playerBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 52, sigmaY: 52),
                child: Opacity(
                  opacity: isDark ? 0.34 : 0.20,
                  child: AlbumArtworkImage(track: widget.video, fit: BoxFit.cover),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: isDark
                        ? [
                            const Color(0x300D1422),
                            const Color(0x55343E4C),
                            const Color(0xAA1A2029),
                            _playerBackground,
                          ]
                        : [
                            const Color(0x18FFFFFF),
                            const Color(0x66FFFFFF),
                            const Color(0xDDF2F5F8),
                            _playerBackground,
                          ],
                    stops: [0, 0.42, 0.76, 1],
                  ),
                ),
              ),
            ),
            // The artwork starts below the Android status bar. The header is
            // overlaid on the artwork, while the image itself never covers the
            // clock, signal, or battery area.
            SafeArea(
              top: true,
              bottom: true,
              child: ValueListenableBuilder<NativeYoutubeState>(
                valueListenable: widget.nativeState,
                builder: (context, state, _) => _buildBody(context, state),
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
              Text(
                'SEDANG DIPUTAR',
                style: TextStyle(color: _citrus, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2.0),
              ),
              const SizedBox(height: 4),
              Text(
                widget.followingRoom ? 'LISTENING ROOM' : 'NOW PLAYING',
                style: TextStyle(color: _muted, fontSize: 8.5, fontWeight: FontWeight.w700, letterSpacing: 1.15),
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
        color: _controlSurface,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 43, height: 43, child: Icon(icon, color: _controlInk, size: 23)),
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
        final compact = height < 650;
        final side = width >= 700 ? 34.0 : 20.0;

        // Wide, edge-to-edge artwork (not a square card). The lower edge fades
        // into the blurred artwork backdrop to create the soft gradient seen
        // in the user's reference. Height is responsive to short phone screens.
        // Keep the artwork visibly taller so the track title sits a little
        // lower, close to the approved reference, without pushing controls
        // toward the bottom edge on compact phones.
        final artworkHeight = math.min(
          width * 1.12,
          height * (compact ? 0.46 : 0.54),
        ).toDouble();

        final controls = Padding(
          padding: EdgeInsets.fromLTRB(side, compact ? 0 : 3, side, compact ? 0 : 5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildTrackInfo(busy),
              _buildSeekBar(
                context: context,
                duration: duration,
                maxMs: maxMs,
                sliderValue: sliderValue,
                bufferedTrackValue: bufferedTrackValue,
              ),
              _buildControlDeck(busy: busy, playing: playing, compact: compact),
              if (matchesTrack && state.playbackState == NativePlaybackState.error)
                const Text(
                  'Audio gagal dimuat. Coba putar ulang atau pilih lagu berikutnya.',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Color(0xFFFF9A91), fontSize: 10.5),
                ),
              _buildBottomActions(context),
            ],
          ),
        );

        // Tablet / landscape gets a true two-column player: large artwork on
        // the left, playback information and controls on the right. Phones keep
        // the familiar vertical composition so all controls stay reachable.
        if (width >= 760 && height >= 520) {
          final artworkWidth = width * 0.53;
          return Row(
            children: [
              SizedBox(
                width: artworkWidth,
                height: height,
                child: _buildArtworkHero(
                  width: artworkWidth,
                  height: height,
                ),
              ),
              Expanded(
                child: controls,
              ),
            ],
          );
        }

        return Column(
          children: [
            _buildArtworkHero(width: width, height: artworkHeight),
            Expanded(child: controls),
          ],
        );
      },
    );
  }

  Widget _buildArtworkHero({required double width, required double height}) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.platformPlayer != null)
            Center(
              child: SizedBox(
                width: width,
                height: math.min(height, width * 9 / 16).toDouble(),
                child: widget.platformPlayer!,
              ),
            )
          else
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.black, Colors.transparent],
                // Preserve the artwork longer and let the blur/gradient begin
                // lower, then blend it smoothly into the player background.
                stops: [0, 0.66, 0.84, 1],
              ).createShader(bounds),
              child: AlbumArtworkImage(
                key: ValueKey<String>('player-wide-art-${widget.video.videoId}'),
                track: widget.video,
                width: width,
                height: height,
                fit: BoxFit.cover,
                iconSize: 58,
              ),
            ),
          // Keep the header readable on bright album artwork without adding
          // a card border, radius, or a separate square cover surface.
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x65000000), Colors.transparent, Colors.transparent],
                    stops: [0, 0.27, 1],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(),
          ),
        ],
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
                style: TextStyle(color: _mainText, fontSize: 22, height: 1.04, fontWeight: FontWeight.w900, letterSpacing: -0.7),
              ),
              const SizedBox(height: 5),
              Text(
                widget.video.channelTitle.trim().isEmpty ? 'Artis tidak diketahui' : widget.video.channelTitle.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _muted, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.only(left: 5),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _citrus)),
          ),
        ValueListenableBuilder<PlayerUiState>(
          valueListenable: widget.playerUiState,
          builder: (context, ui, _) => IconButton(
            tooltip: ui.isFavorite ? 'Hapus dari favorit' : 'Tambah ke favorit',
            onPressed: widget.onToggleFavorite,
            icon: Icon(ui.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: ui.isFavorite ? _coral : _muted, size: 25),
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
            secondaryActiveTrackColor: _controlInk.withValues(alpha: 0.34),
            inactiveTrackColor: _controlInk.withValues(alpha: 0.15),
            thumbColor: _citrus,
            overlayColor: _controlInk.withValues(alpha: 0.12),
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
              Text(_time(Duration(milliseconds: sliderValue.round())), style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
              Text(_time(duration), style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
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
              icon: Icon(Icons.skip_previous_rounded, size: transportSize, color: _controlInk),
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
              icon: Icon(Icons.skip_next_rounded, size: transportSize, color: _controlInk),
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
          duration: MediaQuery.of(context).disableAnimations
              ? Duration.zero
              : const Duration(milliseconds: 180),
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? _citrus.withValues(alpha: 0.16) : Colors.transparent),
          child: Icon(icon, color: selected ? _citrus : _muted, size: 20),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      decoration: BoxDecoration(
        color: _controlSurface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: _controlBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: _bottomAction(
                  icon: widget.inPlaylist ? Icons.check_circle_rounded : Icons.playlist_add_rounded,
                  label: 'Playlist',
                  selected: widget.inPlaylist,
                  onPressed: widget.onAddToPlaylist,
                ),
              ),
              Expanded(
                child: _bottomAction(
                  icon: Icons.lyrics_rounded,
                  label: 'Lirik',
                  onPressed: widget.onOpenLyrics,
                ),
              ),
              Expanded(
                child: _bottomAction(
                  icon: _volumePreview == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  label: 'Volume',
                  selected: _showVolumeControl,
                  onPressed: () => setState(() => _showVolumeControl = !_showVolumeControl),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: widget.sleepActive,
                  builder: (context, active, _) => _bottomAction(
                    icon: active ? Icons.timer_rounded : Icons.bedtime_outlined,
                    label: 'Timer',
                    selected: active,
                    onPressed: widget.followingRoom ? null : widget.onOpenSleepTimer,
                  ),
                ),
              ),
              Expanded(
                child: _bottomAction(
                  icon: Icons.queue_music_rounded,
                  label: 'Antrean',
                  onPressed: widget.onOpenQueue,
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _showVolumeControl
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(9, 5, 9, 1),
                    child: Row(
                      children: [
                        Icon(Icons.volume_down_rounded, color: _muted, size: 17),
                        const SizedBox(width: 5),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              activeTrackColor: _citrus,
                              inactiveTrackColor: _controlInk.withValues(alpha: 0.16),
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
                          width: 35,
                          child: Text(
                            '$_volumePreview%',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              color: _muted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.volume_up_rounded, color: _muted, size: 17),
                      ],
                    ),
                  )
                : const SizedBox(width: 0, height: 0),
          ),
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
              Icon(icon, color: selected ? _citrus : _muted, size: 19),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(color: selected ? _citrus : _muted, fontSize: 9, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }


}
