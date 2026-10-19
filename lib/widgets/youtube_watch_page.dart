import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/native_youtube_state.dart';
import '../models/player_ui_state.dart';
import '../models/loop_mode.dart';
import '../models/youtube_search_result.dart';
import 'channel_avatar.dart';
import 'live_badge.dart';
import 'lyrics_panel.dart';

class YoutubeWatchPage extends StatefulWidget {
  final YoutubeSearchResult video;
  final VoidCallback onBack;
  final VoidCallback? onPip;
  final Future<void> Function()? onPlayNext;
  final Future<void> Function(YoutubeSearchResult video) onPlay;
  final bool signedIn;
  final bool subscribed;
  final Future<void> Function(String channelId)? onSubscribe;
  final Future<void> Function(String videoId, String rating)? onRate;
  final void Function(String channelId, String title)? onOpenChannel;
  final Future<void> Function()? onToggleLandscape;
  final VoidCallback? onToggleShuffle;
  final VoidCallback? onToggleSmartShuffle;
  final VoidCallback? onCycleLoopMode;
  final bool shuffleEnabled;
  final bool smartShuffleEnabled;
  final LoopModeCustom loopMode;

  /// Posisi pemutar native; dipakai untuk sinkronisasi lirik.
  final ValueListenable<NativeYoutubeState>? nativeState;
  final ValueListenable<PlayerUiState>? playerUiState;
  final Future<void> Function(Duration position)? onSeekFromLyrics;

  const YoutubeWatchPage({
    super.key,
    required this.video,
    required this.onBack,
    this.onPip,
    required this.onPlay,
    required this.signedIn,
    required this.subscribed,
    this.onPlayNext,
    this.onSubscribe,
    this.onRate,
    this.onOpenChannel,
    this.onToggleLandscape,
    this.onToggleShuffle,
    this.onToggleSmartShuffle,
    this.onCycleLoopMode,
    this.shuffleEnabled = false,
    this.smartShuffleEnabled = false,
    this.loopMode = LoopModeCustom.off,
    this.nativeState,
    this.playerUiState,
    this.onSeekFromLyrics,
  });

  @override
  State<YoutubeWatchPage> createState() => _YoutubeWatchPageState();
}

class _YoutubeWatchPageState extends State<YoutubeWatchPage> {
  final GlobalKey _lyricsKey = GlobalKey();
  bool _descriptionExpanded = false;
  bool _subscribing = false;
  bool _subscribed = false;

  @override
  void initState() {
    super.initState();
    _subscribed = widget.subscribed;
  }

