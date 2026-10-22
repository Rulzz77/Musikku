import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../models/youtube_search_result.dart';
import '../models/listening_stat.dart';
import '../services/smart_playlist_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_search_service.dart';
import '../services/search_suggest_service.dart';
import '../services/app_settings.dart';
import '../pages/youtube_search_page.dart';
import '../pages/youtube_channel_page.dart';
import '../pages/stats_page.dart';
import '../pages/app_settings_page.dart';
import '../pages/local_music_page.dart';
import 'channel_avatar.dart';
import 'live_badge.dart';
import 'unified_artwork.dart';
import 'app_update_sheet.dart';

part 'youtube_hub/startup_actions.dart';
part 'youtube_hub/home_views.dart';
part 'youtube_hub/search_views.dart';
part 'youtube_hub/video_components.dart';
part 'youtube_hub/library_views.dart';

/// Jembatan dari HomePage ke hub: tombol Back sistem dan membuka channel dari
/// halaman tonton. Halaman channel hidup di dalam hub, jadi video / PiP yang
/// tampil di atas hub tidak menutup halaman channel.
class YoutubeHubController {
  bool Function()? _onBack;
  void Function(String channelId, String title, String thumbnailUrl)? _onOpenChannel;

  /// true kalau Back dipakai untuk menutup halaman channel di hub.
  bool handleBack() => _onBack?.call() ?? false;

  void openChannel(String channelId, {String title = '', String thumbnailUrl = ''}) {
    _onOpenChannel?.call(channelId, title, thumbnailUrl);
  }
}

class _OpenChannel {
  final String id;
  final String title;
  final String thumbnailUrl;
  const _OpenChannel(this.id, this.title, this.thumbnailUrl);
}

class YoutubeHub extends StatefulWidget {
  final YoutubeHubController? controller;
  final Future<void> Function(YoutubeSearchResult) onPlay;
  final VoidCallback onClose;

  /// Tinggi mini player yang tampil di atas bar navigasi hub (0 jika tidak ada).
  /// Dipakai agar daftar video tidak tertutup mini player.
  final double bottomInset;
  final Map<String, double> watchProgress;
  final Map<String, double> watchDuration;
  final List<YoutubeSearchResult> recentlyPlayed;
  final List<YoutubeSearchResult> favorites;
  final List<ListeningStat> listeningStats;
  final int customPlaylistCount;
  final VoidCallback? onOpenCustomPlaylists;
  final String? currentVideoId;
  final Future<void> Function(YoutubeSearchResult video)? onStartRadio;
  final Future<void> Function(YoutubeSearchResult video, List<YoutubeSearchResult> list) onPlayFromList;
  final ValueChanged<YoutubeSearchResult> onAddToQueue;
  final ValueChanged<YoutubeSearchResult>? onShowVideoMenu;
  final ValueChanged<String>? onSearchQueryChanged;
  final AppSettingsController settings;

  const YoutubeHub({
    super.key,
    this.controller,
    required this.onPlay,
    required this.onClose,
    this.bottomInset = 0,
    this.watchProgress = const {},
    this.watchDuration = const {},
    this.recentlyPlayed = const [],
    this.favorites = const [],
    this.listeningStats = const [],
    this.customPlaylistCount = 0,
    this.onOpenCustomPlaylists,
    this.currentVideoId,
    this.onStartRadio,
    required this.onPlayFromList,
    required this.onAddToQueue,
    this.onShowVideoMenu,
    this.onSearchQueryChanged,
    required this.settings,
  });

  @override
  State<YoutubeHub> createState() => _YoutubeHubState();
}

enum _YoutubeSection { home, explore, samples, library }

class _YoutubeHubState extends State<YoutubeHub> {
  final _searchController = TextEditingController();
  final _searchService = YoutubeSearchService();
  final _suggestService = SearchSuggestService();
  final _storage = StorageService();
  int _homeRequestSequence = 0;
  int _chipRequestSequence = 0;
  int _exploreRequestSequence = 0;
  final Random _feedRandom = Random();

