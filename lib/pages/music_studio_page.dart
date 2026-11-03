import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listening_stat.dart';
import '../models/youtube_search_result.dart';
import '../services/app_settings.dart';
import '../services/storage_service.dart';
import '../widgets/unified_artwork.dart';

/// Personal feature center: real, locally persisted tools built on existing
/// listening history. It deliberately does not introduce an account/login.
class MusicStudioPage extends StatefulWidget {
  const MusicStudioPage({
    super.key,
    required this.storage,
    required this.settings,
    this.recentlyPlayed = const <YoutubeSearchResult>[],
    this.currentVideo,
    this.onPlayFromList,
    this.onPlayPause,
    this.onNext,
    this.onPrevious,
    this.onOpenLyrics,
    this.onOpenListeningRoom,
    this.onOpenAudioSettings,
    this.isPlaying = false,
  });

  final StorageService storage;
  final AppSettingsController settings;
  final List<YoutubeSearchResult> recentlyPlayed;
  final YoutubeSearchResult? currentVideo;
  final Future<void> Function(
    YoutubeSearchResult selected,
    List<YoutubeSearchResult> list,
  )? onPlayFromList;
  final Future<void> Function()? onPlayPause;
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrevious;
  final VoidCallback? onOpenLyrics;
  final VoidCallback? onOpenListeningRoom;
  final VoidCallback? onOpenAudioSettings;
  final bool isPlaying;

  @override
  State<MusicStudioPage> createState() => _MusicStudioPageState();
}

class _MusicStudioPageState extends State<MusicStudioPage> with WidgetsBindingObserver {
  static const _diaryKey = 'musikku_radio_diary_v1';
  late Future<_StudioData> _dataFuture;
  List<Map<String, dynamic>> _diary = <Map<String, dynamic>>[];
  bool _diaryLoading = true;
  String _mood = 'Chill';
  int _focusMinutes = 25;
  int _focusRemaining = 25 * 60;
  Timer? _focusTimer;
  DateTime? _focusDeadline;
  bool _focusRunning = false;
  bool _pauseWhenFocusEnds = false;

  static const _moods = <String, (IconData, List<String>)>{
    'Chill': (Icons.spa_rounded, ['chill', 'acoustic', 'lofi', 'lo-fi', 'jazz', 'piano', 'mellow', 'relax', 'slow']),
    'Happy': (Icons.wb_sunny_rounded, ['happy', 'fun', 'dance', 'ceria', 'bahagia', 'upbeat', 'party', 'feel good']),
    'Focus': (Icons.center_focus_strong_rounded, ['instrumental', 'piano', 'classical', 'ambient', 'lofi', 'lo-fi', 'study', 'focus']),
    'Energetic': (Icons.bolt_rounded, ['rock', 'workout', 'metal', 'edm', 'energetic', 'dance', 'remix', 'live']),
    'Sad': (Icons.water_drop_rounded, ['sad', 'galau', 'mellow', 'heartbreak', 'patah hati', 'acoustic', 'slow']),
    'Nostalgic': (Icons.history_rounded, ['90s', '2000s', 'nostalgia', 'kenangan', 'oldies', 'classic', 'memory']),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dataFuture = _loadData();
    _loadDiary();
  }

  Future<_StudioData> _loadData() async {
    await widget.storage.flushPendingWrites();
    final stats = await widget.storage.loadListeningStats();
    final recent = widget.recentlyPlayed.isNotEmpty
        ? widget.recentlyPlayed
        : await widget.storage.loadRecentlyPlayed();
    final favoriteArtists = await widget.storage.loadFavoriteArtistNames();
    final hiddenFlowTrackIds = await widget.storage.loadHiddenFlowTrackIds();
    return _StudioData(
      stats: stats,
      recent: recent,
      favoriteArtists: favoriteArtists,
      hiddenFlowTrackIds: hiddenFlowTrackIds,
    );
  }

