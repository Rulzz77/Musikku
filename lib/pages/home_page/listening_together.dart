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
    if (_currentVideo == null) {
      _toast('Putar lagu dulu sebelum membuat kamar dengar bareng.');
      return;
    }

    final addressController = TextEditingController();
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
                            Text('Satu lagu, diputar serempak tanpa login.'),
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
                        Icon(_listenTogether.onlineConfigured ? Icons.cloud_done_rounded : Icons.wifi_rounded, color: scheme.primary, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _listenTogether.onlineConfigured
                                ? 'Mode online aktif. Teman bisa bergabung dari jaringan mana saja memakai undangan satu kali. Lagu berikutnya, play/pause, dan posisi tersinkron otomatis.'
                                : 'Mode saat ini masih lokal. Agar teman beda Wi-Fi bisa bergabung, konfigurasi SUPABASE_URL dan SUPABASE_PUBLISHABLE_KEY saat build. Setelah aktif, undangan cukup dibagikan sekali.',
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
                      valueListenable: _listenTogether.inviteAddress,
                      builder: (context, address, _) =>
                          ValueListenableBuilder<String>(
                        valueListenable: _listenTogether.roomCode,
                        builder: (context, code, _) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: scheme.outlineVariant),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Undangan kamar • tempel di MusikKu teman',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  SelectableText(
                                    address.isEmpty
                                        ? (_listenTogether.onlineConfigured ? 'Membuat undangan online…' : 'Alamat Wi-Fi belum ditemukan')
                                        : address,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (!_listenTogether.onlineConfigured) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                    children: [
                                      Icon(
                                        Icons.password_rounded,
                                        color: scheme.primary,
                                        size: 22,
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Kode kamar',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              code.isEmpty
                                                  ? '— — — — — —'
                                                  : code,
                                              style: const TextStyle(
                                                fontSize: 24,
                                                letterSpacing: 3,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: address.isEmpty || code.isEmpty
                                  ? null
                                  : () async {
                                      final invite = _listenTogether.onlineConfigured
                                          ? address
                                          : <String>[
                                              'MusikKu — Dengerin Bareng',
                                              'Alamat kamar: $address',
                                              'Kode kamar: $code',
                                              '',
                                              'Bagikan sekali. Lagu akan mengikuti host otomatis.',
                                            ].join('\n');
                                      await Clipboard.setData(
                                        ClipboardData(text: invite),
                                      );
                                      _toast(
                                        _listenTogether.onlineConfigured
                                            ? 'Undangan online disalin. Teman cukup tempel sekali di MusikKu.'
                                            : 'Undangan disalin. Bagikan sekali; pergantian lagu tersinkron otomatis.',
                                      );
                                    },
                              icon: const Icon(Icons.share_rounded),
                              label: const Text('Salin undangan (cukup sekali)'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _listenTogether.onlineConfigured
                                  ? 'Teman cukup menempelkan undangan ini di kolom gabung. Tidak perlu salin ulang saat lagu berganti.'
                                  : 'Tidak perlu membagikan ulang ketika lagu berganti.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_currentVideo?.isLocal == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Lagu lokal tidak dapat dibagikan ke perangkat lain. Putar lagu YouTube agar bisa disinkronkan.',
                          style: TextStyle(color: scheme.error, fontSize: 12),
                        ),
                      ),
                  ],
                  if (!connected) ...[
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () async {
                        try {
                          final address = await _listenTogether.hostRoom();
                          _startListenTogetherBroadcast();
                          _refreshListeningTogetherUi();
                          if (address.isEmpty) {
                            _toast(_listenTogether.onlineConfigured
                                ? 'Kamar online dibuat.'
                                : 'Kamar dibuat, tetapi alamat Wi-Fi tidak ditemukan.');
                          }
                        } catch (error) {
                          _listenTogether.status.value = 'Gagal membuat kamar: $error';
                        }
                      },
                      icon: const Icon(Icons.add_link_rounded),
                      label: const Text('Buat kamar baru'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    ),
                    const SizedBox(height: 12),
                    if (!_listenTogether.onlineConfigured) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final room = await _listenTogether.discoverRoom();
                          if (!mounted) return;
                          if (room == null) {
                            _listenTogether.status.value = 'Kamar tidak ditemukan. Mode lokal memerlukan Wi-Fi/hotspot yang sama.';
                            return;
                          }
                          addressController.text = room.address;
                          _listenTogether.status.value = 'Kamar ditemukan. Masukkan kode 6 digit dari host lalu gabung.';
                        } catch (error) {
                          _listenTogether.status.value = 'Pencarian kamar gagal: $error';
                        }
                      },
                      icon: const Icon(Icons.radar_rounded),
                      label: const Text('Temukan kamar di Wi-Fi ini'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    ),
                    const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: addressController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _listenTogether.onlineConfigured ? 'Undangan online teman' : 'Alamat kamar teman',
                        hintText: _listenTogether.onlineConfigured
                            ? 'Tempel undangan online dari host'
                            : 'Alamat host, mis. 192.168.1.8:41773',
                        prefixIcon: const Icon(Icons.link_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onSubmitted: (_) => _joinListenTogetherRoom(addressController.text, codeController.text),
                    ),
                    if (!_listenTogether.onlineConfigured) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: _listenTogether.onlineConfigured ? 'Kode (otomatis dari undangan)' : 'Kode kamar 6 digit',
                        hintText: _listenTogether.onlineConfigured ? 'Tidak perlu diisi jika menempel undangan' : '123456',
                        counterText: '',
                        prefixIcon: const Icon(Icons.password_rounded),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onSubmitted: (_) => _joinListenTogetherRoom(addressController.text, codeController.text),
                    ),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => _joinListenTogetherRoom(addressController.text, codeController.text),
                      icon: const Icon(Icons.group_add_rounded),
                      label: const Text('Gabung kamar'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
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
    ).whenComplete(() {
      addressController.dispose();
      codeController.dispose();
    });
  }

  Future<void> _joinListenTogetherRoom(String address, String code) async {
    try {
      await _listenTogether.joinRoom(address, code: code);
      _listenTogetherSyncTimer?.cancel();
      _listenTogetherSyncTimer = null;
      _lastRoomUnsupportedTrackId = '';
      // A timer created before joining must not pause a guest and then be
      // immediately undone by the next host sync packet.
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
