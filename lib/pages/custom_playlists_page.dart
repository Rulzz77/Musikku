import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../models/playlist.dart';
import '../models/player_ui_state.dart';
import '../models/native_youtube_state.dart';
import '../models/youtube_search_result.dart';
import '../services/offline_download_service.dart';
import '../services/spotify_playlist_import_service.dart';
import '../services/spotify_youtube_track_matcher.dart';
import '../services/audio_download_estimator.dart';
import '../widgets/playlist_widgets.dart' show showPlaylistNameDialog;
import '../widgets/unified_artwork.dart';
import '../widgets/playlist_artwork.dart';
import '../widgets/flow_components.dart';
import '../widgets/music_design.dart';
import '../widgets/mini_music_player.dart';

/// Management screen for MusikKu's locally saved playlists.
/// The supplied playlist list is shared with HomePage; every mutation is
/// persisted through [onChanged].
class CustomPlaylistsPage extends StatefulWidget {
  const CustomPlaylistsPage({
    super.key,
    required this.playlists,
    this.initialPlaylistId,
    required this.playerUiState,
    this.availableSongs = const [],
    this.searchSongs,
    required this.onChanged,
    required this.onPlayPlaylist,
    this.onPlayOfflinePlaylist,
    required this.onPlaySong,
    this.onShufflePlaylist,
    this.currentVideo,
    this.nativeState,
    this.onOpenCurrentPlayer,
    this.onMiniPlayPause,
    this.onMiniNext,
    this.onSelectTab,
  });

  final List<Playlist> playlists;
  final String? initialPlaylistId;
  final ValueListenable<PlayerUiState> playerUiState;
  final List<YoutubeSearchResult> availableSongs;
  final Future<List<YoutubeSearchResult>> Function(String query)? searchSongs;
  final VoidCallback onChanged;
  final Future<void> Function(Playlist playlist) onPlayPlaylist;
  final Future<void> Function(Playlist playlist)? onPlayOfflinePlaylist;
  final Future<void> Function(Playlist playlist, YoutubeSearchResult song)
      onPlaySong;
  final Future<void> Function(Playlist playlist)? onShufflePlaylist;
  final YoutubeSearchResult? currentVideo;
  final ValueListenable<NativeYoutubeState>? nativeState;
  final VoidCallback? onOpenCurrentPlayer;
  final Future<void> Function()? onMiniPlayPause;
  final Future<void> Function()? onMiniNext;
  final ValueChanged<int>? onSelectTab;

  @override
  State<CustomPlaylistsPage> createState() => _CustomPlaylistsPageState();
}

class _CustomPlaylistsPageState extends State<CustomPlaylistsPage> {
  final ImagePicker _imagePicker = ImagePicker();
  String? _selectedPlaylistId;
  bool _changingArtwork = false;
  bool _songSelectionMode = false;
  final Set<String> _selectedSongIds = <String>{};
  _PlaylistSortMode _sortMode = _PlaylistSortMode.recent;
  final OfflineDownloadService _downloads = OfflineDownloadService.instance;
  final SpotifyPlaylistImportService _spotifyImporter =
      SpotifyPlaylistImportService();
  bool _spotifyImporting = false;

  @override
  void initState() {
    super.initState();
    _selectedPlaylistId = widget.initialPlaylistId;
    _downloads.addListener(_handleDownloadChanges);
    unawaited(_initializeDownloads());
  }

  @override
  void dispose() {
    _downloads.removeListener(_handleDownloadChanges);
    _spotifyImporter.close();
    super.dispose();
  }

  Future<void> _initializeDownloads() async {
    try {
      await _downloads.initialize();
      _handleDownloadChanges();
    } catch (error) {
      debugPrint('OFFLINE DOWNLOAD INIT ERROR: $error');
    }
  }

  void _handleDownloadChanges() {
    if (!mounted) return;
    var playlistChanged = false;
    for (final playlist in widget.playlists) {
      for (var index = 0; index < playlist.songs.length; index++) {
        final song = playlist.songs[index];
        final entry = _downloads.itemFor(song.videoId);
        final completedPath = entry?.status == OfflineDownloadStatus.completed
            ? entry!.filePath
            : '';
        if (song.offlinePath != completedPath) {
          playlist.songs[index] = song.copyWith(offlinePath: completedPath);
          playlistChanged = true;
        }
      }
    }
    if (playlistChanged) {
      widget.onChanged();
      setState(() {});
    }
  }

