part of '../youtube_hub.dart';

// The state extensions share private UI logic; State.setState is used by this library.
// ignore_for_file: invalid_use_of_protected_member

extension _YoutubeHubVideoComponents on _YoutubeHubState {
  Widget _sampleCard(YoutubeSearchResult video) {
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = widget.currentVideoId == video.videoId;
    return SizedBox(
      width: 176,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
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
                    UnifiedArtwork(track: video, fit: BoxFit.cover, iconSize: 40),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Container(
                        margin: const EdgeInsets.all(10),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
                        child: Icon(isCurrent ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, color: scheme.onPrimary, size: 19),
                      ),
                    ),
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Material(
                        color: scheme.surface.withValues(alpha: 0.88),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Opsi lagu',
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onShowVideoMenu == null ? null : () => widget.onShowVideoMenu!(video),
                          icon: Icon(Icons.more_horiz_rounded, color: scheme.onSurface, size: 19),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(MusicTitleFormatter.clean(video.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800, fontSize: 12, height: 1.18)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(child: Text(video.channelTitle.isEmpty ? 'Musik' : video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, fontWeight: FontWeight.w600))),
                        IconButton(
                          tooltip: 'Tambahkan ke antrean',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            widget.onAddToQueue(video);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ditambahkan ke antrean: ${video.title}'), duration: const Duration(seconds: 2)));
                          },
                          icon: Icon(Icons.add_rounded, color: scheme.primary, size: 19),
                        ),
                      ],
                    ),
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
    final scheme = Theme.of(context).colorScheme;
    final label = title ?? appName;
    final icon = switch (label) {
      'Radio' => Icons.radio_rounded,
      'Jelajahi' => Icons.explore_rounded,
      'Koleksi' => Icons.library_music_rounded,
      _ => Icons.music_note_rounded,
    };
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(19, MediaQuery.paddingOf(context).top + 14, 18, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(color: scheme.primary, borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15), bottomRight: Radius.circular(15), bottomLeft: Radius.circular(5))),
              child: Icon(icon, color: scheme.onPrimary, size: 23),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('MUSIKKU  /  YOUR DAILY SOUND', style: TextStyle(color: scheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.05)),
                  const SizedBox(height: 3),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.9)),
                ],
              ),
            ),
            Material(
              color: scheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: IconButton(
                tooltip: 'Cari musik',
                visualDensity: VisualDensity.compact,
                onPressed: _openSearch,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(width: 7),
            Material(
              color: scheme.surfaceContainerHigh,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: IconButton(
                tooltip: 'Pengaturan',
                visualDensity: VisualDensity.compact,
                onPressed: _showAppSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
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
        padding: const EdgeInsets.fromLTRB(19, 25, 16, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 4, height: 20, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(5))),
            const SizedBox(width: 9),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.55, height: 1.05))),
            if (action != null)
              TextButton(onPressed: onAction, style: TextButton.styleFrom(foregroundColor: scheme.primary, visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4)), child: Text(action, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
  }


  Widget _videoCard(YoutubeSearchResult video) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (widget.watchProgress[video.videoId] ?? 0).clamp(0.0, 1.0).toDouble();
    final timeLabel = _watchTimeLabel(video);
    final channel = video.channelTitle.trim();
    final isCurrent = widget.currentVideoId == video.videoId;
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('flow-song-${video.videoId}'),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(opacity: value.clamp(0.0, 1.0).toDouble(), child: Transform.translate(offset: Offset(0, 6 * (1 - value)), child: child)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          color: isCurrent ? scheme.primaryContainer.withValues(alpha: 0.42) : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => unawaited(widget.onPlay(video)),
            onLongPress: widget.onShowVideoMenu == null ? null : () => widget.onShowVideoMenu!(video),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(
                    width: 66,
                    height: 66,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          UnifiedArtwork(track: video, fit: BoxFit.cover, iconSize: 25),
                          if (timeLabel.isNotEmpty)
                            Positioned(right: 4, bottom: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.76), borderRadius: BorderRadius.circular(4)), child: Text(timeLabel, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800)))),
                          if (progress > 0)
                            Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: progress, minHeight: 2.5, backgroundColor: Colors.white.withValues(alpha: 0.28), valueColor: AlwaysStoppedAnimation<Color>(scheme.primary))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isCurrent) ...[Text('SEDANG DIPUTAR', style: TextStyle(color: scheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.85)), const SizedBox(height: 3)],
                        Text(MusicTitleFormatter.clean(video.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 13, fontWeight: FontWeight.w800, height: 1.18, letterSpacing: -0.2)),
                        const SizedBox(height: 4),
                        Text(channel.isEmpty ? 'Musik' : channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(_metaLine(video), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.82), fontSize: 9.3)),
                      ],
                    ),
                  ),
                  if (video.channelId.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(left: 5), child: ChannelAvatar(channelId: video.channelId, videoId: video.videoId, name: channel, radius: 11, onTap: () => _handleControllerOpenChannel(video.channelId, channel, ''))),
                  IconButton(tooltip: 'Opsi lagu', visualDensity: VisualDensity.compact, onPressed: widget.onShowVideoMenu == null ? null : () => widget.onShowVideoMenu!(video), icon: Icon(Icons.more_vert_rounded, size: 20, color: scheme.onSurfaceVariant)),
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
      width: 148,
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: isCurrent ? scheme.primary.withValues(alpha: 0.5) : scheme.outlineVariant.withValues(alpha: 0.55))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(widget.onPlay(video)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    UnifiedArtwork(track: video, fit: BoxFit.cover, iconSize: 30),
                    Positioned(left: 8, top: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)), child: Text('PILIHAN', style: TextStyle(color: scheme.onSurface, fontSize: 7, fontWeight: FontWeight.w900, letterSpacing: 0.6)))),
                    Positioned(right: 8, bottom: 8, child: Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(9)), child: Icon(isCurrent ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded, color: scheme.onPrimary, size: 17))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(MusicTitleFormatter.clean(video.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 10.5, fontWeight: FontWeight.w800, height: 1.16)),
                    const SizedBox(height: 4),
                    Text(video.channelTitle.isEmpty ? 'Musik' : video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
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
