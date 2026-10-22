part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Antrean, shuffle pool, dan menu video.
extension _HomeQueue on _HomePageState {
  String? get _shuffleMusicStyle {
    if (_activeSource == _ListSource.favorites ||
        _activeSource == _ListSource.playlist ||
        _activeSource == _ListSource.local ||
        _activeSource == _ListSource.collection) {
      return null; // Jangan memaksakan filter genre pada playlist/koleksi yang sudah dipilih.
    }

    final query = _activeSource == _ListSource.radio && _radio.hasSeed
        ? _radio.seed
        : _lastSearchQuery;
    return MusicStyleMatcher.styleForContext(
      query: query,
      currentVideo: _currentVideo,
    );
  }

  String? get _shuffleMusicLanguage {
    if (_activeSource == _ListSource.favorites ||
        _activeSource == _ListSource.playlist ||
        _activeSource == _ListSource.local ||
        _activeSource == _ListSource.collection) {
      return null;
    }
    final query = _activeSource == _ListSource.radio && _radio.hasSeed
        ? _radio.seed
        : _lastSearchQuery;
    return MusicStyleMatcher.languageForContext(
      query: query,
      currentVideo: _currentVideo,
    );
  }

  void _prepareShufflePool({
    bool excludeCurrent = true,
    YoutubeSearchResult? sourceVideo,
  }) {
    final style = _shuffleMusicStyle;
    final language = _shuffleMusicLanguage;
    final reference = sourceVideo ?? _currentVideo;
    final bool? localSource = reference?.isLocal;
    final allowMixedPlaylistSources =
        _activeSource == _ListSource.playlist && _activePlaylistId != null;
    _shufflePool = _activeList.where((video) {
      if (!allowMixedPlaylistSources &&
          localSource != null &&
          video.isLocal != localSource) {
        return false;
      }
      return MusicStyleMatcher.isCompatible(
        video: video,
        targetStyle: style,
        targetLanguage: language,
        allowCrossLanguage: _activeSource == _ListSource.radio && !_radio.locksLanguage,
      );
    }).toList();

    final excludedId = sourceVideo?.videoId ?? _currentVideo?.videoId;
    if (excludeCurrent && excludedId != null && excludedId.isNotEmpty) {
      _shufflePool.removeWhere((video) => video.videoId == excludedId);
    }
  }

  /// Queue boleh berisi sumber campuran karena item dapat ditambahkan manual.
  /// Saat Shuffle aktif, hanya ambil item dari sumber yang sedang diputar;
  /// item dari sumber lain tetap menunggu di antrean.
  QueueItem? _takeQueueItemForCurrentMode({required bool shuffle}) {
    if (_queueManager.isEmpty) return null;
    if (!shuffle) return _queueManager.takeFirst();

    final current = _currentVideo;
    if (current == null) return _queueManager.takeRandom();

    bool matchesSource(YoutubeSearchResult video) =>
        video.isLocal == current.isLocal;

    if (_playerUiState.value.isSmartShuffle) {
      return _queueManager.takeSmartMatching(
        matches: matchesSource,
        score: (video) => _smartShuffleScore(
          video,
          currentArtist: current.channelTitle,
        ),
      );
    }
    return _queueManager.takeRandomMatching(matchesSource);
  }

  double _smartShuffleScore(
    YoutubeSearchResult video, {
    String? currentArtist,
  }) {
    final stat = _listeningStatsById[video.videoId];
    final artistKey = SmartQueueScorer.normalizeArtist(video.channelTitle);
    var artistPlayCount = 0;
    var artistSkipCount = 0;
    var artistHasLikedTrack = false;

    if (artistKey.isNotEmpty) {
      for (final entry in _listeningStatsById.entries) {
        if (SmartQueueScorer.normalizeArtist(entry.value.artist) != artistKey) {
          continue;
        }
        artistPlayCount += entry.value.playCount;
        artistSkipCount += entry.value.skipCount;
        if (_likedIds.contains(entry.key)) artistHasLikedTrack = true;
      }
    }

    return SmartQueueScorer.score(
          video: video,
          stat: stat,
          isLiked: _likedIds.contains(video.videoId),
          isDisliked: _dislikedIds.contains(video.videoId),
          currentArtist: currentArtist,
          artistPlayCount: artistPlayCount,
          artistSkipCount: artistSkipCount,
          artistHasLikedTrack: artistHasLikedTrack,
        ) +
        _random.nextDouble() * 2.5;
  }

