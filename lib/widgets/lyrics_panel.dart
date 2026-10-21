import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/lyric.dart';
import '../models/native_youtube_state.dart';

/// Lirik ditempatkan di bawah detail video, bukan di atas video.
/// Dengan begitu player tetap menjadi fokus utama dan panel dapat ditutup atau
/// di-scroll tanpa mengganggu playback atau System PiP.
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

  /// Fill a bounded parent (for example, the full lyrics bottom sheet) instead
  /// of leaving an unused dark area below the fixed-height lyric list.
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
      final target = (index * 58.0) - (viewport / 2) + 26.0;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Widget _body(BuildContext context, Duration position) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.loading) {
      const loadingState = Center(child: CircularProgressIndicator());
      return widget.expandToAvailableHeight
          ? const Expanded(child: loadingState)
          : const SizedBox(height: 180, child: loadingState);
    }
    if (widget.lyrics.isEmpty) {
      final emptyState = Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Text(
            'Lirik belum tersedia untuk lagu ini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
      return widget.expandToAvailableHeight
          ? Expanded(child: emptyState)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Align(alignment: Alignment.centerLeft, child: emptyState),
            );
    }

    final current = widget.synced ? _currentIndex(position) : -1;
    if (current >= 0) _ensureVisible(current);

    final lyricList = ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(20, 72, 20, 72),
      itemCount: widget.lyrics.length,
      itemBuilder: (context, index) {
        final line = widget.lyrics[index];
        final active = index == current;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.synced ? () => widget.onSeek(line.time) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        scheme.primary.withValues(alpha: 0.04),
                        scheme.primary.withValues(alpha: 0.16),
                        scheme.secondary.withValues(alpha: 0.07),
                      ],
                    )
                  : null,
              color: active ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
              border: active
                  ? Border.all(color: scheme.primary.withValues(alpha: 0.22))
                  : Border.all(color: Colors.transparent),
            ),
            child: Text(
              line.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: active ? 23 : 17,
                height: 1.32,
                fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                color: active
                    ? scheme.primary
                    : scheme.onSurfaceVariant.withValues(alpha: index < current ? 0.50 : 0.82),
              ),
            ),
          ),
        );
      },
    );

    // The watch-page version remains a compact fixed-height card. The modal
    // player version expands the list to occupy the entire sheet height, so
    // the unused bottom region no longer looks like a separate black block.
    return widget.expandToAvailableHeight
        ? Expanded(child: lyricList)
        : SizedBox(height: 300, child: lyricList);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: widget.expandToAvailableHeight
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(14, 8, 14, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Theme.of(context).colorScheme.primary.withValues(alpha: 0.18), Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.lyrics_rounded, size: 19, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Lirik',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                if (widget.synced)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Sinkron', style: TextStyle(fontSize: 11)),
                    avatar: const Icon(Icons.sync_rounded, size: 14),
                  )
                else if (widget.lyrics.isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Teks', style: TextStyle(fontSize: 11)),
                    avatar: const Icon(Icons.notes_rounded, size: 14),
                  ),
              ],
            ),
          ),
          if (widget.nativeState != null)
            ValueListenableBuilder<NativeYoutubeState>(
              valueListenable: widget.nativeState!,
              builder: (context, state, _) => _body(context, state.position),
            )
          else
            _body(context, Duration.zero),
        ],
      ),
    );
  }
}
