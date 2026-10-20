import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../app_info.dart';
import '../models/youtube_search_result.dart';
import '../models/listening_stat.dart';
import '../services/smart_playlist_service.dart';
import '../services/youtube_account_service.dart';
import '../services/youtube_library_repository.dart';
import '../services/account_request_guard.dart';
import '../services/storage_service.dart';
import '../services/youtube_search_service.dart';
import '../services/youtube_controller.dart';
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

part 'youtube_hub/account_actions.dart';
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

enum _YoutubeSection { home, samples, explore, subscriptions, library }

class _YoutubeHubState extends State<YoutubeHub> {
  final _searchController = TextEditingController();
  final _searchService = YoutubeSearchService();
  final _suggestService = SearchSuggestService();
  final _storage = StorageService();
  final _account = YoutubeAccountService.instance;
  late final _libraryRepository = YoutubeLibraryRepository(account: _account);
  final _accountRequestGuard = AccountRequestGuard();
  int _accountRefreshSequence = 0;
  int _accountCacheLoadSequence = 0;
  int _feedRefreshSequence = 0;
  int _playlistRequestSequence = 0;
  int _homeRequestSequence = 0;
  int _chipRequestSequence = 0;
  int _exploreRequestSequence = 0;
  final Random _feedRandom = Random();

  _YoutubeSection _section = _YoutubeSection.home;
  GoogleSignInAccount? _user;
  String _rememberedAccountEmail = '';
  bool _loading = false;
  bool _needsAuthorization = false;
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
  List<YoutubeSearchResult> _liked = const [];
  List<YoutubeChannelSummary> _subscriptions = const [];
  List<YoutubePlaylistSummary> _playlists = const [];
  List<YoutubeSearchResult> _subscriptionFeed = const [];
  // Semua channel yang memiliki setidaknya satu unggahan musik pada feed
  // langganan yang telah diperiksa. Tidak dibatasi oleh 30 video yang tampil.
  Set<String> _musicSubscriptionChannelIds = <String>{};
  Timer? _subscriptionTimer;

  /// Video trending (semua kategori). Tampil di beranda TANPA perlu login.
  List<YoutubeSearchResult> _trending = const [];
  bool _feedLoading = false;
  String _feedError = '';

  /// Isi chip Musik / Terpopuler / Video terbaru (kunci = indeks chip).
  final Map<int, List<YoutubeSearchResult>> _chipFeeds = {};
  bool _chipLoading = false;

  List<YoutubeSearchResult> _playlistItems = const [];
  YoutubePlaylistSummary? _selectedPlaylist;

  /// Channel yang sedang dibuka (lapisan di atas hub). Null = tidak ada.
  _OpenChannel? _openedChannel;

