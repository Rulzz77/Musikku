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

  void _prepareShufflePool({
    bool excludeCurrent = true,
    YoutubeSearchResult? sourceVideo,
  }) {
    final style = _shuffleMusicStyle;
    final reference = sourceVideo ?? _currentVideo;
    final bool? localSource = reference?.isLocal;
    _shufflePool = _activeList.where((video) {
      if (localSource != null && video.isLocal != localSource) return false;
      return MusicStyleMatcher.isCompatible(video: video, targetStyle: style);
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
    var score = 10.0;

    if (_likedIds.contains(video.videoId)) {
      score += 10.0;
    }
    if (_dislikedIds.contains(video.videoId)) {
      score -= 100.0;
    }

    if (stat != null) {
      score += (stat.playCount.clamp(0, 8) as num).toDouble() * 1.8;
      score += (stat.listenedSeconds / 600.0).clamp(0.0, 4.0);
      score -= (stat.skipCount.clamp(0, 6) as num).toDouble() * 4.5;

      final lastPlayed = stat.lastPlayedAt;
      if (lastPlayed != null) {
        final hours = DateTime.now().difference(lastPlayed).inMinutes / 60.0;
        if (hours < 24) {
          score -= (24.0 - hours).clamp(0.0, 24.0) / 3.0;
        }
      }
    }

    // Variasi artis: Smart Shuffle sengaja memberi penalti ke artis yang sama
    // dengan lagu aktif agar hasilnya tidak terasa seperti album yang berulang.
    if (currentArtist != null &&
        currentArtist.isNotEmpty &&
        video.channelTitle.trim().toLowerCase() == currentArtist.trim().toLowerCase()) {
      score -= 9.0;
    }

    // Sedikit jitter membuat urutannya tetap bervariasi tanpa kehilangan sinyal
    // personalisasi. Ini bukan random murni.
    score += _random.nextDouble() * 2.5;
    return score;
  }

  YoutubeSearchResult? _takeShuffleVideo() {
    final style = _shuffleMusicStyle;
    final current = _currentVideo;
    _shufflePool.removeWhere((video) {
      // Secondary guard: a stale/mixed pool must never switch local ↔ YouTube.
      if (current != null && video.isLocal != current.isLocal) return true;
      return !MusicStyleMatcher.isCompatible(video: video, targetStyle: style);
    });
    if (_shufflePool.isEmpty) {
      return null;
    }

    // Kandidat yang label genrenya cocok didahulukan; lagu tanpa label genre
    // baru menjadi fallback setelah kandidat yang dikenali habis.
    final preferred = MusicStyleMatcher.prioritizeStyle(_shufflePool, style);
    final candidatesPool = preferred.isNotEmpty ? preferred : _shufflePool;

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

  void _showVideoMenu(YoutubeSearchResult video, {Playlist? fromPlaylist}) {
    showVideoMenuSheet(
      context,
      video: video,
      isFavorite: _isFavorite(video.videoId),
      isLiked: _likedIds.contains(video.videoId),
      isDisliked: _dislikedIds.contains(video.videoId),
      onLike: () => _toggleLike(video),
      onDislike: () => _toggleDislike(video),
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
            _queueManager.clear();
            await _storage.saveQueue(_queueManager.items);
            if (mounted) setState(() {});
            setSheetState(() {});
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
                            return Card(
                              key: ValueKey<String>(item.id),
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: scheme.surfaceContainerLow,
                              child: ListTile(
                                onTap: () {
                                  _queueManager.remove(video.videoId);
                                  unawaited(_storage.saveQueue(_queueManager.items));
                                  Navigator.of(sheetContext).pop();
                                  unawaited(_playVideo(video));
                                },
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 54,
                                    height: 54,
                                    child: video.coverUrl.isEmpty
                                        ? ColoredBox(color: scheme.surfaceContainerHighest, child: Icon(Icons.music_note_rounded, color: scheme.onSurfaceVariant))
                                        : Image.network(video.coverUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: scheme.surfaceContainerHighest, child: Icon(Icons.music_note_rounded, color: scheme.onSurfaceVariant))),
                                  ),
                                ),
                                title: Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                subtitle: Text(video.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Hapus dari antrean',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        _queueManager.remove(video.videoId);
                                        unawaited(_storage.saveQueue(_queueManager.items));
                                        if (mounted) setState(() {});
                                        setSheetState(() {});
                                      },
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                    ),
                                    ReorderableDragStartListener(index: index, child: Icon(Icons.drag_handle_rounded, color: scheme.onSurfaceVariant)),
                                  ],
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
