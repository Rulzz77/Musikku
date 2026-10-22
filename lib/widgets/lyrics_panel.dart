import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/lyric.dart';
import '../models/native_youtube_state.dart';

/// Karaoke-style lyric surface used by the now-playing sheet.
/// It follows playback position, lets synced lines seek, and keeps the
/// compact watch-page variant bounded.
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.lyrics,
    required this.loading,
    required this.synced,
    this.nativeState,
    required this.onSeek,
    this.expandToAvailableHeight = false,
  });

  final List<LyricLine> lyrics;
  final bool loading;
  final bool synced;
  final ValueListenable<NativeYoutubeState>? nativeState;
  final Future<void> Function(Duration position) onSeek;
  final bool expandToAvailableHeight;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  final ScrollController _scroll = ScrollController();
  int _lastIndex = -1;

  int _currentIndex(Duration position) {
    if (widget.lyrics.isEmpty) return -1;
    var low = 0;
    var high = widget.lyrics.length - 1;
    var answer = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (widget.lyrics[mid].time <= position) {
        answer = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return answer;
  }

  void _ensureVisible(int index) {
    if (index < 0 || index >= widget.lyrics.length || index == _lastIndex) return;
    _lastIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final viewport = _scroll.position.viewportDimension;
      final target = (index * 60.0) - (viewport / 2) + 28.0;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _currentLyricBanner(BuildContext context, Duration position) {
    final scheme = Theme.of(context).colorScheme;
    final index = widget.synced ? _currentIndex(position) : -1;
    final line = index >= 0 ? widget.lyrics[index].text : 'Lirik akan mengikuti pemutaran';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.19),
            scheme.secondary.withValues(alpha: 0.09),
            scheme.surfaceContainerHighest.withValues(alpha: 0.58),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.08), blurRadius: 22, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.synced ? 'SEDANG DINYANYIKAN' : 'LIRIK LAGU',
                  style: TextStyle(fontSize: 9.5, letterSpacing: 1.25, fontWeight: FontWeight.w900, color: scheme.primary),
                ),
                const SizedBox(height: 5),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    line,
                    key: ValueKey<int>(index),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, height: 1.25, fontWeight: FontWeight.w800, color: scheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          if (widget.synced)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text('LIVE', style: TextStyle(fontSize: 9, letterSpacing: 0.6, color: scheme.primary, fontWeight: FontWeight.w900)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _lyricsBody(BuildContext context, Duration position) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.loading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: scheme.primary)),
          const SizedBox(height: 12),
          Text('Mencari lirik…', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ]),
      );
    }
    if (widget.lyrics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(Icons.lyrics_outlined, color: scheme.primary, size: 27),
            ),
            const SizedBox(height: 12),
            const Text('Lirik belum tersedia', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 4),
            Text('Coba lagu lain atau periksa lagi setelah metadata tersedia.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.35)),
          ]),
        ),
      );
    }

    final current = widget.synced ? _currentIndex(position) : -1;
    if (current >= 0) _ensureVisible(current);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      itemCount: widget.lyrics.length,
      itemBuilder: (context, index) {
        final line = widget.lyrics[index];
        final active = index == current;
        final passed = current > index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            gradient: active
                ? LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [scheme.primary.withValues(alpha: 0.20), scheme.secondary.withValues(alpha: 0.07)],
                  )
                : null,
            color: active ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: active ? scheme.primary.withValues(alpha: 0.24) : Colors.transparent),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: widget.synced ? () => widget.onSeek(line.time) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: active ? 21 : 16,
                  height: 1.30,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                  color: active ? scheme.primary : scheme.onSurfaceVariant.withValues(alpha: passed ? 0.46 : 0.82),
                ),
                child: Text(line.text, textAlign: TextAlign.center),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liveState = widget.nativeState;
    final position = liveState?.value.position ?? Duration.zero;

    return Container(
      margin: widget.expandToAvailableHeight ? EdgeInsets.zero : const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surfaceContainerLow.withValues(alpha: 0.96), scheme.surface, scheme.surfaceContainerLow.withValues(alpha: 0.92)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 16, 12),
            child: Row(children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [scheme.primary, scheme.secondary]),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.lyrics_rounded, size: 22, color: scheme.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Lirik', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.45)),
                const SizedBox(height: 3),
                Text(widget.synced ? 'Lirik mengikuti posisi lagu' : 'Lirik untuk lagu ini', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ])),
              if (widget.synced)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.sync_rounded, size: 14, color: scheme.primary), const SizedBox(width: 5), Text('Sinkron', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: scheme.primary))]),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(99)),
                  child: Text('TEKS', style: TextStyle(fontSize: 10, letterSpacing: 0.6, fontWeight: FontWeight.w900, color: scheme.onSurfaceVariant)),
                ),
            ]),
          ),
          if (widget.synced && widget.lyrics.isNotEmpty && liveState != null)
            ValueListenableBuilder<NativeYoutubeState>(
              valueListenable: liveState,
              builder: (context, state, _) => _currentLyricBanner(context, state.position),
            ),
          if (widget.synced && widget.lyrics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 7),
              child: Row(children: [
                Icon(Icons.touch_app_rounded, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(child: Text('Ketuk baris untuk melompat ke bagian lagu itu', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant))),
              ]),
            ),
          if (liveState != null)
            ValueListenableBuilder<NativeYoutubeState>(
              valueListenable: liveState,
              builder: (context, state, _) {
                final body = _lyricsBody(context, state.position);
                return widget.expandToAvailableHeight
                    ? Expanded(child: body)
                    : SizedBox(height: widget.loading || widget.lyrics.isEmpty ? 190 : 300, child: body);
              },
            )
          else
            (widget.expandToAvailableHeight
                ? Expanded(child: _lyricsBody(context, position))
                : SizedBox(height: widget.loading || widget.lyrics.isEmpty ? 190 : 300, child: _lyricsBody(context, position))),
        ],
      ),
    );
  }
}
