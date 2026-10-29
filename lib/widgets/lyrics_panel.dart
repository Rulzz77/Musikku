import 'dart:ui' as ui;

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

  double _lineProgress(int index, Duration position) {
    if (index < 0 || index >= widget.lyrics.length) return 0;
    final startMs = widget.lyrics[index].time.inMilliseconds;
    int endMs;
    if (index + 1 < widget.lyrics.length) {
      final nextMs = widget.lyrics[index + 1].time.inMilliseconds;
      endMs = nextMs > startMs ? nextMs : startMs + 2500;
    } else {
      final durationMs = widget.nativeState?.value.duration.inMilliseconds ?? 0;
      final wordCount = widget.lyrics[index].text.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
      endMs = durationMs > startMs ? durationMs : startMs + (wordCount * 360).clamp(2500, 7000).toInt();
    }
    final span = (endMs - startMs).clamp(1, 1 << 30);
    return ((position.inMilliseconds - startMs) / span).clamp(0.0, 1.0).toDouble();
  }

  List<double> _wordProgresses(List<String> words, double lineProgress) {
    if (words.isEmpty) return const <double>[];
    // LRC sources generally expose line timestamps rather than word timestamps.
    // Allocate time by word length and add a small pause weight for punctuation;
    // this feels closer to vocal cadence than splitting every line evenly.
    final weights = words.map((word) {
      final lexicalLength = word.replaceAll(RegExp(r'[,.;:!?…]+$'), '').runes.length;
      var weight = lexicalLength.clamp(1, 12).toDouble();
      if (RegExp(r'[,;:]$').hasMatch(word)) weight += 0.45;
      if (RegExp(r'[.!?…]$').hasMatch(word)) weight += 0.8;
      return weight;
    }).toList(growable: false);
    final total = weights.fold<double>(0, (sum, value) => sum + value);
    var cursor = 0.0;
    final elapsed = lineProgress.clamp(0.0, 1.0) * total;
    return weights.map((weight) {
      final result = ((elapsed - cursor) / weight).clamp(0.0, 1.0).toDouble();
      cursor += weight;
      return result;
    }).toList(growable: false);
  }

  Widget _karaokeLine(
    BuildContext context,
    String text,
    double progress, {
    double fontSize = 21,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final words = text.trim().split(RegExp(r'\s+')).where((word) => word.isNotEmpty).toList(growable: false);
    if (words.isEmpty) return const SizedBox.shrink();
    final wordProgress = _wordProgresses(words, progress);
    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 1.30,
      fontWeight: FontWeight.w900,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.82),
    );
    final fillStyle = baseStyle.copyWith(color: scheme.primary);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 5,
      children: [
        for (var i = 0; i < words.length; i++)
          _KaraokeWord(
            key: ValueKey<String>('$i:${words[i]}'),
            text: words[i],
            progress: wordProgress[i],
            baseStyle: baseStyle,
            fillStyle: fillStyle,
          ),
      ],
    );
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
    // Blok lembut tanpa gradien, garis tepi, atau bayangan.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: widget.synced ? 0.15 : 0.07),
            scheme.surfaceContainerHigh.withValues(alpha: 0.66),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withValues(alpha: widget.synced ? 0.20 : 0.10)),
        boxShadow: [
          BoxShadow(color: scheme.primary.withValues(alpha: 0.045), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.synced) ...[
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      widget.synced ? 'SEDANG DINYANYIKAN' : 'LIRIK LAGU',
                      style: TextStyle(fontSize: 9.5, letterSpacing: 1.4, fontWeight: FontWeight.w800, color: scheme.primary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
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
                  child: widget.synced && index >= 0
                      ? KeyedSubtree(
                          key: ValueKey<int>(index),
                          child: _karaokeLine(context, line, _lineProgress(index, position), fontSize: 15),
                        )
                      : Text(
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
        final lyricProgress = active && widget.synced ? _lineProgress(index, position) : 0.0;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            color: active ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(17),
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
                child: active && widget.synced
                    ? _karaokeLine(context, line.text, lyricProgress)
                    : Text(line.text, textAlign: TextAlign.center),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A song change while the sheet stays open starts a fresh lyric timeline.
    // Reset the scroll sentinel so the new current line can auto-center again.
    if (!identical(oldWidget.lyrics, widget.lyrics) ||
        oldWidget.synced != widget.synced ||
        oldWidget.loading != widget.loading) {
      _lastIndex = -1;
    }
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          margin: widget.expandToAvailableHeight ? EdgeInsets.zero : const EdgeInsets.fromLTRB(14, 8, 14, 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.74),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withValues(alpha: 0.075),
                scheme.surfaceContainerLow.withValues(alpha: 0.80),
                scheme.secondary.withValues(alpha: 0.035),
              ],
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header: judul besar + status kecil, tanpa kotak ikon gradien.
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 18, 10),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Lirik', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -0.9)),
                        const SizedBox(height: 2),
                        Text(
                          widget.synced ? 'Lirik mengikuti posisi lagu' : 'Lirik untuk lagu ini',
                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (widget.synced)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.sync_rounded, size: 15, color: scheme.primary),
                      const SizedBox(width: 5),
                      Text('Sinkron', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: scheme.primary)),
                    ])
                  else
                    Text('TEKS', style: TextStyle(fontSize: 10.5, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
                ]),
              ),
          if (widget.synced && widget.lyrics.isNotEmpty && liveState != null)
            ValueListenableBuilder<NativeYoutubeState>(
              valueListenable: liveState,
              builder: (context, state, _) => _currentLyricBanner(context, state.position),
            ),
          if (widget.synced && widget.lyrics.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
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
        ),
      ),
    );
  }
}


