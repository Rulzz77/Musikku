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
                    onOpenCustomPlaylist: _openCustomPlaylistDetail,
                    customPlaylists: _playlists,
                    onCustomPlaylistsChanged: _handleCustomPlaylistsChanged,
                    currentVideoId: current?.videoId,
                    currentVideo: current,
                    onPlayPause: () => _routeListenTogetherAction('play_pause', _togglePlayPause),
                    onNext: () => _routeListenTogetherAction('next', () => _next()),
                    onPrevious: () => _routeListenTogetherAction('previous', _previous),
                    isPlaying: _nativeState.isEffectivelyPlaying,
                    nativeState: _nativeStateNotifier,
                    onStartRadio: _startRadioFromVideo,
                    onPlayFromList: _playFromCustomList,
                    onAddToQueue: _addToQueue,
                    onShowVideoMenu: (video) => _showVideoMenu(video),
                    onSearchQueryChanged: (query) {
                      _lastSearchQuery = query.trim();
                    },
                    onOpenListeningRoom: _showListenTogetherSheet,
                    onOpenCurrentLyrics: current == null ? null : _openCurrentLyricsPage,
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
                child: Offstage(
                  // WebView-backed YouTube player must remain mounted after
                  // closing Now Playing, otherwise iOS tears down the iframe.
                  offstage: watch == null,
                  child: (watch != null ||
                          (Platform.isIOS && current != null && !current.isLocal))
                      ? MusicPlayerPage(
                          key: const ValueKey<String>('music-player'),
                          video: watch ?? current!,
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
                          onToggleFavorite: () => _toggleFavorite(watch ?? current!),
                          volumePercent: _playerVolumePercent,
                          onVolumeChanged: (percent, persist) =>
                              _setPlayerVolume(percent, persist: persist),
                          onAddToPlaylist: () => _showAddToPlaylist(watch ?? current!),
                          onOpenLyrics: _openCurrentLyricsPage,
                          onOpenQueue: _showQueueSheet,
                          onOpenSleepTimer: _showSleepTimerSheet,
                          onOpenListeningRoom: _showListenTogetherSheet,
                          followingRoom: _listenTogether.isGuest,
                          inPlaylist: _playlists.any(
                            (playlist) => playlist.contains((watch ?? current!).videoId),
                          ),
                          sleepActive: _sleepActive,
                          platformPlayer: Platform.isIOS && !(watch ?? current!).isLocal
                              ? IOSYoutubePlayerSurface(
                                  controller: _youtubeController.iosYoutubeController,
                                )
                              : null,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
