import 'dart:async';

import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';
import '../services/youtube_public_channel_service.dart';
import '../models/youtube_channel_models.dart';
import '../services/youtube_search_service.dart';
import '../widgets/live_badge.dart';

String _channelErrorMessage(Object error) {
  final message = error.toString().replaceFirst('Bad state: ', '').trim();
  if (message.isEmpty) return 'Gagal memuat channel. Periksa koneksi lalu coba lagi.';
  return message;
}

/// 1200 -> "1,2 rb", 3400000 -> "3,4 jt" (format YouTube Indonesia).
String formatCount(int value) {
  String fmt(double x, String unit) {
    final text = x.toStringAsFixed(x >= 100 ? 0 : 1)
        .replaceAll('.', ',')
        .replaceAll(RegExp(r',0$'), '');
    return '$text $unit';
  }

  if (value >= 1000000000) return fmt(value / 1000000000, 'M');
  if (value >= 1000000) return fmt(value / 1000000, 'jt');
  if (value >= 1000) return fmt(value / 1000, 'rb');
  return '$value';
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'baru saja';
  if (diff.inHours < 1) return '${diff.inMinutes} menit lalu';
  if (diff.inDays < 1) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7} minggu lalu';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30} bulan lalu';
  return '${diff.inDays ~/ 365} tahun lalu';
}

/// Halaman channel publik: banner, metadata, video musik, live, dan Tentang.
/// Tidak membutuhkan login akun Google.
class YoutubeChannelPage extends StatefulWidget {
  final String channelId;
  final String title;
  final String thumbnailUrl;
  final Future<void> Function(YoutubeSearchResult video) onPlay;

  /// Kalau diisi, halaman ini tampil sebagai lapisan DI DALAM hub (bukan
  /// route baru). Memutar video tidak menutup halaman ini, jadi tombol Back
  /// dari video kembali ke channel yang sama, bukan ke beranda.
  final VoidCallback? onClose;

  const YoutubeChannelPage({
    super.key,
    required this.channelId,
    required this.onPlay,
    this.title = '',
    this.thumbnailUrl = '',
    this.onClose,
  });

  @override
  State<YoutubeChannelPage> createState() => _YoutubeChannelPageState();
}

class _YoutubeChannelPageState extends State<YoutubeChannelPage> {
  final _channelService = YoutubePublicChannelService.instance;
  YoutubeChannelDetails? _details;
  List<YoutubeSearchResult> _videos = const [];
  bool _loading = true;
  String _error = '';
  int _tab = 0;

  static const int _pageSize = 30;

  /// false = terbaru dulu (urutan asli upload), true = terlama dulu.
  bool _oldestFirst = false;
  bool _sorting = false;
  bool _loadingMore = false;
  String _uploadsId = '';

  // Terbaru: halaman berikutnya diambil dari API lewat token.
  String? _nextToken;

  // Terlama: seluruh upload ditelusuri sekali, dibalik, lalu ditampilkan
  // bertahap (statistik penonton hanya diambil untuk yang tampil).
  List<YoutubeSearchResult> _oldestPool = const [];
  int _oldestShown = 0;
  bool _oldestComplete = false;
  int _sortRequestId = 0;

  // Tab Live: live sekarang, jadwal, dan rekaman live. Halaman pertama upload
  // sudah membawa status live, sisanya ditelusuri saat tab dibuka.
  List<YoutubeSearchResult> _liveItems = const [];
  String? _liveToken;
  bool _liveScanned = false;
  bool _liveLoading = false;
  String _liveError = '';

  bool get _hasMore => _oldestFirst ? _oldestShown < _oldestPool.length : _nextToken != null;

  bool _isMusicChannelUpload(YoutubeSearchResult video) =>
      YoutubeSearchService.isMusicChannelUpload(
        video,
        channelTitle: _details?.title.isNotEmpty == true
            ? _details!.title
            : widget.title,
        channelDescription: _details?.description ?? '',
      );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final details = await _channelService.channelDetails(widget.channelId);
      if (!mounted) return;
      setState(() => _details = details);

