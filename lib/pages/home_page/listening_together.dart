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
      _lastListenTogetherSeekAt = null;
      _listenTogetherPlaybackCommandRevision++;
      _listenTogetherUrgentPlaybackVideoId = '';
      _listenTogetherUrgentPlaybackTarget = null;
      _listenTogetherOptimisticVideoId = '';
      _listenTogetherOptimisticPlaying = null;
      _listenTogetherOptimisticSinceMs = 0;
      unawaited(_pauseListenTogetherGuest());
    } else if (isGuest) {
      _wasFollowingListenTogether = true;
    }
    _refreshListeningTogetherUi();
  }

  /// Dipanggil setiap kali state native berubah (lihat initState di home_page.dart).
  void _stampNativeStateTime() {
    _nativeStateStampedAt = DateTime.now();
  }

  /// Posisi native hanya diperbarui sekitar tiap detik, jadi nilai mentahnya bisa
  /// tertinggal hingga ~1 detik. Tambahkan waktu sejak event terakhir saat
  /// sedang bermain supaya perbandingan dengan target host akurat.
  int _estimatedNativePositionMs() {
    final state = _nativeState;
    var ms = state.position.inMilliseconds;
    if (state.isEffectivelyPlaying) {
      ms += DateTime.now()
          .difference(_nativeStateStampedAt)
          .inMilliseconds
          .clamp(0, 1500)
          .toInt();
    }
    return ms;
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
                          await _listenTogether.replaceSharedQueue(
                            _queueManager.items
                                .map((item) => item.video.toJson())
                                .toList(growable: false),
                          );
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
                          'Semua anggota bisa mengontrol pemutaran dan mengelola antrean bersama. Lagu yang ditambahkan, dihapus, atau diurutkan ulang akan muncul di semua HP; label menunjukkan apakah lagu ditambahkan host atau anggota.',
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

  /// Every room participant reflects the host's canonical queue locally.
  /// The room role check prevents closing a room from clearing the saved queue.
  void _onSharedQueueChanged() {
    if (!_listenTogether.isConnected) {
      _lastSharedQueueVideoIds = <String>{};
      _sharedQueueSnapshotInitialized = false;
      return;
    }

    final seen = <String>{};
    final items = <QueueItem>[];
    final incoming = _listenTogether.sharedQueue.value;
    for (final raw in incoming) {
      final video = YoutubeSearchResult.fromJson(Map<String, dynamic>.from(raw));
      if (video.isLocal || video.videoId.isEmpty || !seen.add(video.videoId)) continue;
      items.add(QueueItem(video: video));
    }

    // Suppress the first snapshot after joining/hosting. Later additions notify
    // all phones so a person knows another member changed the shared queue even
    // when they are not currently looking at the queue sheet.
    if (_sharedQueueSnapshotInitialized) {
      final added = items.where((item) => !_lastSharedQueueVideoIds.contains(item.id)).toList(growable: false);
      if (added.isNotEmpty && mounted) {
        final latest = added.last.video;
        var contributor = 'anggota';
        for (final raw in incoming) {
          if (raw['videoId']?.toString() == latest.videoId) {
            contributor = raw['_addedByLabel']?.toString() ??
                (raw['_addedByRole']?.toString() == 'host' ? 'Host' : 'Anggota');
            break;
          }
        }
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Antrean bersama: ${latest.title} ditambahkan oleh $contributor'),
              duration: const Duration(seconds: 3),
            ),
          );
      }
    }
    _lastSharedQueueVideoIds = items.map((item) => item.id).toSet();
    _sharedQueueSnapshotInitialized = true;
    _queueManager.restore(items);
    unawaited(_storage.saveQueue(_queueManager.items));
    _refreshListeningTogetherUi();
  }

  /// Called when playback consumes an item from the host's local queue.
  /// User-driven room mutations use the explicit shared queue operations below.
  void _syncListeningTogetherQueueFromLocal() {
    if (!_listenTogether.isHost) return;
    unawaited(_listenTogether.replaceSharedQueue(
      _queueManager.items.map((item) => item.video.toJson()).toList(growable: false),
    ));
  }

  String _sharedQueueAddedByLabel(String videoId) {
    for (final item in _listenTogether.sharedQueue.value) {
      if (item['videoId']?.toString() != videoId) continue;
      final contributor = item['_addedByLabel']?.toString().trim() ?? '';
      if (contributor.isNotEmpty) return 'DITAMBAHKAN ${contributor.toUpperCase()}';
      final role = item['_addedByRole']?.toString() ?? '';
      if (role == 'host') return 'DITAMBAHKAN HOST';
      if (role == 'member') return 'DITAMBAHKAN ANGGOTA';
    }
    return 'ANTREAN BERSAMA';
  }

  String _sharedQueueArtistLabel(YoutubeSearchResult video) =>
      MusicTitleFormatter.artistLabel(
        title: video.title,
        channelTitle: video.channelTitle,
      );

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
    _listenTogetherPlaybackCommandRevision++;
    _listenTogetherUrgentPlaybackVideoId = '';
    _listenTogetherUrgentPlaybackTarget = null;
    _listenTogetherOptimisticVideoId = '';
    _listenTogetherOptimisticPlaying = null;
    _listenTogetherOptimisticSinceMs = 0;
    _lastRoomUnsupportedTrackId = '';
    _lastListenTogetherLoadFailureVideoId = '';
    _lastListenTogetherLoadFailureAt = null;
    _lastListenTogetherSeekAt = null;
    try {
      await _listenTogether.joinRoom(normalizedCode, code: normalizedCode);
      _listenTogetherSyncTimer?.cancel();
      _listenTogetherSyncTimer = null;
      _lastListenTogetherLoadFailureAt = null;
      _lastListenTogetherSeekAt = null;
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
      if (action == 'play_pause') {
        final current = _currentVideo;
        final state = _nativeState;
        final nativeTrackReady = current != null &&
            state.videoId == current.videoId &&
            _youtubeController.isUsingYoutubeAudio;
        final optimisticAgeMs = DateTime.now().millisecondsSinceEpoch -
            _listenTogetherOptimisticSinceMs;
        final optimisticIsFresh = _listenTogetherOptimisticSinceMs > 0 &&
            optimisticAgeMs < 1800;
        final lastOptimistic = optimisticIsFresh &&
                _listenTogetherOptimisticVideoId == current?.videoId
            ? _listenTogetherOptimisticPlaying
            : null;
        if (!optimisticIsFresh && _listenTogetherOptimisticSinceMs > 0) {
          _listenTogetherOptimisticVideoId = '';
          _listenTogetherOptimisticPlaying = null;
          _listenTogetherOptimisticSinceMs = 0;
        }
        final desiredPlaying = !(lastOptimistic ?? state.isEffectivelyPlaying);

        // Start the online request first, without waiting for its response.
        // The local device should not need a full network round trip to pause
        // or resume an already-loaded track.
        final request = _listenTogether.requestControl(
          'set_playback',
          playing: desiredPlaying,
        );

        if (nativeTrackReady) {
          // Apply locally first for a responsive button, then let the host
          // confirm the same desired state. Don't call _togglePlayPause here:
          // it intentionally ignores direct local actions while we're a guest.
          _listenTogetherOptimisticVideoId = current.videoId;
          _listenTogetherOptimisticPlaying = desiredPlaying;
          _listenTogetherOptimisticSinceMs =
              DateTime.now().millisecondsSinceEpoch;
          _listenTogetherPlaybackCommandRevision++;
          _listenTogetherUrgentPlaybackVideoId = current.videoId;
          _listenTogetherUrgentPlaybackTarget = desiredPlaying;
          _lastListenTogetherSeekAt = DateTime.now();
          try {
            if (desiredPlaying) {
              unawaited(() async {
                try {
                  await _setPlayerVolume(_playerVolumePercent);
                } catch (error) {
                  debugPrint('LISTEN TOGETHER VOLUME ERROR: $error');
                }
              }());
              await _youtubeController.playVideo();
            } else {
              await _youtubeController.pauseVideo();
            }
          } catch (error) {
            debugPrint('LISTEN TOGETHER OPTIMISTIC PLAYBACK ERROR: $error');
          }
        }

        try {
          await request;
        } catch (error) {
          if (mounted) _toast('Kontrol kamar gagal dikirim: $error');
        }
      } else {
        try {
          await _listenTogether.requestControl(
            action,
            positionMs: position?.inMilliseconds,
          );
        } catch (error) {
          if (mounted) _toast('Kontrol kamar gagal dikirim: $error');
        }
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
      case 'set_playback':
        final desiredPlaying = message['playing'];
        if (desiredPlaying is! bool) return;
        if (!shouldApplyListeningRoomPlaybackCommand(
          currentPlaying: _nativeState.isEffectivelyPlaying,
          desiredPlaying: desiredPlaying,
        )) {
          // A duplicate command is not executed again, but return a snapshot so
          // the guest receives confirmation instead of waiting for heartbeat.
          _broadcastListenTogetherState();
          return;
        }
        if (!desiredPlaying) {
          // Pause is urgent: do not wait for a toggle lock or queue transition.
          await _youtubeController.pauseVideo();
        } else {
          final current = _currentVideo;
          final nativeMatches = current != null &&
              _nativeState.videoId == current.videoId &&
              _youtubeController.isUsingYoutubeAudio &&
              _nativeState.playbackState != NativePlaybackState.error;
          if (nativeMatches && !_restoredNeedsLoad) {
            await _setPlayerVolume(_playerVolumePercent);
            await _youtubeController.playVideo();
          } else {
            await _togglePlayPause();
          }
        }
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
    if (shouldBroadcastListeningRoomSnapshotImmediately(action)) {
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
    // broadcastState() in the service adds `capturedAtMs` (host clock). Guests
    // use it with the measured clock offset to compute `hostTargetPositionMs`.
    _listenTogether.broadcastState(<String, dynamic>{
      'videoId': video.videoId,
      'title': video.title,
      'artist': video.channelTitle,
      'thumbnailUrl': video.coverUrl,
      'durationSeconds': video.durationSeconds,
      'positionMs': matchesTrack ? _estimatedNativePositionMs() : 0,
      'playing': matchesTrack && state.isEffectivelyPlaying,
      'isShuffle': _playerUiState.value.isShuffle,
      'isSmartShuffle': _playerUiState.value.isSmartShuffle,
      'loopModeIndex': _playerUiState.value.loopMode.index,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      'sequence': sequence,
    });
  }

  /// Prevent a pre-click host snapshot from immediately undoing a guest's
  /// optimistic pause/resume. A conflicting snapshot is accepted again after
  /// a short timeout, so the host remains authoritative if the command fails.
  bool _shouldHoldConflictingListenTogetherSnapshot(
    Map<String, dynamic> message,
  ) {
    if (!_listenTogether.isGuest || message['type'] != 'state') return false;
    final optimisticSince = _listenTogetherOptimisticSinceMs;
    final optimisticPlaying = _listenTogetherOptimisticPlaying;
    final videoId = message['videoId']?.toString() ?? '';
    if (optimisticSince <= 0 ||
        optimisticPlaying == null ||
        videoId != _listenTogetherOptimisticVideoId) {
      return false;
    }

    final ageMs = DateTime.now().millisecondsSinceEpoch - optimisticSince;
    if (ageMs >= 1800) {
      _listenTogetherOptimisticSinceMs = 0;
      _listenTogetherOptimisticPlaying = null;
      _listenTogetherOptimisticVideoId = '';
      return false;
    }

    final conflictsWithOptimisticTarget = message['playing'] is bool &&
        message['playing'] != optimisticPlaying;
    // A host heartbeat can already be in flight when the guest taps the button.
    // Ignore a conflicting snapshot briefly; a matching host state confirms the
    // command, and after the timeout the host becomes authoritative again.
    return conflictsWithOptimisticTarget;
  }

  /// Apply same-track pause/resume before any drift-correction seek or queued
  /// snapshot work. Seeking a streaming source can buffer; it must not delay
  /// a user's play/pause action or let an older async apply reverse it later.
  void _applyUrgentListenTogetherPlayback(Map<String, dynamic> message) {
    if (!_listenTogether.isGuest || message['type'] != 'state') return;
    final desiredPlaying = message['playing'];
    if (desiredPlaying is! bool) return;

    final videoId = message['videoId']?.toString().trim() ?? '';
    final current = _currentVideo;
    final state = _nativeState;
    if (videoId.isEmpty ||
        current == null ||
        current.videoId != videoId ||
        state.videoId != videoId ||
        !_youtubeController.isUsingYoutubeAudio) {
      return;
    }

    if (state.isEffectivelyPlaying == desiredPlaying) {
      if (_listenTogetherUrgentPlaybackVideoId == videoId &&
          _listenTogetherUrgentPlaybackTarget == desiredPlaying) {
        // The optimistic/urgent action has now been reflected by native state.
        // Treat this confirmation as a transition snapshot too: don't follow it
        // with an immediate seek that could buffer playback again.
        message['_listenTogetherUrgentPlaybackHandled'] = true;
        _lastListenTogetherSeekAt = DateTime.now();
        _listenTogetherUrgentPlaybackVideoId = '';
        _listenTogetherUrgentPlaybackTarget = null;
      }
      return;
    }

    final sameUrgentCommand =
        _listenTogetherUrgentPlaybackVideoId == videoId &&
            _listenTogetherUrgentPlaybackTarget == desiredPlaying;
    message['_listenTogetherUrgentPlaybackHandled'] = true;
    if (sameUrgentCommand) return;

    _listenTogetherPlaybackCommandRevision++;
    _listenTogetherUrgentPlaybackVideoId = videoId;
    _listenTogetherUrgentPlaybackTarget = desiredPlaying;
    _lastListenTogetherSeekAt = DateTime.now();

    unawaited(() async {
      try {
        if (desiredPlaying) {
          unawaited(_setPlayerVolume(_playerVolumePercent));
          await _youtubeController.playVideo();
        } else {
          await _youtubeController.pauseVideo();
        }
      } catch (error) {
        debugPrint('LISTEN TOGETHER URGENT PLAYBACK ERROR: $error');
      }
    }());
  }

  void _onListenTogetherMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString() ?? '';
    if (_listenTogether.isHost) {
      if (type == 'control') unawaited(_applyListenTogetherRemoteControl(message));
      return;
    }
    if (!_listenTogether.isGuest) return;
    if (type == 'state') {
      // Catat kapan snapshot tiba. Snapshot yang sempat mengantre selama lagu
      // dimuat harus digeser maju sebesar waktu tunggunya.
      message['guestReceivedAtMs'] ??= DateTime.now().millisecondsSinceEpoch;
      if (_shouldHoldConflictingListenTogetherSnapshot(message)) return;
      _applyUrgentListenTogetherPlayback(message);
      final optimisticSince = _listenTogetherOptimisticSinceMs;
      final capturedAtHostMs = (message['capturedAtMs'] as num?)?.toInt();
      final capturedAtGuestMs = capturedAtHostMs == null
          ? null
          : capturedAtHostMs - _listenTogether.clockOffsetMs;
      if (optimisticSince > 0 &&
          message['videoId']?.toString() == _listenTogetherOptimisticVideoId &&
          message['playing'] == _listenTogetherOptimisticPlaying &&
          capturedAtGuestMs != null &&
          capturedAtGuestMs >= optimisticSince - 120) {
        _listenTogetherOptimisticSinceMs = 0;
        _listenTogetherOptimisticPlaying = null;
        _listenTogetherOptimisticVideoId = '';
      }
    }
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
      // A `state` snapshot with the same sequence is a heartbeat re-projection
      // of the current host state. It is idempotent and needed for drift
      // correction, so only strictly older state snapshots are dropped.
      // idle/unsupported keep the strict (<=) duplicate check.
      if (sequence > 0) {
        final stale = type == 'state'
            ? sequence < _lastAppliedListenTogetherSequence
            : sequence <= _lastAppliedListenTogetherSequence;
        if (stale) return;
      }
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

  /// Perbarui lead seek dari durasi seek terakhir (EMA, dibatasi 300–1200 ms).
  void _updateListenTogetherSeekLead(int seekElapsedMs) {
    final target = seekElapsedMs.clamp(300, 1200).toInt();
    _listenTogetherSeekLeadMs =
        ((_listenTogetherSeekLeadMs * 2 + target) / 3).round();
  }

  Future<void> _applyListenTogetherState(Map<String, dynamic> message) async {
    if (!_listenTogether.isGuest) return;

    final playbackRevisionAtStart = _listenTogetherPlaybackCommandRevision;
    final urgentPlaybackHandled =
        message['_listenTogetherUrgentPlaybackHandled'] == true;
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
    // Equal sequence = heartbeat re-projection of the same host state: accept.
    if (incomingSequence > 0 &&
        incomingSequence < _lastAppliedListenTogetherSequence) {
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

    // `hostTargetPositionMs` is computed by ListeningTogetherService: it is the
    // host position projected to "now" using the measured host/guest clock
    // offset. Do NOT subtract the host's `sentAtMs` from the guest clock here;
    // the two phone clocks are not synchronized.
    var positionMs = (message['hostTargetPositionMs'] as num?)?.toInt() ??
        (message['positionMs'] as num?)?.toInt() ??
        0;
    // Snapshot bisa menunggu beberapa detik di antrean saat lagu sebelumnya
    // masih dimuat. Majukan posisinya sebesar waktu tunggu itu.
    final receivedAtMs = (message['guestReceivedAtMs'] as num?)?.toInt();
    if (playing && receivedAtMs != null) {
      positionMs += (DateTime.now().millisecondsSinceEpoch - receivedAtMs)
          .clamp(0, 15000)
          .toInt();
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

        final loadStartedAt = DateTime.now();
        await _playVideo(
          track,
          recordHistory: false,
          restorePosition: positionMs / 1000.0,
          restoreDurationSeconds: durationSeconds,
          autoPlay: playing,
        );
        // A new track must not be held back by the previous track's seek cooldown.
        _lastListenTogetherSeekAt = null;
        if (_youtubeController.isUsingYoutubeAudio &&
            _nativeState.videoId == videoId) {
          _lastListenTogetherLoadFailureVideoId = '';
          _lastListenTogetherLoadFailureAt = null;
          // Resolusi stream bisa makan beberapa detik, selama itu host terus
          // berjalan. Setelah siap, lompat ke posisi host yang sekarang.
          if (playing) {
            final lateMs =
                DateTime.now().difference(loadStartedAt).inMilliseconds;
            if (lateMs > 800) {
              var catchUpMs = positionMs + lateMs + _listenTogetherSeekLeadMs;
              if (durationSeconds != null && durationSeconds > 0) {
                catchUpMs = catchUpMs
                    .clamp(0, (durationSeconds * 1000).round())
                    .toInt();
              }
              _lastListenTogetherSeekAt = DateTime.now();
              await _youtubeController.seekTo(seconds: catchUpMs / 1000.0);
            }
          }
          _listenTogether.syncStatus.value = 'Tersinkron: $title';
        } else {
          _lastListenTogetherLoadFailureVideoId = videoId;
          _lastListenTogetherLoadFailureAt = DateTime.now();
          _listenTogether.syncStatus.value =
              'Gagal memuat lagu host: $title. Periksa ketersediaan audio di perangkat ini.';
        }
        return;
      }

      // A newer pause/resume can arrive while the previous snapshot is in an
      // awaited native operation. Do not let the older snapshot continue.
      if (_listenTogetherPlaybackCommandRevision !=
          playbackRevisionAtStart) {
        return;
      }

      // Urgent same-track playback changes were already applied before this
      // async sync path. Never put a seek in front of a fresh resume/pause.
      if (!urgentPlaybackHandled && !playing && state.isEffectivelyPlaying) {
        await _youtubeController.pauseVideo();
        if (_listenTogetherPlaybackCommandRevision !=
            playbackRevisionAtStart) {
          return;
        }
      }

      // Bandingkan dengan posisi guest yang diperkirakan "sekarang", bukan nilai
      // native mentah yang bisa tertinggal ~1 detik (itu memicu seek palsu).
      final guestPositionMs = _estimatedNativePositionMs();
      final driftMs = guestPositionMs - positionMs;
      if (!urgentPlaybackHandled &&
          state.duration > Duration.zero &&
          shouldCorrectListeningTogetherPosition(
            guestPositionMs: guestPositionMs,
            hostTargetPositionMs: positionMs,
          )) {
        // Correct moderate drift after the urgent pause command (or before a
        // resume). Seeking a stream causes buffering, so repeated corrective
        // seeks are rate-limited; a very large drift (e.g. the host just
        // seeked) bypasses the cooldown.
        if (driftMs.abs() > 5000 ||
            isListeningTogetherSeekCooldownOver(
              lastSeekAt: _lastListenTogetherSeekAt,
            )) {
          _lastListenTogetherSeekAt = DateTime.now();
          // Saat host bermain, lompat sedikit ke depan untuk mengimbangi
          // waktu buffering setelah seek.
          final seekMs =
              playing ? positionMs + _listenTogetherSeekLeadMs : positionMs;
          final seekWatch = Stopwatch()..start();
          await _youtubeController.seekTo(seconds: seekMs / 1000.0);
          _updateListenTogetherSeekLead(seekWatch.elapsedMilliseconds);
          if (_listenTogetherPlaybackCommandRevision !=
              playbackRevisionAtStart) {
            return;
          }
        }
      }

      if (!urgentPlaybackHandled &&
          playing &&
          !_nativeState.isEffectivelyPlaying) {
        if (_listenTogetherPlaybackCommandRevision !=
            playbackRevisionAtStart) {
          return;
        }
        unawaited(_setPlayerVolume(_playerVolumePercent));
        await _youtubeController.playVideo();
      }
      _listenTogether.syncStatus.value =
          'Tersinkron: $title (selisih ${driftMs}ms, RTT ${_listenTogether.bestRttMs ?? '-'}ms)';
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
            pendingSequence >= _lastAppliedListenTogetherSequence) {
          unawaited(Future<void>.sync(() => _onListenTogetherMessage(pending)));
        }
      }
    }
  }
}