  _YoutubeSection _section = _YoutubeSection.home;
  double _sectionSwipeDistance = 0;
  double? _dockDragIndex;
  double _dockReflectionX = 0.5;
  bool _dockDragging = false;
  bool _loading = false;
  String _error = '';
  String _query = '';
  String _searchMode = 'music';
  List<String> _searchHistory = const [];

  /// Chip filter aktif di beranda (0 = Semua). -1 = pencarian bebas.
  int _activeChip = 0;

  /// Explore uses the shared cached search service so genre results are live,
  /// rather than hard-coded sample tracks.
  String _exploreCategory = 'Pop Indonesia';
  List<YoutubeSearchResult> _exploreResults = const [];
  bool _exploreLoading = false;
  String _exploreError = '';
  static const List<String> _exploreCategories = [
    'Sedang tren',
    'Pop Indonesia',
    'Dangdut/Koplo',
    'K-Pop',
    'Hip-hop',
    'Rock',
    'Jazz',
    'Lo-fi',
    'Musik religi',
    'Soundtrack',
  ];
  static const Map<String, String> _exploreQueries = {
    'Pop Indonesia': 'lagu pop Indonesia terbaru official music',
    'Dangdut/Koplo': 'dangdut koplo Indonesia terbaru official',
    'K-Pop': 'K-pop official music video latest',
    'Hip-hop': 'hip hop music official video',
    'Rock': 'rock music official video',
    'Jazz': 'jazz music official',
    'Lo-fi': 'lofi hip hop music mix',
    'Musik religi': 'lagu religi Indonesia official music',
    'Soundtrack': 'soundtrack film Indonesia official music',
  };

  List<YoutubeSearchResult> _searchResults = const [];
  List<YoutubeChannelSearchResult> _searchChannels = const [];
  bool _channelSearchLoading = false;
  /// Video trending musik untuk beranda; tidak memerlukan akun.
  List<YoutubeSearchResult> _trending = const [];
  bool _feedLoading = false;
  String _feedError = '';

  /// Isi chip Musik / Terpopuler / Video terbaru (kunci = indeks chip).
  final Map<int, List<YoutubeSearchResult>> _chipFeeds = {};
  bool _chipLoading = false;

  /// Channel yang sedang dibuka (lapisan di atas hub). Null = tidak ada.
  _OpenChannel? _openedChannel;

  bool _handleControllerBack() {
    if (_openedChannel != null) {
      setState(() => _openedChannel = null);
      return true;
    }
    if (_section != _YoutubeSection.home) {
      _searchRequestId++;
      _searchController.clear();
      setState(() {
        _section = _YoutubeSection.home;
        _query = '';
        _searchResults = const [];
        _searchChannels = const [];
        _error = '';
        _loading = false;
      });
      return true;
    }
    return false;
  }

  void _handleControllerOpenChannel(String id, String title, String thumbnailUrl) {
    if (!mounted || id.isEmpty) return;
    setState(() => _openedChannel = _OpenChannel(id, title, thumbnailUrl));
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._onBack = _handleControllerBack;
    widget.controller?._onOpenChannel = _handleControllerOpenChannel;
    unawaited(_restore());
  }

  @override
  void dispose() {
    if (widget.controller?._onBack == _handleControllerBack) {
      widget.controller?._onBack = null;
      widget.controller?._onOpenChannel = null;
    }
    _searchController.dispose();
    super.dispose();
  }


  List<YoutubeSearchResult> get _homeVideos => List<YoutubeSearchResult>.from(_trending);

  static const _chipTitles = <int, String>{
    1: 'Lagu populer',
    2: 'Lagu terbaru',
  };


  int _searchRequestId = 0;

  /// true selama tarik-untuk-refresh: RefreshIndicator sudah punya spinner
  /// sendiri, jadi spinner inline disembunyikan supaya tidak muncul dobel.
  bool _pullRefreshing = false;
  bool get _inlineLoading => _loading && !_pullRefreshing;


