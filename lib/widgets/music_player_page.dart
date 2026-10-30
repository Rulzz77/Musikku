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
    required this.onAddToPlaylist,
    required this.onOpenQueue,
    required this.onOpenSleepTimer,
    required this.onOpenListeningRoom,
    required this.followingRoom,
    this.inPlaylist = false,
    required this.sleepActive,
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
  final VoidCallback onAddToPlaylist;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenSleepTimer;
  final VoidCallback onOpenListeningRoom;
  final bool followingRoom;
  final bool inPlaylist;
  final ValueListenable<bool> sleepActive;

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage>
    with SingleTickerProviderStateMixin {
  static const Color _canvas = Color(0xFF07111F);
  static const Color _muted = Color(0xFF9EB1C5);
  static const Color _cyan = Color(0xFF67E5F2);
  static const Color _coral = Color(0xFFFF8C78);

  late final AnimationController _recordRotation;
  double? _dragPositionMs;
  double? _seekHoldMs;
  DateTime? _seekHoldAt;

  @override
  void initState() {
    super.initState();
    _recordRotation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    );
  }

  @override
  void dispose() {
    _recordRotation.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MusicPlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.videoId != widget.video.videoId) {
      _dragPositionMs = null;
      _seekHoldMs = null;
      _seekHoldAt = null;
      _recordRotation.value = 0;
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
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0C2135), _canvas, Color(0xFF101B2C)],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
          Positioned(
            top: -135,
            right: -115,
            child: _GlowOrb(color: _cyan.withValues(alpha: 0.14), size: 330),
          ),
          Positioned(
            bottom: -150,
            left: -130,
            child: _GlowOrb(color: _coral.withValues(alpha: 0.11), size: 350),
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
                style: TextStyle(color: _cyan, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2.0),
              ),
              const SizedBox(height: 4),
              Text(
                widget.followingRoom ? 'LISTENING ROOM' : 'MUSIKKU PLAYER',
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
        color: Colors.white.withValues(alpha: 0.07),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 43, height: 43, child: Icon(icon, color: Colors.white, size: 23)),
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

    if (playing && !_recordRotation.isAnimating) {
      _recordRotation.repeat();
    } else if (!playing && _recordRotation.isAnimating) {
      _recordRotation.stop(canceled: false);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final discSize = math.min(width * 0.76, height * 0.37).clamp(176.0, 292.0).toDouble();

        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
          child: Column(
            children: [
              const SizedBox(height: 4),
              SizedBox(
                width: discSize,
                height: discSize,
                child: _buildVinylDisc(discSize, playing),
              ),
              const SizedBox(height: 17),
              _buildTrackInfo(busy),
              const SizedBox(height: 8),
              SizedBox(height: 32, child: _buildCurrentLyricText()),
              const Spacer(flex: 1),
              _buildSeekBar(
                context: context,
                duration: duration,
                maxMs: maxMs,
                sliderValue: sliderValue,
                bufferedTrackValue: bufferedTrackValue,
              ),
              const SizedBox(height: 7),
              _buildTransportRow(busy: busy, playing: playing),
              const SizedBox(height: 3),
              _buildBottomActions(context),
              if (matchesTrack && state.playbackState == NativePlaybackState.error)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Audio gagal dimuat. Coba putar ulang atau pilih lagu berikutnya.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFFF9A91), fontSize: 10.5),
                  ),
                ),
              const SizedBox(height: 3),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVinylDisc(double size, bool playing) {
    return AnimatedBuilder(
      animation: _recordRotation,
      builder: (context, child) => Transform.rotate(
        angle: _recordRotation.value * math.pi * 2,
        child: child,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF26374D), Color(0xFF111B2A), Color(0xFF050A12)],
                stops: [0.1, 0.72, 1],
              ),
              boxShadow: [
                BoxShadow(color: _cyan.withValues(alpha: playing ? 0.16 : 0.08), blurRadius: playing ? 42 : 28, spreadRadius: 2),
                const BoxShadow(color: Colors.black54, blurRadius: 25, offset: Offset(0, 16)),
              ],
              border: Border.all(color: Colors.white.withValues(alpha: 0.13), width: 1.2),
            ),
            child: CustomPaint(painter: _VinylGroovesPainter(color: Colors.white.withValues(alpha: 0.10))),
          ),
          Container(
            width: size * 0.74,
            height: size * 0.74,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.65), width: 3),
              boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 18, offset: Offset(0, 8))],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 480),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: Tween<double>(begin: 0.92, end: 1).animate(animation), child: child),
              ),
              child: ClipOval(
                key: ValueKey<String>('player-cover-${widget.video.videoId}'),
                child: AlbumArtworkImage(track: widget.video, fit: BoxFit.cover, iconSize: 58),
              ),
            ),
          ),
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _cyan,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF09111D), width: 4),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: playing ? _cyan : Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(playing ? Icons.graphic_eq_rounded : Icons.album_rounded, size: 13, color: playing ? _canvas : Colors.white70),
                  const SizedBox(width: 5),
                  Text(playing ? 'PLAYING' : 'PAUSED', style: TextStyle(color: playing ? _canvas : Colors.white70, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.0)),
                ],
              ),
            ),
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
                style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -0.65),
              ),
              const SizedBox(height: 5),
              Text(
                widget.video.channelTitle.trim().isEmpty ? 'Artis tidak diketahui' : widget.video.channelTitle.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.only(left: 5),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _cyan)),
          ),
        ValueListenableBuilder<PlayerUiState>(
          valueListenable: widget.playerUiState,
          builder: (context, ui, _) => IconButton(
            tooltip: ui.isFavorite ? 'Hapus dari favorit' : 'Tambah ke favorit',
            onPressed: widget.onToggleFavorite,
            icon: Icon(ui.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: ui.isFavorite ? _coral : Colors.white70, size: 25),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentLyricText() {
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: widget.playerUiState,
      builder: (context, playerState, _) {
        final lyrics = playerState.lyrics;
        if (playerState.video?.videoId != widget.video.videoId || !playerState.lyricsSynced || lyrics.isEmpty) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<NativeYoutubeState>(
          valueListenable: widget.nativeState,
          builder: (context, state, _) {
            if (state.videoId != widget.video.videoId) return const SizedBox.shrink();
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
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation), child: child),
              ),
              child: Container(
                key: ValueKey<String>('lyric-$lineIndex-$lyric'),
                width: double.infinity,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.055), borderRadius: BorderRadius.circular(11)),
                child: Text(lyric, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _cyan, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2)),
              ),
            );
          },
        );
      },
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
            activeTrackColor: _cyan,
            secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.34),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
            thumbColor: Colors.white,
            overlayColor: _cyan.withValues(alpha: 0.12),
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

  Widget _buildTransportRow({required bool busy, required bool playing}) {
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: widget.playerUiState,
      builder: (context, ui, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _transportSideButton(
            icon: ui.isSmartShuffle ? Icons.auto_awesome_rounded : Icons.shuffle_rounded,
            selected: ui.isShuffle,
            tooltip: ui.isSmartShuffle ? 'Smart Shuffle aktif • tekan lama untuk mematikan' : 'Shuffle • tekan lama untuk Smart Shuffle',
            onPressed: widget.onToggleShuffle,
            onLongPress: widget.onToggleSmartShuffle,
          ),
          IconButton(tooltip: 'Lagu sebelumnya', onPressed: () => widget.onPrevious(), icon: const Icon(Icons.skip_previous_rounded, size: 34, color: Colors.white)),
          SizedBox(
            width: 68,
            height: 68,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_cyan, Color(0xFF26AFC4)]),
                boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.27), blurRadius: 22, offset: const Offset(0, 7))],
              ),
              child: IconButton(
                tooltip: playing ? 'Jeda' : 'Putar',
                onPressed: (busy && !widget.followingRoom) ? null : () => widget.onPlayPause(),
                icon: Icon(busy ? Icons.hourglass_top_rounded : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded), size: 39, color: _canvas),
              ),
            ),
          ),
          IconButton(tooltip: 'Lagu berikutnya', onPressed: () => widget.onNext(), icon: const Icon(Icons.skip_next_rounded, size: 34, color: Colors.white)),
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
          decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? _cyan.withValues(alpha: 0.15) : Colors.transparent),
          child: Icon(icon, color: selected ? _cyan : Colors.white70, size: 20),
        ),
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _bottomAction(icon: widget.inPlaylist ? Icons.check_circle_rounded : Icons.playlist_add_rounded, label: 'Playlist', selected: widget.inPlaylist, onPressed: widget.onAddToPlaylist)),
        Expanded(child: _bottomAction(icon: Icons.lyrics_rounded, label: 'Lirik', onPressed: _openLyrics)),
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
                decoration: BoxDecoration(color: selected ? _cyan.withValues(alpha: 0.17) : Colors.white.withValues(alpha: 0.055), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, color: selected ? _cyan : Colors.white70, size: 19),
              ),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: selected ? _cyan : _muted, fontSize: 9.5, fontWeight: FontWeight.w700)),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
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

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, Colors.transparent])),
        ),
      );
}

class _VinylGroovesPainter extends CustomPainter {
  const _VinylGroovesPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final base = math.min(size.width, size.height) * 0.38;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.8..color = color;
    for (var i = 0; i < 8; i++) {
      final radius = base + (i * 5.1);
      if (radius < size.width / 2 - 2) canvas.drawCircle(center, radius, paint);
    }
    final shine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = const SweepGradient(colors: [Colors.transparent, Color(0x22FFFFFF), Colors.transparent, Color(0x11FFFFFF), Colors.transparent]).createShader(Offset.zero & size);
    canvas.drawCircle(center, size.width * 0.48, shine);
  }

  @override
  bool shouldRepaint(covariant _VinylGroovesPainter oldDelegate) => oldDelegate.color != color;
}