      final uploads = details?.uploadsPlaylistId ?? '';
      _uploadsId = uploads;
      var videos = const <YoutubeSearchResult>[];
      String? token;
      if (uploads.isNotEmpty) {
        final page = await _channelService.playlistItemsPage(uploads, maxResults: _pageSize);
        token = page.nextPageToken;
        final musicOnly = (await _channelService.withViewCounts(page.items))
            .where(_isMusicChannelUpload)
            .toList(growable: false);
        videos = await YoutubeSearchService().removeShorts(musicOnly);
      }
      if (!mounted) return;
      setState(() {
        _videos = videos;
        _nextToken = token;
        _liveItems = videos.where((v) => v.liveStatus.isNotEmpty).toList(growable: false);
        _liveToken = token;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _channelErrorMessage(e);
      });
    }
  }

  /// Telusuri upload yang lebih lama untuk menemukan live & rekaman live.
  Future<void> _scanMoreLive() async {
    if (_liveLoading || _uploadsId.isEmpty) return;
    if (_liveScanned && _liveToken == null) return;
    setState(() {
      _liveLoading = true;
      _liveError = '';
    });
    try {
      final result = await _channelService.scanLiveVideos(
        _uploadsId,
        pageToken: _liveToken,
        channelTitle: _details?.title.isNotEmpty == true ? _details!.title : widget.title,
        channelDescription: _details?.description ?? '',
      );
      if (!mounted) return;
      final known = _liveItems.map((v) => v.videoId).toSet();
      setState(() {
        _liveItems = [
          ..._liveItems,
          ...result.items.where((video) =>
              !known.contains(video.videoId) && _isMusicChannelUpload(video)),
        ];
        _liveToken = result.nextPageToken;
        _liveScanned = true;
      });
    } catch (e) {
      if (mounted) setState(() => _liveError = _channelErrorMessage(e));
    } finally {
      if (mounted) setState(() => _liveLoading = false);
    }
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (index == 1 && !_liveScanned && !_liveLoading && _liveToken != null) {
      unawaited(_scanMoreLive());
    }
  }

  Future<void> _setSort(bool oldestFirst) async {
    if (_oldestFirst == oldestFirst || _sorting) return;
    final requestId = ++_sortRequestId;
    setState(() {
      _oldestFirst = oldestFirst;
      _error = '';
    });
    if (_uploadsId.isEmpty) return;

    setState(() => _sorting = true);
    try {
      if (oldestFirst) {
        // Telusuri semua halaman upload (1 unit kuota per 50 video).
        if (!_oldestComplete) {
          final all = <YoutubeSearchResult>[];
          String? token;
          var guard = 0;
          do {
            final page = await _channelService.playlistItemsPage(_uploadsId, pageToken: token);
            all.addAll(page.items);
            token = page.nextPageToken;
            guard++;
          } while (token != null && guard < 60);
          _oldestPool = all.reversed.toList(growable: false);
          _oldestComplete = true;
        }
        final first = _oldestPool.take(_pageSize).toList(growable: false);
        final musicOnly = (await _channelService.withViewCounts(first))
            .where(_isMusicChannelUpload)
            .toList(growable: false);
        final withStats = await YoutubeSearchService().removeShorts(musicOnly);
        if (!mounted || requestId != _sortRequestId) return;
        setState(() {
          _videos = withStats;
          _oldestShown = first.length;
        });
      } else {
        final page = await _channelService.playlistItemsPage(_uploadsId, maxResults: _pageSize);
        final musicOnly = (await _channelService.withViewCounts(page.items))
            .where(_isMusicChannelUpload)
            .toList(growable: false);
        final withStats = await YoutubeSearchService().removeShorts(musicOnly);
        if (!mounted || requestId != _sortRequestId) return;
        setState(() {
          _videos = withStats;
          _nextToken = page.nextPageToken;
        });
      }
    } catch (e) {
      if (!mounted || requestId != _sortRequestId) return;
      setState(() {
        _oldestFirst = !oldestFirst; // kembalikan pilihan lama kalau gagal
        _error = _channelErrorMessage(e);
      });
    } finally {
      if (mounted && requestId == _sortRequestId) {
        setState(() => _sorting = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _sorting || !_hasMore) return;
    final requestId = _sortRequestId;
    setState(() => _loadingMore = true);
    try {
      List<YoutubeSearchResult> more;
      if (_oldestFirst) {
        final next = _oldestPool.skip(_oldestShown).take(_pageSize).toList(growable: false);
        final musicOnly = (await _channelService.withViewCounts(next))
            .where(_isMusicChannelUpload)
            .toList(growable: false);
        more = await YoutubeSearchService().removeShorts(musicOnly);
        if (!mounted || requestId != _sortRequestId) return;
        setState(() {
          _videos = [..._videos, ...more];
          _oldestShown += next.length;
        });
      } else {
        final page = await _channelService.playlistItemsPage(
          _uploadsId,
          pageToken: _nextToken,
          maxResults: _pageSize,
        );
        final musicOnly = (await _channelService.withViewCounts(page.items))
            .where(_isMusicChannelUpload)
            .toList(growable: false);
        more = await YoutubeSearchService().removeShorts(musicOnly);
        if (!mounted || requestId != _sortRequestId) return;
        setState(() {
          _videos = [..._videos, ...more];
          _nextToken = page.nextPageToken;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_channelErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Widget _sortBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            avatar: const Icon(Icons.arrow_downward_rounded, size: 16),
            label: const Text('Terbaru'),
            selected: !_oldestFirst,
            onSelected: _sorting ? null : (_) => unawaited(_setSort(false)),
          ),
          ChoiceChip(
            avatar: const Icon(Icons.arrow_upward_rounded, size: 16),
            label: const Text('Terlama'),
            selected: _oldestFirst,
            onSelected: _sorting ? null : (_) => unawaited(_setSort(true)),
          ),
          if (_error.isNotEmpty)
            Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _banner(ColorScheme scheme) {
    final url = _details?.bannerUrl ?? '';
    return AspectRatio(
      aspectRatio: 16 / 4.5,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url.isEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [scheme.primaryContainer, scheme.surfaceContainerHighest, scheme.secondaryContainer]),
              ),
              child: Icon(Icons.graphic_eq_rounded, color: scheme.primary.withValues(alpha: 0.32), size: 42),
            )
          else
            Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest)),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, scheme.surface.withValues(alpha: 0.50)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(ColorScheme scheme) {
    final d = _details;
    final title = d?.title ?? widget.title;
    final avatar = (d?.avatarUrl.isNotEmpty == true) ? d!.avatarUrl : widget.thumbnailUrl;

    final meta = <String>[];
    if (d != null) {
      if (d.handle.isNotEmpty) meta.add(d.handle.startsWith('@') ? d.handle : '@${d.handle}');
      if (d.hiddenSubscriberCount) {
        meta.add('Jumlah subscriber disembunyikan');
      } else if (d.subscriberCount != null) {
        meta.add('${formatCount(d.subscriberCount!)} subscriber');
      }
      if (d.videoCount != null) meta.add('${formatCount(d.videoCount!)} video');
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary.withValues(alpha: 0.12), scheme.surfaceContainerLow, scheme.secondary.withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: scheme.surfaceContainerHighest,
                backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                child: avatar.isEmpty ? const Icon(Icons.person_rounded, size: 34) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, height: 1.15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (meta.isNotEmpty)
            Text(
              meta.join(' • '),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4),
            ),
          if ((d?.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _selectTab(2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      d!.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant, size: 20),
                ],
              ),
            ),
          ],
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    final isLiveNow = _liveItems.any((v) => v.isLive);
    final labels = <Widget>[
      const Text('Musik'),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLiveNow) ...[
            const Icon(Icons.circle, size: 9, color: Color(0xFFE53935)),
            const SizedBox(width: 6),
          ],
          const Text('Live'),
        ],
      ),
      const Text('Tentang'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                ChoiceChip(
                  label: labels[i],
                  selected: _tab == i,
                  onSelected: (_) => _selectTab(i),
                  showCheckmark: false,
                ),
                if (i != labels.length - 1) const SizedBox(width: 5),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _videoCard(YoutubeSearchResult video, ColorScheme scheme) {
    final meta = <String>[];
    final liveLine = liveMetaLine(video, formatCount);
    if (liveLine.isNotEmpty) {
      meta.add(liveLine);
    } else if (video.viewCount != null) {
      meta.add('${formatCount(video.viewCount!)} ditonton');
    }
    if (video.isLiveRecording && video.liveStartTime != null) {
      meta.add('Live ${_relativeTime(video.liveStartTime!)}');
    } else if (video.publishedAt != null && !video.isLive && !video.isUpcoming) {
      meta.add(_relativeTime(video.publishedAt!));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          // Mode route lama: tutup halaman dulu. Mode lapisan (onClose != null):
          // halaman tetap ada di bawah halaman tonton.
          if (widget.onClose == null) Navigator.of(context).pop();
          unawaited(widget.onPlay(video));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      video.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest),
                    ),
                    if (video.liveStatus.isNotEmpty)
                      Positioned(left: 8, top: 8, child: LiveBadge(video: video)),
                    Positioned(right: 8, bottom: 8, child: DurationBadge(video: video)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25),
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(meta.join(' • '), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subHeader(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
          child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        ),
      );

  List<Widget> _liveBody(ColorScheme scheme) {
    final live = _liveItems.where((v) => v.isLive).toList(growable: false);
    final upcoming = _liveItems.where((v) => v.isUpcoming).toList(growable: false);
    final recordings = _liveItems.where((v) => v.isLiveRecording).toList()
      ..sort((a, b) => (b.liveStartTime ?? b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.liveStartTime ?? a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0)));

    return [
      if (live.isNotEmpty) ...[
        _subHeader('Sedang live'),
        SliverList.builder(
          itemCount: live.length,
          itemBuilder: (context, index) => _videoCard(live[index], scheme),
        ),
      ],
      if (upcoming.isNotEmpty) ...[
        _subHeader('Dijadwalkan'),
        SliverList.builder(
          itemCount: upcoming.length,
          itemBuilder: (context, index) => _videoCard(upcoming[index], scheme),
        ),
      ],
      _subHeader('Rekaman live'),
      if (recordings.isNotEmpty)
        SliverList.builder(
          itemCount: recordings.length,
          itemBuilder: (context, index) => _videoCard(recordings[index], scheme),
        )
      else if (!_liveLoading)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Text(
              _liveToken == null
                  ? 'Belum ada rekaman live di channel ini.'
                  : 'Belum ada rekaman live di upload terbaru. Coba cari yang lebih lama.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      if (_liveError.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_liveError, style: TextStyle(color: scheme.error, fontSize: 12)),
          ),
        ),
      if (_liveLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (_liveToken != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Center(
              child: OutlinedButton.icon(
                onPressed: _scanMoreLive,
                icon: const Icon(Icons.history_rounded),
                label: const Text('Cari rekaman live lebih lama'),
              ),
            ),
          ),
        ),
    ];
  }

  List<Widget> _body(ColorScheme scheme) {
    if (_tab == 1) {
      if (_loading) {
        return const [
          SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))),
        ];
      }
      return _liveBody(scheme);
    }
    if (_tab == 2) {
      final d = _details;
      final lines = <String>[];
      if (d != null) {
        if (d.subscriberCount != null && !d.hiddenSubscriberCount) {
          lines.add('${formatCount(d.subscriberCount!)} subscriber');
        }
        if (d.videoCount != null) lines.add('${formatCount(d.videoCount!)} video');
      }
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Deskripsi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  (d?.description.trim().isNotEmpty == true) ? d!.description.trim() : 'Tidak ada deskripsi.',
                  style: const TextStyle(height: 1.4),
                ),
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const Text('Statistik', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  for (final line in lines) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(line)),
                ],
              ],
            ),
          ),
        ),
      ];
    }
    if (_loading) {
      return const [
        SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))),
      ];
    }
    if (_sorting) {
      return [
        SliverToBoxAdapter(child: _sortBar()),
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))),
      ];
    }
    if (_error.isNotEmpty && _videos.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(_error, style: TextStyle(color: scheme.error)),
          ),
        ),
      ];
    }
    if (_videos.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Belum menemukan unggahan musik di halaman ini. Sebagian cover mungkin ada di unggahan yang lebih lama.',
                  textAlign: TextAlign.center,
                ),
                if (_loadingMore) ...[
                  const SizedBox(height: 12),
                  const CircularProgressIndicator(),
                ] else if (_hasMore) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _loadMore,
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('Periksa unggahan lainnya'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverToBoxAdapter(child: _sortBar()),
      SliverList.builder(
        itemCount: _videos.length,
        itemBuilder: (context, index) => _videoCard(_videos[index], scheme),
      ),
      if (_hasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Center(
              child: _loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    )
                  : OutlinedButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('Muat lebih banyak'),
                    ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: widget.onClose == null,
            leading: widget.onClose == null
                ? null
                : IconButton(
                    tooltip: 'Kembali',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: widget.onClose,
                  ),
            title: Text(_details?.title ?? widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          SliverToBoxAdapter(child: _banner(scheme)),
          SliverToBoxAdapter(child: _header(scheme)),
          SliverToBoxAdapter(child: _tabs()),
          ..._body(scheme),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