  void _selectDockDestination(int index) {
    final nextSection = _YoutubeSection.values[index];
    _searchRequestId++;
    _searchController.clear();
    setState(() {
      _section = nextSection;
      _dockReflectionX = index / (_YoutubeSection.values.length - 1);
      _query = '';
      _searchResults = const [];
      _searchChannels = const [];
      _loading = false;
      _error = '';
      if (nextSection == _YoutubeSection.home) {
        _activeChip = 0;
        _searchMode = 'music';
      }
    });
    if (nextSection == _YoutubeSection.home) {
      unawaited(_loadHome());
    } else if (nextSection == _YoutubeSection.samples && _trending.isEmpty && !_feedLoading) {
      unawaited(_loadHome());
    } else if (nextSection == _YoutubeSection.explore) {
      unawaited(_loadExploreCategory(_exploreCategory));
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _query.isNotEmpty ? _searchResults : _homeVideos;

    return Stack(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => _sectionSwipeDistance = 0,
          onHorizontalDragUpdate: (details) => _sectionSwipeDistance += details.delta.dx,
          onHorizontalDragEnd: (details) {
            // Main-tab swipes are disabled while searching or viewing a channel.
            // Horizontal carousels inside the page keep their own gesture arena.
            if (_query.isNotEmpty || _openedChannel != null) {
              _sectionSwipeDistance = 0;
              return;
            }
            final distance = _sectionSwipeDistance;
            _sectionSwipeDistance = 0;
            final velocity = details.primaryVelocity ?? 0;
            if (distance.abs() < 60 && velocity.abs() < 500) return;
            final step = distance.abs() >= 60 ? (distance < 0 ? 1 : -1) : (velocity < 0 ? 1 : -1);
            final target = (_section.index + step)
                .clamp(0, _YoutubeSection.values.length - 1)
                .toInt();
            if (target != _section.index) _selectDockDestination(target);
          },
          child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          reverseDuration: const Duration(milliseconds: 210),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.018),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: RefreshIndicator(
            key: ValueKey<String>('hub-${_section.name}-${_query.isNotEmpty ? 'search' : 'browse'}'),
          onRefresh: () async {
            _pullRefreshing = true;
            try {
              if (_section == _YoutubeSection.home) {
                if (_query.isNotEmpty) {
                  await _search(keepResults: true);
                } else if (_activeChip >= 1 && _activeChip <= 3) {
                  await _selectChip(_activeChip, force: true);
                } else {
                  await _loadHome(force: true);
                }
              } else if (_section == _YoutubeSection.samples) {
                await _loadHome(force: true);
              } else if (_section == _YoutubeSection.explore) {
                await _loadExploreCategory(_exploreCategory, force: true);
              }
            } finally {
              _pullRefreshing = false;
              if (mounted) setState(() {});
            }
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
          if (_query.isNotEmpty || _section != _YoutubeSection.home)
            _topBar(title: switch (_section) {
              _YoutubeSection.home => appName,
              _YoutubeSection.samples => 'Radio',
              _YoutubeSection.explore => 'Jelajahi',
              _YoutubeSection.library => 'Koleksi',
            }),
          if (_query.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    avatar: const Icon(Icons.search_rounded, size: 18),
                    label: Text(_query, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _openSearch,
                    onDeleted: _clearSearch,
                  ),
                ),
              ),
            ),
          // Di Beranda, chip dirender oleh _homeSections() (di bawah header
          // sambutan) supaya tidak menempel di bawah status bar.
          if (_query.isNotEmpty) _chipRow(),

          if (_error.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Text(_error, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ),
            ),
          if (_section == _YoutubeSection.home) ...[
            if (_query.isEmpty)
              ..._homeSections()
            else ...[
              if (_searchChannels.isNotEmpty) ...[
                _sectionHeader('Channel musik'),
                SliverToBoxAdapter(
                  child: SizedBox(
                    // Tinggi cukup untuk avatar + nama + label channel bahkan saat
                    // ukuran font sistem dibesarkan (sebelumnya overflow 10 px).
                    height: 136,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      scrollDirection: Axis.horizontal,
                      itemCount: _searchChannels.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final channel = _searchChannels[index];
                        return SizedBox(
                          width: 160,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _handleControllerOpenChannel(
                              channel.channelId,
                              channel.title,
                              channel.thumbnailUrl,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 28,
                                    backgroundImage: channel.thumbnailUrl.isNotEmpty
                                        ? NetworkImage(channel.thumbnailUrl)
                                        : null,
                                    child: channel.thumbnailUrl.isEmpty
                                        ? const Icon(Icons.person_rounded)
                                        : null,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    channel.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text('Buka channel', style: TextStyle(fontSize: 10.5)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
              if (_searchChannels.isEmpty && !_inlineLoading)
                SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: TextButton.icon(
                        onPressed: _channelSearchLoading ? null : _searchChannelsForCurrentQuery,
                        icon: _channelSearchLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.person_search_rounded),
                        label: Text(_channelSearchLoading ? 'Mencari channel…' : 'Cari channel terkait'),
                      ),
                    ),
                  ),
                ),
              _sectionHeader('Lagu untuk “$_query”'),
              if (_inlineLoading && _searchResults.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                )
              else if (_searchResults.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(24), child: Text('Tidak ada lagu.')),
                )
              else
                SliverList.builder(
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) => _videoCard(_searchResults[index]),
                ),
            ],
          ] else if (_section == _YoutubeSection.samples)
            ..._samplesView()
          else if (_section == _YoutubeSection.explore)
            ..._exploreView()
          else
            ..._libraryView(),
          if (_inlineLoading && list.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              // Extra clearance for the floating, inset navigation dock.
              height: 26 + 66 + widget.bottomInset + MediaQuery.paddingOf(context).bottom,
            ),
          ),
            ],
          ),
        ),
        ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 8 + MediaQuery.paddingOf(context).bottom,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
            if (_query.isNotEmpty || _openedChannel != null) return;
            setState(() {
              _dockDragging = true;
              _dockDragIndex = _section.index.toDouble();
              _dockReflectionX = _section.index / (_YoutubeSection.values.length - 1);
            });
          },
          onHorizontalDragUpdate: (details) {
            if (_query.isNotEmpty || _openedChannel != null) return;
            final dockWidth = (MediaQuery.sizeOf(context).width - 34).clamp(200.0, 10000.0);
            final itemWidth = dockWidth / _YoutubeSection.values.length;
            final localX = (details.localPosition.dx - 5).clamp(0.0, dockWidth);
            final next = (localX / itemWidth)
                .clamp(0.0, (_YoutubeSection.values.length - 1).toDouble())
                .toDouble();
            setState(() {
              _dockDragIndex = next;
              _dockReflectionX = (localX / dockWidth).clamp(0.0, 1.0).toDouble();
            });
          },
          onHorizontalDragEnd: (details) {
            if (_query.isNotEmpty || _openedChannel != null) {
              setState(() { _dockDragging = false; _dockDragIndex = null; });
              return;
            }
            final target = (_dockDragIndex ?? _section.index.toDouble())
                .round()
                .clamp(0, _YoutubeSection.values.length - 1)
                .toInt();
            setState(() { _dockDragging = false; _dockDragIndex = null; });
            if (target != _section.index) _selectDockDestination(target);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).colorScheme.surface.withValues(alpha: 0.48),
                      Theme.of(context).colorScheme.surface.withValues(alpha: 0.30),
                      Colors.white.withValues(alpha: 0.045),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 1.15),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 28, offset: const Offset(0, 10)),
                    BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 2)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth / 4;
                      return SizedBox(
                        height: 57,
                        child: Stack(
                          children: [
                            // A permanent glass bevel makes the dock look like
                            // translucent material even before it is touched.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.14),
                                        Colors.white.withValues(alpha: 0.015),
                                        Colors.white.withValues(alpha: 0.055),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedPositioned(
                              duration: _dockDragging ? Duration.zero : const Duration(milliseconds: 430),
                              curve: Curves.easeOutBack,
                              left: itemWidth * (_dockDragIndex ?? _section.index.toDouble()) + 2,
                              top: 1,
                              bottom: 1,
                              width: itemWidth - 4,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                                      Theme.of(context).colorScheme.secondary.withValues(alpha: 0.13),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                                  boxShadow: [
                                    BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.13), blurRadius: 15, offset: const Offset(0, 3)),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedPositioned(
                              duration: _dockDragging ? Duration.zero : const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              left: ((constraints.maxWidth - 72) * _dockReflectionX).clamp(0.0, max(0.0, constraints.maxWidth - 72)).toDouble(),
                              top: -8,
                              bottom: -8,
                              width: 72,
                              child: IgnorePointer(
                                child: Transform.rotate(
                                  angle: pi / 12,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(99),
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          Colors.white.withValues(alpha: 0.0),
                                          Colors.white.withValues(alpha: _dockDragging ? 0.22 : 0.11),
                                          Theme.of(context).colorScheme.primary.withValues(alpha: _dockDragging ? 0.10 : 0.035),
                                          Colors.white.withValues(alpha: 0.0),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(child: _FlowDockDestination(
                                  label: 'Beranda', icon: Icons.home_outlined, selectedIcon: Icons.home_rounded,
                                  selected: _section == _YoutubeSection.home,
                                  onTap: () => _selectDockDestination(_YoutubeSection.home.index),
                                )),
                                Expanded(child: _FlowDockDestination(
                                  label: 'Jelajah', icon: Icons.explore_outlined, selectedIcon: Icons.explore_rounded,
                                  selected: _section == _YoutubeSection.explore,
                                  onTap: () => _selectDockDestination(_YoutubeSection.explore.index),
                                )),
                                Expanded(child: _FlowDockDestination(
                                  label: 'Radio', icon: Icons.radio_outlined, selectedIcon: Icons.radio_rounded,
                                  selected: _section == _YoutubeSection.samples,
                                  onTap: () => _selectDockDestination(_YoutubeSection.samples.index),
                                )),
                                Expanded(child: _FlowDockDestination(
                                  label: 'Koleksi', icon: Icons.library_music_outlined, selectedIcon: Icons.library_music_rounded,
                                  selected: _section == _YoutubeSection.library,
                                  onTap: () => _selectDockDestination(_YoutubeSection.library.index),
                                )),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          ),
        ),
        // Halaman channel sebagai lapisan di atas hub (termasuk bar navigasi).
        // Halaman tonton / PiP milik HomePage berada di atas hub ini, jadi
        // setelah Back dari video kita kembali ke channel yang sama.
        if (_openedChannel != null)
          Positioned.fill(
            child: YoutubeChannelPage(
              key: ValueKey('channel-${_openedChannel!.id}'),
              channelId: _openedChannel!.id,
              title: _openedChannel!.title,
              thumbnailUrl: _openedChannel!.thumbnailUrl,
              onPlay: widget.onPlay,
              onClose: () => setState(() => _openedChannel = null),
            ),
          ),
      ],
    );
  }
}


String _formatHubError(Object error) {
  final message = error.toString().replaceFirst('Bad state: ', '').trim();
  return message.isEmpty ? 'Permintaan gagal. Periksa koneksi lalu coba lagi.' : message;
}


/// Destination untuk floating dock: indikator aktif, ikon, dan label ikut
/// bergerak halus, bukan hanya mengganti warna NavigationBar standar.
class _FlowDockDestination extends StatelessWidget {
  const _FlowDockDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: SizedBox(
              height: 57,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: selected ? 1.12 : 0.96,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        selected ? selectedIcon : icon,
                        key: ValueKey<bool>(selected),
                        size: 22,
                        color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: selected ? 10.4 : 9.5,
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                      letterSpacing: selected ? 0 : 0.05,
                    ),
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
