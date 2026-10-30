part of '../home_page.dart';

/// Layout utama MusikKu. Halaman Now Playing audio-only ditumpuk di atas hub;
/// ketika halaman ditutup, mini-player tetap berada di atas navigation bar.
extension _HomeUiLayout on _HomePageState {
  Widget _buildScaffold(BuildContext context) {
    final watch = _youtubeWatchVideo;
    final current = _currentVideo;
    final showMiniPlayer = watch == null && current != null;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: MusicBackdrop(
        child: Stack(
          children: [
            Positioned.fill(
              // Keep the feed alive so its scroll/navigation state survives, but
              // do not paint it below the full player. Platform-backed previews
              // can otherwise look like a giant, duplicated artwork backdrop.
              child: Offstage(
                offstage: watch != null,
                child: IgnorePointer(
                  ignoring: watch != null,
                  child: YoutubeHub(
                    controller: _hubController,
                    onPlay: _openYoutubeVideo,
                    onClose: _closeYoutubeWatch,
                    // Reserve room above navigation for the persistent mini-player.
                    bottomInset: showMiniPlayer ? 90 : 0,
                    watchProgress: _watchProgress,
                    watchDuration: _watchDuration,
                    recentlyPlayed: _recentlyPlayed,
                    favorites: _favorites,
                    listeningStats: _listeningStatsById.values.toList(growable: false),
                    customPlaylistCount: _playlists.length,
                    onOpenCustomPlaylists: _openCustomPlaylistsPage,
                    currentVideoId: current?.videoId,
                    onStartRadio: _startRadioFromVideo,
                    onPlayFromList: _playFromCustomList,
                    onAddToQueue: _addToQueue,
                    onShowVideoMenu: (video) => _showVideoMenu(video),
                    onSearchQueryChanged: (query) {
                      _lastSearchQuery = query.trim();
                    },
                    onOpenListeningRoom: _showListenTogetherSheet,
                    onOpenAudioSettings: _showAudioSettingsSheet,
                    settings: widget.settings,
                  ),
                ),
              ),
            ),
            if (showMiniPlayer)
              Positioned(
                left: 12,
                right: 12,
                // Keep a real 14dp gap above the 66dp floating dock. Include the
                // Android gesture/system inset so the mini-player never touches it.
                bottom: safeBottom + 66 + 8 + 12,
                child: MiniMusicPlayer(
                  key: ValueKey<String>('mini-music-player-${current.videoId}'),
                  video: current,
                  nativeState: _nativeStateNotifier,
                  onOpen: _openYoutubeWatchFromPlayer,
                  onPlayPause: () => _routeListenTogetherAction('play_pause', _togglePlayPause),
                  onNext: () => _routeListenTogetherAction('next', () => _next()),
                ),
              ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: watch == null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 460),
                  reverseDuration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  // Short, soft lift: gives the player a clear entrance without
                  // changing the stable layout of the music controls.
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(
                        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                      ),
                      child: child,
                    ),
                  ),
                  child: watch == null
                      ? const SizedBox.shrink(key: ValueKey<String>('player-closed'))
                      : MusicPlayerPage(
                          key: const ValueKey<String>('music-player'),
                          video: watch,
                          nextVideo: _queueManager.peekFirst()?.video,
                          nativeState: _nativeStateNotifier,
                          playerUiState: _playerUiState,
                          onBack: () => unawaited(_closeYoutubeWatch()),
                          onPlayPause: () => _routeListenTogetherAction('play_pause', _togglePlayPause),
                          onNext: () => _routeListenTogetherAction('next', () => _next()),
                          onPrevious: () => _routeListenTogetherAction('previous', _previous),
                          onSeek: (position) => _routeListenTogetherAction(
                            'seek',
                            () => _youtubeController.seekTo(
                              seconds: position.inMilliseconds / 1000.0,
                            ),
                            position: position,
                          ),
                          onToggleShuffle: () => _routeListenTogetherModeAction('shuffle', _toggleShuffle),
                          onToggleSmartShuffle: () => _routeListenTogetherModeAction('smart_shuffle', _toggleSmartShuffle),
                          onCycleLoop: () => _routeListenTogetherModeAction('loop', _cycleLoopMode),
                          onToggleFavorite: () => _toggleFavorite(watch),
                          onAddToPlaylist: () => _showAddToPlaylist(watch),
                          onOpenQueue: _showQueueSheet,
                          onOpenSleepTimer: _showSleepTimerSheet,
                          onOpenListeningRoom: _showListenTogetherSheet,
                          followingRoom: _listenTogether.isGuest,
                          // Recompute from the saved playlists so the button
                          // updates immediately after a song is added or removed.
                          inPlaylist: _playlists.any(
                            (playlist) => playlist.contains(watch.videoId),
                          ),
                          sleepActive: _sleepActive,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