  Future<void> _loadDiary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(prefs.getString(_diaryKey) ?? '[]');
      if (decoded is List) {
        _diary = decoded.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
      }
    } catch (_) {
      _diary = <Map<String, dynamic>>[];
    }
    if (mounted) setState(() => _diaryLoading = false);
  }

  Future<void> _saveRadioDiary(_StudioData data) async {
    final songs = data.recent.where((song) => song.videoId.isNotEmpty).take(20).toList();
    if (songs.isEmpty) {
      _toast('Belum ada riwayat lagu untuk disimpan sebagai sesi.');
      return;
    }
    final now = DateTime.now();
    final entry = <String, dynamic>{
      'id': now.microsecondsSinceEpoch.toString(),
      'title': 'Sesi ${_dateLabel(now)}',
      'createdAt': now.toIso8601String(),
      'songs': songs.map((song) => song.toJson()).toList(),
    };
    final next = <Map<String, dynamic>>[entry, ..._diary].take(30).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_diaryKey, jsonEncode(next));
    if (!mounted) return;
    setState(() => _diary = next);
    _toast('Sesi radio disimpan · ${songs.length} lagu');
  }

  Future<void> _playDiaryEntry(Map<String, dynamic> entry) async {
    final raw = entry['songs'];
    if (raw is! List) return;
    final songs = <YoutubeSearchResult>[];
    for (final item in raw) {
      if (item is Map) {
        try {
          final song = YoutubeSearchResult.fromJson(Map<String, dynamic>.from(item));
          if (song.videoId.isNotEmpty) songs.add(song);
        } catch (_) {}
      }
    }
    if (songs.isEmpty) {
      _toast('Sesi ini tidak memiliki lagu yang bisa diputar.');
      return;
    }
    final callback = widget.onPlayFromList;
    if (callback == null) {
      _toast('Kontrol pemutaran belum tersedia.');
      return;
    }
    await callback(songs.first, songs);
  }

  Future<void> _deleteDiaryEntry(String id) async {
    final next = _diary.where((entry) => entry['id']?.toString() != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_diaryKey, jsonEncode(next));
    if (mounted) setState(() => _diary = next);
  }

  List<YoutubeSearchResult> _buildFlowMix(_StudioData data) {
    final terms = _moods[_mood]!.$2;
    final stats = <String, ListeningStat>{for (final item in data.stats) item.videoId: item};
    final source = <YoutubeSearchResult>[];
    final seen = <String>{};
    for (final song in data.recent) {
      if (song.videoId.isEmpty ||
          data.hiddenFlowTrackIds.contains(song.videoId) ||
          !seen.add(song.videoId) || song.isLive || song.isUpcoming) {
        continue;
      }
      source.add(song);
    }
    final matched = source.where((song) {
      final haystack = '${song.title} ${song.channelTitle} ${song.description}'.toLowerCase();
      return terms.any(haystack.contains);
    }).toList();
    final ranked = matched.isNotEmpty ? matched : source;
    ranked.sort((a, b) {
      final sa = stats[a.videoId];
      final sb = stats[b.videoId];
      final scoreA = (sa?.listenedSeconds ?? 0) + (sa?.playCount ?? 0) * 120;
      final scoreB = (sb?.listenedSeconds ?? 0) + (sb?.playCount ?? 0) * 120;
      return scoreB.compareTo(scoreA);
    });
    return ranked.take(15).toList();
  }

  Future<void> _playFlow(_StudioData data) async {
    final mix = _buildFlowMix(data);
    if (mix.isEmpty) {
      _toast('Dengarkan beberapa lagu dulu agar Flow bisa mengenali seleramu.');
      return;
    }
    final callback = widget.onPlayFromList;
    if (callback == null) {
      _toast('Kontrol pemutaran belum tersedia dari halaman ini.');
      return;
    }
    await callback(mix.first, mix);
  }

  void _startFocus() {
    _focusTimer?.cancel();
    final deadline = DateTime.now().add(Duration(minutes: _focusMinutes));
    setState(() {
      _focusDeadline = deadline;
      _focusRemaining = _focusMinutes * 60;
      _focusRunning = true;
    });
    _focusTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateFocusCountdown());
  }

  void _updateFocusCountdown() {
    final deadline = _focusDeadline;
    if (deadline == null || !_focusRunning) return;
    final remaining = deadline.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _focusTimer?.cancel();
      _focusTimer = null;
      _focusDeadline = null;
      if (mounted) {
        setState(() {
          _focusRemaining = 0;
          _focusRunning = false;
        });
      }
      if (_pauseWhenFocusEnds && widget.onPlayPause != null && widget.isPlaying) {
        unawaited(widget.onPlayPause!());
      }
      _toast('Sesi fokus selesai. Istirahat sebentar, ya.');
      return;
    }
    if (mounted && remaining != _focusRemaining) {
      setState(() => _focusRemaining = remaining);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _focusRunning) {
      _updateFocusCountdown();
    }
  }

  void _pauseFocus() {
    _focusTimer?.cancel();
    _focusTimer = null;
    _focusDeadline = null;
    setState(() => _focusRunning = false);
  }

  void _resetFocus() {
    _focusTimer?.cancel();
    _focusTimer = null;
    _focusDeadline = null;
    setState(() {
      _focusRunning = false;
      _focusRemaining = _focusMinutes * 60;
    });
  }

  String _clock(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }

  String _dateLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MusikKu Studio')),
      body: FutureBuilder<_StudioData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _StudioData(stats: [], recent: []);
          final totalSeconds = data.stats.fold<double>(0, (sum, item) => sum + item.listenedSeconds);
          final topArtists = _topArtists(data.stats);
          final topTracks = List<ListeningStat>.from(data.stats)..sort((a, b) => b.playCount.compareTo(a.playCount));
          final activeRecently = data.stats.where((item) => item.lastPlayedAt != null && DateTime.now().difference(item.lastPlayedAt!).inDays <= 30).length;
          final flow = _buildFlowMix(data);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
            children: [
              _hero(context, totalSeconds, activeRecently, data.stats.length),
              const SizedBox(height: 18),
              _sectionTitle(context, 'MUSIK PERSONAL', 'Kenali pola mendengarkanmu'),
              _dnaPanel(context, topArtists, topTracks, totalSeconds, data.stats.length, data.favoriteArtists),
              const SizedBox(height: 18),
              _sectionTitle(context, 'MUSIKKU FLOW', 'Mix mood dari riwayatmu, tanpa pencarian acak'),
              _flowPanel(context, flow, data),
              const SizedBox(height: 18),
              _sectionTitle(context, 'THEMES STUDIO', 'Atur suasana visual MusikKu'),
              _themeStudioPanel(context),
              const SizedBox(height: 18),
              _sectionTitle(context, 'MEMORIES', 'Potongan perjalanan musikmu'),
              _memoriesPanel(context, activeRecently, data.recent, topTracks, data.hiddenFlowTrackIds),
              const SizedBox(height: 18),
              _sectionTitle(context, 'RADIO DIARY · MANUAL', 'Simpan snapshot riwayat lagu untuk diputar ulang'),
              _diaryPanel(context, data),
              const SizedBox(height: 18),
              _sectionTitle(context, 'FOCUS MODE', 'Timer fokus mengikuti waktu saat aplikasi kembali aktif'),
              _focusPanel(context),
              const SizedBox(height: 18),
              _sectionTitle(context, 'QUICK TOOLS', 'Kontrol yang sering dipakai'),
              _quickTools(context),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(BuildContext context, double seconds, int activeRecently, int tracks) {
    final scheme = Theme.of(context).colorScheme;
    final hours = (seconds / 3600).toStringAsFixed(seconds >= 36000 ? 0 : 1);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(24), border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('PERSONAL MUSIC SPACE', style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.6)),
        const SizedBox(height: 9),
        Text('Musik yang\nmewarnai harimu.', style: TextStyle(color: scheme.onSurface, fontSize: 27, height: 1.02, fontWeight: FontWeight.w900, letterSpacing: -.8)),
        const SizedBox(height: 15),
        Row(children: [
          _metric(context, '${hours}j', 'Total didengar'),
          const SizedBox(width: 18),
          _metric(context, '$activeRecently', 'Lagu aktif · 30 hari'),
          const SizedBox(width: 18),
          _metric(context, '$tracks', 'Lagu tercatat'),
        ]),
      ]),
    );
  }

  Widget _metric(BuildContext context, String value, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: TextStyle(color: scheme.onSurface, fontSize: 19, fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(label, maxLines: 2, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9.5, height: 1.15))]));
  }

  Widget _sectionTitle(BuildContext context, String eyebrow, String title) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 9), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(eyebrow, style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.4)), const SizedBox(height: 3), Text(title, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))]));
  }

  Widget _dnaPanel(BuildContext context, List<MapEntry<String, double>> artists, List<ListeningStat> tracks, double totalSeconds, int count, Set<String> favoriteArtists) {
    final scheme = Theme.of(context).colorScheme;
    return _panel(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('DNA mendengarkan', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900, fontSize: 15))), Text('${(totalSeconds / 3600).toStringAsFixed(1)} jam', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900))]),
      const SizedBox(height: 12),
      if (artists.isEmpty) Text('Statistik akan muncul setelah kamu mendengarkan musik.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))
      else ...[
        Text('ARTIS TERATAS', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        const SizedBox(height: 7),
        for (var i = 0; i < artists.take(4).length; i++)
          _rankRow(
            context,
            i + 1,
            artists[i].key,
            artists[i].value,
            isFavorite: favoriteArtists.contains(artists[i].key),
            onFavorite: () => unawaited(_toggleFavoriteArtist(artists[i].key, favoriteArtists)),
          ),
      ],
      const Divider(height: 20),
      Text('LAGU PALING SERING DIPUTAR', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
      const SizedBox(height: 6),
      for (final item in tracks.take(3)) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 11, fontWeight: FontWeight.w700))), Text('${item.playCount}×', style: TextStyle(color: scheme.primary, fontSize: 11, fontWeight: FontWeight.w900))])),
    ]));
  }

  Widget _rankRow(
    BuildContext context,
    int rank,
    String name,
    double seconds, {
    required bool isFavorite,
    required VoidCallback onFavorite,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(width: 23, height: 23, alignment: Alignment.center, decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(7)), child: Text('$rank', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 10, fontWeight: FontWeight.w900))),
        const SizedBox(width: 9),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 11, fontWeight: FontWeight.w700))),
        Text('${(seconds / 60).round()} mnt', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10)),
        IconButton(visualDensity: VisualDensity.compact, tooltip: isFavorite ? 'Hapus artis favorit' : 'Jadikan artis favorit', onPressed: onFavorite, icon: Icon(isFavorite ? Icons.star_rounded : Icons.star_border_rounded, color: isFavorite ? scheme.primary : scheme.onSurfaceVariant, size: 18)),
      ]),
    );
  }

  Future<void> _toggleFavoriteArtist(String artist, Set<String> favorites) async {
    if (favorites.contains(artist)) {
      favorites.remove(artist);
    } else {
      favorites.add(artist);
    }
    await widget.storage.saveFavoriteArtistNames(favorites);
    if (mounted) setState(() {});
  }

  Future<void> _toggleHiddenFlowTrack(YoutubeSearchResult song, Set<String> hiddenIds) async {
    if (hiddenIds.contains(song.videoId)) {
      hiddenIds.remove(song.videoId);
      _toast('Lagu ditampilkan kembali di MusikKu Flow.');
    } else {
      hiddenIds.add(song.videoId);
      _toast('Lagu disembunyikan dari rekomendasi Flow.');
    }
    await widget.storage.saveHiddenFlowTrackIds(hiddenIds);
    if (mounted) setState(() {});
  }

  Widget _flowPanel(BuildContext context, List<YoutubeSearchResult> flow, _StudioData data) {
    final scheme = Theme.of(context).colorScheme;
    return _panel(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 7, runSpacing: 7, children: [for (final mood in _moods.keys) ChoiceChip(label: Text(mood), selected: _mood == mood, onSelected: (_) => setState(() => _mood = mood))]),
      const SizedBox(height: 9),
      Text(flow.isEmpty ? 'Riwayat masih kosong. Putar beberapa lagu agar Flow punya bahan rekomendasi.' : '${flow.length} lagu dipilih dari riwayat dan statistik mendengarkan.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
      const SizedBox(height: 11),
      SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: flow.isEmpty ? null : () => unawaited(_playFlow(data)), icon: const Icon(Icons.play_arrow_rounded), label: Text('Putar Flow $_mood'))),
    ]));
  }


  Widget _themeStudioPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const descriptions = <AppThemeChoice, (String, Color, Color)>{
      AppThemeChoice.system: ('Ikuti perangkat', Color(0xFF607080), Color(0xFFE8EDF0)),
      AppThemeChoice.dark: ('Midnight Slate', Color(0xFF0D1422), Color(0xFF91D9CF)),
      AppThemeChoice.amoled: ('AMOLED', Colors.black, Color(0xFFB8B8EE)),
      AppThemeChoice.light: ('Warm Paper', Color(0xFFF3F0E6), Color(0xFF657F2F)),
      AppThemeChoice.pink: ('Pink Pastel', Color(0xFFFFE2EC), Color(0xFFCE5C8B)),
    };
    return _panel(context, ValueListenableBuilder<AppThemeChoice>(
      valueListenable: widget.settings.theme,
      builder: (context, selected, _) => Wrap(
        spacing: 9,
        runSpacing: 9,
        children: [
          for (final entry in descriptions.entries)
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => unawaited(widget.settings.setTheme(entry.key)),
              child: Container(
                width: 104,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: entry.value.$2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected == entry.key ? scheme.primary : scheme.outlineVariant, width: selected == entry.key ? 2 : 1),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: entry.value.$3, shape: BoxShape.circle)), const Spacer(), if (selected == entry.key) Icon(Icons.check_circle_rounded, size: 15, color: entry.value.$3)]),
                  const SizedBox(height: 13),
                  Text(entry.value.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: entry.key == AppThemeChoice.dark || entry.key == AppThemeChoice.amoled ? Colors.white : const Color(0xFF18221F), fontSize: 9, fontWeight: FontWeight.w900)),
                ]),
              ),
            ),
        ],
      ),
    ));
  }

  Widget _memoriesPanel(BuildContext context, int activeRecently, List<YoutubeSearchResult> recent, List<ListeningStat> topTracks, Set<String> hiddenFlowTrackIds) {
    final scheme = Theme.of(context).colorScheme;
    final top = topTracks.isEmpty ? null : topTracks.first;
    return _panel(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('30 hari terakhir', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900))), Text('$activeRecently lagu aktif', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900, fontSize: 11))]),
      const SizedBox(height: 7),
      Text(top == null ? 'Belum ada lagu favorit yang tercatat.' : 'Lagu paling sering diputar: ${top.title} · ${top.playCount} kali.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, height: 1.4)),
      const SizedBox(height: 7),
      Text('Riwayat terbaru', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
      const SizedBox(height: 4),
      for (final song in recent.take(5))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          subtitle: Text(song.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9)),
          trailing: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: hiddenFlowTrackIds.contains(song.videoId) ? 'Tampilkan di Flow' : 'Sembunyikan dari Flow',
            icon: Icon(hiddenFlowTrackIds.contains(song.videoId) ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
            onPressed: () => unawaited(_toggleHiddenFlowTrack(song, hiddenFlowTrackIds)),
          ),
        ),
    ]));
  }

  Widget _diaryPanel(BuildContext context, _StudioData data) {
    final scheme = Theme.of(context).colorScheme;
    return _panel(context, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text('Snapshot riwayat', style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w900))), TextButton.icon(onPressed: _diaryLoading ? null : () => unawaited(_saveRadioDiary(data)), icon: const Icon(Icons.bookmark_add_outlined, size: 17), label: const Text('Simpan snapshot'))]),
      if (_diaryLoading) const LinearProgressIndicator(minHeight: 2)
      else if (_diary.isEmpty) Text('Simpan snapshot manual dari riwayat terbaru; fitur ini belum merekam sesi Radio secara otomatis.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11))
      else ...[
        for (final entry in _diary.take(5))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.radio_rounded, color: scheme.primary),
            title: Text(entry['title']?.toString() ?? 'Sesi radio', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            subtitle: Text('${(entry['songs'] as List? ?? const []).length} lagu · ${entry['createdAt']?.toString().split('T').first ?? ''}', style: const TextStyle(fontSize: 10)),
            trailing: SizedBox(
              width: 86,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(tooltip: 'Putar sesi', icon: const Icon(Icons.play_circle_outline_rounded, size: 20), onPressed: () => unawaited(_playDiaryEntry(entry))),
                IconButton(tooltip: 'Hapus catatan', icon: const Icon(Icons.delete_outline_rounded, size: 18), onPressed: () => unawaited(_deleteDiaryEntry(entry['id']?.toString() ?? ''))),
              ]),
            ),
          ),
      ],
    ]));
  }

  Widget _focusPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = 1 - (_focusRemaining / (_focusMinutes * 60)).clamp(0.0, 1.0);
    return _panel(context, Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final minutes in [15, 25, 45, 60]) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: ChoiceChip(label: Text('$minutes m'), selected: _focusMinutes == minutes, onSelected: _focusRunning ? null : (_) => setState(() { _focusMinutes = minutes; _focusRemaining = minutes * 60; }))),
      ]),
      const SizedBox(height: 12),
      SizedBox(width: 132, height: 132, child: Stack(alignment: Alignment.center, children: [SizedBox.expand(child: CircularProgressIndicator(value: progress, strokeWidth: 8, backgroundColor: scheme.surfaceContainerHighest)), Column(mainAxisSize: MainAxisSize.min, children: [Text(_clock(_focusRemaining), style: TextStyle(color: scheme.onSurface, fontSize: 28, fontWeight: FontWeight.w900)), Text(_focusRunning ? 'BERJALAN' : 'FOKUS', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.3))])])),
      const SizedBox(height: 12),
      SwitchListTile(contentPadding: EdgeInsets.zero, dense: true, title: const Text('Jeda musik saat timer selesai', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)), value: _pauseWhenFocusEnds, onChanged: (value) => setState(() => _pauseWhenFocusEnds = value)),
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _resetFocus, icon: const Icon(Icons.restart_alt_rounded), label: const Text('Reset'))), const SizedBox(width: 8), Expanded(child: FilledButton.icon(onPressed: _focusRunning ? _pauseFocus : _startFocus, icon: Icon(_focusRunning ? Icons.pause_rounded : Icons.play_arrow_rounded), label: Text(_focusRunning ? 'Jeda' : 'Mulai')))]),
    ]));
  }

  Widget _quickTools(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      if (widget.currentVideo != null)
        _toolTile(context, Icons.directions_car_filled_rounded, 'Car Mode', 'Kontrol besar untuk penggunaan saat berkendara', () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _CarModePage(video: widget.currentVideo!, isPlaying: widget.isPlaying, onPlayPause: widget.onPlayPause, onNext: widget.onNext, onPrevious: widget.onPrevious, onLyrics: widget.onOpenLyrics)))),
      _toolTile(context, Icons.lyrics_rounded, 'Lirik lanjutan', 'Buka halaman lirik lagu yang sedang diputar', widget.onOpenLyrics),
      _toolTile(context, Icons.headphones_rounded, 'Listening Together', 'Buat atau gabung ruang dengar', widget.onOpenListeningRoom),
      _toolTile(context, Icons.speaker_group_rounded, 'Perangkat audio', 'Lihat perangkat output yang terdeteksi', widget.onOpenAudioSettings),
      const SizedBox(height: 8),
      Text('Visualisasi audio real-time, gapless sejati, dan loudness normalization membutuhkan akses stream audio mentah. Player YouTube berbasis iframe tidak menyediakan PCM untuk diproses aplikasi.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, height: 1.45)),
    ]);
  }

  Widget _toolTile(BuildContext context, IconData icon, String title, String subtitle, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 7), child: Material(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14), child: ListTile(enabled: onTap != null, onTap: onTap, leading: Icon(icon, color: scheme.primary), title: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), subtitle: Text(subtitle, style: const TextStyle(fontSize: 10)), trailing: const Icon(Icons.chevron_right_rounded))));
  }

  Widget _panel(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(18), border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5))), child: child);
  }

  List<MapEntry<String, double>> _topArtists(List<ListeningStat> stats) {
    final totals = <String, double>{};
    for (final item in stats) {
      final artist = item.artist.trim();
      if (artist.isEmpty || artist.toLowerCase() == 'unknown') continue;
      totals[artist] = (totals[artist] ?? 0) + item.listenedSeconds;
    }
    final result = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return result;
  }
}

