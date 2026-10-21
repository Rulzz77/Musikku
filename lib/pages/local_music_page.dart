import 'dart:async';

import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../models/youtube_search_result.dart';
import '../services/local_media_service.dart';
import '../widgets/unified_artwork.dart';

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

  Future<void> _playAll() async {
    final songs = _visibleSongs.map((song) => song.toPlayable()).toList(growable: false);
    if (songs.isEmpty) return;
    await widget.onPlayFromList(songs.first, songs);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final songs = _visibleSongs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Musik di perangkat'),
        actions: [
          IconButton(
            tooltip: 'Pindai ulang',
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
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
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [scheme.primaryContainer.withValues(alpha: 0.75), scheme.surfaceContainerLow],
                                  ),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
                                  boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8))],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('YOUR DEVICE LIBRARY', style: TextStyle(color: scheme.secondary, fontSize: 9.5, letterSpacing: 1.25, fontWeight: FontWeight.w900)),
                                    const SizedBox(height: 9),
                                    Row(
                                      children: [
                                        Container(width: 52, height: 52, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)), child: Icon(Icons.folder_open_rounded, color: scheme.primary, size: 26)),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text('${_songs.length} lagu ditemukan', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.35)),
                                            const SizedBox(height: 3),
                                            Text('File audio lokal tetap berada di perangkatmu.', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                                          ]),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 7,
                                      runSpacing: 7,
                                      children: [
                                        _LibraryPill(icon: Icons.library_music_rounded, label: '${_songs.length} lagu'),
                                        _LibraryPill(icon: Icons.person_rounded, label: '${_songs.map((item) => item.artist.trim()).where((item) => item.isNotEmpty).toSet().length} artis'),
                                        const _LibraryPill(icon: Icons.phone_android_rounded, label: 'Lokal · privat'),
                                      ],
                                    ),
                                    const SizedBox(height: 15),
                                    TextField(
                                      controller: _search,
                                      textInputAction: TextInputAction.search,
                                      decoration: InputDecoration(
                                        hintText: 'Cari judul, artis, album…',
                                        prefixIcon: const Icon(Icons.search_rounded),
                                        suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _search.clear, icon: const Icon(Icons.close_rounded)),
                                        filled: true,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        ChoiceChip(label: const Text('Judul'), selected: _sort == _LocalSort.title, onSelected: (_) => setState(() => _sort = _LocalSort.title)),
                                        ChoiceChip(label: const Text('Artis'), selected: _sort == _LocalSort.artist, onSelected: (_) => setState(() => _sort = _LocalSort.artist)),
                                        ChoiceChip(label: const Text('Durasi'), selected: _sort == _LocalSort.duration, onSelected: (_) => setState(() => _sort = _LocalSort.duration)),
                                        FilledButton.icon(onPressed: songs.isEmpty ? null : _playAll, icon: const Icon(Icons.play_arrow_rounded, size: 18), label: const Text('Putar semua')),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (songs.isEmpty)
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.music_off_rounded, size: 48, color: scheme.onSurfaceVariant), const SizedBox(height: 10), const Text('Lagu tidak ditemukan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(_search.text.isEmpty ? 'Tambahkan file audio ke perangkat lalu pindai ulang.' : 'Coba kata kunci lain.', style: TextStyle(color: scheme.onSurfaceVariant), textAlign: TextAlign.center)]))),
                            )
                          else
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 28),
                              sliver: SliverList.builder(
                                itemCount: songs.length,
                                itemBuilder: (context, index) {
                                  final song = songs[index];
                                  final video = song.toPlayable();
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.fromLTRB(9, 4, 6, 4),
                                      onTap: () => unawaited(widget.onPlayFromList(video, songs.map((item) => item.toPlayable()).toList(growable: false))),
                                      leading: ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: UnifiedArtwork(track: video, width: 58, height: 58, cacheWidth: 174, borderRadius: BorderRadius.circular(12)),
                                      ),
                                      title: Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text([song.artist.isEmpty ? 'Artis tidak diketahui' : song.artist, if (song.album.isNotEmpty) song.album].join(' • '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(_duration(song.durationMs), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w700)),
                                          IconButton(tooltip: 'Tambahkan ke antrean', onPressed: () => widget.onAddToQueue(video), icon: const Icon(Icons.playlist_add_rounded)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
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
