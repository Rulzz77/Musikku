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
  });

  final List<LyricLine> lyrics;
  final bool loading;
  final bool synced;
  final ValueListenable<NativeYoutubeState>? nativeState;
  final Future<void> Function(Duration position) onSeek;

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
      final target = (index * 54.0) - 105.0;
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
      return const SizedBox(
        height: 180,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.lyrics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
        child: Text(
          'Lirik belum tersedia untuk lagu ini.',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    final current = widget.synced ? _currentIndex(position) : -1;
    if (current >= 0) _ensureVisible(current);

    return SizedBox(
      height: 300,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
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
                color: active
                    ? scheme.primaryContainer.withValues(alpha: 0.72)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                line.text,
                style: TextStyle(
                  fontSize: active ? 18 : 15,
                  height: 1.28,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                  color: active
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
            child: Row(
              children: [
                const Icon(Icons.lyrics_rounded, size: 20),
                const SizedBox(width: 8),
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
