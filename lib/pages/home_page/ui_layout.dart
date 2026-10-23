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
      body: Stack(
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
                  settings: widget.settings,
                ),
              ),
            ),
          ),
          if (showMiniPlayer)
            Positioned(
              left: 12,
              right: 12,
              // Keep a real 14dp gap above the 64dp glass dock. Include the
              // Android gesture/system inset so the mini-player never touches it.
              bottom: safeBottom + 64 + 8 + 14,
              child: MiniMusicPlayer(
                key: ValueKey<String>('mini-music-player-${current.videoId}'),
                video: current,
                nativeState: _nativeStateNotifier,
                onOpen: _openYoutubeWatchFromPlayer,
                onPlayPause: _togglePlayPause,
                onNext: () => _next(),
              ),
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: watch == null,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 340),
                reverseDuration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, 0.055),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: watch == null
                    ? const SizedBox.shrink(key: ValueKey<String>('player-closed'))
                    : MusicPlayerPage(
                        key: const ValueKey<String>('music-player'),
                        video: watch,
                        nativeState: _nativeStateNotifier,
                        playerUiState: _playerUiState,
                        onBack: () => unawaited(_closeYoutubeWatch()),
                        onPlayPause: _togglePlayPause,
                        onNext: () => _next(),
                        onPrevious: _previous,
                        onSeek: (position) => _youtubeController.seekTo(
                          seconds: position.inMilliseconds / 1000.0,
                        ),
                        onToggleShuffle: _toggleShuffle,
                        onToggleSmartShuffle: _toggleSmartShuffle,
                        onCycleLoop: _cycleLoopMode,
                        onToggleFavorite: () => _toggleFavorite(watch),
                        onAddToPlaylist: () => _showAddToPlaylist(watch),
                        onOpenQueue: _showQueueSheet,
                        onOpenAudioSettings: _showAudioSettingsSheet,
                        onOpenSleepTimer: _showSleepTimerSheet,
                        onOpenListeningRoom: _showListenTogetherSheet,
                        followingRoom: _listenTogether.isGuest,
                        sleepActive: _sleepActive,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