class _StudioData {
  const _StudioData({
    required this.stats,
    required this.recent,
    this.favoriteArtists = const <String>{},
    this.hiddenFlowTrackIds = const <String>{},
  });
  final List<ListeningStat> stats;
  final List<YoutubeSearchResult> recent;
  final Set<String> favoriteArtists;
  final Set<String> hiddenFlowTrackIds;
}

class _CarModePage extends StatelessWidget {
  const _CarModePage({required this.video, required this.isPlaying, this.onPlayPause, this.onNext, this.onPrevious, this.onLyrics});
  final YoutubeSearchResult video;
  final bool isPlaying;
  final Future<void> Function()? onPlayPause;
  final Future<void> Function()? onNext;
  final Future<void> Function()? onPrevious;
  final VoidCallback? onLyrics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Car Mode')), body: SafeArea(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
      const Spacer(),
      ClipRRect(borderRadius: BorderRadius.circular(24), child: SizedBox(width: 220, height: 220, child: UnifiedArtwork(track: video, fit: BoxFit.cover))),
      const SizedBox(height: 24),
      Text(video.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
      const SizedBox(height: 7), Text(video.channelTitle, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      const Spacer(),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _bigControl(context, Icons.skip_previous_rounded, onPrevious),
        _bigControl(context, isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, onPlayPause, large: true),
        _bigControl(context, Icons.skip_next_rounded, onNext),
      ]),
      const SizedBox(height: 26),
      SizedBox(width: double.infinity, height: 54, child: OutlinedButton.icon(onPressed: onLyrics, icon: const Icon(Icons.lyrics_rounded), label: const Text('Buka lirik'), style: OutlinedButton.styleFrom(foregroundColor: scheme.primary, side: BorderSide(color: scheme.primary)))),
      const Spacer(),
      const Text('Gunakan saat kendaraan berhenti atau melalui kontrol hands-free.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 10)),
    ]))));
  }

  Widget _bigControl(BuildContext context, IconData icon, Future<void> Function()? action, {bool large = false}) {
    return SizedBox(width: large ? 86 : 66, height: large ? 86 : 66, child: FilledButton(onPressed: action == null ? null : () => unawaited(action()), style: FilledButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero, backgroundColor: large ? Theme.of(context).colorScheme.primary : const Color(0xFF263244), foregroundColor: large ? Theme.of(context).colorScheme.onPrimary : Colors.white), child: Icon(icon, size: large ? 42 : 32)));
  }
}