  YoutubeSearchResult? _takeShuffleVideo() {
    final style = _shuffleMusicStyle;
    final language = _shuffleMusicLanguage;
    final current = _currentVideo;
    _shufflePool.removeWhere((video) {
      // Explicit custom playlists may intentionally mix local and YouTube
      // tracks. Other Shuffle sessions stay source-pure.
      final allowMixedPlaylistSources =
          _activeSource == _ListSource.playlist && _activePlaylistId != null;
      if (!allowMixedPlaylistSources &&
          current != null &&
          video.isLocal != current.isLocal) {
        return true;
      }
      return !MusicStyleMatcher.isCompatible(
        video: video,
        targetStyle: style,
        targetLanguage: language,
        allowCrossLanguage: _activeSource == _ListSource.radio && !_radio.locksLanguage,
      );
    });
    if (_shufflePool.isEmpty) {
      return null;
    }

    // Kandidat yang label genrenya cocok didahulukan; lagu tanpa label genre
    // baru menjadi fallback setelah kandidat yang dikenali habis.
    final bool radioMix = _activeSource == _ListSource.radio && !_radio.locksLanguage;
    late final List<YoutubeSearchResult> candidatesPool;
    if (radioMix) {
      candidatesPool = MusicStyleMatcher.rankForRadio(
        _shufflePool,
        targetStyle: style,
        targetLanguage: language,
        allowCrossLanguage: true,
      );
    } else {
      final languageCandidates = MusicStyleMatcher.prioritizeLanguage(_shufflePool, language);
      final preferred = MusicStyleMatcher.prioritizeStyle(
        languageCandidates,
        style,
        targetLanguage: language,
      );
      candidatesPool = preferred.isNotEmpty
          ? preferred
          : (languageCandidates.isNotEmpty ? languageCandidates : _shufflePool);
    }

    if (!_playerUiState.value.isSmartShuffle) {
      final selected = candidatesPool[_random.nextInt(candidatesPool.length)];
      _shufflePool.removeWhere((video) => video.videoId == selected.videoId);
      return selected;
    }

    final currentArtist = _currentVideo?.channelTitle;
    final scored = candidatesPool
        .map(
          (video) => (
            video: video,
            score: _smartShuffleScore(video, currentArtist: currentArtist),
          ),
        )
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    // Ambil dari beberapa kandidat teratas supaya tetap terasa acak, tetapi
    // tidak kehilangan preferensi user.
    final topCount = scored.length < 6 ? scored.length : 6;
    final top = scored.take(topCount).map((item) => item.video).toList();
    final differentArtist = currentArtist == null
        ? top
        : top
            .where(
              (video) => video.channelTitle.trim().toLowerCase() !=
                  currentArtist.trim().toLowerCase(),
            )
            .toList();

    final candidates = differentArtist.isNotEmpty ? differentArtist : top;
    final selected = candidates[_random.nextInt(candidates.length)];
    _shufflePool.removeWhere((video) => video.videoId == selected.videoId);
    return selected;
  }

  void _addToQueue(YoutubeSearchResult video) {
    final added = _queueManager.add(video);

    if (added) {
      unawaited(_storage.saveQueue(_queueManager.items));
    }

    if (!mounted) {
      return;
    }

    setState(() {});

    _toast(
      added
          ? '"${video.title}" ditambahkan ke antrean'
          : '"${video.title}" sudah ada di antrean',
    );
  }

