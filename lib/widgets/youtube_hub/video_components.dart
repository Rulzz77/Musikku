part of '../youtube_hub.dart';

// The state extensions share private UI logic; State.setState is used by this library.
// ignore_for_file: invalid_use_of_protected_member

extension _YoutubeHubVideoComponents on _YoutubeHubState {
  String _artistLabelFromTrackTitle(YoutubeSearchResult video) =>
      MusicTitleFormatter.artistLabel(
        title: video.title,
        channelTitle: video.channelTitle,
      );

  Widget _sampleCard(YoutubeSearchResult video) {
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = widget.currentVideoId == video.videoId;
    return SizedBox(
      width: 188,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(widget.onPlay(video)),
          onLongPress: widget.onShowVideoMenu == null ? null : () => widget.onShowVideoMenu!(video),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    UnifiedArtwork(track: video, fit: BoxFit.cover, iconSize: 42),
                    const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xC9000000)]))),
                    Positioned(left: 10, right: 8, bottom: 10, child: Row(children: [Expanded(child: Text(MusicTitleFormatter.clean(video.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, height: 1.15))), const SizedBox(width: 6), Icon(isCurrent ? Icons.graphic_eq_rounded : Icons.play_circle_fill_rounded, color: Colors.white, size: 29)])),
                    Positioned(right: 4, top: 4, child: Material(color: Colors.black.withValues(alpha: 0.45), shape: const CircleBorder(), child: IconButton(tooltip: 'Opsi lagu', visualDensity: VisualDensity.compact, onPressed: widget.onShowVideoMenu == null ? null : () => widget.onShowVideoMenu!(video), icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 19)))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  children: [
                    Expanded(child: Text(_artistLabelFromTrackTitle(video), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w700))),
                    IconButton(tooltip: 'Tambahkan ke antrean', visualDensity: VisualDensity.compact, onPressed: () => widget.onAddToQueue(video), icon: const Icon(Icons.queue_music_rounded, size: 20)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar({String? title}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 4, 10, 4),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                semanticLabel: 'Logo MusikKu',
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title ?? appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.7),
              ),
            ),
            IconButton(
              tooltip: 'Cari',
              visualDensity: VisualDensity.compact,
              onPressed: _openSearch,
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? action, VoidCallback? onAction}) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(17, 20, 12, 10),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 23,
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [scheme.primary, scheme.secondary]),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.55, height: 1.15)),
            ),
            if (action != null) TextButton(onPressed: onAction, style: TextButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(action, style: const TextStyle(fontWeight: FontWeight.w800))),
            if (action == null) Icon(Icons.auto_awesome_rounded, size: 17, color: scheme.primary.withValues(alpha: 0.70)),
          ],
        ),
      ),
    );
  }

  Widget _videoCard(YoutubeSearchResult video) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (widget.watchProgress[video.videoId] ?? 0).clamp(0.0, 1.0).toDouble();
    final timeLabel = _watchTimeLabel(video);
    final artistLabel = _artistLabelFromTrackTitle(video);
    final isCurrent = widget.currentVideoId == video.videoId;

    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('flow-song-${video.videoId}'),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      child: Material(
        color: isCurrent ? scheme.primaryContainer.withValues(alpha: 0.50) : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isCurrent ? scheme.primary.withValues(alpha: 0.48) : scheme.outlineVariant.withValues(alpha: 0.28), width: isCurrent ? 1.35 : 0.7),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(widget.onPlay(video)),
          onLongPress: widget.onShowVideoMenu == null ? null : () => widget.onShowVideoMenu!(video),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  height: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        UnifiedArtwork(track: video, fit: BoxFit.cover, iconSize: 32),
                        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: 0.03), Colors.black.withValues(alpha: 0.40)]))),
                        Center(
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: isCurrent ? scheme.primary : Colors.black.withValues(alpha: 0.53), border: Border.all(color: Colors.white.withValues(alpha: 0.72), width: 1.1)),
                            child: Icon(isCurrent ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
                          ),
                        ),
                        if (video.liveStatus.isNotEmpty) Positioned(left: 4, top: 4, child: LiveBadge(video: video)),
                        if (timeLabel.isNotEmpty)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.78), borderRadius: BorderRadius.circular(5)),
                              child: Text(timeLabel, style: const TextStyle(color: Colors.white, fontSize: 7.5, fontWeight: FontWeight.w800)),
                            ),
                          ),
                        if (progress > 0)
                          Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: progress, minHeight: 2.5, backgroundColor: Colors.white.withValues(alpha: 0.30), valueColor: AlwaysStoppedAnimation<Color>(scheme.primary))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isCurrent) ...[
                        Row(children: [Icon(Icons.volume_up_rounded, size: 12, color: scheme.primary), const SizedBox(width: 4), Text('SEDANG DIPUTAR', style: TextStyle(color: scheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.7))]),
                        const SizedBox(height: 3),
                      ],
                      Text(MusicTitleFormatter.clean(video.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.2)),
                      const SizedBox(height: 5),
                      Text(artistLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(_metaLine(video), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.84), fontSize: 9.5)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Opsi lagu',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onShowVideoMenu == null ? null : () => widget.onShowVideoMenu!(video),
                  icon: const Icon(Icons.more_vert_rounded, size: 21),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _quickPickCard(YoutubeSearchResult video) {
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = widget.currentVideoId == video.videoId;
    return SizedBox(
      width: 152,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isCurrent ? scheme.primary.withValues(alpha: 0.42) : scheme.outlineVariant.withValues(alpha: 0.26))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(widget.onPlay(video)),
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 123,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        UnifiedArtwork(track: video, fit: BoxFit.cover, iconSize: 34),
                        DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withValues(alpha: 0.42)]))),
                        Positioned(
                          left: 7,
                          top: 7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.50), borderRadius: BorderRadius.circular(999)),
                            child: const Text('PUTAR LAGI', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.65)),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Container(
                            margin: const EdgeInsets.all(7),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: isCurrent ? scheme.primary : Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8)]),
                            child: Icon(isCurrent ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, color: isCurrent ? Colors.white : scheme.primary, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(MusicTitleFormatter.clean(video.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 11, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.1)),
                const SizedBox(height: 3),
                Text(_artistLabelFromTrackTitle(video), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _watchTimeLabel(YoutubeSearchResult video) {
    final progress = (widget.watchProgress[video.videoId] ?? 0).clamp(0.0, 1.0).toDouble();
    final duration = widget.watchDuration[video.videoId] ?? video.durationSeconds ?? 0.0;
    if (duration <= 0) return '';
    if (progress <= 0) return _formatTime(duration.round());
    final elapsed = (duration * progress).round();
    return '${_formatTime(elapsed)} / ${_formatTime(duration.round())}';
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final mins = minutes % 60;
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  String _metaLine(YoutubeSearchResult video) {
    final bits = <String>[];
    final views = video.viewCount;
    final liveLine = liveMetaLine(video, _formatViews);
    if (liveLine.isNotEmpty) {
      bits.add(liveLine);
    } else if (views != null) {
      bits.add('${_formatViews(views)} ditonton');
    }
    if (video.publishedAt != null && !video.isLive && !video.isUpcoming) {
      final days = DateTime.now().difference(video.publishedAt!).inDays;
      if (days <= 0) {
        bits.add('hari ini');
      } else if (days < 7) {
        bits.add('$days hari lalu');
      } else if (days < 30) {
        bits.add('${days ~/ 7} minggu lalu');
      } else if (days < 365) {
        bits.add('${days ~/ 30} bulan lalu');
      } else {
        bits.add('${days ~/ 365} tahun lalu');
      }
    }
    return bits.isEmpty ? 'YouTube' : bits.join(' • ');
  }

  String _formatViews(int value) {
    if (value >= 1000000000) return '${(value / 1000000000).toStringAsFixed(1)} M';
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} jt';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)} rb';
    return value.toString();
  }
}