  String _formatViews(int value) {
    if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)} M';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} jt';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} rb';
    return value.toString();
  }


  Widget _channelRow() {
    final scheme = Theme.of(context).colorScheme;
    final channelTitle = widget.video.channelTitle;
    final channelId = widget.video.channelId.trim();
    final canOpen = widget.onOpenChannel != null && channelId.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: canOpen ? () => widget.onOpenChannel!(channelId, channelTitle) : null,
            child: Row(
              children: [
                ChannelAvatar(
                  channelId: channelId,
                  videoId: widget.video.videoId,
                  name: channelTitle,
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!widget.signedIn)
          const SizedBox.shrink()
        else
          FilledButton(
            onPressed: _subscribing || widget.onSubscribe == null || channelId.isEmpty
                ? null
                : () async {
                    setState(() => _subscribing = true);
                    try {
                      await widget.onSubscribe!(channelId);
                      if (mounted) setState(() => _subscribed = true);
                    } finally {
                      if (mounted) setState(() => _subscribing = false);
                    }
                  },
            style: FilledButton.styleFrom(
              backgroundColor: _subscribed
                  ? scheme.surfaceContainerHigh
                  : Colors.white,
              foregroundColor: _subscribed ? scheme.onSurface : Colors.black,
              disabledBackgroundColor: scheme.surfaceContainerHigh,
              disabledForegroundColor: scheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              minimumSize: const Size(0, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            child: Text(_subscribed ? 'Subscribed' : 'Subscribe'),
          ),
      ],
    );
  }

  void _scrollToLyrics() {
    if (_lyricsKey.currentContext != null) {
      Scrollable.ensureVisible(
        _lyricsKey.currentContext!,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lirik belum tersedia untuk video ini.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pageSize = MediaQuery.sizeOf(context);
    final isLandscape = pageSize.width > pageSize.height;
    final title = widget.video.title;
    final description = widget.video.description;
    final views = widget.video.viewCount;
    final isLive = widget.video.isLive || widget.video.liveStatus.isNotEmpty;

    if (isLandscape) {
      // Halaman ini tidak lagi memuat panel komentar/live chat. Player utama
      // tetap ditangani oleh pemutar MusikKu.
      return const SizedBox.shrink();
    }

    final statText = <String>[];
    if (views != null) statText.add('${_formatViews(views)} views');
    if (widget.video.publishedAt != null) {
      final publishedAt = widget.video.publishedAt!;
      statText.add('${publishedAt.day}/${publishedAt.month}/${publishedAt.year}');
    }

    return Material(
      color: scheme.surface,
      child: CustomScrollView(
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35))),
              ),
              child: Row(
                children: [
                  IconButton(onPressed: widget.onBack, icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Kembali'),
                  Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                  IconButton(onPressed: widget.onPip, tooltip: 'Mini player', icon: const Icon(Icons.picture_in_picture_alt_outlined)),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                            letterSpacing: -0.15,
                          ),
                        ),
                      ),
                      if (isLive) ...[
                        const SizedBox(width: 8),
                        LiveBadge(video: widget.video),
                      ],
                    ],
                  ),
                  if (statText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      statText.join(' • '),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Row(
                children: [Expanded(child: _channelRow())],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 64,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                scrollDirection: Axis.horizontal,
                itemCount: 6,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  late IconData icon;
                  late String label;
                  VoidCallback? action;
                  bool selected = false;
                  switch (index) {
                    case 0:
                      icon = Icons.shuffle_rounded;
                      label = widget.shuffleEnabled ? 'Shuffle' : 'Acak';
                      selected = widget.shuffleEnabled;
                      action = widget.onToggleShuffle;
                      break;
                    case 1:
                      icon = Icons.auto_awesome_rounded;
                      label = 'Smart';
                      selected = widget.smartShuffleEnabled;
                      action = widget.onToggleSmartShuffle;
                      break;
                    case 2:
                      icon = widget.loopMode == LoopModeCustom.one
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded;
                      label = switch (widget.loopMode) {
                        LoopModeCustom.off => 'Repeat',
                        LoopModeCustom.all => 'Repeat semua',
                        LoopModeCustom.one => 'Repeat satu',
                      };
                      selected = widget.loopMode != LoopModeCustom.off;
                      action = widget.onCycleLoopMode;
                      break;
                    case 3:
                      icon = Icons.lyrics_outlined;
                      label = 'Lirik';
                      action = _scrollToLyrics;
                      break;
                    case 4:
                      icon = Icons.picture_in_picture_alt_outlined;
                      label = 'Mini player';
                      action = widget.onPip;
                      break;
                    default:
                      icon = Icons.link_rounded;
                      label = 'Salin link';
                      action = () {
                        unawaited(Clipboard.setData(ClipboardData(text: 'https://youtu.be/${widget.video.videoId}')));
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan disalin')));
                      };
                  }
                  final child = FilledButton.tonalIcon(
                    onPressed: action,
                    icon: Icon(icon, size: 17),
                    label: Text(label),
                    style: FilledButton.styleFrom(
                      backgroundColor: selected
                          ? scheme.primary.withValues(alpha: 0.17)
                          : scheme.surfaceContainerLow,
                      foregroundColor: selected
                          ? scheme.primary
                          : scheme.onSurface,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 38),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  );
                  return child;
                },
              ),
            ),
          ),
          if (description.isNotEmpty)
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [const Icon(Icons.description_outlined, size: 18), const SizedBox(width: 8), const Expanded(child: Text('Deskripsi', style: TextStyle(fontWeight: FontWeight.w900))), Icon(_descriptionExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded)]),
                      const SizedBox(height: 7),
                      Text(description, maxLines: _descriptionExpanded ? null : 3, overflow: _descriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis, style: const TextStyle(height: 1.35, fontSize: 12.5)),
                    ]),
                  ),
                ),
              ),
            ),
          if (widget.playerUiState != null)
            SliverToBoxAdapter(
              child: ValueListenableBuilder<PlayerUiState>(
                valueListenable: widget.playerUiState!,
                builder: (context, state, _) {
                  if (state.video?.videoId != widget.video.videoId || (state.lyrics.isEmpty && !state.lyricsLoading)) return const SizedBox.shrink();
                  return KeyedSubtree(
                    key: _lyricsKey,
                    child: LyricsPanel(lyrics: state.lyrics, loading: state.lyricsLoading, synced: state.lyricsSynced, nativeState: widget.nativeState, onSeek: widget.onSeekFromLyrics ?? (_) async {}),
                  );
                },
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }

}

