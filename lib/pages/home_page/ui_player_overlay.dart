part of '../home_page.dart';

extension _HomeYoutubePlayerUi on _HomePageState {
    Widget _youtubeWatchHeader(
      BuildContext context,
      YoutubeSearchResult watch, {
      required bool landscape,
    }) {
      final content = Padding(
        padding: EdgeInsets.fromLTRB(
          8,
          landscape ? 4 : 2,
          10,
          landscape ? 12 : 6,
        ),
        child: Row(
          children: [
            _videoOverlayButton(
              icon: Icons.arrow_back_rounded,
              tooltip: 'Kembali',
              onTap: _handleYoutubeWatchBack,
            ),
            const SizedBox(width: 8),
            ChannelAvatar(
              channelId: watch.channelId,
              videoId: watch.videoId,
              name: watch.channelTitle,
              radius: 16,
              onTap: watch.channelId.trim().isEmpty
                  ? null
                  : () => _openChannelPage(
                      watch.channelId,
                      watch.channelTitle,
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    watch.title,
                    maxLines: landscape ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                    ),
                  ),
                  if (watch.channelTitle.trim().isNotEmpty)
                    Text(
                      watch.channelTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                ],
              ),
            ),
            _videoOverlayButton(
              icon: Icons.settings_rounded,
              tooltip: 'Pengaturan video',
              onTap: () => unawaited(_showYoutubePlayerSettings(context)),
            ),
          ],
        ),
      );

      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: landscape
            ? SafeArea(bottom: false, child: content)
            : content,
      );
    }
    Widget _youtubeSeekControls(NativeYoutubeState nativeState) {
      final duration = nativeState.duration.inMilliseconds / 1000.0;
      if (duration <= 0) return const SizedBox.shrink();

      return ValueListenableBuilder<double?>(
        valueListenable: _youtubeSeekPreviewSeconds,
        builder: (context, preview, _) {
          final currentSeconds = nativeState.position.inMilliseconds / 1000.0;
          final position = (preview ?? currentSeconds)
              .clamp(0.0, duration)
              .toDouble();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableTrackWidth =
                      (constraints.maxWidth - 32.0).clamp(0.0, constraints.maxWidth);
                  final bufferedWidth =
                      availableTrackWidth * nativeState.safeBufferedFraction;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Container(
                            height: 3,
                            width: bufferedWidth.clamp(0.0, constraints.maxWidth),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.48),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          // Garis progres merah seperti pemutar YouTube.
                          activeTrackColor: const Color(0xFFFF0033),
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                          thumbColor: const Color(0xFFFF0033),
                          overlayColor: const Color(0xFFFF0033).withValues(alpha: 0.14),
                        ),
                        child: Slider(
                          value: position,
                          min: 0,
                          max: duration,
                          onChangeStart: (value) {
                            _youtubeSeekPreviewSeconds.value = value;
                            _youtubeLandscapeControlsTimer?.cancel();
                          },
                          onChanged: (value) {
                            _youtubeSeekPreviewSeconds.value = value;
                          },
                          onChangeEnd: (value) {
                            _youtubeSeekPreviewSeconds.value = null;
                            _showLandscapeControls();
                            unawaited(_youtubeController.seekTo(seconds: value));
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      _formatStoredPosition(position),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatStoredPosition(duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (nativeState.duration > Duration.zero)
                ValueListenableBuilder<bool>(
                  valueListenable: widget.settings.showDataUsageOnPlayer,
                  builder: (context, showData, _) {
                    if (!showData) return const SizedBox.shrink();
                    final alertSeconds = widget.settings.bufferAlertSeconds.value;
                    final lowBuffer = nativeState.isEffectivelyPlaying &&
                        nativeState.bufferedAhead.inSeconds <= alertSeconds;
                    return Padding(
                      padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
                      child: Row(
                        children: [
                          Icon(
                            lowBuffer
                                ? Icons.warning_amber_rounded
                                : (nativeState.isBuffering
                                    ? Icons.sync_rounded
                                    : Icons.wifi_tethering_rounded),
                            color: lowBuffer
                                ? Colors.amberAccent
                                : Colors.white.withValues(alpha: 0.72),
                            size: 11,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              lowBuffer
                                  ? 'Buffer rendah • ${nativeState.bufferedAhead.inSeconds}s tersedia'
                                  : nativeState.bufferedAhead > Duration.zero
                                      ? 'Buffer ${_formatStoredPosition(nativeState.bufferedAhead.inMilliseconds / 1000.0)}'
                                      : (nativeState.isBuffering ? 'Menunggu buffer…' : 'Buffer siap'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: lowBuffer
                                    ? Colors.amberAccent
                                    : Colors.white.withValues(alpha: 0.72),
                                fontSize: 9.5,
                                fontWeight: lowBuffer ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (nativeState.networkRxBytes > 0)
                            Text(
                              '${_formatBytesCompact(nativeState.networkRxBytes)} • ${_networkTypeLabel(nativeState.networkType)}',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          );
        },
      );
    }

    String _formatBytesCompact(int bytes) {
      if (bytes < 1024) return '${bytes}B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)}KB';
      if (bytes < 1024 * 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 100 * 1024 * 1024 ? 1 : 0)}MB';
      }
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
    }

    String _networkTypeLabel(String type) {
      switch (type) {
        case 'wifi':
          return 'Wi-Fi';
        case 'mobile':
          return 'Seluler';
        case 'ethernet':
          return 'Ethernet';
        case 'offline':
          return 'Offline';
        default:
          return 'Jaringan';
      }
    }
    Widget _videoOverlayButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onTap,
      double size = 42,
    }) {
      return Material(
        color: Colors.black.withValues(alpha: 0.58),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: Colors.white, size: size * 0.52),
            ),
          ),
        ),
      );
    }
}
