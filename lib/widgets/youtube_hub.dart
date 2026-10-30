import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../models/listening_stat.dart';
import '../models/youtube_search_result.dart';
import '../pages/app_settings_page.dart';
import '../pages/artist_page.dart';
import '../pages/local_music_page.dart';
import '../pages/stats_page.dart';
import '../pages/youtube_channel_page.dart';
import '../pages/youtube_search_page.dart';
import '../services/app_settings.dart';
import '../services/music_title_formatter.dart';
import '../services/search_suggest_service.dart';
import '../services/smart_playlist_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_search_service.dart';
import 'app_update_sheet.dart';
import 'channel_avatar.dart';
import 'live_badge.dart';
import 'unified_artwork.dart';
import 'flow_components.dart';

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
  final VoidCallback? onOpenListeningRoom;
  final VoidCallback? onOpenAudioSettings;
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
    this.onOpenListeningRoom,
    this.onOpenAudioSettings,
    required this.settings,
  });

  @override
  State<YoutubeHub> createState() => _YoutubeHubState();
}

enum _YoutubeSection { home, explore, samples, library }

class _YoutubeHubState extends State<YoutubeHub> {
  // ---------------------------------------------------------------------------
  // Services & controllers
  // ---------------------------------------------------------------------------

  final _searchController = TextEditingController();
  final _searchService = YoutubeSearchService();
  final _suggestService = SearchSuggestService();
  final _storage = StorageService();
  final Random _feedRandom = Random();

  // ---------------------------------------------------------------------------
  // Request bookkeeping (menolak hasil request lama)
  // ---------------------------------------------------------------------------

  int _homeRequestSequence = 0;
  int _chipRequestSequence = 0;
  int _exploreRequestSequence = 0;
  int _searchRequestId = 0;

  // ---------------------------------------------------------------------------
  // Navigasi & pencarian
  // ---------------------------------------------------------------------------

  _YoutubeSection _section = _YoutubeSection.home;
  bool _loading = false;
  String _error = '';
  String _query = '';
  String _searchMode = 'music';
  List<String> _searchHistory = const [];
  List<YoutubeSearchResult> _searchResults = const [];
  List<YoutubeChannelSearchResult> _searchChannels = const [];
  bool _channelSearchLoading = false;
  bool _artistChannelMode = false;

  /// true selama tarik-untuk-refresh: RefreshIndicator sudah punya spinner
  /// sendiri, jadi spinner inline disembunyikan supaya tidak muncul dobel.
  bool _pullRefreshing = false;
  bool get _inlineLoading => _loading && !_pullRefreshing;

  // ---------------------------------------------------------------------------
  // Beranda
  // ---------------------------------------------------------------------------

  /// Chip filter aktif di beranda (0 = Semua). -1 = pencarian bebas.
  int _activeChip = 0;

  /// Isi chip Musik / Terpopuler / Video terbaru (kunci = indeks chip).
  final Map<int, List<YoutubeSearchResult>> _chipFeeds = {};
  bool _chipLoading = false;

  /// Video trending musik untuk beranda; tidak memerlukan akun.
  List<YoutubeSearchResult> _trending = const [];
  bool _feedLoading = false;
  String _feedError = '';

  List<YoutubeSearchResult> get _homeVideos => List<YoutubeSearchResult>.from(_trending);

  static const _chipTitles = <int, String>{
    1: 'Lagu populer',
    2: 'Lagu terbaru',
  };

  // ---------------------------------------------------------------------------
  // Jelajahi
  // ---------------------------------------------------------------------------

  /// Explore uses the shared cached search service so genre results are live,
  /// rather than hard-coded sample tracks.
  String _exploreCategory = 'Pop Indonesia';
  List<YoutubeSearchResult> _exploreResults = const [];
  bool _exploreLoading = false;
  String _exploreError = '';

  static const List<String> _exploreCategories = [
    'Sedang tren',
    'Pop Indonesia',
    'Dangdut',
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
    'Pop Indonesia': 'lagu pop Indonesia official music video',
    'Dangdut': 'lagu dangdut Indonesia official music video',
    'Dangdut/Koplo': 'lagu dangdut koplo Indonesia official music video',
    'K-Pop': 'K-pop official music video latest',
    'Hip-hop': 'hip hop music official video',
    'Rock': 'rock music official video',
    'Jazz': 'jazz music official',
    'Lo-fi': 'lofi hip hop music mix',
    'Musik religi': 'lagu religi Indonesia official music',
    'Soundtrack': 'soundtrack film Indonesia official music',
  };

  // ---------------------------------------------------------------------------
  // Halaman channel
  // ---------------------------------------------------------------------------

  /// Channel yang sedang dibuka (lapisan di atas hub). Null = tidak ada.
  _OpenChannel? _openedChannel;

  // ---------------------------------------------------------------------------
  // Lifecycle & controller
  // ---------------------------------------------------------------------------

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
        _artistChannelMode = false;
        _channelSearchLoading = false;
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

