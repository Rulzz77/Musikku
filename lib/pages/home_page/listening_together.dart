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
                                ? 'Online aktif. Teman dari Wi-Fi atau jaringan seluler mana pun cukup memasukkan kode 8 digit. Tidak perlu alamat IP atau login. Pergantian lagu, play/pause, dan posisi mengikuti host otomatis.'
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
                      onPressed: onlineReady ? () async {
                        try {
                          await _listenTogether.hostRoom();
                          _startListenTogetherBroadcast();
                          _refreshListeningTogetherUi();
                        } catch (error) {
                          _listenTogether.status.value = 'Gagal membuat kamar online: $error';
                        }
                      } : null,
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
                      onSubmitted: (_) {
                        if (onlineReady) unawaited(_joinListenTogetherRoom(codeController.text));
                      },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: onlineReady ? () => _joinListenTogetherRoom(codeController.text) : null,
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
                          'Pemutaran di perangkat ini mengikuti host. Kontrol lagu utama berada di perangkat host.',
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
    if (!_listenTogether.onlineConfigured) {
      _listenTogether.status.value = 'Server online belum dikonfigurasi. Buat APK dengan variabel Supabase dari GitHub Actions.';
      return;
    }
    final normalizedCode = code.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(normalizedCode)) {
      _listenTogether.status.value = 'Masukkan kode kamar 8 digit dari host.';
      return;
    }
    try {
      await _listenTogether.joinRoom(normalizedCode, code: normalizedCode);
      _listenTogetherSyncTimer?.cancel();
      _listenTogetherSyncTimer = null;
      _lastRoomUnsupportedTrackId = '';
      _clearSleepTimer();
      _refreshListeningTogetherUi();
    } catch (error) {
      _listenTogether.status.value = 'Gagal bergabung: $error';
    }
  }

  void _startListenTogetherBroadcast() {
    _listenTogetherSyncTimer?.cancel();
    _listenTogetherSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_listenTogether.isHost) {
        _listenTogetherSyncTimer?.cancel();
        _listenTogetherSyncTimer = null;
        return;
      }

      final video = _currentVideo;
      if (video == null) {
        _listenTogether.broadcastState(<String, dynamic>{'type': 'idle'});
        return;
      }
      if (video.isLocal) {
        _listenTogether.broadcastState(<String, dynamic>{
          'type': 'unsupported',
          'videoId': video.videoId,
          'message': 'Host sedang memutar file lokal. Pilih lagu YouTube untuk sinkronisasi.',
        });
        return;
      }

      final state = _nativeState;
      final matchesTrack = state.videoId.isEmpty || state.videoId == video.videoId;
      _listenTogether.broadcastState(<String, dynamic>{
        'videoId': video.videoId,
        'title': video.title,
        'artist': video.channelTitle,
        'thumbnailUrl': video.coverUrl,
        'durationSeconds': video.durationSeconds,
        'positionMs': matchesTrack ? state.position.inMilliseconds : 0,
        'playing': matchesTrack && state.isEffectivelyPlaying,
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  void _onListenTogetherMessage(Map<String, dynamic> message) {
    if (!_listenTogether.isGuest) return;
    final type = message['type']?.toString() ?? '';
    if (type == 'idle') {
      if (_lastRoomUnsupportedTrackId != 'idle') {
        _lastRoomUnsupportedTrackId = 'idle';
        unawaited(_pauseListenTogetherGuest());
      }
      return;
    }
    if (type == 'unsupported') {
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
    if (!_listenTogether.isGuest || _applyingListenTogetherState) return;
    final videoId = message['videoId']?.toString().trim() ?? '';
    if (videoId.isEmpty || videoId.startsWith('local:')) return;

    _lastRoomUnsupportedTrackId = '';
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

    _applyingListenTogetherState = true;
    try {
      if (_currentVideo?.videoId != videoId) {
        await _playVideo(
          track,
          recordHistory: false,
          restorePosition: positionMs / 1000.0,
          restoreDurationSeconds: durationSeconds,
          autoPlay: playing,
        );
        return;
      }

      final state = _nativeState;
      final sameTrackState = state.videoId.isEmpty || state.videoId == videoId;
      if (sameTrackState && state.duration > Duration.zero) {
        final driftMs = (state.position.inMilliseconds - positionMs).abs();
        if (driftMs > 2800) {
          await _youtubeController.seekTo(seconds: positionMs / 1000.0);
        }
      }

      if (playing && !state.isEffectivelyPlaying) {
        await _youtubeController.playVideo();
      } else if (!playing && state.isEffectivelyPlaying) {
        await _youtubeController.pauseVideo();
      }
    } catch (error) {
      debugPrint('LISTEN TOGETHER SYNC ERROR: $error');
    } finally {
      _applyingListenTogetherState = false;
    }
  }
}
