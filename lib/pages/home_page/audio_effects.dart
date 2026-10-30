part of '../home_page.dart';

// Extension ini bagian dari _HomePageState; setState aman dipakai di sini.
// ignore_for_file: invalid_use_of_protected_member

/// Crossfade, volume fade, pengaturan audio, dan sleep timer.
extension _HomeAudioEffects on _HomePageState {
  void _maybeStartAutoCrossfade(NativeYoutubeState state) {
    if (_crossfadeSeconds <= 0 ||
        !state.isPlaying ||
        state.duration <= Duration.zero ||
        state.videoId.isEmpty ||
        _crossfadeFadingVideoId == state.videoId) {
      return;
    }

    final remaining = state.duration - state.position;
    final lead = Duration(milliseconds: _crossfadeSeconds * 500);

    if (remaining <= lead && remaining > Duration.zero) {
      _crossfadeFadingVideoId = state.videoId;
      unawaited(
        _fadeVolume(
          from: _playerVolumePercent,
          to: 0,
          duration: remaining < lead ? remaining : lead,
        ),
      );
    }
  }

  void _cancelVolumeFade() {
    _volumeFadeGeneration++;
  }

  Future<void> _setPlayerVolume(int percent, {bool persist = false}) async {
    _cancelVolumeFade();
    final safe = percent.clamp(0, 100).toInt();
    _playerVolumePercent = safe;
    await _youtubeController.setVolume(safe);
    if (persist) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_playerVolumePrefKey, safe);
      } catch (_) {}
    }
  }

  Future<void> _fadeVolume({
    required int from,
    required int to,
    required Duration duration,
  }) async {
    final generation = ++_volumeFadeGeneration;

    if (duration <= Duration.zero) {
      if (generation != _volumeFadeGeneration) {
        return;
      }
      await _youtubeController.setVolume(to.clamp(0, 100).toInt());
      return;
    }

    final steps = (duration.inMilliseconds / 90).round().clamp(5, 24);
    for (var i = 1; i <= steps; i++) {
      if (generation != _volumeFadeGeneration) {
        return;
      }

      final value = (from + ((to - from) * i / steps).round())
          .clamp(0, 100)
          .toInt();
      try {
        await _youtubeController.setVolume(value);
      } catch (e) {
        debugPrint('FADE VOLUME ERROR: $e');
        return;
      }

      if (i != steps) {
        await Future<void>.delayed(
          Duration(milliseconds: (duration.inMilliseconds / steps).round()),
        );
      }
    }
  }

  void _clearSleepTimer() {
    _sleepTimer?.cancel();

    _sleepTimer = null;

    _stopAfterCurrent = false;

    _sleepActive.value = false;
  }
}

extension _HomeAudioSettingsUi on _HomePageState {
  Future<void> _applyEqualizerPreset(String preset) async {
    _equalizerPreset = preset;
    var applied = false;
    try {
      applied = await _youtubeController.setEqualizerPreset(preset);
    } catch (_) {}
    await _storage.saveEqualizerPreset(preset);
    final current = _currentVideo;
    if (current != null) {
      await _storage.saveEqualizerPresetForTrack(current.videoId, preset);
    }
    if (mounted) setState(() {});
    _toast(applied
        ? 'Equalizer: $preset'
        : 'Preset $preset disimpan. Efek EQ bergantung dukungan perangkat.');
  }