  void _playNext(YoutubeSearchResult video) {
    _queueManager.addNext(video);
    unawaited(_storage.saveQueue(_queueManager.items));

    if (!mounted) {
      return;
    }

    setState(() {});

    _toast('"${video.title}" akan diputar berikutnya');
  }

  Future<void> _toggleChannelBlock(YoutubeSearchResult video) async {
    final keys = ChannelBlockFilter.keysFor(video);
    if (keys.isEmpty) return;

    final alreadyBlocked = keys.any(_blockedChannelKeys.contains);
    setState(() {
      if (alreadyBlocked) {
        _blockedChannelKeys.removeAll(keys);
      } else {
        _blockedChannelKeys.addAll(keys);
      }
    });
    await _storage.saveBlockedChannelKeys(_blockedChannelKeys);

    // Refresh the recommendation pool so an updated block immediately affects
    // the next Radio choice. The current song is not interrupted.
    if (_radio.hasSeed) {
      _radio.restart(_radio.seed);
      unawaited(_radio.refill());
    }

    _toast(
      alreadyBlocked
          ? 'Rekomendasi channel diizinkan lagi'
          : 'Channel disembunyikan dari rekomendasi Radio',
      duration: const Duration(seconds: 2),
    );
  }

  void _showVideoMenu(YoutubeSearchResult video, {Playlist? fromPlaylist}) {
    showVideoMenuSheet(
      context,
      video: video,
      isFavorite: _isFavorite(video.videoId),
      isLiked: _likedIds.contains(video.videoId),
      isDisliked: _dislikedIds.contains(video.videoId),
      isChannelBlocked: ChannelBlockFilter.isBlocked(video, _blockedChannelKeys),
      onLike: () => _toggleLike(video),
      onDislike: () => _toggleDislike(video),
      onToggleChannelBlock: () => _toggleChannelBlock(video),
      onOpenArtist: () => _openArtist(video.channelTitle),
      onPlayNext: () => _playNext(video),
      onAddToQueue: () => _addToQueue(video),
      onToggleFavorite: () => _toggleFavorite(video),
      onAddToPlaylist: () => _showAddToPlaylist(video),
      onStartRadio: () => _startRadioFromVideo(video),
      onRemoveFromPlaylist: fromPlaylist == null
          ? null
          : () => _removeFromPlaylist(fromPlaylist, video),
    );
  }
}

// Sheet antrean terpadu dari layar Now Playing. Perubahan urutan, hapus item,
// dan clear queue langsung disimpan sehingga antrean pulih setelah aplikasi dibuka lagi.
extension _HomeQueueSheet on _HomePageState {
  void _showQueueSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          final items = _queueManager.items;
          final current = _currentVideo;
          final maxHeight = MediaQuery.sizeOf(context).height * 0.82;

          final messenger = ScaffoldMessenger.of(context);

