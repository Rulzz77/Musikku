import 'dart:async';

import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../models/youtube_search_result.dart';
import '../services/local_media_service.dart';
import '../widgets/unified_artwork.dart';
import '../widgets/music_design.dart';

class LocalMusicPage extends StatefulWidget {
  const LocalMusicPage({
    super.key,
    required this.onPlayFromList,
    required this.onAddToQueue,
  });

  final Future<void> Function(YoutubeSearchResult video, List<YoutubeSearchResult> list) onPlayFromList;
  final ValueChanged<YoutubeSearchResult> onAddToQueue;

  @override
  State<LocalMusicPage> createState() => _LocalMusicPageState();
}

enum _LocalSort { title, artist, duration }

class _LocalMusicPageState extends State<LocalMusicPage> {
  final LocalMediaService _service = LocalMediaService();
  final TextEditingController _search = TextEditingController();
  List<LocalSong> _songs = const [];
  bool _loading = true;
  bool _permissionNeeded = false;
  String? _error;
  _LocalSort _sort = _LocalSort.title;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool requestPermission = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final bool granted;
      final List<LocalSong> songs;
      if (requestPermission) {
        songs = await _service.requestAndScan();
        granted = await _service.hasPermission();
      } else {
        granted = await _service.hasPermission();
        songs = granted ? await _service.scanSongs() : const <LocalSong>[];
      }
      if (!mounted) return;
      setState(() {
        _permissionNeeded = !granted;
        _songs = songs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Musik di perangkat tidak bisa dipindai. Periksa izin audio lalu coba lagi.';
      });
    }
  }

  List<LocalSong> get _visibleSongs {
    final q = _search.text.trim().toLowerCase();
    final result = _songs.where((song) {
      if (q.isEmpty) return true;
      return song.title.toLowerCase().contains(q) ||
          song.artist.toLowerCase().contains(q) ||
          song.album.toLowerCase().contains(q) ||
          song.genre.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case _LocalSort.title:
        result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case _LocalSort.artist:
        result.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case _LocalSort.duration:
        result.sort((a, b) => b.durationMs.compareTo(a.durationMs));
        break;
    }
    return result;
  }

  String _duration(int milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final songs = _visibleSongs;
    final playableSongs = songs.map((song) => song.toPlayable()).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Musik Lokal'),
        actions: [
          IconButton(
            tooltip: 'Pindai ulang',
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: MusicBackdrop(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _LocalMessage(
                  icon: Icons.error_outline_rounded,
                  title: 'Gagal memuat musik',
                  message: _error!,
                  actionLabel: 'Coba lagi',
                  onAction: () => unawaited(_load()),
                )
              : _permissionNeeded
                  ? _LocalMessage(
                      icon: Icons.library_music_outlined,
                      title: 'Izinkan akses musik',
                      message: 'MusikKu perlu izin audio untuk menampilkan lagu yang tersimpan di perangkat. File tidak diunggah ke mana pun.',
                      actionLabel: 'Izinkan akses',
                      onAction: () => unawaited(_load(requestPermission: true)),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: MusicPageEntrance(
                        child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 9, 16, 14),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [scheme.primaryContainer.withValues(alpha: 0.82), scheme.surfaceContainerLow, scheme.tertiaryContainer.withValues(alpha: 0.24)],
                                  ),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
                                  boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.07), blurRadius: 22, offset: const Offset(0, 8))],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]), borderRadius: BorderRadius.circular(16)),
                                          child: Icon(Icons.phone_android_rounded, color: scheme.onPrimary, size: 22),
                                        ),
                                        const SizedBox(width: 11),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('KOLEKSI PERANGKAT', style: TextStyle(color: scheme.primary, fontSize: 9, letterSpacing: 1.3, fontWeight: FontWeight.w900)),
                                              const SizedBox(height: 3),
                                              Text('${_songs.length} lagu tersedia', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 11),
                                    Text('File audio tetap tersimpan di perangkatmu. MusikKu tidak mengunggahnya.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5, height: 1.35)),
                                    const SizedBox(height: 13),
                                    Row(
                                      children: [
                                        _LibraryPill(icon: Icons.person_rounded, label: '${_songs.map((item) => item.artist.trim()).where((item) => item.isNotEmpty).toSet().length} artis'),
                                        const SizedBox(width: 7),
                                        const _LibraryPill(icon: Icons.lock_outline_rounded, label: 'Privat'),
                                        const Spacer(),
                                        IconButton.filled(
                                          tooltip: 'Putar semua lagu lokal',
                                          onPressed: playableSongs.isEmpty ? null : () => widget.onPlayFromList(playableSongs.first, playableSongs),
                                          icon: const Icon(Icons.play_arrow_rounded),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: TextField(
                                controller: _search,
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  hintText: 'Cari judul, artis, album, atau genre',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _search.clear, icon: const Icon(Icons.close_rounded)),
                                  filled: true,
                                  fillColor: scheme.surfaceContainerLow,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7))),
                                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55))),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.primary, width: 1.5)),
                                ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 16, 10),
                              child: Row(
                                children: [
                                  const Expanded(child: Text('Semua lagu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3))),
                                  Text('${songs.length} lagu', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 8),
                                  PopupMenuButton<_LocalSort>(
                                    tooltip: 'Urutkan lagu',
                                    initialValue: _sort,
                                    onSelected: (value) => setState(() => _sort = value),
                                    icon: const Icon(Icons.sort_rounded),
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(value: _LocalSort.title, child: Text('Urutkan: judul')),
                                      PopupMenuItem(value: _LocalSort.artist, child: Text('Urutkan: artis')),
                                      PopupMenuItem(value: _LocalSort.duration, child: Text('Durasi terpanjang')),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (songs.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.music_off_rounded, size: 48, color: scheme.onSurfaceVariant),
                                      const SizedBox(height: 10),
                                      const Text('Lagu tidak ditemukan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 4),
                                      Text(_search.text.isEmpty ? 'Tambahkan file audio ke perangkat lalu pindai ulang.' : 'Coba kata kunci lain.', style: TextStyle(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                              sliver: SliverList.builder(
                                itemCount: songs.length,
                                itemBuilder: (context, index) {
                                  final song = songs[index];
                                  final video = song.toPlayable();
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Material(
                                      color: scheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(15),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(15),
                                        onTap: () => unawaited(widget.onPlayFromList(video, playableSongs)),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(10, 9, 5, 9),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                child: Text('${index + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                                              ),
                                              const SizedBox(width: 8),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(13),
                                                child: UnifiedArtwork(track: video, width: 56, height: 56, cacheWidth: 168, borderRadius: BorderRadius.circular(13)),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                                                    const SizedBox(height: 4),
                                                    Text([song.artist.isEmpty ? 'Artis tidak diketahui' : song.artist, if (song.album.isNotEmpty) song.album].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                                                    const SizedBox(height: 5),
                                                    Text(_sort == _LocalSort.duration ? 'Durasi ${_duration(song.durationMs)}' : 'Audio lokal · ${_duration(song.durationMs)}', style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w800)),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Tambahkan ke antrean',
                                                onPressed: () => widget.onAddToQueue(video),
                                                icon: const Icon(Icons.playlist_add_rounded),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ))),
    );
  }
}


class _LibraryPill extends StatelessWidget {
  const _LibraryPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: scheme.primary),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _LocalMessage extends StatelessWidget {
  const _LocalMessage({required this.icon, required this.title, required this.message, required this.actionLabel, required this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 76, height: 76, alignment: Alignment.center, decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(24)), child: Icon(icon, size: 38, color: scheme.primary)),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 7),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.refresh_rounded), label: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