  Future<void> _downloadSong(YoutubeSearchResult song) async {
    try {
      await _downloads.enqueue(song);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${song.title}" masuk antrean download')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tidak bisa mengunduh lagu: $error')),
      );
    }
  }

  Future<void> _downloadPlaylist(Playlist playlist) async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download playlist saat ini hanya tersedia di Android.')),
      );
      return;
    }

    await _downloads.initialize();
    if (!mounted) return;

    // Deduplicate by video ID so the estimate and queue count match the
    // downloader's identity key and duplicate playlist rows are not counted.
    final uniqueSongs = <String, YoutubeSearchResult>{};
    for (final song in playlist.songs) {
      if (song.videoId.isNotEmpty) {
        uniqueSongs.putIfAbsent(song.videoId, () => song);
      }
    }

    final pending = <YoutubeSearchResult>[];
    for (final song in uniqueSongs.values) {
      if (song.isLocal) continue;
      if (song.isOfflineDownloaded &&
          await _downloads.isOfflineFileUsable(song.offlinePath)) {
        continue;
      }
      final existing = _downloads.itemFor(song.videoId);
      if (existing != null &&
          existing.status == OfflineDownloadStatus.completed &&
          await _downloads.hasUsableCompletedDownload(song.videoId)) {
        continue;
      }
      pending.add(song);
    }

    // Permission, storage, and file checks are asynchronous; do not touch the
    // page context until every awaited preflight step has completed and mounted.
    if (!mounted) return;

    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua lagu playlist sudah tersedia offline.')),
      );
      return;
    }

    final knownFileSizes = <String, int>{};
    final alreadyDownloadedBytes = <String, int>{};
    for (final song in pending) {
      final entry = _downloads.itemFor(song.videoId);
      final totalBytes = entry?.totalBytes ?? 0;
      final downloadedBytes = entry?.downloadedBytes ?? 0;
      if (totalBytes > 0) knownFileSizes[song.videoId] = totalBytes;
      if (downloadedBytes > 0) {
        alreadyDownloadedBytes[song.videoId] = downloadedBytes;
      }
    }
    final estimate = AudioDownloadEstimate.fromSongs(
      pending,
      knownFileSizes: knownFileSizes,
      alreadyDownloadedBytes: alreadyDownloadedBytes,
    );
    const storageReserveBytes = 48 * 1024 * 1024;
    int availableStorageBytes;
    try {
      availableStorageBytes = await _downloads.getAvailableStorageBytes();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tidak bisa memeriksa penyimpanan: $error')),
      );
      return;
    }
    if (!mounted) return;
    final estimatedRequiredBytes = estimate.maximumBytes;
    final hasEnoughEstimatedSpace = !estimate.hasEstimate ||
        estimatedRequiredBytes + storageReserveBytes <= availableStorageBytes;
    final alreadyQueued = pending.where((song) {
      final status = _downloads.itemFor(song.videoId)?.status;
      return status == OfflineDownloadStatus.queued ||
          status == OfflineDownloadStatus.downloading;
    }).length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Download seluruh playlist?'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${pending.length} lagu belum tersedia offline.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PERKIRAAN UKURAN',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          estimate.hasEstimate
                              ? _formatMegabytes(estimate.estimatedBytes)
                              : 'Belum diketahui',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 27,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (estimate.hasEstimate) ...[
                          const SizedBox(height: 3),
                          Text(
                            'Rentang kasar ${_formatMegabytes(estimate.minimumBytes)}–${_formatMegabytes(estimate.maximumBytes)}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _downloadEstimateRow(
                    'Lagu yang akan disiapkan',
                    '${pending.length} lagu',
                    scheme,
                  ),
                  _downloadEstimateRow(
                    'Penyimpanan tersedia',
                    _formatMegabytes(availableStorageBytes),
                    scheme,
                  ),
                  _downloadEstimateRow(
                    'Cadangan ruang wajib',
                    _formatMegabytes(storageReserveBytes),
                    scheme,
                  ),
                  if (alreadyQueued > 0)
                    _downloadEstimateRow(
                      'Sudah ada di antrean',
                      '$alreadyQueued lagu',
                      scheme,
                    ),
                  if (estimate.knownFileSizeTracks > 0)
                    _downloadEstimateRow(
                      'Ukuran file sudah terdeteksi',
                      '${estimate.knownFileSizeTracks} lagu',
                      scheme,
                    ),
                  if (estimate.knownDurationTracks > 0)
                    _downloadEstimateRow(
                      'Dihitung dari durasi',
                      '${estimate.knownDurationTracks} lagu',
                      scheme,
                    ),
                  if (estimate.unknownDurationTracks > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${estimate.unknownDurationTracks} lagu belum memiliki ukuran atau data durasi, jadi belum masuk ke estimasi MB. Ruang akan tetap diperiksa selama transfer.',
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (!hasEnoughEstimatedSpace) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Ruang penyimpanan diperkirakan tidak cukup. Kosongkan ruang atau unduh lagu lebih sedikit.',
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Ukuran yang sudah diketahui mengikuti data antrean. Lagu lain dihitung memakai asumsi audio 128 kbps (rentang 96–192 kbps), jadi total tetap perkiraan. Ukuran akhir mengikuti format dan bitrate sumber. Lagu lokal dan yang sudah tersedia offline tidak dihitung.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gunakan fitur unduhan hanya untuk audio yang memang memiliki izin pengunduhan dan pemutaran offline.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: hasEnoughEstimatedSpace
                  ? () => Navigator.pop(dialogContext, true)
                  : null,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Mulai download'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;
    try {
      final result = await _downloads.enqueueAll(pending);
      if (!mounted) return;
      final summary = <String>[];
      if (result.added > 0) {
        summary.add('${result.added} lagu masuk antrean');
      }
      if (result.alreadyQueued > 0) {
        summary.add('${result.alreadyQueued} sudah di antrean');
      }
      if (result.alreadyDownloaded > 0) {
        summary.add('${result.alreadyDownloaded} sudah offline');
      }
      if (result.duplicateInput > 0) {
        summary.add('${result.duplicateInput} duplikat diabaikan');
      }
      if (result.failed > 0) {
        summary.add('${result.failed} gagal ditambahkan');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            summary.isEmpty
                ? 'Tidak ada lagu baru untuk diunduh.'
                : summary.join(' · '),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Antrean download gagal: $error')),
      );
    }
  }

  Widget _downloadEstimateRow(
    String label,
    String value,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _formatMegabytes(int bytes) =>
      '${(bytes / 1000000).toStringAsFixed(1)} MB';

  Future<void> _showDownloadManager() async {
    await _downloads.initialize();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: _downloads,
        builder: (context, _) {
          final items = _downloads.items;
          final scheme = Theme.of(context).colorScheme;
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 16, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('DOWNLOAD MANAGER', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                            SizedBox(height: 4),
                            Text('Unduhan offline', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      Text(_formatBytes(_downloads.totalDownloadedBytes), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: !Platform.isAndroid
                              ? null
                              : _downloads.isPaused
                                  ? () => unawaited(_downloads.resumeAll())
                                  : () => unawaited(_downloads.pauseAll()),
                          icon: Icon(_downloads.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                          label: Text(_downloads.isPaused ? 'Lanjutkan' : 'Jeda semua'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 18),
                Expanded(
                  child: items.isEmpty
                      ? Center(child: Text('Belum ada unduhan.', style: TextStyle(color: scheme.onSurfaceVariant)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: items.length,
                          separatorBuilder: (context, separatorIndex) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final completed = item.status == OfflineDownloadStatus.completed;
                            final active = item.status == OfflineDownloadStatus.downloading;
                            final failed = item.status == OfflineDownloadStatus.failed;
                            return Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(width: 42, height: 42, child: UnifiedArtwork(track: item.song, width: 42, height: 42)),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item.song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                            const SizedBox(height: 3),
                                            Text(
                                              completed ? 'Selesai · ${_formatBytes(item.downloadedBytes)}' : failed ? 'Gagal · ${item.errorMessage}' : active ? 'Mengunduh · ${_formatBytes(item.downloadedBytes)}${item.totalBytes > 0 ? ' / ${_formatBytes(item.totalBytes)}' : ''}' : item.status == OfflineDownloadStatus.queued ? 'Menunggu antrean' : 'Dijeda · ${_formatBytes(item.downloadedBytes)}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if ((failed || item.status == OfflineDownloadStatus.paused) &&
                                          !_downloads.isActiveDownload(item.song.videoId))
                                        IconButton(
                                          tooltip: 'Coba lagi',
                                          onPressed: () => unawaited(_downloads.retry(item.song.videoId)),
                                          icon: const Icon(Icons.refresh_rounded),
                                        ),
                                      if (completed || failed ||
                                          item.status == OfflineDownloadStatus.queued ||
                                          (item.status == OfflineDownloadStatus.paused &&
                                              !_downloads.isActiveDownload(item.song.videoId)))
                                        IconButton(
                                          tooltip: 'Hapus dari manager',
                                          onPressed: () async {
                                            try {
                                              await _downloads.delete(item.song.videoId);
                                            } catch (error) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(this.context).showSnackBar(SnackBar(content: Text('$error')));
                                              }
                                            }
                                          },
                                          icon: const Icon(Icons.delete_outline_rounded),
                                        ),
                                      if (active) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                                    ],
                                  ),
                                  if (!completed)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: LinearProgressIndicator(
                                        value: item.totalBytes > 0 ? item.progress : null,
                                        minHeight: 4,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Playlist? get _selectedPlaylist {
    final id = _selectedPlaylistId;
    if (id == null) return null;
    for (final playlist in widget.playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  void _selectMainTab(int index) {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    widget.onSelectTab?.call(index);
  }

  Future<void> _createPlaylist() async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Playlist baru',
      confirmLabel: 'Buat',
    );
    if (!mounted || name == null) return;

    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
    );
    setState(() {
      widget.playlists.insert(0, playlist);
      _selectedPlaylistId = playlist.id;
    });
    widget.onChanged();
  }

  Future<void> _importSpotifyPlaylist() async {
    if (_spotifyImporting) return;
    final searchSongs = widget.searchSongs;
    if (searchSongs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pencarian YouTube belum siap untuk impor.')),
      );
      return;
    }

    final controller = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Impor playlist Spotify'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tempel link playlist Spotify yang bisa dibuka secara publik. '
              'Tidak perlu Spotify API, API key, atau login.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
              decoration: InputDecoration(
                hintText: 'https://open.spotify.com/playlist/...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Tempel link',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
                    final value = clipboard?.text?.trim();
                    if (value != null && value.isNotEmpty) {
                      controller.text = value;
                      controller.selection = TextSelection.collapsed(
                        offset: controller.text.length,
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Baca playlist'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || link == null || link.trim().isEmpty) return;

    setState(() => _spotifyImporting = true);
    try {
      BuildContext? readingDialogContext;
      final readingDialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          readingDialogContext = dialogContext;
          return const PopScope(
            canPop: false,
            child: AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(width: 16),
                  Text('Membaca halaman playlist Spotify…'),
                ],
              ),
            ),
          );
        },
      );
      late final SpotifyPlaylistSnapshot snapshot;
      try {
        snapshot = await _spotifyImporter.fetchPublicPlaylist(link);
      } finally {
        final dialogContext = readingDialogContext;
        if (dialogContext != null && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        await readingDialog;
      }
      if (!mounted) return;

      final supplementaryTracksController = TextEditingController();
      final preview = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(snapshot.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.totalTrackCount != null
                      ? '${snapshot.tracks.length} lagu terbaca dari total ${snapshot.totalTrackCount} lagu yang diiklankan metadata publik Spotify.'
                      : snapshot.tracks.length >= 100
                          ? '≥${snapshot.tracks.length} lagu terbaca dari embed publik. Itu hanya jumlah minimum yang terlihat, BUKAN total playlist. Spotify tidak memberikan halaman lanjutan pada embed ini.'
                          : snapshot.mayBePartial
                              ? '${snapshot.tracks.length} lagu terbaca dari embed publik. Jumlah total playlist belum bisa dipastikan.'
                              : '${snapshot.tracks.length} lagu terbaca dari halaman embed publik Spotify.',
                ),
                if (snapshot.mayBePartial) ...[
                  const SizedBox(height: 8),
                  Text(
                    snapshot.knownMissingTrackCount > 0
                        ? 'Embed publik hanya menampilkan ${snapshot.tracks.length} dari ${snapshot.totalTrackCount} lagu. Sisa ${snapshot.knownMissingTrackCount} lagu tidak disediakan oleh halaman publik ini. Tanpa pagination publik/API, MusikKu tidak bisa mengambil sisanya.'
                        : snapshot.tracks.length == 100
                            ? 'Embed publik pada playlist ini berhenti di 100 baris pertama. Jumlah total dan lagu setelahnya tidak disediakan oleh halaman ini. Tempel daftar lagu yang tersisa untuk melengkapinya tanpa API.'
                            : snapshot.tracks.length > 100
                                ? 'Embed publik mengirim ${snapshot.tracks.length} baris, tetapi tidak mengiklankan total playlist. Angka ini adalah jumlah minimum yang terbaca, bukan total akhir.'
                                : 'Embed publik mungkin hanya menampilkan sebagian daftar. Jika Spotify tidak mengirim baris sisanya, MusikKu tidak bisa mengambilnya tanpa pagination publik/API.',
                    style: const TextStyle(color: Colors.orange),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: supplementaryTracksController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: 'Tambahkan lagu setelah ${snapshot.tracks.length} lagu yang terbaca (opsional)',
                      hintText: 'Judul lagu<TAB>Artis\natau Judul lagu — Artis',
                      helperText: 'Tempel lagu yang belum muncul, satu lagu per baris. Format: Judul<TAB>Artis atau Judul — Artis. Urutan dan duplikat dipertahankan.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ...snapshot.tracks.take(5).map(
                  (track) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.music_note_rounded, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${track.title} — ${track.artists.join(', ')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (snapshot.tracks.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('dan ${snapshot.tracks.length - 5} lagu lainnya…'),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'MusikKu akan mencari pasangan lagu di YouTube Music. Lagu yang tidak cocok akan dilewati, bukan diganti dengan lagu lain.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Cocokkan & impor'),
            ),
          ],
        ),
      );
      final supplementaryTracks =
          SpotifyPlaylistImportService.parseSupplementaryTrackText(
        supplementaryTracksController.text,
      );
      supplementaryTracksController.dispose();
      if (!mounted || preview != true) return;
      final tracksToImport = <SpotifyPlaylistTrack>[
        ...snapshot.tracks,
        ...supplementaryTracks,
      ];

      final progressText = ValueNotifier<String>('Menyiapkan pencarian lagu…');
      final progress = ValueNotifier<double>(0);
      BuildContext? progressDialogContext;
      final progressDialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          progressDialogContext = dialogContext;
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('Mengimpor playlist'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<String>(
                      valueListenable: progressText,
                      builder: (context, value, child) => Text(value),
                    ),
                    const SizedBox(height: 14),
                    ValueListenableBuilder<double>(
                      valueListenable: progress,
                      builder: (context, value, child) => Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          LinearProgressIndicator(value: value),
                          const SizedBox(height: 6),
                          Text('${(value * 100).round()}%'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

      final resolved = List<YoutubeSearchResult?>.filled(
        tracksToImport.length,
        null,
      );
      try {
        // Small batches keep network pressure low while preserving Spotify's
        // original ordering in the resolved array.
        for (var start = 0; start < tracksToImport.length; start += 2) {
          final end = (start + 2 < tracksToImport.length)
              ? start + 2
              : tracksToImport.length;
          progressText.value = 'Mencocokkan lagu ${start + 1}–$end dari ${tracksToImport.length}…';
          final indexes = List<int>.generate(end - start, (offset) => start + offset);
          final batch = await Future.wait(indexes.map((index) async {
            final track = tracksToImport[index];
            try {
              // Search by performer + title first, then title alone. YouTube
              // may order these fields either way ("Artist - Song" or
              // "Song - Artist"), so the query policy compares their tokens
              // across title/channel/description and the matcher verifies the
              // actual primary artist before accepting anything.
              final queries = <String>{};
              final coreTitle = track.title
                  .replaceFirst(
                    RegExp(r'\s+[-–—]\s*from\s+.+$', caseSensitive: false),
                    '',
                  )
                  .trim();
              if (track.primaryArtist.isNotEmpty) {
                queries.add('${track.primaryArtist} $coreTitle'.trim());
              }
              queries.add(coreTitle);
              if (track.title.trim() != coreTitle) {
                queries.add(track.title.trim());
              }
              if (track.artists.length > 1) {
                queries.add('$coreTitle ${track.artists.join(' ')}'.trim());
              }
              if (track.primaryArtist.isNotEmpty) {
                queries.add('$coreTitle ${track.primaryArtist}'.trim());
              }
              if (track.primaryArtist.isNotEmpty) {
                queries.add(track.primaryArtist.trim());
              }

              final candidatesById = <String, YoutubeSearchResult>{};
              YoutubeSearchResult? match;
              var queryIndex = 0;
              for (final query in queries) {
                queryIndex++;
                List<YoutubeSearchResult> results;
                try {
                  results = await searchSongs(query);
                } catch (error) {
                  debugPrint(
                    'SPOTIFY SEARCH FAILED [${track.title}] '
                    'query#$queryIndex "$query": $error',
                  );
                  continue;
                }
                for (final result in results) {
                  if (result.videoId.isNotEmpty) {
                    candidatesById.putIfAbsent(result.videoId, () => result);
                  }
                }
                match = SpotifyYoutubeTrackMatcher.bestMatch(
                  track,
                  candidatesById.values.toList(growable: false),
                );
                if (match != null) break;
              }

              return match == null
                  ? null
                  : SpotifyYoutubeTrackMatcher.applySpotifyMetadata(track, match);
            } catch (error) {
              debugPrint('SPOTIFY IMPORT SEARCH FAILED [${track.title}]: $error');
              return null;
            }
          }));
          for (var offset = 0; offset < indexes.length; offset++) {
            resolved[indexes[offset]] = batch[offset];
          }
          progress.value = end / tracksToImport.length;
        }
      } finally {
        final dialogContext = progressDialogContext;
        if (dialogContext != null && dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        await progressDialog;
        progressText.dispose();
        progress.dispose();
      }

      if (!mounted) return;
      // Preserve every resolved Spotify occurrence, including intentional
      // repeats of the same song. A playlist is an ordered sequence, not a
      // set; duplicate entries are valid Spotify playlist content.
      final importedSongs = resolved
          .whereType<YoutubeSearchResult>()
          .toList(growable: true);

      final unmatchedTracks = <SpotifyPlaylistTrack>[
        for (var index = 0; index < tracksToImport.length; index++)
          if (resolved[index] == null) tracksToImport[index],
      ];
      if (importedSongs.isEmpty) {
        await _showSpotifyUnmatchedReport(
          unmatchedTracks,
          summary: 'Metadata ${tracksToImport.length} lagu terbaca, tetapi tidak ada pasangan YouTube Music yang cukup cocok. Playlist tidak dibuat.',
        );
        return;
      }

      final unmatchedCount = unmatchedTracks.length;
      final playlist = Playlist(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: snapshot.title,
        description: 'Diimpor dari playlist Spotify publik · ${snapshot.sourceUrl}',
        folderName: 'Impor Spotify',
        songs: importedSongs,
      );
      setState(() {
        widget.playlists.insert(0, playlist);
        _selectedPlaylistId = playlist.id;
      });
      widget.onChanged();

      final summary = <String>[
        '${importedSongs.length}/${tracksToImport.length} lagu berhasil diimpor',
        if (unmatchedCount > 0) '$unmatchedCount tidak ditemukan/cocok',
        if (snapshot.mayBePartial)
          snapshot.knownMissingTrackCount > 0
              ? '${(snapshot.knownMissingTrackCount - supplementaryTracks.length).clamp(0, snapshot.knownMissingTrackCount)} lagu dari metadata belum dilengkapi'
              : 'jumlah asli belum diketahui; sekurangnya ${snapshot.tracks.length} baris terlihat di embed, bukan total playlist',
        if (supplementaryTracks.isNotEmpty)
          '${supplementaryTracks.length} lagu tambahan dibaca dari daftar tempel',
      ];
      if (unmatchedTracks.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(summary.join(' · ')),
            duration: const Duration(seconds: 7),
          ),
        );
      } else {
        await _showSpotifyUnmatchedReport(
          unmatchedTracks,
          summary: summary.join(' · '),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Impor Spotify gagal: $error'),
          duration: const Duration(seconds: 7),
        ),
      );
    } finally {
      if (mounted) setState(() => _spotifyImporting = false);
    }
  }

  Future<void> _showSpotifyUnmatchedReport(
    List<SpotifyPlaylistTrack> unmatchedTracks, {
    required String summary,
  }) async {
    if (!mounted || unmatchedTracks.isEmpty) return;

    final unmatchedReport = unmatchedTracks
        .map((track) => '${track.title} — ${track.artists.join(', ')}')
        .join('\n');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lagu Spotify belum cocok'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(summary),
              const SizedBox(height: 10),
              const Text(
                'Lagu berikut belum menemukan pasangan YouTube Music yang cukup cocok. '
                'MusikKu sengaja tidak menggantinya dengan penyanyi atau versi lain:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: unmatchedTracks.length > 30
                      ? 30
                      : unmatchedTracks.length,
                  separatorBuilder: (context, index) => const Divider(height: 8),
                  itemBuilder: (_, index) {
                    final track = unmatchedTracks[index];
                    return Text(
                      '${index + 1}. ${track.title}\n${track.artists.join(', ')}',
                      style: const TextStyle(fontSize: 12),
                    );
                  },
                ),
              ),
              if (unmatchedTracks.length > 30)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Dan ${unmatchedTracks.length - 30} lagu lainnya.'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: unmatchedReport));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Daftar lagu yang terlewat disalin.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Salin daftar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _changePlaylistArtwork(Playlist playlist) async {
    if (_changingArtwork) return;
    setState(() => _changingArtwork = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null || !mounted) return;

      final documents = await getApplicationDocumentsDirectory();
      final coverDirectory = Directory('${documents.path}/musikku_playlist_covers');
      await coverDirectory.create(recursive: true);
      final safeId = playlist.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final pickedName = picked.name;
      final extension = pickedName.contains('.')
          ? '.${pickedName.split('.').last.toLowerCase()}'
          : '.jpg';
      final destination = File(
        '${coverDirectory.path}/${safeId}_${DateTime.now().millisecondsSinceEpoch}$extension',
      );
      await File(picked.path).copy(destination.path);
      if (!mounted) return;

      final oldPath = playlist.artworkPath;
      setState(() => playlist.artworkPath = destination.path);
      widget.onChanged();
      _deleteManagedArtwork(oldPath);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto cover playlist berhasil diganti.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Foto cover belum bisa disimpan: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _changingArtwork = false);
    }
  }

  Future<void> _removePlaylistArtwork(Playlist playlist) async {
    final oldPath = playlist.artworkPath;
    if (oldPath == null || oldPath.isEmpty) return;
    setState(() => playlist.artworkPath = null);
    widget.onChanged();
    _deleteManagedArtwork(oldPath);
  }

  void _deleteManagedArtwork(String? path) {
    if (path == null || path.isEmpty) return;
    unawaited(() async {
      try {
        final documents = await getApplicationDocumentsDirectory();
        final managedDirectory = '${documents.path}/musikku_playlist_covers/';
        if (path.startsWith(managedDirectory)) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      } catch (_) {
        // A stale cover file must never block a playlist edit.
      }
    }());
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final name = await showPlaylistNameDialog(
      context,
      title: 'Ubah nama playlist',
      initial: playlist.name,
      confirmLabel: 'Simpan',
    );
    if (!mounted || name == null || name == playlist.name) return;
    setState(() => playlist.name = name);
    widget.onChanged();
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus playlist?'),
        content: Text('Playlist "${playlist.name}" akan dihapus dari MusikKu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final oldArtworkPath = playlist.artworkPath;
    setState(() {
      widget.playlists.removeWhere((item) => item.id == playlist.id);
      if (_selectedPlaylistId == playlist.id) _selectedPlaylistId = null;
    });
    widget.onChanged();
    _deleteManagedArtwork(oldArtworkPath);
  }

  Future<void> _removeSong(Playlist playlist, YoutubeSearchResult song) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus dari playlist?'),
        content: Text('"${song.title}" akan dihapus dari "${playlist.name}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => playlist.songs.removeWhere((item) => item.videoId == song.videoId));
    widget.onChanged();
  }

  Future<void> _editPlaylistDetails(Playlist playlist) async {
    final noteController = TextEditingController(text: playlist.description);
    final folderController = TextEditingController(text: playlist.folderName);
    const colors = <Color>[
      Color(0xFF91D9CF), Color(0xFFB8B8EE), Color(0xFFFF9676),
      Color(0xFFE7BD67), Color(0xFFE58AAE), Color(0xFF8CB5E8),
    ];
    var selectedColor = Color(playlist.accentColorValue ?? colors.first.toARGB32());
    final result = await showDialog<({String description, String folder, int color})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Detail playlist'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: noteController, maxLines: 3, decoration: const InputDecoration(labelText: 'Catatan / deskripsi', hintText: 'Tambahkan cerita playlist ini')),
              const SizedBox(height: 12),
              TextField(controller: folderController, decoration: const InputDecoration(labelText: 'Folder', hintText: 'Contoh: Santai, Kerja, Perjalanan')),
              const SizedBox(height: 16),
              const Text('Warna playlist', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final color in colors)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setDialogState(() => selectedColor = color),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: selectedColor.toARGB32() == color.toARGB32() ? Theme.of(context).colorScheme.onSurface : Colors.transparent, width: 3)),
                      child: selectedColor.toARGB32() == color.toARGB32() ? const Icon(Icons.check_rounded, size: 17, color: Colors.black) : null,
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, (description: noteController.text.trim(), folder: folderController.text.trim().isEmpty ? 'Umum' : folderController.text.trim(), color: selectedColor.toARGB32())), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    noteController.dispose();
    folderController.dispose();
    if (result == null || !mounted) return;
    setState(() {
      playlist.description = result.description;
      playlist.folderName = result.folder;
      playlist.accentColorValue = result.color;
    });
    widget.onChanged();
  }

  Future<void> _mergePlaylist(Playlist source) async {
    final destinations = widget.playlists.where((item) => item.id != source.id).toList();
    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Buat playlist lain dulu untuk tujuan penggabungan.')));
      return;
    }
    final targetId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Gabungkan "${source.name}" ke'),
        children: [
          for (final target in destinations)
            SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, target.id), child: Row(children: [const Icon(Icons.queue_music_rounded), const SizedBox(width: 10), Expanded(child: Text('${target.name} · ${target.songs.length} lagu'))])),
        ],
      ),
    );
    if (targetId == null || !mounted) return;
    final target = destinations.firstWhere((item) => item.id == targetId);
    final ids = target.songs.map((song) => song.videoId).toSet();
    for (final song in source.songs) {
      if (song.videoId.isNotEmpty && ids.add(song.videoId)) target.songs.add(song);
    }
    final oldArtwork = source.artworkPath;
    setState(() {
      widget.playlists.removeWhere((item) => item.id == source.id);
      if (_selectedPlaylistId == source.id) _selectedPlaylistId = target.id;
    });
    widget.onChanged();
    _deleteManagedArtwork(oldArtwork);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playlist digabung ke "${target.name}".')));
  }

  Future<void> _removeSelectedSongs(Playlist playlist) async {
    if (_selectedSongIds.isEmpty) return;
    final count = _selectedSongIds.length;
    setState(() {
      playlist.songs.removeWhere((song) => _selectedSongIds.contains(song.videoId));
      _selectedSongIds.clear();
      _songSelectionMode = false;
    });
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count lagu dihapus dari playlist.')));
  }

  List<Playlist> get _sortedPlaylists {
    final result = List<Playlist>.from(widget.playlists);
    switch (_sortMode) {
      case _PlaylistSortMode.recent:
        break;
      case _PlaylistSortMode.name:
        result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _PlaylistSortMode.songs:
        result.sort((a, b) => b.songs.length.compareTo(a.songs.length));
        break;
      case _PlaylistSortMode.folder:
        result.sort((a, b) => a.folderName.toLowerCase().compareTo(b.folderName.toLowerCase()));
        break;
    }
    return result;
  }

  Future<void> _showAddSongsSheet(Playlist playlist) async {
    final seen = <String>{};
    final candidates = widget.availableSongs
        .where((song) => song.videoId.isNotEmpty &&
            !playlist.contains(song.videoId) &&
            seen.add(song.videoId))
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada lagu dari favorit, riwayat, atau daftar yang dimuat. Putar/cari lagu dulu, lalu coba lagi.')),
      );
      return;
    }

    final selectedIds = <String>{};
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.70,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: MusicGlassPanel(
                    padding: const EdgeInsets.all(14),
                    radius: 21,
                    child: Row(
                      children: [
                        const Expanded(
                          child: MusicSheetHeading(
                            icon: Icons.playlist_add_rounded,
                            title: 'Tambah lagu',
                            subtitle: 'Pilih lagu untuk koleksi ini.',
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${selectedIds.length}',
                            style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (context, index) {
                      final song = candidates[index];
                      final checked = selectedIds.contains(song.videoId);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (value) => setSheetState(() {
                          if (value == true) {
                            selectedIds.add(song.videoId);
                          } else {
                            selectedIds.remove(song.videoId);
                          }
                        }),
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: UnifiedArtwork(track: song, width: 48, height: 48, fit: BoxFit.cover),
                        ),
                        title: Text(song.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(song.channelTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Batal')),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => Navigator.pop(sheetContext, Set<String>.from(selectedIds)),
                          icon: const Icon(Icons.playlist_add_rounded),
                          label: Text('Tambah (${selectedIds.length})'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (!mounted || selected == null || selected.isEmpty) return;

    var added = 0;
    setState(() {
      for (final song in candidates) {
        if (selected.contains(song.videoId) && !playlist.contains(song.videoId)) {
          playlist.songs.add(song);
          added++;
        }
      }
    });
    if (added > 0) {
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$added lagu ditambahkan ke "${playlist.name}"')),
      );
    }
  }

  void _reorderSongs(Playlist playlist, int oldIndex, int newIndex) {
    final moved = playlist.moveSong(oldIndex, newIndex);
    if (!moved) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _playPlaylistAndReturn(Playlist playlist) async {
    try {
      // Let the parent update the active source/player before closing this route,
      // but do not keep the playlist page on screen while the native player loads.
      final playback = widget.onPlayPlaylist(playlist);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await playback;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagu belum bisa diputar. Coba lagi ya.')),
        );
      }
    }
  }

  Future<void> _playOfflinePlaylistAndReturn(Playlist playlist) async {
    final action = widget.onPlayOfflinePlaylist;
    if (action == null || playlist.offlineSongCount == 0) return;
    try {
      final playback = action(playlist);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await playback;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagu lokal belum bisa diputar. Periksa file dan izin musik perangkat.')),
        );
      }
    }
  }

  Future<void> _shufflePlaylistAndReturn(Playlist playlist) async {
    final action = widget.onShufflePlaylist;
    if (action == null || playlist.songs.isEmpty) return;
    try {
      final playback = action(playlist);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await playback;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playlist belum bisa diacak. Coba lagi ya.')),
        );
      }
    }
  }

  Future<void> _playSongAndReturn(Playlist playlist, YoutubeSearchResult song) async {
    try {
      final playback = widget.onPlaySong(playlist, song);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await playback;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lagu belum bisa diputar. Coba lagi ya.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _selectedPlaylist;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.94),
        leading: playlist == null
            ? null
            : IconButton(
                tooltip: 'Kembali ke playlist',
                onPressed: () => setState(() => _selectedPlaylistId = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(playlist?.name ?? 'Playlist MusikKu'),
        actions: [
          IconButton(
            tooltip: 'Download manager',
            onPressed: () => unawaited(_showDownloadManager()),
            icon: const Icon(Icons.downloading_rounded),
          ),
          if (playlist != null && playlist.songs.isNotEmpty)
            IconButton(
              tooltip: 'Download semua lagu',
              onPressed: !Platform.isAndroid
                  ? null
                  : () => unawaited(_downloadPlaylist(playlist)),
              icon: const Icon(Icons.download_for_offline_rounded),
            ),
          if (playlist != null && playlist.songs.isNotEmpty)
            IconButton(
              tooltip: 'Putar semua',
              onPressed: () => unawaited(_playPlaylistAndReturn(playlist)),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          if (playlist != null)
            IconButton(
              tooltip: 'Tambah lagu ke playlist',
              onPressed: () => unawaited(_showAddSongsSheet(playlist)),
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          if (playlist != null)
            IconButton(
              tooltip: _songSelectionMode ? 'Batalkan pilih lagu' : 'Pilih beberapa lagu',
              onPressed: () => setState(() {
                _songSelectionMode = !_songSelectionMode;
                _selectedSongIds.clear();
              }),
              icon: Icon(_songSelectionMode ? Icons.close_rounded : Icons.checklist_rounded),
            ),
          if (_songSelectionMode && playlist != null)
            IconButton(
              tooltip: 'Hapus ${_selectedSongIds.length} lagu terpilih',
              onPressed: _selectedSongIds.isEmpty ? null : () => unawaited(_removeSelectedSongs(playlist)),
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
          if (playlist == null && widget.playlists.length > 1)
            PopupMenuButton<_PlaylistSortMode>(
              tooltip: 'Urutkan playlist',
              initialValue: _sortMode,
              onSelected: (value) => setState(() => _sortMode = value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: _PlaylistSortMode.recent, child: Text('Urutan terbaru')),
                PopupMenuItem(value: _PlaylistSortMode.name, child: Text('Nama A–Z')),
                PopupMenuItem(value: _PlaylistSortMode.songs, child: Text('Jumlah lagu terbanyak')),
                PopupMenuItem(value: _PlaylistSortMode.folder, child: Text('Folder')),
              ],
            ),
          IconButton(
            tooltip: 'Playlist baru',
            onPressed: () => unawaited(_createPlaylist()),
            icon: const Icon(Icons.add_rounded),
          ),
          if (playlist != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'cover') unawaited(_changePlaylistArtwork(playlist));
                if (value == 'reset_cover') unawaited(_removePlaylistArtwork(playlist));
                if (value == 'rename') unawaited(_renamePlaylist(playlist));
                if (value == 'details') unawaited(_editPlaylistDetails(playlist));
                if (value == 'merge') unawaited(_mergePlaylist(playlist));
                if (value == 'delete') unawaited(_deletePlaylist(playlist));
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'cover', child: Text('Ganti foto cover')),
                if (playlist.artworkPath != null && playlist.artworkPath!.isNotEmpty)
                  const PopupMenuItem(value: 'reset_cover', child: Text('Pakai cover lagu pertama')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'details', child: Text('Catatan, folder & warna')) ,
                const PopupMenuItem(value: 'merge', child: Text('Gabungkan ke playlist lain')),
                const PopupMenuItem(value: 'rename', child: Text('Ubah nama')),
                const PopupMenuItem(value: 'delete', child: Text('Hapus playlist')),
              ],
            ),
        ],
      ),
      body: MusicBackdrop(
        child: Stack(
          children: [
            Positioned.fill(
              child: MusicPageEntrance(
                child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0.035, 0), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: playlist == null
                ? KeyedSubtree(key: const ValueKey<String>('playlist-library'), child: _buildPlaylistList(scheme))
                : KeyedSubtree(key: ValueKey<String>('playlist-${playlist.id}'), child: _buildPlaylistSongs(playlist, scheme)),
                ),
              ),
            ),
            if (widget.currentVideo != null &&
                widget.nativeState != null &&
                widget.onOpenCurrentPlayer != null &&
                widget.onMiniPlayPause != null &&
                widget.onMiniNext != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: MediaQuery.paddingOf(context).bottom + 66 + 18,
                child: MiniMusicPlayer(
                  video: widget.currentVideo!,
                  nativeState: widget.nativeState!,
                  onOpen: widget.onOpenCurrentPlayer!,
                  onPlayPause: widget.onMiniPlayPause!,
                  onNext: widget.onMiniNext!,
                ),
              ),
            Positioned(
              left: 14,
              right: 14,
              bottom: MediaQuery.paddingOf(context).bottom + 8,
              child: _PlaylistDock(onSelect: _selectMainTab),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistList(ColorScheme scheme) {
    const hero = FlowPageHero(
      icon: Icons.queue_music_rounded,
      eyebrow: 'YOUR MUSIC SPACE',
      title: 'Ruang playlist',
      subtitle: 'Susun soundtrack sendiri. Ganti artwork, atur urutan lagu, lalu putar sesuai mood.',
    );
    if (widget.playlists.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 184),
        children: [
          hero,
          const SizedBox(height: 18),
          MusicEmptyState(
            icon: Icons.library_music_rounded,
            title: 'Mulai dari playlist pertama',
            message: 'Buat ruang untuk lagu yang ingin kamu simpan bersama. Kamu bisa memilih cover sendiri dari galeri.',
            actionLabel: 'Buat playlist',
            onAction: () => unawaited(_createPlaylist()),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _spotifyImporting ? null : () => unawaited(_importSpotifyPlaylist()),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Impor dari Spotify'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 184),
      children: [
        hero,
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KOLEKSI PERSONAL', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text('${widget.playlists.length} playlist', style: TextStyle(color: scheme.onSurface, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.7)),
                ],
              ),
            ),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _spotifyImporting ? null : () => unawaited(_importSpotifyPlaylist()),
                  icon: const Icon(Icons.link_rounded, size: 17),
                  label: const Text('Spotify'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(_createPlaylist()),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Baru'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 13),
        for (final playlist in _sortedPlaylists) ...[
          _playlistPoster(playlist, scheme),
          const SizedBox(height: 9),
        ],
      ],
    );
  }

  Widget _playlistPoster(Playlist playlist, ColorScheme scheme) {
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _selectedPlaylistId = playlist.id),
        child: SizedBox(
          height: 112,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: SizedBox(
                    width: 94,
                    height: 94,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PlaylistArtwork(playlist: playlist, fit: BoxFit.cover, iconSize: 32),
                        Positioned(
                          right: 5,
                          bottom: 5,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(6)),
                            child: Text('${playlist.songs.length}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 14, height: 1.12, fontWeight: FontWeight.w900, letterSpacing: -0.25)),
                      const SizedBox(height: 6),
                      Text(
                        playlist.songs.isEmpty
                            ? 'Belum ada lagu'
                            : '${playlist.songs.length} lagu · ${playlist.offlineSongCount} tersedia offline · ${playlist.folderName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w600),
                      ),
                      if (playlist.description.trim().isNotEmpty) ...[const SizedBox(height: 3), Text(playlist.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9.5))],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.photo_camera_back_outlined, size: 13, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(playlist.artworkPath?.isNotEmpty == true ? 'Cover kustom' : 'Artwork otomatis', style: TextStyle(color: Color(playlist.accentColorValue ?? scheme.primary.toARGB32()), fontSize: 9.5, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Putar ${playlist.name}',
                  onPressed: playlist.songs.isEmpty ? null : () => unawaited(_playPlaylistAndReturn(playlist)),
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _playlistDetailArtwork(Playlist playlist, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: SizedBox(
                width: 116,
                height: 116,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PlaylistArtwork(playlist: playlist, fit: BoxFit.cover, iconSize: 42),
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.62),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _changingArtwork ? null : () => unawaited(_changePlaylistArtwork(playlist)),
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: _changingArtwork
                                ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('PLAYLIST PRIBADI', style: TextStyle(color: scheme.primary, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 1.15)),
                  const SizedBox(height: 7),
                  Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 21, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -0.65)),
                  const SizedBox(height: 7),
                  Text(
                    '${playlist.songs.length} lagu · ${playlist.offlineSongCount} tersedia offline · ${playlist.folderName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5, fontWeight: FontWeight.w600),
                  ),
                  if (playlist.description.trim().isNotEmpty) ...[const SizedBox(height: 4), Text(playlist.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10))],
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Icon(Icons.photo_camera_back_outlined, size: 14, color: scheme.primary),
                      const SizedBox(width: 5),
                      Text('Ubah foto cover', style: TextStyle(color: scheme.primary, fontSize: 9.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistActionRow(Playlist playlist, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: OutlinedButton(
              onPressed: playlist.songs.isEmpty || widget.onShufflePlaylist == null
                  ? null
                  : () => unawaited(_shufflePlaylistAndReturn(playlist)),
              style: OutlinedButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                side: BorderSide(color: scheme.primary.withValues(alpha: 0.42)),
                foregroundColor: scheme.primary,
              ),
              child: const Icon(Icons.shuffle_rounded, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: playlist.songs.isEmpty
                    ? null
                    : () => unawaited(_playPlaylistAndReturn(playlist)),
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 24),
                label: const Text('Play', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 52,
            height: 52,
            child: IconButton.filledTonal(
              tooltip: 'Tambah lagu',
              onPressed: () => unawaited(_showAddSongsSheet(playlist)),
              style: IconButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor: scheme.secondaryContainer.withValues(alpha: 0.78),
                foregroundColor: scheme.onSecondaryContainer,
              ),
              icon: const Icon(Icons.add_rounded, size: 25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _downloadSongButton(YoutubeSearchResult song, ColorScheme scheme) {
    return AnimatedBuilder(
      animation: _downloads,
      builder: (context, _) {
        final item = _downloads.itemFor(song.videoId);
        if (song.isOfflineDownloaded ||
            item?.status == OfflineDownloadStatus.completed) {
          return IconButton(
            tooltip: 'Tersedia offline',
            onPressed: () => unawaited(_showDownloadManager()),
            icon: Icon(Icons.offline_pin_rounded, color: scheme.primary, size: 21),
          );
        }
        if (item?.status == OfflineDownloadStatus.downloading) {
          return SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: item!.totalBytes > 0 ? item.progress : null,
                ),
              ),
            ),
          );
        }
        if (item?.status == OfflineDownloadStatus.queued) {
          return IconButton(
            tooltip: 'Menunggu antrean download',
            onPressed: () => unawaited(_showDownloadManager()),
            icon: Icon(Icons.more_time_rounded, color: scheme.onSurfaceVariant, size: 20),
          );
        }
        final isPaused = item?.status == OfflineDownloadStatus.paused;
        final isFailed = item?.status == OfflineDownloadStatus.failed;
        return IconButton(
          tooltip: isPaused || isFailed
              ? 'Lanjutkan download'
              : 'Download untuk offline',
          onPressed: !Platform.isAndroid || song.isLocal
              ? null
              : isPaused && _downloads.isActiveDownload(song.videoId)
                  ? () => unawaited(_downloads.resumeAll())
                  : () => unawaited(_downloadSong(song)),
          icon: Icon(
            isPaused || isFailed
                ? Icons.refresh_rounded
                : Icons.download_for_offline_outlined,
            color: scheme.onSurfaceVariant,
            size: 21,
          ),
        );
      },
    );
  }

  Widget _buildPlaylistSongs(Playlist playlist, ColorScheme scheme) {
    return Column(
      children: [
        _playlistDetailArtwork(playlist, scheme),
        _playlistActionRow(playlist, scheme),
        if (playlist.offlineSongCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: OutlinedButton.icon(
              onPressed: widget.onPlayOfflinePlaylist == null
                  ? null
                  : () => unawaited(_playOfflinePlaylistAndReturn(playlist)),
              icon: const Icon(Icons.offline_pin_rounded, size: 18),
              label: Text('Putar offline · ${playlist.offlineSongCount} lagu'),
            ),
          ),
        if (playlist.songs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: Text(
              playlist.offlineSongCount == 0
                  ? 'Lagu playlist belum diunduh. Tekan ikon download pada lagu atau Download semua untuk menyiapkan pemutaran offline.'
                  : 'Mode offline memutar ${playlist.offlineSongCount} lagu lokal/unduhan yang tersedia. Lagu lain akan dilewati.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(23, 2, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Daftar lagu',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: scheme.onSurface),
                ),
              ),
              Text(
                '${playlist.songs.length} lagu',
                style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Expanded(
          child: playlist.songs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_note_rounded, size: 44, color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
                        const SizedBox(height: 9),
                        const Text('Playlist masih kosong', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        Text(
                          'Tambahkan lagu dari favorit, riwayat, atau hasil pencarian.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 184),
                  itemCount: playlist.songs.length,
                  onReorderItem: (oldIndex, newIndex) => _reorderSongs(playlist, oldIndex, newIndex),
                  itemBuilder: (context, index) {
                    final song = playlist.songs[index];
                    return ValueListenableBuilder<PlayerUiState>(
                      key: ValueKey<String>('${playlist.id}:$index:${song.videoId}'),
                      valueListenable: widget.playerUiState,
                      builder: (context, playerState, _) {
                        final current = playerState.video;
                        final isCurrent = current?.videoId == song.videoId ||
                            current?.localMediaId == 'offline_${song.videoId}';
                        return Material(
                          color: isCurrent ? scheme.primaryContainer.withValues(alpha: 0.22) : Colors.transparent,
                          child: InkWell(
                            onTap: _songSelectionMode ? () => setState(() { _selectedSongIds.contains(song.videoId) ? _selectedSongIds.remove(song.videoId) : _selectedSongIds.add(song.videoId); }) : () => unawaited(_playSongAndReturn(playlist, song)),
                            onLongPress: () => setState(() { _songSelectionMode = true; _selectedSongIds.add(song.videoId); }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.42))),
                              ),
                              child: Row(
                                children: [
                                  if (_songSelectionMode)
                                    Checkbox(
                                      value: _selectedSongIds.contains(song.videoId),
                                      onChanged: (selected) => setState(() { if (selected == true) { _selectedSongIds.add(song.videoId); } else { _selectedSongIds.remove(song.videoId); } }),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          UnifiedArtwork(track: song, width: 52, height: 52, fit: BoxFit.cover),
                                          if (isCurrent)
                                            ColoredBox(
                                              color: Colors.black.withValues(alpha: 0.34),
                                              child: const Icon(Icons.equalizer_rounded, color: Colors.white, size: 24),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          song.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 14, fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700, color: isCurrent ? scheme.primary : scheme.onSurface),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          song.channelTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCurrent)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 2),
                                      child: Icon(Icons.volume_up_rounded, color: scheme.primary, size: 18),
                                    ),
                                  _downloadSongButton(song, scheme),
                                  PopupMenuButton<String>(
                                    tooltip: 'Opsi lagu',
                                    onSelected: (value) {
                                      if (value == 'remove') unawaited(_removeSong(playlist, song));
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'remove', child: Text('Hapus dari playlist')),
                                    ],
                                    icon: Icon(Icons.more_vert_rounded, color: scheme.onSurfaceVariant),
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: Icon(Icons.drag_handle_rounded, color: scheme.onSurfaceVariant.withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

}

enum _PlaylistSortMode { recent, name, songs, folder }

class _PlaylistDock extends StatelessWidget {
  const _PlaylistDock({required this.onSelect});

  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget destination(int index, String label, IconData icon, IconData activeIcon) {
      final selected = index == 3;
      return Expanded(
        child: InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? activeIcon : icon, size: 20, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(height: 3),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, fontWeight: selected ? FontWeight.w900 : FontWeight.w600, color: selected ? scheme.primary : scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      height: 60,
      decoration: BoxDecoration(color: scheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(15), border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7))),
      child: Row(children: [
        destination(0, 'Beranda', Icons.home_outlined, Icons.home_rounded),
        destination(1, 'Jelajah', Icons.explore_outlined, Icons.explore_rounded),
        destination(2, 'Radio', Icons.radio_outlined, Icons.radio_rounded),
        destination(3, 'Koleksi', Icons.library_music_outlined, Icons.library_music_rounded),
      ]),
    );
  }
}