  void _showAudioSettingsSheet() {
    var crossfadePreview = _crossfadeSeconds;
    var volumePreview = _playerVolumePercent;
    final customBands = <double>[0, 0, 0, 0, 0];
    var customBandsLoaded = false;
    const customBandsPrefKey = 'equalizer_manual_bands_v1';
    const bandLabels = <String>['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];
    const presets = <({String name, String detail})>[
      (name: 'Flat', detail: 'Suara netral'),
      (name: 'Bass Boost', detail: 'Bass lebih terasa'),
      (name: 'Pop', detail: 'Vokal dan detail cerah'),
      (name: 'Dangdut', detail: 'Kendang, bass, dan vokal lebih terasa'),
      (name: 'Rock', detail: 'Gitar dan drum lebih tegas'),
      (name: 'Vocal', detail: 'Fokus pada suara vokal'),
      (name: 'Electronic', detail: 'Bass dan treble untuk EDM'),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          if (!customBandsLoaded) {
            customBandsLoaded = true;
            unawaited(() async {
              try {
                final prefs = await SharedPreferences.getInstance();
                final saved = prefs.getStringList(customBandsPrefKey);
                if (saved != null && saved.length == 5 && context.mounted) {
                  setSheetState(() {
                    for (var i = 0; i < 5; i++) {
                      customBands[i] = (double.tryParse(saved[i]) ?? 0).clamp(-12, 12).toDouble();
                    }
                  });
                }
              } catch (_) {}
            }());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MusicGlassPanel(
                  padding: const EdgeInsets.all(16),
                  radius: 22,
                  accent: scheme.primary,
                  child: const MusicSheetHeading(
                    icon: Icons.graphic_eq_rounded,
                    title: 'Studio suara',
                    subtitle: 'Bentuk karakter audio, atur level volume, dan haluskan perpindahan lagu.',
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Icon(Icons.equalizer_rounded, color: scheme.primary),
                    const SizedBox(width: 9),
                    const Text('Equalizer', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    Text(_equalizerPreset, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 43,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: presets.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final preset = presets[index];
                      return ChoiceChip(
                        label: Text(preset.name),
                        selected: _equalizerPreset == preset.name,
                        avatar: _equalizerPreset == preset.name ? const Icon(Icons.check_rounded, size: 16) : null,
                        side: BorderSide(
                          color: _equalizerPreset == preset.name
                              ? scheme.primary.withValues(alpha: 0.45)
                              : scheme.outlineVariant.withValues(alpha: 0.55),
                        ),
                        shape: const StadiumBorder(),
                        onSelected: (_) async {
                          await _applyEqualizerPreset(preset.name);
                          if (context.mounted) setSheetState(() {});
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  presets.firstWhere((item) => item.name == _equalizerPreset, orElse: () => presets.first).detail,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(13, 14, 13, 12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.tune_rounded, color: scheme.primary, size: 19),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(child: Text('EQ manual', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
                          Text('5 band • ±12 dB', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Geser tiap band untuk membentuk karakter suara.', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 174,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var band = 0; band < customBands.length; band++)
                              Expanded(
                                child: Column(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 140),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(
                                        '${customBands[band] > 0 ? '+' : ''}${customBands[band].toStringAsFixed(0)}',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: scheme.primary),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Expanded(
                                      child: Center(
                                        child: RotatedBox(
                                          quarterTurns: 3,
                                          child: SizedBox(
                                            width: 118,
                                            child: SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: 3.5,
                                                activeTrackColor: scheme.primary,
                                                inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.8),
                                                thumbColor: scheme.primary,
                                                overlayColor: scheme.primary.withValues(alpha: 0.12),
                                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
                                              ),
                                              child: Slider(
                                                value: customBands[band],
                                                min: -12,
                                                max: 12,
                                                divisions: 24,
                                                label: '${customBands[band].toStringAsFixed(0)} dB',
                                                onChanged: (value) => setSheetState(() => customBands[band] = value),
                                                onChangeEnd: (_) async {
                                                  var applied = false;
                                                  try {
                                                    applied = await _youtubeController.setEqualizerBands(customBands);
                                                    final prefs = await SharedPreferences.getInstance();
                                                    await prefs.setStringList(customBandsPrefKey, customBands.map((v) => v.toString()).toList());
                                                  } catch (_) {}
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                      content: Text(applied ? 'Equalizer manual diterapkan' : 'Efek manual bergantung dukungan audio perangkat'),
                                                      duration: const Duration(seconds: 2),
                                                    ));
                                                  }
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(bandLabels[band], maxLines: 1, style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            setSheetState(() { for (var i = 0; i < customBands.length; i++) { customBands[i] = 0; } });
                            var applied = false;
                            try {
                              applied = await _youtubeController.setEqualizerBands(customBands);
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setStringList(customBandsPrefKey, customBands.map((v) => v.toString()).toList());
                            } catch (_) {}
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(applied ? 'Equalizer direset' : 'Nilai EQ direset; efek bergantung dukungan perangkat')));
                            }
                          },
                          icon: const Icon(Icons.restart_alt_rounded, size: 17),
                          label: const Text('Reset band'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: scheme.primary),
                    const SizedBox(width: 9),
                    const Expanded(child: Text('Crossfade antar lagu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
                    Text(crossfadePreview == 0 ? 'Mati' : '$crossfadePreview dtk', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900)),
                  ],
                ),
                Slider(
                  value: crossfadePreview.toDouble(),
                  min: 0,
                  max: 6,
                  divisions: 6,
                  label: crossfadePreview == 0 ? 'Mati' : '$crossfadePreview detik',
                  onChanged: (value) => setSheetState(() => crossfadePreview = value.round()),
                  onChangeEnd: (value) async {
                    final seconds = value.round().clamp(0, 6).toInt();
                    _crossfadeSeconds = seconds;
                    await _storage.saveCrossfadeSeconds(seconds);
                    if (mounted) setState(() {});
                    setSheetState(() => crossfadePreview = seconds);
                  },
                ),
                Text(
                  crossfadePreview == 0
                      ? 'Lagu berganti langsung saat track berikutnya mulai.'
                      : 'Volume lagu saat ini turun perlahan selama sekitar $crossfadePreview detik terakhir.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, height: 1.35),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Icon(Icons.volume_up_rounded, color: scheme.primary),
                    const SizedBox(width: 9),
                    const Expanded(child: Text('Volume pemutar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
                    Text('$volumePreview%', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900)),
                  ],
                ),
                Slider(
                  value: volumePreview.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '$volumePreview%',
                  onChanged: (value) {
                    final next = (value / 5).round() * 5;
                    setSheetState(() => volumePreview = next);
                    unawaited(_setPlayerVolume(next));
                  },
                  onChangeEnd: (value) => unawaited(_setPlayerVolume(value.round(), persist: true)),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Efek equalizer adalah best-effort: keberhasilannya bergantung pada dukungan output audio perangkat Android. Crossfade memudarkan lagu aktif, bukan melakukan mixing dua stream secara penuh.',
                          style: TextStyle(fontSize: 11, height: 1.35, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSleepTimerSheet() {
    var selectedMinutes = 30;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => ValueListenableBuilder<bool>(
          valueListenable: _sleepActive,
          builder: (context, active, _) {
            final scheme = Theme.of(context).colorScheme;

            void startTimer(Duration duration) {
              _clearSleepTimer();
              _stopAfterCurrent = false;
              _sleepActive.value = true;
              _sleepTimer = Timer(duration, () {
                if (!mounted) return;
                _clearSleepTimer();
                unawaited(_stopPlayback());
                _toast('Timer tidur selesai. Pemutaran dijeda.');
              });
              Navigator.of(sheetContext).pop();
              _toast('MusikKu akan berhenti dalam ${duration.inMinutes} menit.');
            }

            void stopAfterTrack() {
              _sleepTimer?.cancel();
              _sleepTimer = null;
              _stopAfterCurrent = true;
              _sleepActive.value = true;
              Navigator.of(sheetContext).pop();
              _toast('Musik akan berhenti setelah lagu ini selesai.');
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: MusicSheetHeading(
                          icon: Icons.bedtime_rounded,
                          title: 'Timer tidur',
                          subtitle: 'Musik berhenti otomatis saat waktunya tiba.',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          scheme.primaryContainer.withValues(alpha: 0.88),
                          scheme.surfaceContainerHighest.withValues(alpha: 0.82),
                        ],
                      ),
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.surface.withValues(alpha: 0.70),
                            border: Border.all(color: scheme.primary.withValues(alpha: 0.26), width: 1.5),
                          ),
                          child: Icon(Icons.hourglass_bottom_rounded, size: 34, color: scheme.primary),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                active ? 'Timer sudah aktif' : 'Musik berhenti dalam',
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                active
                                    ? (_stopAfterCurrent ? 'Lagu ini selesai' : 'Waktu berjalan')
                                    : '$selectedMinutes menit',
                                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.7),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                active ? 'Timer akan mem-pause pemutar.' : 'Geser untuk mengatur durasi.',
                                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!active) ...[
                    const SizedBox(height: 12),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 5,
                        activeTrackColor: scheme.primary,
                        inactiveTrackColor: scheme.outlineVariant,
                        thumbColor: scheme.primary,
                        overlayColor: scheme.primary.withValues(alpha: 0.13),
                      ),
                      child: Slider(
                        value: selectedMinutes.toDouble(),
                        min: 5,
                        max: 180,
                        divisions: 35,
                        label: '$selectedMinutes menit',
                        onChanged: (value) {
                          setSheetState(() => selectedMinutes = (value / 5).round() * 5);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('5 mnt', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                          Text('3 jam', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final minutes in const [15, 30, 45, 60, 90, 120])
                          ChoiceChip(
                            label: Text('$minutes mnt'),
                            selected: selectedMinutes == minutes,
                            onSelected: (_) => setSheetState(() => selectedMinutes = minutes),
                            showCheckmark: false,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => startTimer(Duration(minutes: selectedMinutes)),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('Mulai timer · $selectedMinutes menit'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _currentVideo == null ? null : stopAfterTrack,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Berhenti setelah lagu ini'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  ),
                  if (active)
                    TextButton.icon(
                      onPressed: () {
                        _clearSleepTimer();
                        Navigator.of(sheetContext).pop();
                        _toast('Timer tidur dibatalkan.');
                      },
                      icon: const Icon(Icons.timer_off_rounded),
                      label: const Text('Batalkan timer'),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Timer berlaku selama proses MusikKu tetap berjalan. Mode “setelah lagu ini” mengikuti event selesai dari pemutar.',
                          style: TextStyle(fontSize: 11, height: 1.35, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