  // ---------------------------------------------------------------------------
  // Navigasi dock & refresh
  // ---------------------------------------------------------------------------

  void _selectDockDestination(int index) {
    final nextSection = _YoutubeSection.values[index];
    _searchRequestId++;
    _searchController.clear();
    setState(() {
      _section = nextSection;
      _query = '';
      _searchResults = const [];
      _searchChannels = const [];
      _artistChannelMode = false;
      _channelSearchLoading = false;
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

  Future<void> _hubRefresh() async {
    _pullRefreshing = true;
    try {
      switch (_section) {
        case _YoutubeSection.home:
          if (_query.isNotEmpty) {
            await _search(keepResults: true);
          } else if (_activeChip >= 1 && _activeChip <= 3) {
            await _selectChip(_activeChip, force: true);
          } else {
            await _loadHome(force: true);
          }
        case _YoutubeSection.samples:
          await _loadHome(force: true);
        case _YoutubeSection.explore:
          await _loadExploreCategory(_exploreCategory, force: true);
        case _YoutubeSection.library:
          break;
      }
    } finally {
      _pullRefreshing = false;
      if (mounted) setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final channel = _openedChannel;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dockInset = screenWidth >= 700
        ? ((screenWidth - 820) / 2).clamp(14.0, 180.0).toDouble()
        : 14.0;

    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            // Keep reading widths comfortable on tablets and desktop-sized windows.
            constraints: const BoxConstraints(maxWidth: 1200),
            child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
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
            key: ValueKey<String>(
              'hub-${_section.name}-${_query.isNotEmpty ? 'search' : 'browse'}',
            ),
            onRefresh: _hubRefresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _hubSlivers(),
            ),
          ),
            ),
          ),
        ),
        Positioned(
          left: dockInset,
          right: dockInset,
          bottom: MediaQuery.paddingOf(context).bottom + 8,
          child: _EditorialFloatingDock(
            selectedIndex: _section.index,
            onSelect: _selectDockDestination,
          ),
        ),
        // Halaman channel sebagai lapisan di atas hub (termasuk bar navigasi).
        // Halaman tonton / PiP milik HomePage berada di atas hub ini, jadi
        // setelah Back dari video kita kembali ke channel yang sama.
        if (channel != null)
          Positioned.fill(
            child: YoutubeChannelPage(
              key: ValueKey('channel-${channel.id}'),
              channelId: channel.id,
              title: channel.title,
              thumbnailUrl: channel.thumbnailUrl,
              onPlay: widget.onPlay,
              onClose: () => setState(() => _openedChannel = null),
            ),
          ),
      ],
    );
  }

  /// Seluruh sliver untuk daftar utama hub.
  List<Widget> _hubSlivers() {
    final list = _query.isNotEmpty ? _searchResults : _homeVideos;
    final theme = Theme.of(context);

    return [
      if (_query.isNotEmpty || _section != _YoutubeSection.home)
        _topBar(
          title: switch (_section) {
            _YoutubeSection.home => appName,
            _YoutubeSection.samples => 'Radio',
            _YoutubeSection.explore => 'Jelajahi',
            _YoutubeSection.library => 'Koleksi',
          },
        ),
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
            child: Text(
              _error,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ),
        ),
      ..._hubBodySlivers(),
      if (_inlineLoading && list.isNotEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      SliverToBoxAdapter(
        child: SizedBox(
          // Extra clearance for the floating, inset navigation dock.
          height: 14 + 72 + widget.bottomInset + MediaQuery.paddingOf(context).bottom,
        ),
      ),
    ];
  }

  List<Widget> _hubBodySlivers() {
    switch (_section) {
      case _YoutubeSection.home:
        return _query.isEmpty ? _homeSections() : _hubSearchSlivers();
      case _YoutubeSection.samples:
        return _samplesView();
      case _YoutubeSection.explore:
        return _exploreView();
      case _YoutubeSection.library:
        return _libraryView();
    }
  }

  /// Hasil pencarian di Beranda: channel terkait, lalu daftar lagu.
  List<Widget> _hubSearchSlivers() {
    return [
      if (_searchChannels.isNotEmpty) ...[
        _sectionHeader(_artistChannelMode ? 'Artis' : 'Channel musik'),
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
              itemBuilder: (context, index) => _hubChannelCard(_searchChannels[index]),
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
                onPressed: _channelSearchLoading ? null : () => _searchChannelsForCurrentQuery(),
                icon: _channelSearchLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_search_rounded),
                label: Text(_channelSearchLoading ? 'Mencari channel…' : 'Cari channel terkait'),
              ),
            ),
          ),
        ),
      _sectionHeader('Lagu untuk “$_query”'),
      if (_inlineLoading && _searchResults.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
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
    ];
  }

  Widget _hubChannelCard(YoutubeChannelSearchResult channel) {
    final hasThumbnail = channel.thumbnailUrl.isNotEmpty;
    return SizedBox(
      width: 160,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (_artistChannelMode) {
            _openArtistCatalogue(channel);
          } else {
            _handleControllerOpenChannel(
              channel.channelId,
              channel.title,
              channel.thumbnailUrl,
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: hasThumbnail ? NetworkImage(channel.thumbnailUrl) : null,
                child: hasThumbnail ? null : const Icon(Icons.person_rounded),
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
              Text(
                _artistChannelMode ? 'Lihat daftar lagu' : 'Buka channel',
                style: const TextStyle(fontSize: 10.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Floating dock
// -----------------------------------------------------------------------------

class _DockItem {
  const _DockItem(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Urutan harus sama dengan [_YoutubeSection]: home, explore, samples, library.
const List<_DockItem> _dockItems = [
  _DockItem('Beranda', Icons.home_outlined, Icons.home_rounded),
  _DockItem('Jelajah', Icons.explore_outlined, Icons.explore_rounded),
  _DockItem('Radio', Icons.radio_outlined, Icons.radio_rounded),
  _DockItem('Koleksi', Icons.library_music_outlined, Icons.library_music_rounded),
];

/// Seberapa besar ikon [index] diperbesar oleh lensa pada posisi [visualIndex].
double _dockMagnification(
  int index,
  double visualIndex,
  bool dragging,
  int activeIndex,
) {
  if (!dragging) return index == activeIndex ? 0.22 : 0.0;
  final distance = (index - visualIndex).abs();
  return (1.0 - distance / 1.35).clamp(0.0, 1.0).toDouble();
}

String _formatHubError(Object error) {
  final message = error.toString().replaceFirst('Bad state: ', '').trim();
  return message.isEmpty ? 'Permintaan gagal. Periksa koneksi lalu coba lagi.' : message;
}

/// Floating editorial dock. Drag state stays inside this widget so moving the
/// selected capsule does not rebuild the whole music feed on every pointer tick.
class _EditorialFloatingDock extends StatefulWidget {
  const _EditorialFloatingDock({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  State<_EditorialFloatingDock> createState() => _EditorialFloatingDockState();
}

class _EditorialFloatingDockState extends State<_EditorialFloatingDock> {
  double? _dragX;

  int get _lastIndex => _dockItems.length - 1;

  double _clampDragX(double x, double cellWidth, double maxWidth) =>
      x.clamp(cellWidth * 0.5, maxWidth - cellWidth * 0.5).toDouble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 66,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final cellWidth = maxWidth / _dockItems.length;
          final activeIndex = widget.selectedIndex;
          final dragX = _dragX;
          final dragging = dragX != null;
          final visualIndex = dragging
              ? (dragX / cellWidth - 0.5).clamp(0.0, _lastIndex.toDouble()).toDouble()
              : activeIndex.toDouble();
          final activeLeft = (visualIndex * cellWidth + 5).clamp(0.0, maxWidth - cellWidth + 5).toDouble();

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              setState(() => _dragX = _clampDragX(details.localPosition.dx, cellWidth, maxWidth));
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                final nextX = (_dragX ?? ((activeIndex + 0.5) * cellWidth)) + details.delta.dx;
                _dragX = _clampDragX(nextX, cellWidth, maxWidth);
              });
            },
            onHorizontalDragEnd: (_) {
              final endX = _dragX;
              final target = endX == null
                  ? activeIndex
                  : (endX / cellWidth - 0.5).round().clamp(0, _lastIndex).toInt();
              setState(() => _dragX = null);
              if (target != widget.selectedIndex) widget.onSelect(target);
            },
            onHorizontalDragCancel: () => setState(() => _dragX = null),
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(19),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.92)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.34 : 0.10),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedPositioned(
                      duration: dragging ? Duration.zero : const Duration(milliseconds: 230),
                      curve: Curves.easeOutCubic,
                      left: activeLeft,
                      top: 6,
                      bottom: 6,
                      width: cellWidth - 10,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < _dockItems.length; i++)
                          Expanded(
                            child: _FlowDockDestination(
                              label: _dockItems[i].label,
                              icon: _dockItems[i].icon,
                              selectedIcon: _dockItems[i].selectedIcon,
                              selected: dragging
                                  ? (i - visualIndex).abs() < 0.48
                                  : activeIndex == i,
                              magnification: _dockMagnification(i, visualIndex, dragging, activeIndex),
                              onTap: () => widget.onSelect(i),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Destination untuk floating dock: ikon dan label ikut bergerak halus,
/// bukan hanya mengganti warna NavigationBar standar. Permukaan "terpilih"
/// disediakan oleh lensa kaca di belakang baris, bukan oleh destination.
class _FlowDockDestination extends StatelessWidget {
  const _FlowDockDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.magnification,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final double magnification;
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
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedScale(
                    scale: 1.0 + magnification * 0.18,
                    duration: const Duration(milliseconds: 130),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      selected ? selectedIcon : icon,
                      size: 21,
                      color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 130),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: selected ? 9.7 : 9.2,
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                      color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                      letterSpacing: 0,
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
