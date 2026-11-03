import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lyric.dart';
import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/youtube_search_result.dart';
import '../widgets/album_artwork_image.dart';

/// Full-screen lyric space. Playback remains owned by HomePage.
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
  int _syncOffsetMs = 0;
  double _lyricsFontSize = 25;
  String _settingsVideoId = '';

  String _offsetKey(String videoId) => 'lyrics_sync_offset_${videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}_v1';

  Future<void> _loadTrackPreferences(String videoId) async {
    if (videoId.isEmpty || _settingsVideoId == videoId) return;
    _settingsVideoId = videoId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final offset = prefs.getInt(_offsetKey(videoId)) ?? 0;
      final font = prefs.getDouble('lyrics_font_size_v1') ?? 25.0;
      if (!mounted || _settingsVideoId != videoId) return;
      setState(() {
        _syncOffsetMs = offset.clamp(-8000, 8000).toInt();
        _lyricsFontSize = font.clamp(15.0, 32.0).toDouble();
      });
    } catch (_) {
      // Prefer default sync and font size if local preferences are unavailable.
    }
  }

  Future<void> _saveLyricsPreferences({int? offset, double? fontSize}) async {
    final prefs = await SharedPreferences.getInstance();
    if (offset != null) {
      final safe = offset.clamp(-8000, 8000).toInt();
      if (mounted) setState(() => _syncOffsetMs = safe);
      if (_trackedVideoId.isNotEmpty) await prefs.setInt(_offsetKey(_trackedVideoId), safe);
    }
    if (fontSize != null) {
      final safe = fontSize.clamp(15.0, 32.0).toDouble();
      if (mounted) setState(() => _lyricsFontSize = safe);
      await prefs.setDouble('lyrics_font_size_v1', safe);
    }
  }

  Future<void> _openLyricsSettings() async {
    var offset = _syncOffsetMs.toDouble();
    var fontSize = _lyricsFontSize;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Pengaturan lirik', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Sesuaikan waktu dan ukuran teks untuk lagu ini.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 18),
              Row(children: [const Expanded(child: Text('Sinkronisasi manual', style: TextStyle(fontWeight: FontWeight.w800))), Text('${offset.round()} ms', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900))]),
              Slider(
                value: offset, min: -8000, max: 8000, divisions: 160,
                label: '${offset.round()} ms',
                onChanged: (value) => setSheetState(() => offset = value),
              ),
              Row(children: [const Expanded(child: Text('Ukuran teks', style: TextStyle(fontWeight: FontWeight.w800))), Text('${fontSize.round()} px', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900))]),
              Slider(
                value: fontSize, min: 15, max: 32, divisions: 17,
                label: '${fontSize.round()} px',
                onChanged: (value) => setSheetState(() => fontSize = value),
              ),
              Row(children: [
                TextButton(onPressed: () => setSheetState(() { offset = 0; fontSize = 25; }), child: const Text('Reset')),
                const Spacer(),
                FilledButton(onPressed: () async {
                  await _saveLyricsPreferences(offset: offset.round(), fontSize: fontSize);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                }, child: const Text('Simpan')),
              ]),
            ]),
          );
        },
      ),
    );
  }

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
        alignment: 0.47,
        duration: const Duration(milliseconds: 460),
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
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<PlayerUiState>(
      valueListenable: widget.playerUiState,
      builder: (context, player, _) {
        final activeVideo = player.video ?? widget.video;
        unawaited(_loadTrackPreferences(activeVideo.videoId));
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
              if (mounted && _scrollController.hasClients) _scrollController.jumpTo(0);
            });
          }
        }

        return Scaffold(
          backgroundColor: scheme.surface,
          body: SafeArea(
            child: ValueListenableBuilder<NativeYoutubeState>(
              valueListenable: widget.nativeState,
              builder: (context, native, _) {
                final position = native.videoId.isEmpty || native.videoId == activeVideo.videoId
                    ? native.position
                    : Duration.zero;
                final duration = native.duration;
                final lyricPosition = position + Duration(milliseconds: _syncOffsetMs);
                final currentIndex = player.lyricsSynced ? _currentLine(lyrics, lyricPosition) : -1;
                if (currentIndex >= 0) _centerLine(currentIndex);
                final progress = duration.inMilliseconds > 0
                    ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble()
                    : 0.0;

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                      child: Row(
                        children: [
                          _LyricsIconButton(
                            icon: Icons.arrow_back_rounded,
                            tooltip: 'Kembali ke pemutar',
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('LISTEN CLOSER', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
                                const SizedBox(height: 3),
                                Text('Ruang lirik', style: TextStyle(color: scheme.onSurface, fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                              ],
                            ),
                          ),
                          _LyricsStatus(isPlaying: native.isEffectivelyPlaying),
                          const SizedBox(width: 7),
                          _LyricsIconButton(
                            icon: Icons.tune_rounded,
                            tooltip: 'Pengaturan lirik',
                            onTap: _openLyricsSettings,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(13),
                            child: AlbumArtworkImage(track: activeVideo, width: 58, height: 58, fit: BoxFit.cover),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(activeVideo.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 14, height: 1.18, fontWeight: FontWeight.w900, letterSpacing: -0.2)),
                                const SizedBox(height: 4),
                                Text(activeVideo.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 22),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                      child: Row(
                        children: [
                          Text('SING WITH THE MOMENT', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                          const Spacer(),
                          Text(player.lyricsSynced ? 'SYNCED · ${_syncOffsetMs}MS' : 'UNSYNCED', style: TextStyle(color: player.lyricsSynced ? scheme.primary : scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _buildLyricsContent(
                        context,
                        player: player,
                        lyrics: lyrics,
                        currentIndex: currentIndex,
                        loading: player.lyricsLoading,
                        fontSize: _lyricsFontSize,
                        syncOffsetMs: _syncOffsetMs,
                        scheme: scheme,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 17),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(_formatTime(position), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w800)),
                              const Spacer(),
                              Text(_formatTime(duration), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              value: progress,
                              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.52),
                              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            player.lyricsSynced ? 'Ketuk satu baris untuk menuju bagian lagu itu' : 'Lirik mengikuti lagu ketika sinkronisasi tersedia',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildLyricsContent(
    BuildContext context, {
    required PlayerUiState player,
    required List<LyricLine> lyrics,
    required int currentIndex,
    required bool loading,
    required double fontSize,
    required int syncOffsetMs,
    required ColorScheme scheme,
  }) {
    if (loading && lyrics.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.2, color: scheme.primary)),
            const SizedBox(height: 13),
            Text('Mencari lirik…', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
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
              Icon(Icons.notes_rounded, color: scheme.primary, size: 42),
              const SizedBox(height: 14),
              Text('Belum ada lirik', style: TextStyle(color: scheme.onSurface, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('Lirik akan muncul di sini ketika ditemukan untuk lagu ini.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.45)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 30, 24, 38),
      itemCount: lyrics.length,
      itemBuilder: (context, index) {
        final line = lyrics[index];
        final active = index == currentIndex;
        final past = currentIndex >= 0 && index < currentIndex;
        return Padding(
          key: _lineKeys[index],
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: InkWell(
            onTap: player.lyricsSynced
                ? () {
                    final target = line.time - Duration(milliseconds: syncOffsetMs);
                    widget.onSeek(target.isNegative ? Duration.zero : target);
                  }
                : null,
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(left: active ? 14 : 0, top: 3, bottom: 3),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: active ? scheme.primary : Colors.transparent, width: 3.5)),
              ),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: active ? scheme.primary : scheme.onSurface.withValues(alpha: past ? 0.28 : 0.66),
                  fontSize: active ? fontSize : fontSize * 0.72,
                  height: 1.28,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                  letterSpacing: active ? -0.65 : -0.25,
                ),
                child: Text(line.text, textAlign: TextAlign.left),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LyricsIconButton extends StatelessWidget {
  const _LyricsIconButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(width: 42, height: 42, child: Icon(icon, color: scheme.onSurface, size: 20)),
        ),
      ),
    );
  }
}

class _LyricsStatus extends StatelessWidget {
  const _LyricsStatus({required this.isPlaying});
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: isPlaying ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPlaying ? Icons.graphic_eq_rounded : Icons.pause_rounded, size: 13, color: isPlaying ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(isPlaying ? 'LIVE' : 'PAUSE', style: TextStyle(color: isPlaying ? scheme.onPrimaryContainer : scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
        ],
      ),
    );
  }
}