  bool _handleControllerBack() {
    if (_openedChannel != null) {
      setState(() => _openedChannel = null);
      return true;
    }
    if (_section == _YoutubeSection.library && _selectedPlaylist != null) {
      setState(() {
        _selectedPlaylist = null;
        _playlistItems = const [];
      });
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
    _user = _account.user;
    // Matikan worker notifikasi subscription versi lama setelah pembaruan.
    // Notifikasi kontrol pemutar Android tetap terpisah agar audio background aman.
    unawaited(NativeYoutubeController.configureBackgroundWatch(enabled: false));
    // Feed subscription masih disegarkan secara ringan; notif unggahan/live
    // sengaja dimatikan.
    _subscriptionTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      // Pada Super hemat kita hanya refresh di beberapa interval supaya request
      // background tidak terlalu sering.
      // interval ganjil sehingga frekuensinya turun tanpa membuat timer baru.
      final nowMinute = DateTime.now().minute;
      if (_account.isSignedIn && !_loading && (widget.settings.dataSaverMode.value != DataSaverMode.superSaver || nowMinute.isEven)) {
        unawaited(_refreshSubscriptionInBackground());
      }
    });
    unawaited(_restore());
  }

  @override
  void dispose() {
    if (widget.controller?._onBack == _handleControllerBack) {
      widget.controller?._onBack = null;
      widget.controller?._onOpenChannel = null;
    }
    _subscriptionTimer?.cancel();
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


  @override
  Widget build(BuildContext context) {
    final list = _query.isNotEmpty ? _searchResults : _homeVideos;

    return Stack(
      children: [
        RefreshIndicator(
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
                  if (_account.isSignedIn) await _run(_refreshAccount);
                }
              } else if (_section == _YoutubeSection.samples) {
                await _loadHome(force: true);
              } else if (_section == _YoutubeSection.explore) {
                await _loadExploreCategory(_exploreCategory, force: true);
              } else if (_account.isSignedIn) {
                await _run(_refreshAccount);
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
              _YoutubeSection.samples => 'Mix',
              _YoutubeSection.explore => 'Jelajahi',
              _YoutubeSection.subscriptions => 'Langganan',
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
          if (_needsAuthorization)
            SliverToBoxAdapter(
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_open_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Akun Google tersimpan. Izin YouTube perlu disetujui sekali.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: _loading ? null : _authorizeYoutube,
                        child: const Text('Izinkan'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
                _sectionHeader('Akun'),
                SliverToBoxAdapter(
                  child: SizedBox(
                    // Tinggi cukup untuk avatar + nama + "Buka akun" bahkan saat
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
                                  const Text('Buka akun', style: TextStyle(fontSize: 10.5)),
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
          else if (_section == _YoutubeSection.subscriptions)
            ..._subscriptionsView()
          else
            ..._libraryView(),
          if (_inlineLoading && list.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              // 66 = tinggi NavigationBar yang menimpa daftar (Positioned bottom).
              height: 12 + 66 + widget.bottomInset + MediaQuery.paddingOf(context).bottom,
            ),
          ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            elevation: 8,
            child: NavigationBar(
              selectedIndex: _section.index,
              onDestinationSelected: (index) {
                final nextSection = _YoutubeSection.values[index];
                if (nextSection == _YoutubeSection.home) {
                  _searchRequestId++;
                  _searchController.clear();
                  setState(() {
                    _section = _YoutubeSection.home;
                    _activeChip = 0;
                    _query = '';
                    _searchMode = 'music';
                    _searchResults = const [];
                    _searchChannels = const [];
                    _selectedPlaylist = null;
                    _playlistItems = const [];
                    _loading = false;
                    _error = '';
                  });
                  unawaited(_loadHome());
                  return;
                }
                _searchRequestId++;
                _searchController.clear();
                setState(() {
                  _section = nextSection;
                  _query = '';
                  _searchResults = const [];
                  _searchChannels = const [];
                  _selectedPlaylist = null;
                  _playlistItems = const [];
                  _loading = false;
                  _error = '';
                });
                if (nextSection == _YoutubeSection.samples && _trending.isEmpty && !_feedLoading) {
                  unawaited(_loadHome());
                } else if (nextSection == _YoutubeSection.explore) {
                  unawaited(_loadExploreCategory(_exploreCategory));
                }
                if ((nextSection == _YoutubeSection.subscriptions || nextSection == _YoutubeSection.library) && !_account.isSignedIn) {
                  unawaited(_restoreAccountAfterUserAction());
                }
              },
              height: 66,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Beranda',
                ),
                NavigationDestination(
                  icon: Icon(Icons.queue_music_rounded),
                  selectedIcon: Icon(Icons.graphic_eq_rounded),
                  label: 'Mix',
                ),
                NavigationDestination(
                  icon: Icon(Icons.explore_outlined),
                  selectedIcon: Icon(Icons.explore_rounded),
                  label: 'Jelajahi',
                ),
                NavigationDestination(
                  icon: Icon(Icons.subscriptions_outlined),
                  selectedIcon: Icon(Icons.subscriptions_rounded),
                  label: 'Langganan',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music_rounded),
                  label: 'Koleksi',
                ),
              ],
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
              onSubscriptionChanged: _onChannelSubscriptionChanged,
              onClose: () => setState(() => _openedChannel = null),
            ),
          ),
      ],
    );
  }
}
