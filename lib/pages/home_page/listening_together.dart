part of '../home_page.dart';

/// Kamar dengar bareng tanpa akun; online lintas jaringan bila Supabase dikonfigurasi.
/// Undangan disalin sekali per kamar dan status lagu dikirim otomatis berkala.
extension _HomeListeningTogether on _HomePageState {
  void _onListenTogetherStatusChanged() {
    final isGuest = _listenTogether.isGuest;
    if (_wasFollowingListenTogether && !isGuest) {
      // If the host leaves or the socket drops, don't let a guest keep playing
      // the last received song as if it were still synchronized.
      _wasFollowingListenTogether = false;
      unawaited(_pauseListenTogetherGuest());
    } else if (isGuest) {
      _wasFollowingListenTogether = true;
    }
    _refreshListeningTogetherUi();
  }

  void _showListenTogetherSheet() {
    // The room can be opened from Beranda before a song is selected. If the
    // host starts playing later, the existing broadcaster synchronizes it.
    final codeController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 540),
      builder: (sheetContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ValueListenableBuilder<String>(
            valueListenable: _listenTogether.status,
            builder: (context, status, _) {
              final connected = _listenTogether.isConnected;
              final isHost = _listenTogether.isHost;
              final isGuest = _listenTogether.isGuest;
              final onlineReady = _listenTogether.onlineConfigured;
              final scheme = Theme.of(context).colorScheme;

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              scheme.primary.withValues(alpha: 0.22),
                              scheme.tertiary.withValues(alpha: 0.10),
                            ],
                          ),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Icon(Icons.headphones_rounded, color: scheme.primary, size: 26),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Dengerin bareng',
                              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                            ),
                            SizedBox(height: 3),
                            Text('Bagikan kode kamar sekali. Lagu tersinkron otomatis.'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(onlineReady ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: scheme.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            onlineReady
                                ? 'Online aktif. Teman dari Wi-Fi atau jaringan seluler mana pun cukup memasukkan kode 8 digit. Tidak perlu alamat IP atau login. Semua anggota bisa mengontrol pemutaran; status terbaru disinkronkan ke seluruh kamar.'
                                : 'Server online belum dikonfigurasi pada build ini. Tambahkan SUPABASE_URL dan SUPABASE_PUBLISHABLE_KEY di GitHub Actions, lalu buat APK baru. Alamat IP lokal tidak digunakan di layar ini.',
                            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: connected
                          ? scheme.primaryContainer.withValues(alpha: 0.62)
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: connected
                            ? scheme.primary.withValues(alpha: 0.40)
                            : scheme.outlineVariant.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          connected ? Icons.wifi_tethering_rounded : Icons.radio_button_unchecked_rounded,
                          color: connected ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                connected ? (isHost ? 'Kamu host kamar' : 'Kamu bergabung') : 'Belum ada kamar',
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 3),
                              Text(status, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                              if (connected) ...[
                                const SizedBox(height: 4),
                                ValueListenableBuilder<String>(
                                  valueListenable: _listenTogether.syncStatus,
                                  builder: (context, syncStatus, _) => Text(
                                    syncStatus,
                                    style: TextStyle(
                                      color: syncStatus.toLowerCase().contains('gagal')
                                          ? scheme.error
                                          : scheme.onSurfaceVariant,
                                      fontSize: 11,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (isHost)
                          ValueListenableBuilder<int>(
                            valueListenable: _listenTogether.peerCount,
                            builder: (context, count, _) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: scheme.surface.withValues(alpha: 0.78),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('$count teman', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isHost) ...[
                    const SizedBox(height: 12),
                    ValueListenableBuilder<String>(
                      valueListenable: _listenTogether.roomCode,
                      builder: (context, code, _) => Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        child: Column(
                          children: [
                            Text('KODE KAMAR', style: TextStyle(fontSize: 11, letterSpacing: 1.8, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            SelectableText(
                              code.isEmpty ? '— — — — — — — —' : code,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 31, letterSpacing: 3.0, fontWeight: FontWeight.w900, color: scheme.primary),
                            ),
                            const SizedBox(height: 9),
                            FilledButton.icon(
                              onPressed: code.isEmpty ? null : () async {
                                await Clipboard.setData(ClipboardData(text: code));
                                _toast('Kode kamar disalin. Bagikan sekali saja ke teman.');
                              },
                              icon: const Icon(Icons.copy_rounded),
                              label: const Text('Salin kode kamar'),
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Teman cukup memasukkan kode ini di MusikKu. Tidak perlu IP atau menyalin ulang saat lagu berganti.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11, height: 1.35, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_currentVideo?.isLocal == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Lagu lokal tidak dapat dibagikan ke perangkat lain. Putar lagu YouTube agar tersinkron.',
                          style: TextStyle(color: scheme.error, fontSize: 12),
                        ),
                      ),
                  ],
                  if (!connected) ...[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      // Keep this tappable even when setup is missing so the
                      // reason is shown in the room status instead of failing silently.
                      onPressed: () async {
                        try {
                          await _listenTogether.hostRoom();
                          _startListenTogetherBroadcast();
                          _refreshListeningTogetherUi();
                        } catch (error) {
                          _listenTogether.status.value = 'Gagal membuat kamar online: $error';
                        }
                      },
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Buat kamar'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(8),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Kode kamar teman',
                        hintText: '8 digit, mis. 58319427',
                        prefixIcon: const Icon(Icons.password_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onSubmitted: (_) => unawaited(_joinListenTogetherRoom(codeController.text)),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _joinListenTogetherRoom(codeController.text),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Gabung pakai kode'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () async {
                        _listenTogetherSyncTimer?.cancel();
                        _listenTogetherSyncTimer = null;
                        await _listenTogether.closeRoom();
                        _refreshListeningTogetherUi();
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(isHost ? 'Tutup kamar' : 'Keluar dari kamar'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    ),
                    if (isGuest)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Semua anggota bisa play/pause, Next/Previous, geser posisi, Shuffle, dan Repeat. Perintah dikirim ke host lalu tersinkron ke kamar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    ).whenComplete(codeController.dispose);
  }

  Future<void> _joinListenTogetherRoom(String code) async {
    final normalizedCode = code.trim();
    if (!_listenTogether.onlineConfigured) {
      _listenTogether.status.value =
          'Server online belum dikonfigurasi pada APK ini. Atur SUPABASE_URL dan SUPABASE_PUBLISHABLE_KEY di GitHub Actions, lalu build APK baru.';
      return;
    }
    if (!RegExp(r'^\d{8}$').hasMatch(normalizedCode)) {
      _listenTogether.status.value = 'Masukkan kode kamar 8 digit. Tidak perlu alamat IP.';
      return;
    }
    _pendingListenTogetherState = null;
    _lastAppliedListenTogetherSequence = 0;
    _lastRoomUnsupportedTrackId = '';
    _lastListenTogetherLoadFailureVideoId = '';
    _lastListenTogetherLoadFailureAt = null;
    try {
      await _listenTogether.joinRoom(normalizedCode, code: normalizedCode);
      _listenTogetherSyncTimer?.cancel();
      _listenTogetherSyncTimer = null;
      _lastListenTogetherLoadFailureAt = null;
      _clearSleepTimer();
      _refreshListeningTogetherUi();
    } catch (error) {
      _listenTogether.status.value = 'Gagal bergabung: $error';
    }
  }

  Future<void> _routeListenTogetherAction(
    String action,
    Future<void> Function() localAction, {
    Duration? position,
  }) async {
    if (_listenTogether.isGuest) {
      try {
        await _listenTogether.requestControl(
          action,
          positionMs: position?.inMilliseconds,
        );
      } catch (error) {
        if (mounted) _toast('Kontrol kamar gagal dikirim: $error');
      }
      return;
    }
    await localAction();
  }

  void _routeListenTogetherModeAction(String action, VoidCallback localAction) {
    if (_listenTogether.isGuest) {
      unawaited(_requestListenTogetherControl(action));
      return;
    }
    localAction();
  }

  Future<void> _requestListenTogetherControl(String action) async {
    try {
      await _listenTogether.requestControl(action);
    } catch (error) {
      if (mounted) _toast('Kontrol kamar gagal dikirim: $error');
    }
  }

  Future<void> _applyListenTogetherRemoteControl(Map<String, dynamic> message) async {
    if (!_listenTogether.isHost || message['type'] != 'control') return;
    final action = message['action']?.toString() ?? '';
    switch (action) {
      case 'sync_request':
        _broadcastListenTogetherState();
        return;
      case 'play_pause':
        await _togglePlayPause();
        break;
      case 'play_track':
        final videoId = message['videoId']?.toString().trim() ?? '';
        final title = message['title']?.toString().trim() ?? '';
        if (!isValidSharedYouTubeVideoId(videoId) || title.isEmpty) {
          return;
        }
        final rawArtist = message['artist']?.toString().trim() ?? '';
        final rawThumbnail = message['thumbnailUrl']?.toString().trim() ?? '';
        final thumbnailUrl = rawThumbnail.startsWith('https://i.ytimg.com/') ||
                rawThumbnail.startsWith('https://img.youtube.com/')
            ? rawThumbnail
            : '';
        final rawDuration = message['durationSeconds'];
        final durationSeconds = rawDuration is num &&
                rawDuration.isFinite && rawDuration > 0
            ? rawDuration.toDouble().clamp(0.0, 86400.0).toDouble()
            : null;
        // A guest choosing a song should establish a coherent Radio seed on
        // the host, so the next song follows the newly selected track instead
        // of the host's unrelated previous queue/search context.
        await _startRadioFromVideo(
          YoutubeSearchResult(
            videoId: videoId,
            title: title.substring(0, title.length.clamp(0, 180).toInt()),
            channelTitle: rawArtist.substring(0, rawArtist.length.clamp(0, 160).toInt()),
            thumbnailUrl: thumbnailUrl,
            durationSeconds: durationSeconds,
          ),
        );
        break;
      case 'stop':
        await _stopPlayback();
        break;
      case 'next':
        await _next();
        break;
      case 'previous':
        await _previous();
        break;
      case 'seek':
        final current = _currentVideo;
        if (current == null) return;
        final requestedMs = (message['positionMs'] as num?)?.toInt() ?? 0;
        final maxMs = _nativeState.duration > Duration.zero
            ? _nativeState.duration.inMilliseconds
            : 24 * 60 * 60 * 1000;
        final targetMs = requestedMs.clamp(0, maxMs).toInt();
        try {
          await _youtubeController.seekTo(seconds: targetMs / 1000.0);
        } catch (error) {
          debugPrint('LISTEN TOGETHER REMOTE SEEK ERROR: $error');
        }
        break;
      case 'shuffle':
        _toggleShuffle();
        break;
      case 'smart_shuffle':
        _toggleSmartShuffle();
        break;
      case 'loop':
        _cycleLoopMode();
        break;
      default:
        return;
    }
    // The regular 2-second heartbeat remains the authoritative correction;
    // this immediate snapshot makes pause/seek/mode changes feel responsive.
    if (action == 'play_pause' ||
        action == 'play_track' ||
        action == 'stop' ||
        action == 'next' ||
        action == 'previous' ||
        action == 'seek' ||
        action == 'shuffle' ||
        action == 'smart_shuffle' ||
        action == 'loop') {
      // Push state immediately after every accepted host-side control. The
      // periodic heartbeat remains a correction, not the primary response.
      _broadcastListenTogetherState();
    }
  }

  void _startListenTogetherBroadcast() {
    _listenTogetherStateSequence = 0;
    _listenTogetherSyncTimer?.cancel();
    _listenTogetherSyncTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _broadcastListenTogetherState(),
    );
    _broadcastListenTogetherState();
  }

  void _broadcastListenTogetherState() {
    if (!_listenTogether.isHost) return;
    final video = _currentVideo;
    final sequence = ++_listenTogetherStateSequence;
    if (video == null) {
      _listenTogether.syncStatus.value = 'Menunggu host memutar lagu';
      _listenTogether.broadcastState(<String, dynamic>{
        'type': 'idle',
        'sequence': sequence,
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      return;
    }
    if (video.isLocal) {
      _listenTogether.syncStatus.value = 'File lokal tidak bisa dikirim ke kamar';
      _listenTogether.broadcastState(<String, dynamic>{
        'type': 'unsupported',
        'videoId': video.videoId,
        'message': 'Host sedang memutar file lokal. Pilih lagu YouTube agar tersinkron.',
        'sequence': sequence,
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      return;
    }

    final state = _nativeState;
    final matchesTrack = state.videoId == video.videoId &&
        _youtubeController.isUsingYoutubeAudio;
    _listenTogether.syncStatus.value = 'Membagikan: ${video.title}';
    _listenTogether.broadcastState(<String, dynamic>{
      'videoId': video.videoId,
      'title': video.title,
      'artist': video.channelTitle,
      'thumbnailUrl': video.coverUrl,
      'durationSeconds': video.durationSeconds,
      'positionMs': matchesTrack ? state.position.inMilliseconds : 0,
      'playing': matchesTrack && state.isEffectivelyPlaying,
      'isShuffle': _playerUiState.value.isShuffle,
      'isSmartShuffle': _playerUiState.value.isSmartShuffle,
      'loopModeIndex': _playerUiState.value.loopMode.index,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      'sequence': sequence,
    });
  }

  void _onListenTogetherMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString() ?? '';
    if (_listenTogether.isHost) {
      if (type == 'control') unawaited(_applyListenTogetherRemoteControl(message));
      return;
    }
    if (!_listenTogether.isGuest) return;
    if (type == 'room_closed') {
      _lastRoomUnsupportedTrackId = 'room_closed';
      unawaited(_pauseListenTogetherGuest());
      return;
    }
    if (type == 'state' || type == 'idle' || type == 'unsupported') {
      if (_applyingListenTogetherState) {
        // Treat idle/unsupported as snapshots too. Otherwise a delayed idle event
        // could pause the new track while its previous source is still resolving.
        _pendingListenTogetherState = newestQueuedListeningState(
          _pendingListenTogetherState,
          message,
        );
        return;
      }
      final sequence = (message['sequence'] as num?)?.toInt() ?? 0;
      if (sequence > 0 && sequence <= _lastAppliedListenTogetherSequence) return;
      if (sequence > 0 && type != 'state') {
        _lastAppliedListenTogetherSequence = sequence;
      }
    }
    if (type == 'idle') {
      _listenTogether.syncStatus.value = 'Host belum memutar lagu';
      if (_lastRoomUnsupportedTrackId != 'idle') {
        _lastRoomUnsupportedTrackId = 'idle';
        unawaited(_pauseListenTogetherGuest());
      }
      return;
    }
    if (type == 'unsupported') {
      _listenTogether.syncStatus.value = 'Lagu host tidak dapat disinkronkan';
      final trackId = message['videoId']?.toString() ?? 'unsupported';
      if (trackId != _lastRoomUnsupportedTrackId) {
        _lastRoomUnsupportedTrackId = trackId;
        unawaited(_pauseListenTogetherGuest());
        _toast(message['message']?.toString() ?? 'Sumber lagu ini tidak bisa disinkronkan.');
      }
      return;
    }
    if (type == 'state') unawaited(_applyListenTogetherState(message));
  }

  Future<void> _pauseListenTogetherGuest() async {
    try {
      await _youtubeController.pauseVideo();
    } catch (_) {
      // The native player may not have loaded a stream yet.
    }
  }

  Future<void> _applyListenTogetherState(Map<String, dynamic> message) async {
    if (!_listenTogether.isGuest) return;

    final incomingSequence = (message['sequence'] as num?)?.toInt() ?? 0;
    if (_applyingListenTogetherState) {
      // Audio resolution can take several seconds. Never discard the newest host
      // state just because an older track is still loading; coalesce the queue to
      // the most recent sequence and apply it immediately after the current load.
      _pendingListenTogetherState = newestQueuedListeningState(
        _pendingListenTogetherState,
        message,
      );
      return;
    }
    if (incomingSequence > 0 &&
        incomingSequence <= _lastAppliedListenTogetherSequence) {
      return;
    }
    if (incomingSequence > 0) {
      _lastAppliedListenTogetherSequence = incomingSequence;
    }

    final videoId = message['videoId']?.toString().trim() ?? '';
    if (videoId.isEmpty || videoId.startsWith('local:')) return;

    _lastRoomUnsupportedTrackId = '';
    final remoteShuffle = message['isShuffle'] as bool?;
    final remoteSmartShuffle = message['isSmartShuffle'] as bool?;
    final remoteLoopIndex = (message['loopModeIndex'] as num?)?.toInt();
    if (remoteShuffle != null || remoteSmartShuffle != null || remoteLoopIndex != null) {
      final safeLoopIndex = remoteLoopIndex == null
          ? _playerUiState.value.loopMode.index
          : remoteLoopIndex.clamp(0, LoopModeCustom.values.length - 1).toInt();
      _playerUiState.value = _playerUiState.value.copyWith(
        isShuffle: remoteShuffle,
        isSmartShuffle: remoteSmartShuffle,
        loopMode: LoopModeCustom.values[safeLoopIndex],
      );
    }
    final title = message['title']?.toString() ?? 'Lagu dari host';
    final artist = message['artist']?.toString() ?? 'Tidak diketahui';
    final thumbnail = message['thumbnailUrl']?.toString() ?? '';
    final durationSeconds = (message['durationSeconds'] as num?)?.toDouble();
    final playing = message['playing'] == true;
    var positionMs = (message['positionMs'] as num?)?.toInt() ?? 0;
    final sentAtMs = (message['sentAtMs'] as num?)?.toInt();
    if (playing && sentAtMs != null) {
      final age = (DateTime.now().millisecondsSinceEpoch - sentAtMs).clamp(0, 5000).toInt();
      positionMs += age;
    }
    if (durationSeconds != null && durationSeconds > 0) {
      positionMs = positionMs.clamp(0, (durationSeconds * 1000).round()).toInt();
    } else {
      positionMs = positionMs.clamp(0, 24 * 60 * 60 * 1000).toInt();
    }

    final track = YoutubeSearchResult(
      videoId: videoId,
      title: title,
      channelTitle: artist,
      thumbnailUrl: thumbnail,
      durationSeconds: durationSeconds,
    );

    // A different host track clears the retry backoff for the previous track.
    if (_lastListenTogetherLoadFailureVideoId != videoId) {
      _lastListenTogetherLoadFailureVideoId = '';
      _lastListenTogetherLoadFailureAt = null;
    }

    _listenTogether.syncStatus.value = 'Menerima lagu host: $title';
    _applyingListenTogetherState = true;
    try {
      final state = _nativeState;
      // The restored UI metadata/state notifier may already contain this ID
      // even though Media3 has not loaded any source yet. Require proof from
      // both the native state ID and the controller's actual audio-source flag;
      // otherwise playVideo() can target an empty/stale native item and the
      // guest appears connected but never starts following the host.
      final needsNativeLoad = shouldLoadListeningTogetherTrack(
        currentVideoId: _currentVideo?.videoId ?? '',
        targetVideoId: videoId,
        nativeStateVideoId: state.videoId,
        nativeAudioLoaded: _youtubeController.isUsingYoutubeAudio,
      );
      if (needsNativeLoad) {
        // A failed NewPipe/audio resolution used to retry on every 2-second
        // room heartbeat. That can flood the resolver and hide the real issue.
        // Retry the same failed track only after a short cooldown; a new host
        // track always gets an immediate attempt.
        final lastFailureAt = _lastListenTogetherLoadFailureAt;
        if (_lastListenTogetherLoadFailureVideoId == videoId &&
            lastFailureAt != null &&
            DateTime.now().difference(lastFailureAt) <
                const Duration(seconds: 12)) {
          return;
        }

        await _playVideo(
          track,
          recordHistory: false,
          restorePosition: positionMs / 1000.0,
          restoreDurationSeconds: durationSeconds,
          autoPlay: playing,
        );
        if (_youtubeController.isUsingYoutubeAudio &&
            _nativeState.videoId == videoId) {
          _lastListenTogetherLoadFailureVideoId = '';
          _lastListenTogetherLoadFailureAt = null;
          _listenTogether.syncStatus.value = 'Tersinkron: $title';
        } else {
          _lastListenTogetherLoadFailureVideoId = videoId;
          _lastListenTogetherLoadFailureAt = DateTime.now();
          _listenTogether.syncStatus.value =
              'Gagal memuat lagu host: $title. Periksa ketersediaan audio di perangkat ini.';
        }
        return;
      }

      if (state.duration > Duration.zero &&
          shouldCorrectListeningTogetherPosition(
            guestPositionMs: state.position.inMilliseconds,
            hostTargetPositionMs: positionMs,
          )) {
        // Correct moderate drift earlier so the two independent audio streams
        // do not remain noticeably out of step. The threshold avoids seeking
        // for harmless sub-second buffering differences.
        await _youtubeController.seekTo(seconds: positionMs / 1000.0);
      }

      if (playing && !state.isEffectivelyPlaying) {
        await _youtubeController.playVideo();
      } else if (!playing && state.isEffectivelyPlaying) {
        await _youtubeController.pauseVideo();
      }
      _listenTogether.syncStatus.value = 'Tersinkron: $title';
    } catch (error) {
      debugPrint('LISTEN TOGETHER SYNC ERROR: $error');
      _listenTogether.syncStatus.value =
          'Gagal menyinkronkan lagu: ${error.runtimeType}';
    } finally {
      _applyingListenTogetherState = false;
      final pending = _pendingListenTogetherState;
      _pendingListenTogetherState = null;
      if (pending != null && _listenTogether.isGuest) {
        final pendingSequence = (pending['sequence'] as num?)?.toInt() ?? 0;
        if (pendingSequence == 0 ||
            pendingSequence > _lastAppliedListenTogetherSequence) {
          unawaited(Future<void>.sync(() => _onListenTogetherMessage(pending)));
        }
      }
    }
  }
}
