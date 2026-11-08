import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../models/local_song.dart';
import '../models/native_youtube_state.dart';
import '../models/playlist.dart';
import '../models/youtube_search_result.dart';
import '../services/local_media_service.dart';
import '../widgets/unified_artwork.dart';
import '../widgets/music_design.dart';
import '../widgets/playlist_widgets.dart' show showPlaylistNameDialog;

class LocalMusicPage extends StatefulWidget {
  const LocalMusicPage({
    super.key,
    required this.onPlayFromList,
    required this.onAddToQueue,
    this.playlists = const <Playlist>[],
    this.onPlaylistsChanged,
    this.nativeState,
    this.onPlayPause,
  });

  final Future<void> Function(YoutubeSearchResult video, List<YoutubeSearchResult> list) onPlayFromList;
  final ValueChanged<YoutubeSearchResult> onAddToQueue;
  final List<Playlist> playlists;
  final VoidCallback? onPlaylistsChanged;
  /// Live player state keeps the active local track highlighted on this route.
  final ValueListenable<NativeYoutubeState>? nativeState;
  final Future<void> Function()? onPlayPause;

  @override
  State<LocalMusicPage> createState() => _LocalMusicPageState();
}

enum _LocalSort { title, artist, duration, recentlyAdded }

class _LocalMusicPageState extends State<LocalMusicPage> with WidgetsBindingObserver {
  final LocalMediaService _service = LocalMediaService();
  final TextEditingController _search = TextEditingController();
  List<LocalSong> _songs = const [];
  bool _loading = true;
  bool _permissionNeeded = false;
  bool _permissionSettingsRequired = false;
  bool _returningFromPermissionSettings = false;
  String? _error;
  _LocalSort _sort = _LocalSort.title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_refresh);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _returningFromPermissionSettings) {
      _returningFromPermissionSettings = false;
      unawaited(_load());
    }
  }

  Future<void> _openPermissionSettings() async {
    _returningFromPermissionSettings = true;
    await _service.openSettings();
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
      final settingsRequired = granted ? false : await _service.shouldOpenSettings();
      if (!mounted) return;
      setState(() {
        _permissionNeeded = !granted;
        _permissionSettingsRequired = settingsRequired;
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
      case _LocalSort.recentlyAdded:
        result.sort((a, b) => b.dateAddedSeconds.compareTo(a.dateAddedSeconds));
        break;
    }
    return result;
  }

  String _duration(int milliseconds) {
    final seconds = (milliseconds / 1000).floor();
    final minutes = seconds ~/ 60;
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _songMeta(LocalSong song) {
    if (_sort == _LocalSort.recentlyAdded && song.dateAddedSeconds > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(
        song.dateAddedSeconds * 1000,
      ).toLocal();
      final dateLabel =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      return 'Ditambahkan $dateLabel';
    }
    if (_sort == _LocalSort.duration) {
      return 'Durasi ${_duration(song.durationMs)}';
    }
    return 'Audio lokal · ${_duration(song.durationMs)}';
  }

  Future<void> _addLocalSongToPlaylist(LocalSong localSong) async {
    final video = localSong.toPlayable();
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.62,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TAMBAH LAGU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                            SizedBox(height: 4),
                            Text('Tambahkan ke playlist', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.add_circle_outline_rounded, color: scheme.primary),
                  title: const Text('Buat playlist baru', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Playlist baru langsung berisi lagu ini'),
                  onTap: () => Navigator.pop(sheetContext, '__create__'),
                ),
                const Divider(height: 1),
                Expanded(
                  child: widget.playlists.isEmpty
                      ? Center(
                          child: Text('Belum ada playlist lain.', style: TextStyle(color: scheme.onSurfaceVariant)),
                        )
                      : ListView.builder(
                          itemCount: widget.playlists.length,
                          itemBuilder: (context, index) {
                            final playlist = widget.playlists[index];
                            final contains = playlist.containsTrack(video);
                            return ListTile(
                              leading: Icon(
                                contains ? Icons.check_circle_rounded : Icons.queue_music_rounded,
                                color: contains ? scheme.primary : scheme.onSurfaceVariant,
                              ),
                              title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text('${playlist.songs.length} lagu · ${playlist.offlineSongCount} offline'),
                              trailing: contains ? const Icon(Icons.check_rounded) : const Icon(Icons.add_rounded),
                              enabled: !contains,
                              onTap: contains ? null : () => Navigator.pop(sheetContext, playlist.id),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selectedId == null) return;

    Playlist? target;
    if (selectedId == '__create__') {
      final name = await showPlaylistNameDialog(
        context,
        title: 'Playlist baru',
        confirmLabel: 'Buat',
      );
      if (!mounted || name == null) return;
      final created = Playlist(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        songs: <YoutubeSearchResult>[video],
      );
      target = created;
      widget.playlists.insert(0, created);
    } else {
      for (final playlist in widget.playlists) {
        if (playlist.id == selectedId) {
          target = playlist;
          break;
        }
      }
      if (target == null) return;
      if (!target.containsTrack(video)) {
        target.songs.add(video);
      }
    }

    final addedTo = target;
    widget.onPlaylistsChanged?.call();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${video.title}" ditambahkan ke "${addedTo.name}"')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.nativeState;
    if (listenable == null) {
      return _buildContent(context, const NativeYoutubeState());
    }
    return ValueListenableBuilder<NativeYoutubeState>(
      valueListenable: listenable,
      builder: (context, playbackState, _) =>
          _buildContent(context, playbackState),
    );
  }

  Widget _buildContent(BuildContext context, NativeYoutubeState playbackState) {
    final scheme = Theme.of(context).colorScheme;
    final songs = _visibleSongs;
    final playableSongs = songs.map((song) => song.toPlayable()).toList(growable: false);
    LocalSong? activeLocalSong;
    if (playbackState.videoId.startsWith('local:')) {
      for (final song in _songs) {
        if (song.toPlayable().videoId == playbackState.videoId) {
          activeLocalSong = song;
          break;
        }
      }
    }
    final isActivePlaying = playbackState.isEffectivelyPlaying;

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
                      message: _permissionSettingsRequired
                          ? 'Izin musik pernah ditolak. Aktifkan akses Musik dan audio di Pengaturan aplikasi agar lagu di HP bisa ditampilkan.'
                          : 'MusikKu perlu izin untuk menampilkan lagu yang tersimpan di perangkat. File tetap berada di HP dan tidak diunggah.',
                      actionLabel: _permissionSettingsRequired ? 'Buka pengaturan' : 'Izinkan akses',
                      onAction: () => unawaited(
                        _permissionSettingsRequired
                            ? _openPermissionSettings()
                            : _load(requestPermission: true),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: MusicPageEntrance(
                        child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 15),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(17, 17, 13, 15),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24), bottomRight: Radius.circular(24), bottomLeft: Radius.circular(7)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.phone_android_rounded, color: scheme.onPrimaryContainer, size: 17),
                                        const SizedBox(width: 7),
                                        Text('KOLEKSI DI PERANGKAT', style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.78), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                                        const Spacer(),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('${_songs.length}', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 43, height: 0.95, fontWeight: FontWeight.w900, letterSpacing: -1.7)),
                                              const SizedBox(height: 5),
                                              Text('lagu tersimpan di perangkat', style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.80), fontSize: 11, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                        FilledButton.icon(
                                          onPressed: playableSongs.isEmpty ? null : () => widget.onPlayFromList(playableSongs.first, playableSongs),
                                          style: FilledButton.styleFrom(backgroundColor: scheme.onPrimaryContainer, foregroundColor: scheme.primaryContainer),
                                          icon: const Icon(Icons.play_arrow_rounded, size: 19),
                                          label: const Text('Putar semua'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Icon(Icons.lock_outline_rounded, color: scheme.onPrimaryContainer.withValues(alpha: 0.7), size: 13),
                                        const SizedBox(width: 5),
                                        Text('Privat · tidak diunggah ke server', style: TextStyle(color: scheme.onPrimaryContainer.withValues(alpha: 0.76), fontSize: 9.5, fontWeight: FontWeight.w700)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (activeLocalSong != null)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: Material(
                                  color: scheme.primaryContainer.withValues(alpha: 0.58),
                                  borderRadius: BorderRadius.circular(16),
                                  child: ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
                                    leading: Icon(
                                      isActivePlaying ? Icons.equalizer_rounded : Icons.pause_circle_outline_rounded,
                                      color: scheme.primary,
                                      size: 25,
                                    ),
                                    title: Text(
                                      isActivePlaying ? 'Sedang diputar' : playbackState.isEnded ? 'Lagu selesai' : 'Lagu dijeda',
                                      style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.6),
                                    ),
                                    subtitle: Text(
                                      '${activeLocalSong.title} · ${activeLocalSong.artist.isEmpty ? 'Artis tidak diketahui' : activeLocalSong.artist}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                    ),
                                    trailing: widget.onPlayPause == null
                                        ? null
                                        : IconButton.filledTonal(
                                            tooltip: isActivePlaying ? 'Jeda lagu' : 'Lanjutkan lagu',
                                            onPressed: () => unawaited(widget.onPlayPause!.call()),
                                            icon: Icon(isActivePlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                          ),
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
                                      PopupMenuItem(value: _LocalSort.recentlyAdded, child: Text('Baru ditambahkan')),
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
                                      Text(_songs.isEmpty ? 'Belum ada musik di perangkat' : 'Lagu tidak ditemukan', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                                      const SizedBox(height: 4),
                                      Text(_songs.isEmpty ? 'Simpan file audio di HP, lalu tarik layar ke bawah atau tekan Pindai ulang.' : 'Coba kata kunci lain.', style: TextStyle(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
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
                                  final isCurrent = playbackState.videoId == video.videoId;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: AnimatedContainer(
                                      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
                                      decoration: BoxDecoration(
                                        color: isCurrent
                                            ? scheme.primaryContainer.withValues(alpha: 0.48)
                                            : scheme.surfaceContainerLow,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isCurrent ? scheme.primary.withValues(alpha: 0.55) : Colors.transparent,
                                          width: 1,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(13),
                                        child: InkWell(
                                        borderRadius: BorderRadius.circular(13),
                                        onTap: () {
                                          if (isCurrent && widget.onPlayPause != null) {
                                            unawaited(widget.onPlayPause!.call());
                                          } else {
                                            unawaited(widget.onPlayFromList(video, playableSongs));
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(10, 9, 5, 9),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 24,
                                                child: isCurrent
                                                    ? Icon(
                                                        isActivePlaying ? Icons.equalizer_rounded : Icons.pause_circle_outline_rounded,
                                                        size: 19,
                                                        color: scheme.primary,
                                                      )
                                                    : Text('${index + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                                              ),
                                              const SizedBox(width: 8),
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(13),
                                                child: Stack(
                                                  alignment: Alignment.center,
                                                  children: [
                                                    UnifiedArtwork(
                                                      track: video,
                                                      width: 56,
                                                      height: 56,
                                                      cacheWidth: 168,
                                                    ),
                                                    if (isCurrent)
                                                      Positioned.fill(
                                                        child: DecoratedBox(
                                                          decoration: BoxDecoration(
                                                            color: scheme.primary.withValues(alpha: 0.48),
                                                          ),
                                                          child: Icon(
                                                            isActivePlaying
                                                                ? Icons.equalizer_rounded
                                                                : Icons.pause_rounded,
                                                            color: Colors.white,
                                                            size: 25,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: isCurrent ? scheme.primary : null)),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      isCurrent
                                                          ? '${playbackState.isEnded ? 'SELESAI' : isActivePlaying ? 'SEDANG DIPUTAR' : 'DIJEDA'} · ${song.artist.isEmpty ? 'Artis tidak diketahui' : song.artist}'
                                                          : [song.artist.isEmpty ? 'Artis tidak diketahui' : song.artist, if (song.album.isNotEmpty) song.album].join(' · '),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(color: isCurrent ? scheme.primary : scheme.onSurfaceVariant, fontSize: 11.5, fontWeight: isCurrent ? FontWeight.w800 : FontWeight.normal),
                                                    ),
                                                    const SizedBox(height: 5),
                                                    Text(_songMeta(song), style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w800)),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuButton<String>(
                                                tooltip: 'Opsi lagu lokal',
                                                onSelected: (action) {
                                                  if (action == 'playlist') {
                                                    unawaited(_addLocalSongToPlaylist(song));
                                                  } else if (action == 'queue') {
                                                    widget.onAddToQueue(video);
                                                  }
                                                },
                                                itemBuilder: (context) => const [
                                                  PopupMenuItem(
                                                    value: 'playlist',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.playlist_add_rounded),
                                                        SizedBox(width: 12),
                                                        Text('Tambah ke playlist'),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'queue',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.queue_music_rounded),
                                                        SizedBox(width: 12),
                                                        Text('Tambah ke antrean'),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
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