          Future<void> clearQueue() async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Kosongkan antrean?'),
                content: const Text('Semua lagu yang menunggu akan dihapus dari antrean.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
                  FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Kosongkan')),
                ],
              ),
            );
            if (confirm != true) return;
            final previousItems = List<QueueItem>.from(_queueManager.items);
            if (previousItems.isEmpty) return;
            _queueManager.clear();
            await _storage.saveQueue(_queueManager.items);
            if (mounted) setState(() {});
            if (sheetContext.mounted) setSheetState(() {});
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text('${previousItems.length} lagu dihapus dari antrean'),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'URUNGKAN',
                  onPressed: () {
                    // Restore missing entries at their former indexes without
                    // deleting songs that may have been added after clearing.
                    for (var i = 0; i < previousItems.length; i++) {
                      _queueManager.restoreAtIndex(previousItems[i], i);
                    }
                    unawaited(_storage.saveQueue(_queueManager.items));
                    if (mounted) setState(() {});
                    if (sheetContext.mounted) setSheetState(() {});
                  },
                ),
              ),
            );
          }

          void removeFromQueueWithUndo(YoutubeSearchResult video) {
            final removal = _queueManager.removeWithIndex(video.videoId);
            if (removal == null) return;
            unawaited(_storage.saveQueue(_queueManager.items));
            if (mounted) setState(() {});
            setSheetState(() {});
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text('"${video.title}" dihapus dari antrean'),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: 'URUNGKAN',
                  onPressed: () {
                    final restored = _queueManager.restoreAtIndex(
                      removal.item,
                      removal.index,
                    );
                    if (!restored) return;
                    unawaited(_storage.saveQueue(_queueManager.items));
                    if (mounted) setState(() {});
                    if (sheetContext.mounted) setSheetState(() {});
                  },
                ),
              ),
            );
          }

          return SizedBox(
            height: maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Antrean putar', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.45)),
                            const SizedBox(height: 3),
                            Text('${items.length} lagu menunggu', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (items.isNotEmpty)
                        IconButton(
                          tooltip: 'Kosongkan antrean',
                          onPressed: () => unawaited(clearQueue()),
                          icon: const Icon(Icons.delete_sweep_outlined),
                        ),
                      if (items.isNotEmpty)
                        IconButton.filledTonal(
                          tooltip: 'Putar lagu pertama di antrean',
                          onPressed: () {
                            final first = _queueManager.takeFirst();
                            if (first == null) return;
                            unawaited(_storage.saveQueue(_queueManager.items));
                            Navigator.of(sheetContext).pop();
                            unawaited(_playVideo(first.video));
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                        ),
                    ],
                  ),
                ),
                if (current != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.graphic_eq_rounded, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('SEDANG DIPUTAR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1, color: scheme.primary)),
                              const SizedBox(height: 3),
                              Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text(current.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.queue_music_rounded, size: 54, color: scheme.onSurfaceVariant.withValues(alpha: 0.65)),
                                const SizedBox(height: 12),
                                const Text('Antrean masih kosong', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                                const SizedBox(height: 5),
                                Text('Tambahkan lagu lewat menu ⋮ pada kartu lagu.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          itemCount: items.length,
                          onReorderItem: (oldIndex, newIndex) {
                            // onReorderItem sudah menyesuaikan newIndex untuk item
                            // yang dipindahkan; jangan kurangi indeks lagi.
                            final target = newIndex.clamp(0, items.length - 1).toInt();
                            _queueManager.move(oldIndex: oldIndex, newIndex: target);
                            unawaited(_storage.saveQueue(_queueManager.items));
                            if (mounted) setState(() {});
                            setSheetState(() {});
                          },
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final video = item.video;
                            return Padding(
                              key: ValueKey<String>(item.id),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Material(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () {
                                    _queueManager.remove(video.videoId);
                                    unawaited(_storage.saveQueue(_queueManager.items));
                                    Navigator.of(sheetContext).pop();
                                    unawaited(_playVideo(video));
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(13),
                                          child: SizedBox(
                                            width: 54,
                                            height: 54,
                                            child: video.coverUrl.isEmpty
                                                ? ColoredBox(color: scheme.surfaceContainerHighest, child: Icon(Icons.music_note_rounded, color: scheme.onSurfaceVariant))
                                                : Image.network(video.coverUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest, child: Icon(Icons.music_note_rounded, color: scheme.onSurfaceVariant))),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                              const SizedBox(height: 4),
                                              Text(video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                              const SizedBox(height: 5),
                                              Text('MENUNGGU DIPUTAR', style: TextStyle(fontSize: 8.5, letterSpacing: 0.8, fontWeight: FontWeight.w900, color: scheme.primary)),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Hapus dari antrean',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => removeFromQueueWithUndo(video),
                                          icon: const Icon(Icons.close_rounded, size: 20),
                                        ),
                                        ReorderableDragStartListener(
                                          index: index,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 5),
                                            child: Icon(Icons.drag_handle_rounded, color: scheme.onSurfaceVariant),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
