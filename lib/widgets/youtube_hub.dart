import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../app_info.dart';
import '../models/youtube_search_result.dart';
import '../services/youtube_account_service.dart';
import '../services/storage_service.dart';
import '../services/youtube_search_service.dart';
import '../services/youtube_controller.dart';
import '../services/subscription_notification_service.dart';
import '../services/search_suggest_service.dart';
import '../services/app_settings.dart';
import '../pages/youtube_search_page.dart';
import '../pages/youtube_channel_page.dart';
import '../pages/stats_page.dart';
import 'channel_avatar.dart';
import 'live_badge.dart';
import 'data_usage_card.dart';
import 'app_update_sheet.dart';

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
  final String? currentVideoId;
  final Future<void> Function(YoutubeSearchResult video)? onStartRadio;
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
    this.currentVideoId,
    this.onStartRadio,
    this.onSearchQueryChanged,
    required this.settings,
  });

  @override
  State<YoutubeHub> createState() => _YoutubeHubState();
}

enum _YoutubeSection { home, subscriptions, library }

class _YoutubeHubState extends State<YoutubeHub> {
  final _searchController = TextEditingController();
  final _searchService = YoutubeSearchService();
  final _suggestService = SearchSuggestService();
  final _storage = StorageService();
  final _account = YoutubeAccountService.instance;
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

  List<YoutubeSearchResult> _searchResults = const [];
  List<YoutubeChannelSearchResult> _searchChannels = const [];
  List<YoutubeSearchResult> _liked = const [];
  List<YoutubeChannelSummary> _subscriptions = const [];
  List<YoutubePlaylistSummary> _playlists = const [];
  List<YoutubeSearchResult> _subscriptionFeed = const [];
  Timer? _subscriptionTimer;

  /// Video trending (semua kategori). Tampil di beranda TANPA perlu login.
  List<YoutubeSearchResult> _trending = const [];
  bool _feedLoading = false;
  String _feedError = '';

  /// Isi chip Musik / Terpopuler / Video terbaru (kunci = indeks chip).
  final Map<int, List<YoutubeSearchResult>> _chipFeeds = {};
  bool _chipLoading = false;

  /// Siaran langsung dari channel yang di-subscribe.
  List<YoutubeSearchResult> _liveNow = const [];
  List<YoutubeSearchResult> _upcomingLive = const [];
  List<YoutubeSearchResult> _playlistItems = const [];
  YoutubePlaylistSummary? _selectedPlaylist;

  /// Channel yang sedang dibuka (lapisan di atas hub). Null = tidak ada.
  _OpenChannel? _openedChannel;