/// Fills a word from left to right. Exact word timestamps are not supplied by
/// the current lyric model, so progress is interpolated across each synced line.
class _KaraokeWord extends StatefulWidget {
  const _KaraokeWord({
    super.key,
    required this.text,
    required this.progress,
    required this.baseStyle,
    required this.fillStyle,
  });

  final String text;
  final double progress;
  final TextStyle baseStyle;
  final TextStyle fillStyle;

  @override
  State<_KaraokeWord> createState() => _KaraokeWordState();
}

class _KaraokeWordState extends State<_KaraokeWord> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _from = 0;
  double _to = 0;

  double get _displayProgress => _from + ((_to - _from) * _controller.value);

  @override
  void initState() {
    super.initState();
    _from = widget.progress;
    _to = widget.progress;
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 140))..value = 1;
  }

  @override
  void didUpdateWidget(covariant _KaraokeWord oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.progress.clamp(0.0, 1.0).toDouble();
    if ((next - _to).abs() < 0.001) return;
    final current = _displayProgress;
    _from = current;
    _to = next;
    // Smaller duration when seeking backwards, but don't restart every frame
    // from zero. This interpolates from the most recent rendered fill amount.
    _controller.duration = next < current
        ? const Duration(milliseconds: 75)
        : const Duration(milliseconds: 145);
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.fillStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final wordWidth = painter.width;
    final wordHeight = painter.height;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final progress = _displayProgress.clamp(0.0, 1.0).toDouble();
        return SizedBox(
          width: wordWidth,
          height: wordHeight,
          child: Stack(
            alignment: Alignment.topLeft,
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Text(widget.text, style: widget.baseStyle, maxLines: 1, softWrap: false),
              ),
              if (progress > 0)
                Positioned(
                  left: 0,
                  top: 0,
                  width: wordWidth * progress,
                  height: wordHeight,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: wordWidth,
                      maxWidth: wordWidth,
                      minHeight: wordHeight,
                      maxHeight: wordHeight,
                      child: SizedBox(
                        width: wordWidth,
                        height: wordHeight,
                        child: Text(widget.text, style: widget.fillStyle, maxLines: 1, softWrap: false),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}