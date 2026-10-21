part of '../youtube_hub.dart';

// The state extensions share private UI logic; State.setState is used by this library.
// ignore_for_file: invalid_use_of_protected_member

extension _YoutubeHubSearchViews on _YoutubeHubState {
  Future<void> _openSearch() async {
    if (!mounted) return;
    final picked = await Navigator.of(context).push<YoutubeSearchRequest>(
      MaterialPageRoute(
        builder: (_) => YoutubeSearchPage(
          suggestService: _suggestService,
          initialQuery: _query,
          history: _searchHistory,
          onDeleteHistory: _deleteSearchHistory,
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

  Future<void> _searchChannelsForCurrentQuery() async {
    final query = _query.trim();
    if (!mounted || query.isEmpty || _channelSearchLoading) return;
    final requestId = _searchRequestId;
    setState(() => _channelSearchLoading = true);
    try {
      final channels = await _searchService.searchChannels(query);
      if (!mounted || requestId != _searchRequestId || query != _query.trim()) return;
      setState(() => _searchChannels = channels.take(8).toList(growable: false));
    } catch (error) {
      if (!mounted || requestId != _searchRequestId || query != _query.trim()) return;
      setState(() {
        _error = error is YoutubeSearchException
            ? error.message
            : 'Pencarian channel gagal. Coba lagi nanti.';
      });
    } finally {
      if (mounted && requestId == _searchRequestId && query == _query.trim()) {
        setState(() => _channelSearchLoading = false);
      }
    }
  }

  Future<void> _deleteSearchHistory(String? query) async {
    final updated = query == null
        ? <String>[]
        : _searchHistory
            .where((item) => item.toLowerCase() != query.toLowerCase())
            .toList(growable: false);
    await _storage.saveHistory(updated);
    if (!mounted) return;
    setState(() => _searchHistory = updated);
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
      _channelSearchLoading = false;
    });
    unawaited(_loadHome());
  }

  /// Set state loading pencarian langsung agar indikator muncul seketika.
  /// _query diisi sebelum request selesai supaya hasil pencarian responsif.
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
        _channelSearchLoading = false;
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
      }
      // Channel search is requested only when the user taps its button;
      // do not spend a second search.list call for every song query.
      _searchChannels = const [];
      _channelSearchLoading = false;
      _section = _YoutubeSection.home;
      _loading = true;
      _error = '';
    });

    try {
      final videos = await _searchService.search(query, filter: _searchMode);
      if (!mounted || requestId != _searchRequestId) return;

      final updatedHistory = List<String>.from(_searchHistory)
        ..removeWhere((item) => item.toLowerCase() == query.toLowerCase())
        ..insert(0, query);
      if (updatedHistory.length > StorageService.maxHistory) {
        updatedHistory.removeRange(StorageService.maxHistory, updatedHistory.length);
      }

      setState(() {
        _searchResults = videos.take(30).toList(growable: false);
        _searchHistory = updatedHistory;
      });
      unawaited(_storage.saveHistory(updatedHistory));
    } catch (e) {
      if (!mounted || requestId != _searchRequestId) return;
      debugPrint('YOUTUBE SEARCH ERROR: $e');
      setState(() {
        _error = e is YoutubeSearchException ? e.message : _formatHubError(e);
      });
    } finally {
      if (mounted && requestId == _searchRequestId) {
        setState(() => _loading = false);
      }
    }
  }

  List<YoutubeSearchResult> _sampleVideos() {
    final result = <YoutubeSearchResult>[];
    final seen = <String>{};
    for (final video in [..._trending, ...widget.recentlyPlayed]) {
      if (video.videoId.isNotEmpty &&
          !video.isLive &&
          !video.isUpcoming &&
          YoutubeSearchService.isMusicCandidate(video) &&
          seen.add(video.videoId)) {
        result.add(video);
      }
    }
    return result;
  }

  Future<void> _loadExploreCategory(String category, {bool force = false}) async {
    final requestSequence = ++_exploreRequestSequence;
    if (category == 'Sedang tren') {
      setState(() {
        _exploreCategory = category;
        _exploreResults = _trending;
        _exploreError = _feedError;
        _exploreLoading = false;
      });
      if (_trending.isEmpty && !_feedLoading) {
        await _loadHome(force: force);
        if (!mounted ||
            requestSequence != _exploreRequestSequence ||
            _exploreCategory != category) {
          return;
        }
        setState(() {
          _exploreResults = _trending;
          _exploreError = _feedError;
          _exploreLoading = false;
        });
      }
      return;
    }
    if (!force && category == _exploreCategory && _exploreResults.isNotEmpty) {
      if (mounted && _exploreLoading) setState(() => _exploreLoading = false);
      return;
    }
    final query = _YoutubeHubState._exploreQueries[category];
    if (query == null) return;
    setState(() {
      _exploreCategory = category;
      _exploreLoading = true;
      _exploreError = '';
    });
    try {
      final results = await _searchService.search(query, filter: 'music');
      if (!mounted ||
          requestSequence != _exploreRequestSequence ||
          _exploreCategory != category) {
        return;
      }
      setState(() {
        _exploreResults = results.where((video) => !video.isLive && !video.isUpcoming).toList(growable: false);
        _exploreError = '';
      });
    } catch (error) {
      if (!mounted ||
          requestSequence != _exploreRequestSequence ||
          _exploreCategory != category) {
        return;
      }
      setState(() {
        _exploreResults = const [];
        _exploreError = error is YoutubeSearchException
            ? error.message
            : 'Belum bisa memuat genre ini. Periksa koneksi lalu coba lagi.';
      });
    } finally {
      if (mounted &&
          requestSequence == _exploreRequestSequence &&
          _exploreCategory == category) {
        setState(() => _exploreLoading = false);
      }
    }
  }

  List<Widget> _samplesView() {
    final videos = _sampleVideos();
    YoutubeSearchResult? seedVideo;
    for (final video in videos) {
      if (video.videoId == widget.currentVideoId) {
        seedVideo = video;
        break;
      }
    }
    final radioSeed = seedVideo ?? (videos.isEmpty ? null : videos.first);
    final scheme = Theme.of(context).colorScheme;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Radio untuk selera kamu', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.7)),
              const SizedBox(height: 6),
              Text('Mulai dari satu lagu, lalu lanjutkan ke rekomendasi yang diacak tetapi tetap nyambung. Bahasa boleh berganti kalau gaya musiknya cocok.', style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: videos.isEmpty ? null : () => unawaited(widget.onPlayFromList(videos.first, videos)),
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('Putar mix'),
                  ),
                  OutlinedButton.icon(
                    onPressed: radioSeed == null || widget.onStartRadio == null
                        ? null
                        : () => unawaited(widget.onStartRadio!(radioSeed)),
                    icon: const Icon(Icons.radio_rounded, size: 18),
                    label: const Text('Mulai radio'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _feedLoading ? null : () => unawaited(_loadHome(force: true)),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Segarkan'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (videos.isEmpty && _feedLoading)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator())))
      else if (videos.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.explore_rounded, size: 44),
                    const SizedBox(height: 10),
                    const Text('Radio belum tersedia', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(_feedError.isNotEmpty ? _feedError : 'Muat rekomendasi musik terlebih dahulu.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: () => unawaited(_loadHome(force: true)), icon: const Icon(Icons.refresh_rounded), label: const Text('Muat ulang')),
                  ],
                ),
              ),
            ),
          ),
        )
      else ...[
        SliverToBoxAdapter(
          child: SizedBox(
            height: 304,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: min(videos.length, 14).toInt(),
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _sampleCard(videos[index]),
            ),
          ),
        ),
        _sectionHeader('Terus jelajahi'),
        SliverList.builder(
          itemCount: videos.length,
          itemBuilder: (context, index) => _videoCard(videos[index]),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
  }

  List<Widget> _exploreView() {
    final scheme = Theme.of(context).colorScheme;
    final exploreSource = _exploreCategory == 'Sedang tren' ? _trending : _exploreResults;
    final shownResults = exploreSource.where((video) => YoutubeSearchService.isMusicCandidate(video)).toList(growable: false);
    final shownLoading = _exploreCategory == 'Sedang tren' ? _feedLoading : _exploreLoading;
    final shownError = _exploreCategory == 'Sedang tren' ? _feedError : _exploreError;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Jelajahi musik', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.7)),
              const SizedBox(height: 6),
              Text('Pilih genre untuk mencari katalog musik yang relevan.', style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
              if (shownResults.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => unawaited(widget.onPlayFromList(shownResults.first, shownResults)),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Putar semua'),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.onStartRadio == null ? null : () => unawaited(widget.onStartRadio!(shownResults.first)),
                      icon: const Icon(Icons.radio_rounded, size: 18),
                      label: const Text('Radio genre'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in _YoutubeHubState._exploreCategories)
                ChoiceChip(
                  label: Text(category),
                  selected: _exploreCategory == category,
                  showCheckmark: false,
                  onSelected: (selected) { if (selected && category != _exploreCategory) unawaited(_loadExploreCategory(category)); },
                ),
            ],
          ),
        ),
      ),
      if (shownLoading && shownResults.isEmpty)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator())))
      else if (shownError.isNotEmpty && shownResults.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 40),
                    const SizedBox(height: 10),
                    const Text('Musik belum bisa dimuat', style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(shownError, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: () => unawaited(_loadExploreCategory(_exploreCategory, force: true)), icon: const Icon(Icons.refresh_rounded), label: const Text('Coba lagi')),
                  ],
                ),
              ),
            ),
          ),
        )
      else if (shownResults.isEmpty)
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Belum ada hasil untuk genre ini.', style: TextStyle(color: scheme.onSurfaceVariant)))))
      else ...[
        _sectionHeader('Pilihan ${_exploreCategory.toLowerCase()}'),
        SliverList.builder(itemCount: shownResults.length, itemBuilder: (context, index) => _videoCard(shownResults[index])),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ];
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
}
