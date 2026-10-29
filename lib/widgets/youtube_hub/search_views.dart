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

  Future<void> _searchChannelsForCurrentQuery({bool artistMode = false}) async {
    final query = _query.trim();
    if (!mounted || query.isEmpty || _channelSearchLoading) return;
    final requestId = _searchRequestId;
    if (artistMode) {
      // Hasil pencarian sudah memuat channel artisnya (mis. 3+ lagu dari
      // channel yang namanya cocok). Pakai itu langsung: instan dan tanpa
      // request search.list tambahan.
      final local = _artistChannelsFromResults(query);
      if (local.isNotEmpty) {
        setState(() {
          _searchChannels = local;
          _artistChannelMode = true;
        });
        return;
      }
    }
    setState(() {
      _channelSearchLoading = true;
      _artistChannelMode = artistMode;
    });
    try {
      var channels = await _searchService.searchChannels(query);
      if (!mounted || requestId != _searchRequestId || query != _query.trim()) return;
      if (artistMode) {
        // Automatic artist discovery only keeps channels whose names actually
        // match the query (e.g. "Raisa Official" for "Raisa"). This avoids
        // showing unrelated channels and avoids a second search for ordinary
        // song/genre queries.
        channels = channels
            .where((channel) => _channelNameMatchesArtistQuery(channel.title, query))
            .toList(growable: false);
      }
      setState(() {
        _searchChannels = channels.take(8).toList(growable: false);
        _artistChannelMode = artistMode && _searchChannels.isNotEmpty;
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId || query != _query.trim()) return;
      setState(() {
        _artistChannelMode = false;
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

  String _normalizeArtistChannelName(String value) => value
      .toLowerCase()
      .replaceAll(
        RegExp(r'\b(?:official(?:\s+music)?(?:\s+channel)?|vevo|topic|music\s+channel|channel)\b', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _channelNameMatchesArtistQuery(String channelTitle, String query) {
    final normalizedQuery = _normalizeArtistChannelName(query);
    final normalizedChannel = _normalizeArtistChannelName(channelTitle);
    if (normalizedQuery.isEmpty || normalizedChannel.isEmpty) return false;
    if (normalizedChannel == normalizedQuery ||
        normalizedChannel.startsWith('$normalizedQuery ') ||
        normalizedQuery.startsWith('$normalizedChannel ')) {
      return true;
    }
    // Toleran terhadap spasi dan kata tambahan: "sheila on 7" ~ "SheilaOn7",
    // "hindia" ~ "Hindia Band".
    final compactQuery = normalizedQuery.replaceAll(' ', '');
    final compactChannel = normalizedChannel.replaceAll(' ', '');
    if (compactQuery.length >= 3 &&
        compactChannel.length >= 3 &&
        (compactChannel == compactQuery ||
            compactChannel.startsWith(compactQuery) ||
            compactQuery.startsWith(compactChannel))) {
      return true;
    }
    final channelTokens = normalizedChannel.split(' ').toSet();
    final queryTokens =
        normalizedQuery.split(' ').where((t) => t.length >= 2).toList();
    return queryTokens.isNotEmpty &&
        queryTokens.every(channelTokens.contains);
  }

  /// Turunkan kartu artis dari hasil pencarian yang sudah ada: channel yang
  /// namanya cocok dengan query dan memiliki minimal 3 lagu di hasil teratas.
  List<YoutubeChannelSearchResult> _artistChannelsFromResults(String query) {
    final counts = <String, int>{};
    final samples = <String, YoutubeSearchResult>{};
    for (final video in _searchResults.take(20)) {
      if (video.isLocal || video.channelTitle.trim().isEmpty) continue;
      final key = video.channelId.isNotEmpty
          ? video.channelId
          : _normalizeArtistChannelName(video.channelTitle);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      samples.putIfAbsent(key, () => video);
    }
    final ranked = counts.entries
        .where((entry) =>
            entry.value >= 3 &&
            _channelNameMatchesArtistQuery(
              samples[entry.key]!.channelTitle,
              query,
            ))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.take(3).map((entry) {
      final sample = samples[entry.key]!;
      return YoutubeChannelSearchResult(
        channelId: sample.channelId,
        title: sample.channelTitle,
        description: '',
        thumbnailUrl: '',
      );
    }).toList(growable: false);
  }

  bool _isLikelyArtistNameSearch(String query, List<YoutubeSearchResult> videos) {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length > 36) return false;
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.isEmpty || words.length > 2) return false;
    if (RegExp(
      r'\b(?:lagu|musik|music|song|songs|official|video|mv|lyrics?|lirik|audio|cover|remix|album|playlist|radio|mix|karaoke|soundtrack|terbaru|latest|hits|popular|populer)\b',
      caseSensitive: false,
    ).hasMatch(trimmed)) {
      return false;
    }

    final normalizedQuery = _normalizeArtistChannelName(trimmed);
    const genericGenreQueries = <String>{
      'pop', 'rock', 'jazz', 'metal', 'indie', 'dangdut', 'koplo', 'dj',
      'remix', 'k pop', 'hip hop', 'lofi', 'lo fi', 'radio', 'soundtrack',
      'instrumental', 'karaoke', 'chill', 'blues', 'reggae', 'classical',
      'country', 'folk', 'edm', 'house', 'techno', 'trance', 'ambient',
      'pop indonesia', 'rock indonesia', 'lagu inggris', 'lagu indonesia',
      'lagu jawa', 'lagu akustik', 'dangdut koplo', 'dj remix',
    };
    if (genericGenreQueries.contains(normalizedQuery) ||
        RegExp(r'\b(?:indonesia|inggris|english|jawa|akustik|acoustic)\b', caseSensitive: false)
            .hasMatch(normalizedQuery)) {
      return false;
    }
    if (normalizedQuery.isEmpty) return false;
    // Don't spend a channel-search request on obvious exact track-title queries.
    final exactSongTitle = videos.take(12).any((video) =>
        _normalizeArtistChannelName(video.title) == normalizedQuery);
    return !exactSongTitle;
  }

  void _openArtistCatalogue(YoutubeChannelSearchResult channel) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ArtistPage(
          artist: _query.trim().isNotEmpty ? _query.trim() : channel.title,
          channelId: channel.channelId,
          searchService: _searchService,
          initialSearchResults: _searchResults,
          onPlayList: widget.onPlayFromList,
          onPlay: (video) => unawaited(widget.onPlay(video)),
          onLongPress: widget.onShowVideoMenu,
        ),
      ),
    );
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
      _artistChannelMode = false;
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
        _artistChannelMode = false;
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
      // The secondary channel lookup is deferred until we know whether this
      // query looks like an artist name, to avoid extra requests for songs/genres.
      _searchChannels = const [];
      _channelSearchLoading = false;
      _artistChannelMode = false;
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

      final visibleVideos = videos.take(30).toList(growable: false);
      setState(() {
        _searchResults = visibleVideos;
        _searchHistory = updatedHistory;
      });
      unawaited(_storage.saveHistory(updatedHistory));

      // Artist-name searches get an artist entry automatically, like a music
      // catalogue. Song titles and genre queries keep the single search.list
      // request path; channel discovery is only triggered for likely names.
      if (_isLikelyArtistNameSearch(query, visibleVideos)) {
        unawaited(_searchChannelsForCurrentQuery(artistMode: true));
      } else if (query.split(RegExp(r'\s+')).length <= 4) {
        // Nama artis 3-4 kata ("Sheila On 7", "Hindia Band"): hanya jalur
        // gratis dari hasil yang sudah ada, tanpa request tambahan.
        final local = _artistChannelsFromResults(query);
        if (local.isNotEmpty) {
          setState(() {
            _searchChannels = local;
            _artistChannelMode = true;
          });
        }
      }
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FlowPageHero(
                icon: Icons.radio_rounded,
                eyebrow: 'MUSIC DISCOVERY',
                title: 'Radio untuk selera kamu',
                subtitle: 'Mulai dari satu lagu, lalu temukan lagu lain yang nyambung. Rekomendasi mempertimbangkan gaya musik, artis, dan bahasa.',
              ),
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
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
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
            height: 260,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FlowPageHero(
                icon: Icons.explore_rounded,
                eyebrow: 'DISCOVER YOUR SOUND',
                title: 'Jelajahi musik',
                subtitle: 'Pilih genre untuk menemukan katalog musik yang lebih relevan dengan suasana kamu.',
              ),
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
        child: SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
            itemCount: _YoutubeHubState._exploreCategories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = _YoutubeHubState._exploreCategories[index];
              final selected = _exploreCategory == category;
              return ChoiceChip(
                label: Text(category),
                selected: selected,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (value) {
                  if (value && category != _exploreCategory) unawaited(_loadExploreCategory(category));
                },
                backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
                selectedColor: scheme.primary,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                labelStyle: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? scheme.onPrimary : scheme.onSurfaceVariant),
              );
            },
          ),
        ),
      ),
      if (shownLoading && shownResults.isEmpty)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator())))
      else if (shownError.isNotEmpty && shownResults.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
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
              selectedColor: scheme.primary,
              backgroundColor: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              labelStyle: TextStyle(
                color: selected
                    ? scheme.onPrimary
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