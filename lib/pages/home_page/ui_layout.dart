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
            child: IgnorePointer(
              ignoring: watch != null,
              child: YoutubeHub(
                controller: _hubController,
                onPlay: _openYoutubeVideo,
                onClose: _closeYoutubeWatch,
                // Reserve room above navigation for the persistent mini-player.
                bottomInset: showMiniPlayer ? 94 : 0,
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
                settings: widget.settings,
              ),
            ),
          ),
          if (showMiniPlayer)
            Positioned(
              left: 12,
              right: 12,
              // Keep a visible gap between the mini-player and the glass dock.
              // MediaQuery padding accounts for Android system navigation/gestures.
              bottom: safeBottom + 66 + 18,
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
                        key: ValueKey<String>('music-player-${watch.videoId}'),
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
                        sleepActive: _sleepActive,
                        showDataUsageOnPlayer: widget.settings.showDataUsageOnPlayer,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