  bool _handleControllerBack() {
    if (_openedChannel == null) return false;
    setState(() => _openedChannel = null);
    return true;
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
    unawaited(SubscriptionNotificationService.instance.loadUnread());
    // Cek video baru + siapa yang sedang live tiap 10 menit (hanya 1 unit
    // kuota per channel, jadi aman).
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

  /// Saat app dibuka hanya memuat riwayat lokal. Google Sign-In TIDAK
  /// disentuh sama sekali sampai pengguna menekan tombol Masuk / ikon akun,
  /// jadi tidak ada popup login di awal.
  Future<void> _restore() async {
    final history = await _storage.loadHistory();
    final rememberedEmail = await _account.rememberedAccountEmail();
    if (mounted) {
      setState(() {
        _searchHistory = history;
        _rememberedAccountEmail = rememberedEmail ?? '';
      });
    }
    // Video trending dimuat paralel dengan pemulihan sesi dan tidak butuh login.
    unawaited(_loadHome());
    // Jangan memanggil lightweight authentication saat hub pertama dibuat.
    // Pada google_sign_in 7.x, Android boleh menampilkan UI minimal sehingga
    // restore otomatis di startup terasa seperti aplikasi selalu meminta login.
    // Restore sekarang dilakukan oleh aksi login/account pengguna.
    if (_account.isSignedIn) {
      setState(() => _user = _account.user);
      unawaited(_run(_refreshAccount));
    }
  }

  Future<void> _refreshSubscriptionInBackground() async {
    if (!mounted || !_account.isSignedIn) return;
    if (widget.settings.prefetchWifiOnly.value) {
      final type = await NativeYoutubeController().getNetworkType();
      if (type != 'wifi' && type != 'ethernet') {
        return;
      }
    }
    await _refreshFeedOnly();
  }

  /// Beranda musik: lagu populer kategori Music di Indonesia.
  /// Trending memakai API key, jadi TIDAK perlu login.
  Future<void> _loadHome({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _feedLoading = true;
      _feedError = '';
    });
    try {
      final videos = await _searchService.mostPopular(
        categoryId: '10',
        maxResults: widget.settings.dataSaverLevel >= 2 ? 12 : (widget.settings.dataSaverLevel == 1 ? 20 : 30),
        force: force,
      );
      if (!mounted) return;
      final freshVideos = List<YoutubeSearchResult>.from(videos);
      if (force && freshVideos.length > 1) {
        freshVideos.shuffle(_feedRandom);
      }
      setState(() => _trending = freshVideos);
    } catch (e) {
      if (!mounted) return;
      debugPrint('YOUTUBE TRENDING ERROR: $e');
      setState(() {
        _feedError = e is YoutubeSearchException
            ? e.message
            : 'Tidak bisa memuat lagu. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      if (mounted) setState(() => _feedLoading = false);
    }
  }

  List<YoutubeSearchResult> get _homeVideos => List<YoutubeSearchResult>.from(_trending);

  static const _chipTitles = <int, String>{
    1: 'Lagu populer',
    2: 'Lagu terbaru',
  };

  /// Chip beranda hanya menampilkan katalog musik dan lagu terbaru.
  Future<void> _selectChip(int index, {bool force = false}) async {
    _searchRequestId++; // batalkan pencarian yang masih berjalan
    _searchController.clear();
    setState(() {
      _activeChip = index;
      _query = '';
      _searchMode = 'music';
      _searchResults = const [];
      _searchChannels = const [];
      _section = _YoutubeSection.home;
      _loading = false;
      _error = '';
      _feedError = '';
    });
    if (!force && (_chipFeeds[index]?.isNotEmpty ?? false)) return;

    setState(() => _chipLoading = true);
    try {
      final List<YoutubeSearchResult> videos;
      switch (index) {
        case 1:
          videos = await _searchService.mostPopular(
            categoryId: '10',
            maxResults: widget.settings.dataSaverLevel >= 2 ? 12 : (widget.settings.dataSaverLevel == 1 ? 20 : 30),
            force: force,
          );
          break;
        case 2:
        default:
          videos = await _searchService.recentPopular(
            maxResults: widget.settings.dataSaverLevel >= 2 ? 12 : (widget.settings.dataSaverLevel == 1 ? 20 : 30),
            force: force,
          );
          break;
      }
      if (!mounted || _activeChip != index) return;
      final freshVideos = List<YoutubeSearchResult>.from(videos);
      if (force && freshVideos.length > 1) {
        freshVideos.shuffle(_feedRandom);
      }
      setState(() => _chipFeeds[index] = freshVideos);
    } catch (e) {
      if (!mounted || _activeChip != index) return;
      debugPrint('YOUTUBE CHIP ERROR: $e');
      setState(() {
        _feedError = e is YoutubeSearchException
            ? e.message
            : 'Tidak bisa memuat lagu. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      if (mounted) setState(() => _chipLoading = false);
    }
  }

  List<Widget> _chipSections() {
    final videos = _chipFeeds[_activeChip] ?? const <YoutubeSearchResult>[];
    return [
      _sectionHeader(_chipTitles[_activeChip] ?? 'Musik'),
      if (videos.isEmpty && _chipLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else if (videos.isEmpty)
        _homeEmptyState(signedIn: _user != null, retry: () => _selectChip(_activeChip, force: true))
      else
        SliverList.builder(
          itemCount: videos.length,
          itemBuilder: (context, index) => _videoCard(videos[index]),
        ),
    ];
  }

  List<Widget> _homeSections() {
    // Filter views reuse the same search and feed pipeline as before.
    if (_activeChip >= 1 && _activeChip <= 3) {
      return [
        SliverToBoxAdapter(
          child: SizedBox(height: MediaQuery.paddingOf(context).top + 8),
        ),
        _chipRow(),
        ..._chipSections(),
      ];
    }

    // Build a YouTube-like vertical feed, alternating subscription uploads and
    // popular videos. Dedupe IDs so one video isn't shown twice.
    final subscriptionVideos = _subscriptionFeed
        .where((video) => !video.isLive && !video.isUpcoming)
        .toList(growable: false);
    final popularVideos = _trending
        .where((video) => !video.isLive && !video.isUpcoming)
        .toList(growable: false);
    final feed = <YoutubeSearchResult>[];
    final seenIds = <String>{};

    void addUnique(YoutubeSearchResult video) {
      if (video.videoId.isNotEmpty && seenIds.add(video.videoId)) {
        feed.add(video);
      }
    }

    final feedLength = subscriptionVideos.length > popularVideos.length
        ? subscriptionVideos.length
        : popularVideos.length;
    for (var index = 0; index < feedLength; index++) {
      if (index < subscriptionVideos.length) addUnique(subscriptionVideos[index]);
      if (index < popularVideos.length) addUnique(popularVideos[index]);
    }

    final recentlyPlayed = widget.recentlyPlayed.take(12).toList(growable: false);

    return [
      SliverToBoxAdapter(child: _modernWelcomeHeader()),
      _chipRow(),
      if (recentlyPlayed.isNotEmpty) ...[
        _sectionHeader('Putar lagi'),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 190,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              scrollDirection: Axis.horizontal,
              itemCount: recentlyPlayed.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _quickPickCard(recentlyPlayed[index]),
            ),
          ),
        ),
      ],
      if (feed.isNotEmpty) ...[
        _sectionHeader('Pilihan musik untukmu'),
        SliverList.builder(
          itemCount: feed.length,
          itemBuilder: (context, index) => _videoCard(feed[index]),
        ),
      ] else if (_feedLoading || _inlineLoading)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Center(child: CircularProgressIndicator()),
          ),
        )
      else
        _homeEmptyState(
          signedIn: _user != null,
          retry: () => _loadHome(force: true),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
  }

  Widget _modernWelcomeHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        MediaQuery.paddingOf(context).top + 3,
        8,
        2,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.secondary],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.music_note_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.7,
                height: 1.0,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cari',
            visualDensity: VisualDensity.compact,
            onPressed: _openSearch,
            icon: const Icon(Icons.search_rounded),
          ),
          ValueListenableBuilder<Set<String>>(
            valueListenable: SubscriptionNotificationService.instance.unreadIds,
            builder: (context, ids, _) => IconButton(
              tooltip: 'Notifikasi',
              visualDensity: VisualDensity.compact,
              onPressed: _showNotifications,
              icon: Badge(
                isLabelVisible: _user != null && ids.isNotEmpty,
                label: Text(ids.length > 99 ? '99+' : '${ids.length}'),
                child: Icon(
                  _liveNow.isNotEmpty
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _user == null ? 'Hubungkan YouTube' : 'Akun YouTube',
            visualDensity: VisualDensity.compact,
            onPressed: _user == null ? _login : _showAccountSheet,
            icon: CircleAvatar(
              radius: 15,
              backgroundColor: scheme.surfaceContainerHighest,
              child: _user == null
                  ? Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: scheme.onSurface,
                    )
                  : Text(
                      (_user!.displayName?.trim().isNotEmpty == true
                              ? _user!.displayName!.trim().characters.first
                              : '?')
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDataSaverSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => ValueListenableBuilder<DataSaverMode>(
        valueListenable: widget.settings.dataSaverMode,
        builder: (context, mode, _) {
          final scheme = Theme.of(context).colorScheme;
          final state = _account.isSignedIn ? 'Akun tersambung' : 'Tanpa login';
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 2, 18, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hemat data',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Atur seberapa agresif MusikKu mengurangi request tambahan. Playback YouTube tetap ditentukan player.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const DataUsageCard(),
                    RadioGroup<DataSaverMode>(
                      groupValue: mode,
                      onChanged: (value) {
                        if (value == null) return;
                        unawaited(widget.settings.setDataSaverMode(value));
                      },
                      child: Column(
                        children: [
                          for (final choice in DataSaverMode.values)
                            RadioListTile<DataSaverMode>(
                              value: choice,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                choice.label,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              subtitle: Text(choice.description),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 16),
                    ValueListenableBuilder<bool>(
                      valueListenable: widget.settings.prefetchWifiOnly,
                      builder: (context, wifiOnly, _) => SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Prefetch hanya saat Wi-Fi',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          wifiOnly
                              ? 'Request tambahan tidak diprioritaskan saat seluler.'
                              : 'Request tambahan boleh berjalan di seluler.',
                        ),
                        value: wifiOnly,
                        onChanged: (value) =>
                            unawaited(widget.settings.setPrefetchWifiOnly(value)),
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: widget.settings.bufferAlertSeconds,
                      builder: (context, seconds, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Text(
                            'Peringatan buffer rendah • $seconds dtk',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Slider(
                            value: seconds.toDouble(),
                            min: 3,
                            max: 30,
                            divisions: 9,
                            label: '$seconds dtk',
                            onChanged: (value) => unawaited(
                              widget.settings.setBufferAlertSeconds(value.round()),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.verified_user_outlined, size: 17, color: scheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$state • data tambahan ditunda sampai dibutuhkan.',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
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

  Widget _horizontalVideoRail(List<YoutubeSearchResult> videos) {
    if (videos.isEmpty) return const SizedBox.shrink();
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final double railHeight = 208.0 + (textScale - 1.0).clamp(0.0, 0.6).toDouble() * 70.0;
    return SizedBox(
      height: railHeight,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        scrollDirection: Axis.horizontal,
        itemCount: videos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final video = videos[index];
          final progress = (widget.watchProgress[video.videoId] ?? 0).clamp(0.0, 1.0).toDouble();
          return SizedBox(
            width: 210,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => unawaited(widget.onPlay(video)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AspectRatio(aspectRatio: 16 / 9, child: Stack(fit: StackFit.expand, children: [Image.network(video.coverUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest)), if (progress > 0) Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: progress, minHeight: 3))])),
                    Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 3), child: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.2))),
                    Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 8), child: Text(video.channelTitle.isEmpty ? 'YouTube' : video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant))),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openSearch() async {
    if (!mounted) return;
    final picked = await Navigator.of(context).push<YoutubeSearchRequest>(
      MaterialPageRoute(
        builder: (_) => YoutubeSearchPage(
          suggestService: _suggestService,
          initialQuery: _query,
          history: _searchHistory,
        ),
      ),
    );
    if (picked == null || picked.query.trim().isEmpty || !mounted) return;
    setState(() {
      _activeChip = -1;
      _searchMode = 'music';
    });
    _searchController.text = picked.query.trim();
    await _search();
  }

  void _clearSearch() {
    _searchRequestId++;
    _searchController.clear();
    setState(() {
      _activeChip = 0;
      _loading = false;
      _query = '';
      _searchMode = 'music';
      _searchResults = const [];
      _searchChannels = const [];
    });
    unawaited(_loadHome());
  }

  Future<void> _showNotifications() async {
    if (_user == null) {
      await _login();
      return;
    }
    final service = SubscriptionNotificationService.instance;
    final unread = Set<String>.from(service.unreadIds.value);
    final live = _liveNow;
    final upcoming = _upcomingLive;
    final items = _subscriptionFeed.where((v) => !v.isLive).toList(growable: false);
    unawaited(service.markAllRead());
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;

    Widget thumb(YoutubeSearchResult video) => ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 96,
            height: 54,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  video.coverUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest),
                ),
                if (video.liveStatus.isNotEmpty)
                  Positioned(left: 4, bottom: 4, child: LiveBadge(video: video)),
              ],
            ),
          ),
        );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Notifikasi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            // Dropdown siaran langsung: terbuka otomatis kalau ada yang live.
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: live.isNotEmpty,
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: Icon(
                  Icons.sensors_rounded,
                  color: live.isNotEmpty ? const Color(0xFFE53935) : scheme.onSurfaceVariant,
                ),
                title: Text(
                  live.isEmpty ? 'Siaran langsung' : 'Sedang live (${live.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  live.isEmpty && upcoming.isEmpty
                      ? 'Belum ada yang live'
                      : upcoming.isEmpty
                          ? 'Channel yang kamu subscribe'
                          : '${upcoming.length} dijadwalkan',
                ),
                children: [
                  if (live.isEmpty && upcoming.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Tidak ada siaran langsung dari channel yang kamu subscribe.'),
                      ),
                    ),
                  for (final video in [...live, ...upcoming])
                    ListTile(
                      leading: thumb(video),
                      title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '${video.channelTitle} • ${liveMetaLine(video, (n) => _formatViews(n))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(widget.onPlay(video));
                      },
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text('Musik baru', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Belum ada notifikasi.')),
              )
            else
              for (final video in items)
                ListTile(
                  leading: thumb(video),
                  title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: unread.contains(video.videoId)
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(widget.onPlay(video));
                  },
                ),
          ],
        ),
      ),
    );
  }

  int _searchRequestId = 0;

  /// true selama tarik-untuk-refresh: RefreshIndicator sudah punya spinner
  /// sendiri, jadi spinner inline disembunyikan supaya tidak muncul dobel.
  bool _pullRefreshing = false;
  bool get _inlineLoading => _loading && !_pullRefreshing;

  /// Pencarian TIDAK lewat [_run]: _run diam-diam membatalkan tugas kalau
  /// _loading sedang true (mis. saat akun/subscription masih dimuat), sehingga
  /// hasil pencarian tidak pernah muncul. _query juga langsung diisi supaya
  /// layar hasil + indikator loading tampil seketika.
  Future<void> _search({bool keepResults = false}) async {
    final query = _searchController.text.trim();
    widget.onSearchQueryChanged?.call(query);
    final requestId = ++_searchRequestId;

    if (query.isEmpty) {
      setState(() {
        _activeChip = 0;
        _query = '';
        _searchMode = 'music';
        _searchResults = const [];
        _searchChannels = const [];
        _section = _YoutubeSection.home;
        _loading = false;
      });
      await _loadHome();
      return;
    }

    setState(() {
      _query = query;
      if (!keepResults) {
        _searchResults = const [];
        _searchChannels = const [];
      }
      _section = _YoutubeSection.home;
      _loading = true;
      _error = '';
    });

    try {
      final videos = await _searchService.search(query, filter: _searchMode);
      var channels = const <YoutubeChannelSearchResult>[];
      if (widget.settings.dataSaverMode.value != DataSaverMode.superSaver) {
        try {
          channels = await _searchService.searchChannels(query);
        } catch (_) {
          // Hasil video tetap ditampilkan kalau pencarian channel sedang terkena rate limit.
        }
      }
      if (!mounted || requestId != _searchRequestId) return;

      final updatedHistory = List<String>.from(_searchHistory)
        ..removeWhere((item) => item.toLowerCase() == query.toLowerCase())
        ..insert(0, query);
      if (updatedHistory.length > StorageService.maxHistory) {
        updatedHistory.removeRange(StorageService.maxHistory, updatedHistory.length);
      }

      setState(() {
        _searchResults = videos.take(30).toList(growable: false);
        _searchChannels = channels.take(8).toList(growable: false);
        _searchHistory = updatedHistory;
      });
      unawaited(_storage.saveHistory(updatedHistory));
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      debugPrint('YOUTUBE SEARCH ERROR: $e');
      setState(() {
        _error = e is YoutubeSearchException ? e.message : describeLoginError(e);
      });
    } finally {
      if (mounted && requestId == _searchRequestId) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _homeEmptyState({required bool signedIn, Future<void> Function()? retry}) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 56, 28, 24),
        child: Column(
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.video_library_rounded, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              _feedError.isNotEmpty
                  ? 'Lagu belum bisa dimuat'
                  : (signedIn ? 'Belum ada lagu baru' : 'Beranda masih kosong'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              _feedError.isNotEmpty
                  ? _feedError
                  : (signedIn
                      ? 'Cari lagu lewat kolom pencarian untuk mulai mendengarkan.'
                      : 'Cari lagu lewat kolom pencarian atau pilih rekomendasi musik di beranda.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (retry != null)
                  FilledButton.icon(
                    onPressed: () => unawaited(retry()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Coba lagi'),
                  ),
                if (!signedIn)
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _login,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Masuk'),
                  ),
                OutlinedButton.icon(
                  onPressed: _openSearch,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Telusuri'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshAccount() async {
    if (!_account.isSignedIn) return;
    if (_account.needsInteractiveAuthorization) {
      if (mounted) setState(() => _needsAuthorization = true);
      return;
    }
    final subscriptions = await _account.subscriptions();
    final liked = await _account.likedVideos();
    final playlists = await _account.playlists();
    final feed = await _account.subscriptionFeed(subscriptions);
    if (!mounted) return;
    setState(() {
      _subscriptions = subscriptions;
      _liked = liked;
      _playlists = playlists;
    });
    unawaited(_syncBackgroundWatch(subscriptions));
    await _applyFeed(feed);
  }

  /// Kirim daftar channel ke worker native supaya notifikasi live / video baru
  /// tetap muncul saat aplikasi ditutup.
  Future<void> _syncBackgroundWatch(List<YoutubeChannelSummary> channels) {
    return NativeYoutubeController.configureBackgroundWatch(
      enabled: true,
      apiKey: const String.fromEnvironment('YOUTUBE_API_KEY'),
      channels: [
        for (final c in channels)
          if (c.uploadsPlaylistId.isNotEmpty)
            {'id': c.id, 'title': c.title, 'uploads': c.uploadsPlaylistId},
      ],
    );
  }

  /// Hanya menyegarkan feed + status live (tanpa memuat ulang playlist/likes).
  Future<void> _refreshFeedOnly() async {
    if (!_account.isSignedIn || _account.needsInteractiveAuthorization) return;
    if (_subscriptions.isEmpty) return;
    try {
      final feed = await _account.subscriptionFeed(_subscriptions);
      await _applyFeed(feed);
    } catch (e) {
      debugPrint('YOUTUBE FEED REFRESH ERROR: $e');
    }
  }

  /// Memisahkan video biasa, yang sedang live, dan yang dijadwalkan; lalu
  /// kirim notifikasi sistem untuk video baru dan live baru.
  Future<void> _applyFeed(List<YoutubeSearchResult> feed) async {
    final musicFeed = feed
        .where((video) => YoutubeSearchService.isMusicCatalogItem(
              video,
              requireCategoryId: true,
            ))
        .toList(growable: false);
    final live = musicFeed.where((v) => v.isLive).toList(growable: false);
    final upcoming = musicFeed.where((v) => v.isUpcoming).toList(growable: false);
    final regular = musicFeed.where((v) => !v.isLive && !v.isUpcoming).toList(growable: false);
    final notifications = SubscriptionNotificationService.instance;
    try {
      await notifications.syncAndNotify(regular);
      await notifications.notifyLive(live);
    } catch (e) {
      debugPrint('YOUTUBE NOTIFY ERROR: $e');
    }
    if (!mounted) return;
    setState(() {
      _subscriptionFeed = [...live, ...regular].take(30).toList(growable: false);
      _liveNow = live;
      _upcomingLive = upcoming;
    });
  }

  Future<void> _restoreAccountAfterUserAction() async {
    try {
      await _account.tryRestoreSession();
      if (!mounted || !_account.isSignedIn) return;
      setState(() => _user = _account.user);
      await _run(_refreshAccount);
    } catch (e) {
      debugPrint('GOOGLE RESTORE AFTER USER ACTION ERROR: $e');
    }
  }

  Future<void> _login() async {
    await _run(() async {
      // Dipanggil hanya dari tap pengguna. Kalau pernah login, coba pulihkan
      // akun tersimpan dulu; kalau belum, tampilkan pemilih akun Google.
      await _account.tryRestoreSession();
      if (_account.user == null) {
        _user = await _account.signIn();
      } else {
        _user = _account.user;
        if (_account.needsInteractiveAuthorization) {
          await _account.authorizeYouTubeAccess();
        }
      }
      if (mounted) {
        setState(() {
          _needsAuthorization = false;
          _rememberedAccountEmail = _account.user?.email ?? _rememberedAccountEmail;
        });
      }
      await _refreshAccount();
    });
  }

  Future<void> _authorizeYoutube() async {
    await _run(() async {
      final ok = await _account.authorizeYouTubeAccess();
      if (!ok) throw StateError('Akun Google belum tersedia.');
      if (mounted) setState(() => _needsAuthorization = false);
      await _refreshAccount();
    });
  }

  Future<void> _logout() async {
    await _run(() async {
      await _account.signOut();
      unawaited(NativeYoutubeController.configureBackgroundWatch(enabled: false));
      if (!mounted) return;
      setState(() {
        _user = null;
        _subscriptions = const [];
        _liked = const [];
        _playlists = const [];
        _selectedPlaylist = null;
        _playlistItems = const [];
        _subscriptionFeed = const [];
        _liveNow = const [];
        _upcomingLive = const [];
        _rememberedAccountEmail = '';
      });
    });
  }

  /// Dipanggil halaman channel setelah subscribe/unsubscribe. Kalau pengguna
  /// baru login dari halaman channel, status login hub ikut diperbarui.
  void _onChannelSubscriptionChanged() {
    if (!mounted) return;
    if (_account.isSignedIn && _user == null) {
      setState(() => _user = _account.user);
    }
    unawaited(_run(_refreshAccount));
  }

  void _openChannel(YoutubeChannelSummary channel) {
    _handleControllerOpenChannel(channel.id, channel.title, channel.thumbnailUrl);
  }

  void _openAllSubscriptions() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => YoutubeSubscriptionsPage(
          channels: _subscriptions,
          onOpen: (channel) {
            // Tutup daftar dulu, lalu channel terbuka sebagai lapisan hub.
            Navigator.of(routeContext).pop();
            _openChannel(channel);
          },
        ),
      ),
    );
  }

  Future<void> _openPlaylist(YoutubePlaylistSummary playlist) async {
    await _run(() async {
      final videos = await _account.playlistItems(playlist.id);
      if (!mounted) return;
      setState(() {
        _selectedPlaylist = playlist;
        _playlistItems = videos;
      });
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_loading) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      await task();
    } catch (e) {
      if (!mounted) return;
      debugPrint('YOUTUBE HUB ERROR: $e');
      setState(() => _error = describeLoginError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Widget _topBar() {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, MediaQuery.paddingOf(context).top + 4, 10, 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 23,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.play_arrow_rounded, size: 21, color: Colors.white),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5),
              ),
            ),
            IconButton(
              tooltip: 'Cari',
              visualDensity: VisualDensity.compact,
              onPressed: _openSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            IconButton(
              tooltip: 'Hemat data',
              visualDensity: VisualDensity.compact,
              onPressed: _showDataSaverSheet,
              icon: const Icon(Icons.tune_rounded),
            ),
            ValueListenableBuilder<Set<String>>(
              valueListenable: SubscriptionNotificationService.instance.unreadIds,
              builder: (context, ids, _) => IconButton(
                tooltip: 'Notifikasi',
                visualDensity: VisualDensity.compact,
                onPressed: _showNotifications,
                icon: Badge(
                  isLabelVisible: _user != null && ids.isNotEmpty,
                  label: Text(ids.length > 99 ? '99+' : '${ids.length}'),
                  child: Icon(
                    _liveNow.isNotEmpty ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: _user == null ? 'Hubungkan YouTube' : 'Akun YouTube',
              visualDensity: VisualDensity.compact,
              onPressed: _user == null ? _login : _showAccountSheet,
              icon: CircleAvatar(
                radius: 15,
                backgroundColor: scheme.surfaceContainerHighest,
                child: _user == null
                    ? Icon(Icons.person_outline_rounded, size: 18, color: scheme.onSurface)
                    : Text(
                        (_user!.displayName?.trim().isNotEmpty == true
                                ? _user!.displayName!.trim().characters.first
                                : '?')
                            .toUpperCase(),
                        style: TextStyle(color: scheme.onSurface, fontSize: 12, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipRow() {
    const labels = [
      'Musik',
      'Lagu populer',
      'Lagu terbaru',
      'Jawa',
      'Pop Indonesia',
      'Dangdut/Koplo',
      'DJ/Remix',
      'K-Pop',
    ];
    const genreQueries = <int, String>{
      3: 'lagu Jawa Indonesia',
      4: 'lagu Pop Indonesia',
      5: 'lagu Dangdut Koplo Indonesia',
      6: 'DJ Remix Indonesia',
      7: 'K-Pop songs',
    };
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          scrollDirection: Axis.horizontal,
          itemCount: labels.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final genreQuery = genreQueries[index];
            final selected = genreQuery != null
                ? _query.toLowerCase() == genreQuery.toLowerCase()
                : _query.isEmpty && _activeChip == index;
            return ChoiceChip(
              label: Text(labels[index]),
              selected: selected,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              selectedColor: scheme.primaryContainer,
              backgroundColor: scheme.surfaceContainerLow,
              side: BorderSide(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.22)
                    : scheme.outlineVariant.withValues(alpha: 0.46),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              labelStyle: TextStyle(
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0.02,
              ),
              onSelected: (_) {
                if (index == 0) {
                  _clearSearch();
                  return;
                }
                if (index == 1 || index == 2) {
                  unawaited(_selectChip(index));
                  return;
                }
                if (genreQuery != null) {
                  setState(() {
                    _activeChip = -1;
                    _searchMode = 'music';
                  });
                  _searchController.text = genreQuery;
                  unawaited(_search());
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? action, VoidCallback? onAction}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                  height: 1.15,
                ),
              ),
            ),
            if (action != null)
              TextButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }

  Widget _videoCard(YoutubeSearchResult video) {
    final scheme = Theme.of(context).colorScheme;
    final progress = (widget.watchProgress[video.videoId] ?? 0)
        .clamp(0.0, 1.0)
        .toDouble();
    final timeLabel = _watchTimeLabel(video);
    final channel = video.channelTitle.trim();
    final isCurrent = widget.currentVideoId == video.videoId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isCurrent
            ? scheme.primaryContainer.withValues(alpha: 0.42)
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isCurrent
                ? scheme.primary.withValues(alpha: 0.24)
                : scheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => unawaited(widget.onPlay(video)),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: 78,
                  height: 78,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          video.coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.music_note_rounded,
                              color: scheme.onSurfaceVariant,
                              size: 34,
                            ),
                          ),
                        ),
                        Center(
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.48),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Icon(
                              isCurrent
                                  ? Icons.graphic_eq_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                        if (video.liveStatus.isNotEmpty)
                          Positioned(
                            left: 3,
                            top: 3,
                            child: LiveBadge(video: video),
                          ),
                        if (timeLabel.isNotEmpty)
                          Positioned(
                            right: 4,
                            bottom: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                timeLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        if (progress > 0)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 2.5,
                              backgroundColor: Colors.white.withValues(alpha: 0.30),
                              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                            ),
                          ),
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
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.22,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        channel.isEmpty ? 'Musik' : channel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _metaLine(video),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.82),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (video.channelId.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  ChannelAvatar(
                    channelId: video.channelId,
                    videoId: video.videoId,
                    name: channel,
                    radius: 15,
                    onTap: () => _handleControllerOpenChannel(
                      video.channelId,
                      channel,
                      '',
                    ),
                  ),
                ],
                const SizedBox(width: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickPickCard(YoutubeSearchResult video) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 132,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => unawaited(widget.onPlay(video)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      video.coverUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.music_note_rounded,
                          color: scheme.onSurfaceVariant,
                          size: 36,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        margin: const EdgeInsets.all(7),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              video.channelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
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

  List<Widget> _subscriptionsView() {
    return <Widget>[
      _sectionHeader(
        _subscriptions.isEmpty ? 'Subscription' : 'Subscription • ${_subscriptions.length} channel',
        action: _subscriptions.length > 1 ? 'Semua' : null,
        onAction: _openAllSubscriptions,
      ),
      if (_user == null)
        SliverToBoxAdapter(child: _loginCard())
      else if (_subscriptions.isEmpty)
        const SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.all(18), child: Text('Belum ada channel yang kamu subscribe.')),
        )
      else ...[
        SliverToBoxAdapter(
          child: SizedBox(
            height: 82,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
              scrollDirection: Axis.horizontal,
              itemCount: _subscriptions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final channel = _subscriptions[index];
                return InkWell(
                  onTap: () => _openChannel(channel),
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: channel.thumbnailUrl.isNotEmpty ? NetworkImage(channel.thumbnailUrl) : null,
                          child: channel.thumbnailUrl.isEmpty ? const Icon(Icons.person_rounded) : null,
                        ),
                        const SizedBox(height: 4),
                        Text(channel.title, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        _sectionHeader('Musik terbaru'),
        if (_subscriptionFeed.isEmpty)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(18), child: Text('Belum ada musik baru dari channel yang kamu subscribe.')))
        else
          SliverList.builder(
            itemCount: _subscriptionFeed.length,
            itemBuilder: (context, index) => _videoCard(_subscriptionFeed[index]),
          ),
      ],
    ];
  }

  Widget _libraryCard(String title, String subtitle, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }

  List<Widget> _libraryView() {
    final scheme = Theme.of(context).colorScheme;
    final likedCount = _user == null ? widget.favorites.length : _liked.length;
    final playlistCount = _user == null ? 0 : _playlists.length;
    final displayName = _user?.displayName?.trim();

    Widget spacedCard(String title, String subtitle, IconData icon, VoidCallback onTap) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: _libraryCard(title, subtitle, icon, onTap),
        ),
      );
    }

    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 8, 16, 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.surfaceContainerHighest,
                child: _user == null
                    ? Icon(Icons.person_outline_rounded, color: scheme.onSurface, size: 28)
                    : Text(
                        (displayName != null && displayName.isNotEmpty
                                ? displayName.characters.first
                                : '?')
                            .toUpperCase(),
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Anda', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(
                      _user?.email ?? 'Kelola koleksi dan fitur MusikKu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Pembaruan aplikasi',
                onPressed: () => unawaited(AppUpdateSheet.show(context)),
                icon: const Icon(Icons.system_update_alt_rounded),
              ),
              IconButton(
                tooltip: 'Pengaturan hemat data',
                onPressed: _showDataSaverSheet,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
      ),
      if (_user == null)
        SliverToBoxAdapter(child: _loginCard())
      else ...[
        spacedCard(
          'Lagu yang disukai',
          '$likedCount lagu musik di akun YouTube',
          Icons.thumb_up_alt_outlined,
          () => _showSongList('Lagu yang disukai', _liked),
        ),
        spacedCard(
          'Playlist YouTube',
          '$playlistCount playlist',
          Icons.queue_music_rounded,
          _showPlaylistPicker,
        ),
      ],
      spacedCard(
        'Riwayat dengar',
        '${widget.recentlyPlayed.length} lagu didengarkan di MusikKu',
        Icons.history_rounded,
        () => _showSongList('Riwayat dengar MusikKu', widget.recentlyPlayed),
      ),
      spacedCard(
        'Favorit MusikKu',
        '${widget.favorites.length} video tersimpan lokal',
        Icons.favorite_border_rounded,
        () => _showSongList('Favorit MusikKu', widget.favorites),
      ),
      spacedCard(
        'Radio otomatis',
        'Lanjutkan pemutaran dengan video sejenis',
        Icons.radio_rounded,
        _startRadioFromCollection,
      ),
      spacedCard(
        'Statistik mendengarkan',
        'Ringkasan aktivitas pemutaran',
        Icons.insights_outlined,
        () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => StatsPage(storage: _storage)),
        ),
      ),
      spacedCard(
        'Hemat data',
        'Atur request tambahan dan penyegaran feed',
        Icons.data_saver_on_outlined,
        _showDataSaverSheet,
      ),
      if (_selectedPlaylist != null) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedPlaylist!.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _selectedPlaylist = null;
                    _playlistItems = const [];
                  }),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Tutup playlist',
                ),
              ],
            ),
          ),
        ),
        if (_playlistItems.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(18), child: Text('Playlist kosong.')),
          )
        else
          SliverList.builder(
            itemCount: _playlistItems.length,
            itemBuilder: (context, index) => _videoCard(_playlistItems[index]),
          ),
      ],
    ];
  }

  void _startRadioFromCollection() {
    final seed = _subscriptionFeed.isNotEmpty
        ? _subscriptionFeed.first
        : widget.recentlyPlayed.isNotEmpty
            ? widget.recentlyPlayed.first
            : widget.favorites.isNotEmpty
                ? widget.favorites.first
                : _trending.isNotEmpty
                    ? _trending.first
                    : null;

    if (seed != null && widget.onStartRadio != null) {
      unawaited(widget.onStartRadio!(seed));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Belum ada lagu untuk memulai radio. Putar lagu dulu ya.')),
    );
  }


  Widget _loginCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.account_circle_rounded, size: 40),
            const SizedBox(height: 10),
            Text(
              _rememberedAccountEmail.isEmpty ? 'Hubungkan akun YouTube' : 'Akun YouTube tersimpan',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              _rememberedAccountEmail.isEmpty
                  ? 'Akses subscription, video yang disukai, dan playlist kamu.'
                  : 'Akun terakhir: $_rememberedAccountEmail. Tekan untuk memulihkan sesi Google tanpa harus memilih akun lagi bila sesi masih tersedia.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _login,
              icon: Icon(_rememberedAccountEmail.isEmpty ? Icons.login_rounded : Icons.restore_rounded),
              label: Text(_rememberedAccountEmail.isEmpty ? 'Hubungkan Google' : 'Pulihkan akun'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSongList(String title, List<YoutubeSearchResult> songs) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => SafeArea(
          child: ListView.builder(
            controller: controller,
            itemCount: songs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                );
              }
              final video = songs[index - 1];
              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(video.coverUrl, width: 96, height: 54, fit: BoxFit.cover),
                ),
                title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(widget.onPlay(video));
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showPlaylistPicker() {
    if (_playlists.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 18),
          children: [
            const ListTile(title: Text('Pilih playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
            ..._playlists.map(
              (playlist) => ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text(playlist.title),
                subtitle: Text('${playlist.itemCount} item • hanya musik ditampilkan'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_openPlaylist(playlist));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(child: Text((_user?.displayName ?? '?').characters.first.toUpperCase())),
              title: Text(_user?.displayName ?? 'Akun'),
              subtitle: Text(_user?.email ?? ''),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Keluar'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_logout());
              },
            ),
          ],
        ),
      ),
    );
  }

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
          if (_query.isNotEmpty || _section != _YoutubeSection.home) _topBar(),
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
          if (_query.isNotEmpty || _section != _YoutubeSection.home) _chipRow(),
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
          ] else if (_section == _YoutubeSection.subscriptions)
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
                setState(() {
                  _section = nextSection;
                  _selectedPlaylist = null;
                  _playlistItems = const [];
                });
                if (nextSection != _YoutubeSection.home && !_account.isSignedIn) {
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
                  icon: Icon(Icons.subscriptions_outlined),
                  selectedIcon: Icon(Icons.subscriptions_rounded),
                  label: 'Subscription',
                ),
                NavigationDestination(
                  icon: Icon(Icons.video_library_outlined),
                  selectedIcon: Icon(Icons.video_library_rounded),
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
