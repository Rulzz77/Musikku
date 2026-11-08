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
import '../services/audio_download_estimator.dart';
import '../services/offline_download_service.dart';
import '../services/spotify_playlist_import_service.dart';
import '../services/spotify_youtube_track_matcher.dart';
import '../services/youtube_music_policy.dart';
import '../widgets/playlist_widgets.dart' show showPlaylistNameDialog;
import '../widgets/unified_artwork.dart';
import '../widgets/playlist_artwork.dart';
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
    this.searchSpotifyFast,
    this.enrichSearchResults,
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

  /// Full Spotify fallback search. Used only when the cheap first pass does
  /// not find a corroborated source.
  final Future<List<YoutubeSearchResult>> Function(String query)? searchSongs;

  /// One-page relevance search used for the fast first pass of Spotify import.
  final Future<List<YoutubeSearchResult>> Function(String query)?
  searchSpotifyFast;
  final Future<List<YoutubeSearchResult>> Function(
    List<YoutubeSearchResult> candidates,
  )?
  enrichSearchResults;
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
        const SnackBar(
          content: Text(
            'Download playlist saat ini hanya tersedia di Android.',
          ),
        ),
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
        const SnackBar(
          content: Text('Semua lagu playlist sudah tersedia offline.'),
        ),
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
    final hasEnoughEstimatedSpace =
        !estimate.hasEstimate ||
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Antrean download gagal: $error')));
    }
  }

  Widget _downloadEstimateRow(String label, String value, ColorScheme scheme) {
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
                            Text(
                              'DOWNLOAD MANAGER',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Unduhan offline',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatBytes(_downloads.totalDownloadedBytes),
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _downloadSummaryCard(
                          context,
                          icon: Icons.downloading_rounded,
                          label: 'Aktif',
                          value: items
                              .where(
                                (item) =>
                                    item.status ==
                                        OfflineDownloadStatus.queued ||
                                    item.status ==
                                        OfflineDownloadStatus.downloading,
                              )
                              .length
                              .toString(),
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _downloadSummaryCard(
                          context,
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Offline',
                          value: items
                              .where(
                                (item) =>
                                    item.status ==
                                    OfflineDownloadStatus.completed,
                              )
                              .length
                              .toString(),
                          color: scheme.tertiary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _downloadSummaryCard(
                          context,
                          icon: Icons.error_outline_rounded,
                          label: 'Gagal',
                          value: items
                              .where(
                                (item) =>
                                    item.status == OfflineDownloadStatus.failed,
                              )
                              .length
                              .toString(),
                          color: scheme.error,
                        ),
                      ),
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
                          icon: Icon(
                            _downloads.isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                          ),
                          label: Text(
                            _downloads.isPaused ? 'Lanjutkan' : 'Jeda semua',
                          ),
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
                      ? Center(
                          child: Text(
                            'Belum ada unduhan.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: items.length,
                          separatorBuilder: (context, separatorIndex) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final completed =
                                item.status == OfflineDownloadStatus.completed;
                            final active =
                                item.status ==
                                OfflineDownloadStatus.downloading;
                            final failed =
                                item.status == OfflineDownloadStatus.failed;
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
                                        child: SizedBox(
                                          width: 42,
                                          height: 42,
                                          child: UnifiedArtwork(
                                            track: item.song,
                                            width: 42,
                                            height: 42,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.song.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              completed
                                                  ? 'Selesai · ${_formatBytes(item.downloadedBytes)}'
                                                  : failed
                                                  ? 'Gagal · ${item.errorMessage}'
                                                  : active
                                                  ? 'Mengunduh · ${_formatBytes(item.downloadedBytes)}${item.totalBytes > 0 ? ' / ${_formatBytes(item.totalBytes)}' : ''}'
                                                  : item.status ==
                                                        OfflineDownloadStatus
                                                            .queued
                                                  ? 'Menunggu antrean'
                                                  : 'Dijeda · ${_formatBytes(item.downloadedBytes)}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: scheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if ((failed ||
                                              item.status ==
                                                  OfflineDownloadStatus
                                                      .paused) &&
                                          !_downloads.isActiveDownload(
                                            item.song.videoId,
                                          ))
                                        IconButton(
                                          tooltip: 'Coba lagi',
                                          onPressed: () => unawaited(
                                            _downloads.retry(item.song.videoId),
                                          ),
                                          icon: const Icon(
                                            Icons.refresh_rounded,
                                          ),
                                        ),
                                      if (completed ||
                                          failed ||
                                          item.status ==
                                              OfflineDownloadStatus.queued ||
                                          (item.status ==
                                                  OfflineDownloadStatus
                                                      .paused &&
                                              !_downloads.isActiveDownload(
                                                item.song.videoId,
                                              )))
                                        IconButton(
                                          tooltip: 'Hapus dari manager',
                                          onPressed: () async {
                                            try {
                                              await _downloads.delete(
                                                item.song.videoId,
                                              );
                                            } catch (error) {
                                              if (mounted) {
                                                ScaffoldMessenger.of(
                                                  this.context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text('$error'),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                        ),
                                      if (active)
                                        const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (!completed)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: LinearProgressIndicator(
                                        value: item.totalBytes > 0
                                            ? item.progress
                                            : null,
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

  Widget _downloadSummaryCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final fastSearchSongs = widget.searchSpotifyFast ?? searchSongs;
    if (searchSongs == null || fastSearchSongs == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pencarian YouTube belum siap untuk impor.'),
        ),
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
              onSubmitted: (value) =>
                  Navigator.pop(dialogContext, value.trim()),
              decoration: InputDecoration(
                hintText: 'https://open.spotify.com/playlist/...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Tempel link',
                  icon: const Icon(Icons.content_paste_rounded),
                  onPressed: () async {
                    final clipboard = await Clipboard.getData(
                      Clipboard.kTextPlain,
                    );
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
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
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

      final preview = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            snapshot.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
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
                      ? '≥${snapshot.tracks.length} lagu terbaca dari embed publik. Ini jumlah minimum yang terlihat, bukan total playlist. MusikKu akan memproses otomatis semua lagu yang tersedia.'
                      : snapshot.mayBePartial
                      ? '${snapshot.tracks.length} lagu terbaca dari embed publik. Jumlah total playlist belum bisa dipastikan.'
                      : '${snapshot.tracks.length} lagu terbaca dari halaman embed publik Spotify.',
                ),
                if (snapshot.mayBePartial) ...[
                  const SizedBox(height: 8),
                  Text(
                    snapshot.knownMissingTrackCount > 0
                        ? 'Spotify hanya menyediakan ${snapshot.tracks.length} dari ${snapshot.totalTrackCount} lagu pada halaman publik ini. MusikKu akan mengimpor otomatis semua lagu yang tersedia; sisa ${snapshot.knownMissingTrackCount} lagu tidak dikirim oleh embed. Tidak perlu memasukkan lagu satu per satu.'
                        : snapshot.tracks.length == 100
                        ? 'Embed publik menampilkan 100 baris. Itu bisa merupakan batas tampilan, bukan berarti total playlist tepat 100. MusikKu mengimpor semua lagu yang diterima; baris setelahnya tidak tersedia dari link publik ini.'
                        : snapshot.tracks.length > 100
                        ? 'Embed publik mengirim ${snapshot.tracks.length} baris. Semua baris yang tersedia akan diimpor otomatis; jumlah total playlist belum diketahui.'
                        : 'Embed publik mungkin hanya menampilkan sebagian daftar. MusikKu akan mengimpor semua lagu yang tersedia tanpa meminta kamu memasukkan judul satu per satu.',
                    style: const TextStyle(color: Colors.orange),
                  ),
                ],
                const SizedBox(height: 12),
                ...snapshot.tracks
                    .take(5)
                    .map(
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
                    child: Text(
                      'dan ${snapshot.tracks.length - 5} lagu lainnya…',
                    ),
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
      if (!mounted || preview != true) return;
      final tracksToImport = snapshot.tracks;

      final progressText = ValueNotifier<String>('Menyiapkan pencarian lagu…');
      final progress = ValueNotifier<double>(0);
      final trackStatuses = ValueNotifier<List<String>>(
        List<String>.filled(tracksToImport.length, 'Menunggu'),
      );
      void updateTrackStatus(int index, String status) {
        final next = List<String>.from(trackStatuses.value);
        if (index < 0 || index >= next.length) return;
        next[index] = status;
        trackStatuses.value = next;
      }

      BuildContext? progressDialogContext;
      final progressDialog = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          progressDialogContext = dialogContext;
          final scheme = Theme.of(dialogContext).colorScheme;
          return PopScope(
            canPop: false,
            child: Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              child: SizedBox(
                width: 520,
                height: MediaQuery.sizeOf(dialogContext).height * 0.70,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(
                              Icons.library_music_rounded,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Mengimpor playlist',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '${tracksToImport.length} lagu · pencocokan YouTube Music',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<String>(
                        valueListenable: progressText,
                        builder: (context, value, child) => Text(
                          value,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<double>(
                        valueListenable: progress,
                        builder: (context, value, child) => Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: LinearProgressIndicator(
                                value: value,
                                minHeight: 7,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${(value * 100).round()}%',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _importStatusLegend(scheme.primary, 'Ditemukan'),
                          const SizedBox(width: 12),
                          _importStatusLegend(scheme.tertiary, 'Alternatif'),
                          const SizedBox(width: 12),
                          _importStatusLegend(scheme.error, 'Belum cocok'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ValueListenableBuilder<List<String>>(
                          valueListenable: trackStatuses,
                          builder: (context, statuses, child) =>
                              ListView.separated(
                                itemCount: tracksToImport.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 1,
                                  color: scheme.outlineVariant.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                itemBuilder: (context, index) {
                                  final track = tracksToImport[index];
                                  final status = statuses[index];
                                  final isFound = status == 'Ditemukan';
                                  final isAlternative = status == 'Alternatif';
                                  final isSearching = status == 'Mencari';
                                  final isMissing = status == 'Belum cocok';
                                  final color = isFound
                                      ? scheme.primary
                                      : isAlternative
                                      ? scheme.tertiary
                                      : isMissing
                                      ? scheme.error
                                      : scheme.onSurfaceVariant;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 1,
                                    ),
                                    leading: SizedBox(
                                      width: 34,
                                      height: 34,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Icon(
                                          isSearching
                                              ? Icons.more_horiz_rounded
                                              : isFound
                                              ? Icons.check_rounded
                                              : isAlternative
                                              ? Icons.library_music_rounded
                                              : isMissing
                                              ? Icons.close_rounded
                                              : Icons.music_note_rounded,
                                          color: color,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      track.artists.join(', '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    trailing: Text(
                                      status,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: color,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  );
                                },
                              ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Versi original diprioritaskan. Versi alternatif ditandai terpisah dan lagu yang belum cocok tidak diganti diam-diam.',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
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

      Future<YoutubeSearchResult?> resolveSpotifyTrack(
        SpotifyPlaylistTrack track,
      ) async {
        try {
          final queries = SpotifyYoutubeTrackMatcher.buildSearchQueries(track);
          final fastQueries = widget.searchSpotifyFast != null
              ? SpotifyYoutubeTrackMatcher.buildFastSearchQueries(track)
              : queries.take(1).toList(growable: false);
          if (queries.isEmpty || fastQueries.isEmpty) {
            debugPrint(
              'SPOTIFY IMPORT SKIPPED EMPTY SEARCH TITLE: ${track.title}',
            );
            return null;
          }

          final candidatesById = <String, YoutubeSearchResult>{};
          var fastQueryCount = 0;
          var deepFallbackUsed = false;
          var metadataLookupCount = 0;

          void mergeCandidates(
            Iterable<YoutubeSearchResult> results, {
            bool replaceExisting = false,
          }) {
            for (final result in results) {
              if (result.videoId.isEmpty) continue;
              if (replaceExisting ||
                  !candidatesById.containsKey(result.videoId)) {
                candidatesById[result.videoId] = result;
              }
            }
          }

          bool hasConfidentMatch() =>
              SpotifyYoutubeTrackMatcher.hasHighConfidenceMatch(
                track,
                candidatesById.values.toList(growable: false),
              );

          // Stage 1: query the canonical artist and its punctuation-free alias
          // together. This catches names such as `NDX A.K.A.` / `NDX AKA` while
          // keeping the first pass to at most two simultaneous requests.
          final primaryQueries = fastQueries.take(2).toList(growable: false);
          fastQueryCount += primaryQueries.length;
          final primaryResults = await Future.wait(
            primaryQueries.map((query) async {
              try {
                return await fastSearchSongs(query);
              } catch (error) {
                debugPrint(
                  'SPOTIFY FAST SEARCH FAILED [${track.title}] '
                  '"$query": $error',
                );
                return const <YoutubeSearchResult>[];
              }
            }),
          );
          for (final results in primaryResults) {
            mergeCandidates(results);
          }

          // Do not stop at a popular/relevant result. Run any remaining fast
          // collaborator/title-only query unless a verified artist-owned
          // original is already present. Label/Topic credits are compared
          // together before the importer decides whether deep fallback is
          // needed, so a cover cannot short-circuit the original search.
          if (!SpotifyYoutubeTrackMatcher.hasPreferredOfficialMatch(
            track,
            candidatesById.values.toList(growable: false),
          )) {
            for (final query in fastQueries.skip(2)) {
              fastQueryCount++;
              try {
                mergeCandidates(await fastSearchSongs(query));
              } catch (error) {
                debugPrint(
                  'SPOTIFY FAST FALLBACK FAILED [${track.title}] '
                  '"$query": $error',
                );
              }
              if (SpotifyYoutubeTrackMatcher.hasPreferredOfficialMatch(
                track,
                candidatesById.values.toList(growable: false),
              )) {
                break;
              }
            }
          }

          // Stage 2: only unresolved/low-confidence tracks pay for the deeper
          // search (extra relevance pages + popularity fallback). Reuse the
          // most focused artist/title query; do not repeat every query variant.
          if (!hasConfidentMatch() && widget.searchSpotifyFast != null) {
            deepFallbackUsed = true;
            final deepQueries = <String>{
              queries.first,
              ...SpotifyYoutubeTrackMatcher.buildTitleOnlyFallbackQueries(
                track,
              ),
              ...SpotifyYoutubeTrackMatcher.buildArtistOnlyFallbackQueries(
                track,
              ),
            };
            for (final deepQuery in deepQueries) {
              if (deepQuery.trim().isEmpty) continue;
              try {
                mergeCandidates(await searchSongs(deepQuery));
              } catch (error) {
                debugPrint(
                  'SPOTIFY DEEP FALLBACK FAILED [${track.title}] '
                  '"$deepQuery": $error',
                );
              }
              // The artist-only result pool is broad; stop after a corroborated
              // original is found, while cover candidates never stop the search.
              if (hasConfidentMatch()) break;
            }
          }

          // Stage 3: structured MusicData is expensive. Only inspect a tiny
          // shortlist when the search candidates still lack a high-confidence
          // match. Cache hits are cheap; uncached detail requests are capped.
          if (!hasConfidentMatch() && widget.enrichSearchResults != null) {
            final allCandidates = candidatesById.values.toList(growable: false);
            final detailCandidates =
                SpotifyYoutubeTrackMatcher.metadataLookupCandidates(
                  track,
                  allCandidates,
                  limit: 3,
                );
            if (detailCandidates.isNotEmpty) {
              metadataLookupCount = detailCandidates.length;
              try {
                final enriched = await widget.enrichSearchResults!(
                  detailCandidates,
                );
                // Enrichment returns the same video IDs with structured
                // MusicData/artist/duration fields filled in. Replace the
                // lightweight search entries; putIfAbsent here silently threw
                // away every enriched result and made the matcher blind to it.
                mergeCandidates(enriched, replaceExisting: true);
              } catch (detailError) {
                debugPrint(
                  'SPOTIFY MUSIC METADATA LOOKUP FAILED '
                  '[${track.title}]: $detailError',
                );
              }
            }
          }

          final allCandidates = candidatesById.values.toList(growable: false);
          final match = SpotifyYoutubeTrackMatcher.bestMatch(
            track,
            allCandidates,
          );
          final coverCandidates = allCandidates
              .where(YoutubeMusicPolicy.isExplicitCoverVersion)
              .length;
          debugPrint(
            'SPOTIFY IMPORT MATCH [${track.title} - ${track.primaryArtist}]: '
            'fastQueries=$fastQueryCount, deep=$deepFallbackUsed, '
            'metadataLookups=$metadataLookupCount, candidates=${allCandidates.length}, '
            'covers=$coverCandidates, '
            'metadata=${allCandidates.where((item) => item.musicDataTitle.isNotEmpty && item.musicDataArtist.isNotEmpty).length}, '
            'selected=${match?.videoId ?? 'NONE'}',
          );
          if (match == null && allCandidates.isNotEmpty) {
            final diagnosticCandidates = allCandidates
                .take(12)
                .map((item) {
                  final duration =
                      item.durationSeconds?.round().toString() ?? '?';
                  final views = item.viewCount?.toString() ?? '?';
                  return '${item.title} '
                      '[${item.channelTitle}; ${duration}s; $views views]';
                })
                .join(' || ');
            debugPrint(
              'SPOTIFY IMPORT UNMATCHED CANDIDATES [${track.title}]: '
              '$diagnosticCandidates',
            );
          }
          return match == null
              ? null
              : SpotifyYoutubeTrackMatcher.applySpotifyMetadata(track, match);
        } catch (error) {
          debugPrint('SPOTIFY IMPORT SEARCH FAILED [${track.title}]: $error');
          return null;
        }
      }

      // Identical Spotify tracks can appear more than once in a playlist.
      // Resolve each unique identity once, then reuse the same video for every
      // original occurrence while preserving the playlist's order and repeats.
      final matchFutures = <String, Future<YoutubeSearchResult?>>{};
      String trackIdentity(SpotifyPlaylistTrack track) {
        final spotifyId = track.spotifyTrackId.trim();
        if (spotifyId.isNotEmpty) return 'spotify:$spotifyId';
        return '${track.title.toLowerCase().trim()}|'
            '${track.artists.map((artist) => artist.toLowerCase().trim()).join('|')}|'
            '${track.durationMs ?? ''}';
      }

      try {
        // Four tracks can make progress concurrently. The staged strategy
        // ensures most tracks issue only one inexpensive network search.
        const batchSize = 4;
        for (var start = 0; start < tracksToImport.length; start += batchSize) {
          final end = (start + batchSize < tracksToImport.length)
              ? start + batchSize
              : tracksToImport.length;
          progressText.value =
              'Mencocokkan lagu ${start + 1}–$end dari ${tracksToImport.length}…';
          final indexes = List<int>.generate(
            end - start,
            (offset) => start + offset,
          );
          for (final index in indexes) {
            updateTrackStatus(index, 'Mencari');
          }
          final batch = await Future.wait(
            indexes.map((index) {
              final track = tracksToImport[index];
              final key = trackIdentity(track);
              return matchFutures.putIfAbsent(
                key,
                () => resolveSpotifyTrack(track),
              );
            }),
          );
          for (var offset = 0; offset < indexes.length; offset++) {
            final index = indexes[offset];
            final match = batch[offset];
            resolved[index] = match;
            updateTrackStatus(
              index,
              match == null
                  ? 'Belum cocok'
                  : YoutubeMusicPolicy.isExplicitCoverVersion(match)
                  ? 'Alternatif'
                  : 'Ditemukan',
            );
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
        trackStatuses.dispose();
      }

      if (!mounted) return;
      // Preserve every resolved Spotify occurrence, including intentional
      // repeats of the same song. A playlist is an ordered sequence, not a
      // set; duplicate entries are valid Spotify playlist content.
      final importedSongs = resolved.whereType<YoutubeSearchResult>().toList(
        growable: true,
      );

      final unmatchedTracks = <SpotifyPlaylistTrack>[
        for (var index = 0; index < tracksToImport.length; index++)
          if (resolved[index] == null) tracksToImport[index],
      ];
      if (importedSongs.isEmpty) {
        await _showSpotifyUnmatchedReport(
          unmatchedTracks,
          summary:
              'Metadata ${tracksToImport.length} lagu terbaca, tetapi tidak ada pasangan YouTube Music yang cukup cocok. Playlist tidak dibuat.',
        );
        return;
      }

      final unmatchedCount = unmatchedTracks.length;
      final playlist = Playlist(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: snapshot.title,
        description:
            'Diimpor dari playlist Spotify publik · ${snapshot.sourceUrl}',
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
              ? '${snapshot.knownMissingTrackCount} lagu tidak disediakan oleh embed publik Spotify'
              : 'jumlah asli belum diketahui; ${snapshot.tracks.length} lagu yang terlihat telah diproses',
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

  Widget _importStatusLegend(Color color, String label) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
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
                  separatorBuilder: (context, index) =>
                      const Divider(height: 8),
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
                  child: Text(
                    'Dan ${unmatchedTracks.length - 30} lagu lainnya.',
                  ),
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
                  const SnackBar(
                    content: Text('Daftar lagu yang terlewat disalin.'),
                  ),
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
      final coverDirectory = Directory(
        '${documents.path}/musikku_playlist_covers',
      );
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
    setState(
      () => playlist.songs.removeWhere((item) => item.videoId == song.videoId),
    );
    widget.onChanged();
  }

  Future<void> _editPlaylistDetails(Playlist playlist) async {
    final noteController = TextEditingController(text: playlist.description);
    final folderController = TextEditingController(text: playlist.folderName);
    const colors = <Color>[
      Color(0xFF91D9CF),
      Color(0xFFB8B8EE),
      Color(0xFFFF9676),
      Color(0xFFE7BD67),
      Color(0xFFE58AAE),
      Color(0xFF8CB5E8),
    ];
    var selectedColor = Color(
      playlist.accentColorValue ?? colors.first.toARGB32(),
    );
    final result =
        await showDialog<({String description, String folder, int color})>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Detail playlist'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Catatan / deskripsi',
                        hintText: 'Tambahkan cerita playlist ini',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: folderController,
                      decoration: const InputDecoration(
                        labelText: 'Folder',
                        hintText: 'Contoh: Santai, Kerja, Perjalanan',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Warna playlist',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final color in colors)
                          InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () =>
                                setDialogState(() => selectedColor = color),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color:
                                      selectedColor.toARGB32() ==
                                          color.toARGB32()
                                      ? Theme.of(context).colorScheme.onSurface
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child:
                                  selectedColor.toARGB32() == color.toARGB32()
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 17,
                                      color: Colors.black,
                                    )
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, (
                    description: noteController.text.trim(),
                    folder: folderController.text.trim().isEmpty
                        ? 'Umum'
                        : folderController.text.trim(),
                    color: selectedColor.toARGB32(),
                  )),
                  child: const Text('Simpan'),
                ),
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
    final destinations = widget.playlists
        .where((item) => item.id != source.id)
        .toList();
    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buat playlist lain dulu untuk tujuan penggabungan.'),
        ),
      );
      return;
    }
    final targetId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Gabungkan "${source.name}" ke'),
        children: [
          for (final target in destinations)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, target.id),
              child: Row(
                children: [
                  const Icon(Icons.queue_music_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${target.name} · ${target.songs.length} lagu'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (targetId == null || !mounted) return;
    final target = destinations.firstWhere((item) => item.id == targetId);
    for (final song in source.songs) {
      if (song.videoId.isNotEmpty && !target.containsTrack(song)) {
        target.songs.add(song);
      }
    }
    final oldArtwork = source.artworkPath;
    setState(() {
      widget.playlists.removeWhere((item) => item.id == source.id);
      if (_selectedPlaylistId == source.id) _selectedPlaylistId = target.id;
    });
    widget.onChanged();
    _deleteManagedArtwork(oldArtwork);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Playlist digabung ke "${target.name}".')),
    );
  }

  Future<void> _removeSelectedSongs(Playlist playlist) async {
    if (_selectedSongIds.isEmpty) return;
    final count = _selectedSongIds.length;
    setState(() {
      playlist.songs.removeWhere(
        (song) => _selectedSongIds.contains(song.videoId),
      );
      _selectedSongIds.clear();
      _songSelectionMode = false;
    });
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count lagu dihapus dari playlist.')),
    );
  }

  List<Playlist> get _sortedPlaylists {
    final result = List<Playlist>.from(widget.playlists);
    switch (_sortMode) {
      case _PlaylistSortMode.recent:
        break;
      case _PlaylistSortMode.name:
        result.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case _PlaylistSortMode.songs:
        result.sort((a, b) => b.songs.length.compareTo(a.songs.length));
        break;
      case _PlaylistSortMode.folder:
        result.sort(
          (a, b) =>
              a.folderName.toLowerCase().compareTo(b.folderName.toLowerCase()),
        );
        break;
    }
    return result;
  }

  Future<void> _showAddSongsSheet(Playlist playlist) async {
    final seen = <String>{};
    final candidates = widget.availableSongs
        .where(
          (song) =>
              song.videoId.isNotEmpty &&
              !playlist.containsTrack(song) &&
              seen.add(song.videoId),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Belum ada lagu dari favorit, riwayat, atau daftar yang dimuat. Putar/cari lagu dulu, lalu coba lagi.',
          ),
        ),
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
                          duration: MediaQuery.of(context).disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
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
                          child: UnifiedArtwork(
                            track: song,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          song.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          song.channelTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                        TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: const Text('Batal'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: selectedIds.isEmpty
                              ? null
                              : () => Navigator.pop(
                                  sheetContext,
                                  Set<String>.from(selectedIds),
                                ),
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
        if (selected.contains(song.videoId) && !playlist.containsTrack(song)) {
          playlist.songs.add(song);
          added++;
        }
      }
    });
    if (added > 0) {
      widget.onChanged();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$added lagu ditambahkan ke "${playlist.name}"'),
        ),
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
          const SnackBar(
            content: Text('Lagu belum bisa diputar. Coba lagi ya.'),
          ),
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
          const SnackBar(
            content: Text(
              'Lagu lokal belum bisa diputar. Periksa file dan izin musik perangkat.',
            ),
          ),
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
          const SnackBar(
            content: Text('Playlist belum bisa diacak. Coba lagi ya.'),
          ),
        );
      }
    }
  }

  Future<void> _playSongAndReturn(
    Playlist playlist,
    YoutubeSearchResult song,
  ) async {
    try {
      final playback = widget.onPlaySong(playlist, song);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await playback;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lagu belum bisa diputar. Coba lagi ya.'),
          ),
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
        centerTitle: false,
        toolbarHeight: 70,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor
            .withValues(alpha: 0.82),
        leading: playlist == null
            ? null
            : IconButton(
                tooltip: 'Kembali ke playlist',
                onPressed: () => setState(() => _selectedPlaylistId = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(
          playlist?.name ?? 'Koleksi Playlist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.55,
          ),
        ),
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
              tooltip: _songSelectionMode
                  ? 'Batalkan pilih lagu'
                  : 'Pilih beberapa lagu',
              onPressed: () => setState(() {
                _songSelectionMode = !_songSelectionMode;
                _selectedSongIds.clear();
              }),
              icon: Icon(
                _songSelectionMode
                    ? Icons.close_rounded
                    : Icons.checklist_rounded,
              ),
            ),
          if (_songSelectionMode && playlist != null)
            IconButton(
              tooltip: 'Hapus ${_selectedSongIds.length} lagu terpilih',
              onPressed: _selectedSongIds.isEmpty
                  ? null
                  : () => unawaited(_removeSelectedSongs(playlist)),
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
          if (playlist == null && widget.playlists.length > 1)
            PopupMenuButton<_PlaylistSortMode>(
              tooltip: 'Urutkan playlist',
              initialValue: _sortMode,
              onSelected: (value) => setState(() => _sortMode = value),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _PlaylistSortMode.recent,
                  child: Text('Urutan terbaru'),
                ),
                PopupMenuItem(
                  value: _PlaylistSortMode.name,
                  child: Text('Nama A–Z'),
                ),
                PopupMenuItem(
                  value: _PlaylistSortMode.songs,
                  child: Text('Jumlah lagu terbanyak'),
                ),
                PopupMenuItem(
                  value: _PlaylistSortMode.folder,
                  child: Text('Folder'),
                ),
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
                if (value == 'cover') {
                  unawaited(_changePlaylistArtwork(playlist));
                }
                if (value == 'reset_cover') {
                  unawaited(_removePlaylistArtwork(playlist));
                }
                if (value == 'rename') {
                  unawaited(_renamePlaylist(playlist));
                }
                if (value == 'details') {
                  unawaited(_editPlaylistDetails(playlist));
                }
                if (value == 'merge') {
                  unawaited(_mergePlaylist(playlist));
                }
                if (value == 'delete') {
                  unawaited(_deletePlaylist(playlist));
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'cover',
                  child: Text('Ganti foto cover'),
                ),
                if (playlist.artworkPath != null &&
                    playlist.artworkPath!.isNotEmpty)
                  const PopupMenuItem(
                    value: 'reset_cover',
                    child: Text('Pakai cover lagu pertama'),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'details',
                  child: Text('Catatan, folder & warna'),
                ),
                const PopupMenuItem(
                  value: 'merge',
                  child: Text('Gabungkan ke playlist lain'),
                ),
                const PopupMenuItem(value: 'rename', child: Text('Ubah nama')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Hapus playlist'),
                ),
              ],
            ),
        ],
      ),
      body: MusicBackdrop(
        child: playlist == null
            ? _buildPlaylistList(scheme)
            : _buildPlaylistSongs(playlist, scheme),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            7,
            12,
            8 + MediaQuery.paddingOf(context).bottom * 0.18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.currentVideo != null &&
                  widget.nativeState != null &&
                  widget.onOpenCurrentPlayer != null &&
                  widget.onMiniPlayPause != null &&
                  widget.onMiniNext != null) ...[
                MiniMusicPlayer(
                  video: widget.currentVideo!,
                  nativeState: widget.nativeState!,
                  onOpen: widget.onOpenCurrentPlayer!,
                  onPlayPause: widget.onMiniPlayPause!,
                  onNext: widget.onMiniNext!,
                ),
                const SizedBox(height: 9),
              ],
              _PlaylistDock(onSelect: _selectMainTab),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playlistLibraryHero(ColorScheme scheme) {
    final heroEnd =
        Color.lerp(scheme.primary, scheme.tertiary, 0.42) ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Container(
          constraints: const BoxConstraints(minHeight: 236),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                heroEnd,
                Color.lerp(heroEnd, Colors.black, 0.24)!,
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -26,
                top: -42,
                child: Icon(
                  Icons.library_music_rounded,
                  size: 210,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              Positioned(
                right: 24,
                bottom: -54,
                child: Icon(
                  Icons.album_rounded,
                  size: 150,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(
                            Icons.queue_music_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 9),
                        Text(
                          'YOUR MUSIC SPACE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 17),
                    Text(
                      'Semua playlist.\nSemua ceritamu.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 29,
                        height: 0.98,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.1,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Atur koleksi musikmu, impor dari Spotify, dan simpan lagu untuk didengarkan offline.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 17),
                    Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      children: [
                        FilledButton.icon(
                          onPressed: () => unawaited(_createPlaylist()),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: scheme.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 15,
                              vertical: 11,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text(
                            'Playlist baru',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _spotifyImporting
                              ? null
                              : () => unawaited(_importSpotifyPlaylist()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(Icons.link_rounded, size: 17),
                          label: const Text(
                            'Impor Spotify',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _playlistHeroStat(
                          '${widget.playlists.length}',
                          'PLAYLIST',
                        ),
                        const SizedBox(width: 22),
                        _playlistHeroStat(
                          '${widget.playlists.fold<int>(0, (total, item) => total + item.songs.length)}',
                          'LAGU',
                        ),
                        const SizedBox(width: 22),
                        _playlistHeroStat(
                          '${widget.playlists.fold<int>(0, (total, item) => total + item.offlineSongCount)}',
                          'OFFLINE',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playlistHeroStat(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.70),
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistList(ColorScheme scheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 5
            : constraints.maxWidth >= 820
                ? 4
                : constraints.maxWidth >= 590
                    ? 3
                    : 2;

        return CustomScrollView(
          key: const PageStorageKey<String>('musikku-playlist-library-scroll'),
          primary: false,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(child: _playlistLibraryHero(scheme)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 18, 13),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'KOLEKSI PRIBADI',
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Playlist kamu',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.85,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${widget.playlists.length} playlist',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_sortedPlaylists.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: MusicEmptyState(
                    icon: Icons.library_music_rounded,
                    title: 'Playlist kamu masih kosong',
                    message:
                        'Buat playlist pertama untuk menyimpan lagu favorit dan mengunduhnya agar bisa didengarkan offline.',
                    actionLabel: 'Buat playlist',
                    onAction: () => unawaited(_createPlaylist()),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 30),
                sliver: SliverGrid.builder(
                  itemCount: _sortedPlaylists.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 13,
                    mainAxisSpacing: 13,
                    childAspectRatio: constraints.maxWidth < 420 ? 0.76 : 0.82,
                  ),
                  itemBuilder: (context, index) =>
                      _playlistPoster(_sortedPlaylists[index], scheme),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _playlistPoster(Playlist playlist, ColorScheme scheme) {
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedPlaylistId = playlist.id;
            _songSelectionMode = false;
            _selectedSongIds.clear();
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PlaylistArtwork(
                    playlist: playlist,
                    fit: BoxFit.cover,
                    iconSize: 34,
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x05000000), Color(0x79000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 9,
                    top: 9,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${playlist.songs.length} TRACKS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 9,
                    bottom: 9,
                    child: Material(
                      color: scheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: playlist.songs.isEmpty
                            ? null
                            : () => unawaited(
                                  _playPlaylistAndReturn(playlist),
                                ),
                        child: SizedBox(
                          width: 39,
                          height: 39,
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: scheme.onPrimary,
                            size: 23,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    playlist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${playlist.offlineSongCount} offline · ${playlist.folderName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistDetailArtwork(Playlist playlist, ColorScheme scheme) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 760;
    final stacked = screenWidth < 430;
    final artworkSize = wide
        ? 190.0
        : stacked
            ? 166.0
            : 148.0;

    Widget artwork() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: artworkSize,
          height: artworkSize,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PlaylistArtwork(
                playlist: playlist,
                fit: BoxFit.cover,
                iconSize: 48,
              ),
              Positioned(
                right: 7,
                bottom: 7,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.74),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _changingArtwork
                        ? null
                        : () => unawaited(_changePlaylistArtwork(playlist)),
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: _changingArtwork
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.edit_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget details({bool center = false}) {
      final alignment = center ? TextAlign.center : TextAlign.start;
      return Column(
        crossAxisAlignment:
            center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'YOUR PLAYLIST',
            textAlign: alignment,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.65,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            playlist.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: alignment,
            style: TextStyle(
              color: Colors.white,
              fontSize: wide ? 29 : 23,
              height: 1.02,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.85,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '${playlist.songs.length} lagu  ·  ${playlist.offlineSongCount} offline',
            textAlign: alignment,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (playlist.description.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              playlist.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: alignment,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 9),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_camera_back_outlined,
                size: 13,
                color: Colors.white,
              ),
              const SizedBox(width: 5),
              Text(
                'Ubah artwork',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      );
    }

    final backgroundColor = Color(
      playlist.accentColorValue ?? scheme.primary.toARGB32(),
    );
    final secondColor =
        Color.lerp(backgroundColor, Colors.black, 0.52) ?? Colors.black;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 3),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(29),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [backgroundColor, secondColor],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -35,
                top: -50,
                child: Icon(
                  Icons.album_rounded,
                  size: 230,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(wide ? 24 : 18),
                child: stacked
                    ? Column(
                        children: [
                          artwork(),
                          const SizedBox(height: 18),
                          details(center: true),
                        ],
                      )
                    : Row(
                        children: [
                          artwork(),
                          SizedBox(width: wide ? 24 : 17),
                          Expanded(child: details()),
                        ],
                      ),
              ),
            ],
          ),
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
              onPressed:
                  playlist.songs.isEmpty || widget.onShufflePlaylist == null
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
                label: const Text(
                  'Play',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
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
                backgroundColor: scheme.secondaryContainer.withValues(
                  alpha: 0.78,
                ),
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
            icon: Icon(
              Icons.offline_pin_rounded,
              color: scheme.primary,
              size: 21,
            ),
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
            icon: Icon(
              Icons.more_time_rounded,
              color: scheme.onSurfaceVariant,
              size: 20,
            ),
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

  Widget _playlistDetailHeader(Playlist playlist, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _playlistDetailArtwork(playlist, scheme),
        _playlistActionRow(playlist, scheme),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DAFTAR LAGU',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${playlist.songs.length} lagu · ${playlist.offlineSongCount} tersedia offline',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (playlist.offlineSongCount > 0)
                OutlinedButton.icon(
                  onPressed: widget.onPlayOfflinePlaylist == null
                      ? null
                      : () => unawaited(
                            _playOfflinePlaylistAndReturn(playlist),
                          ),
                  icon: const Icon(Icons.offline_pin_rounded, size: 16),
                  label: const Text('Offline'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    shape: const StadiumBorder(),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _playlistSongRow(
    Playlist playlist,
    YoutubeSearchResult song,
    int index,
    ColorScheme scheme,
  ) {
    return ValueListenableBuilder<PlayerUiState>(
      key: ValueKey<String>('${playlist.id}:song:${song.videoId}'),
      valueListenable: widget.playerUiState,
      builder: (context, playerState, _) {
        final current = playerState.video;
        final isCurrent =
            current?.videoId == song.videoId ||
            current?.localMediaId == 'offline_${song.videoId}';
        final selected = _selectedSongIds.contains(song.videoId);
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Material(
            color: isCurrent
                ? scheme.primaryContainer.withValues(alpha: 0.55)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _songSelectionMode
                  ? () => setState(() {
                      if (selected) {
                        _selectedSongIds.remove(song.videoId);
                      } else {
                        _selectedSongIds.add(song.videoId);
                      }
                    })
                  : () => unawaited(_playSongAndReturn(playlist, song)),
              onLongPress: () => setState(() {
                _songSelectionMode = true;
                _selectedSongIds.add(song.videoId);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
                child: Row(
                  children: [
                    if (_songSelectionMode)
                      Checkbox(
                        value: selected,
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            _selectedSongIds.add(song.videoId);
                          } else {
                            _selectedSongIds.remove(song.videoId);
                          }
                        }),
                        visualDensity: VisualDensity.compact,
                      )
                    else
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${index + 1}'.padLeft(2, '0'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isCurrent
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 58,
                        height: 58,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            UnifiedArtwork(
                              track: song,
                              width: 58,
                              height: 58,
                              fit: BoxFit.cover,
                            ),
                            if (isCurrent)
                              ColoredBox(
                                color: Colors.black.withValues(alpha: 0.36),
                                child: const Icon(
                                  Icons.equalizer_rounded,
                                  color: Colors.white,
                                  size: 25,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isCurrent) ...[
                            Text(
                              'NOW PLAYING',
                              style: TextStyle(
                                color: scheme.primary,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.75,
                              ),
                            ),
                            const SizedBox(height: 3),
                          ],
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: isCurrent
                                  ? scheme.primary
                                  : scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            song.artistName.trim().isNotEmpty
                                ? song.artistName
                                : song.channelTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (song.sourceChannelTitle.trim().isNotEmpty &&
                              song.sourceChannelTitle.trim() !=
                                  song.channelTitle.trim())
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Sumber: ${song.sourceChannelTitle}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.76,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _downloadSongButton(song, scheme),
                    PopupMenuButton<String>(
                      tooltip: 'Opsi lagu',
                      onSelected: (value) {
                        if (value == 'remove') {
                          unawaited(_removeSong(playlist, song));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Hapus dari playlist'),
                        ),
                      ],
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index + 1,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          color: scheme.onSurfaceVariant.withValues(
                            alpha: 0.82,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaylistSongs(Playlist playlist, ColorScheme scheme) {
    // One scrollable owns the full detail page. The header is the first item,
    // followed by lazy-built tracks; the mini-player and dock live in the
    // Scaffold bottomNavigationBar so neither can cover the last song.
    return ReorderableListView.builder(
      // Dedicated controller prevents this route from inheriting the hidden
      // HomePage feed's PrimaryScrollController. One scrollable owns the entire
      // playlist detail; the mini-player and dock reserve their own Scaffold
      // height below it, so the last track remains reachable.
      key: PageStorageKey<String>('musikku-playlist-detail-${playlist.id}'),
      primary: false,
      shrinkWrap: false,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        0,
        0,
        0,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      buildDefaultDragHandles: false,
      itemCount: playlist.songs.length + 1 + (playlist.songs.isEmpty ? 1 : 0),
      onReorderItem: (oldIndex, newIndex) {
        if (oldIndex == 0 || playlist.songs.isEmpty) return;
        final oldSongIndex = oldIndex - 1;
        final targetListIndex = newIndex
            .clamp(1, playlist.songs.length)
            .toInt();
        final newSongIndex = targetListIndex - 1;
        _reorderSongs(playlist, oldSongIndex, newSongIndex);
      },
      itemBuilder: (context, index) {
        if (index == 0) {
          return KeyedSubtree(
            key: ValueKey<String>('playlist-detail-header-${playlist.id}'),
            child: _playlistDetailHeader(playlist, scheme),
          );
        }
        if (playlist.songs.isEmpty && index == 1) {
          return KeyedSubtree(
            key: ValueKey<String>('playlist-empty-${playlist.id}'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              child: MusicEmptyState(
                icon: Icons.library_music_rounded,
                title: 'Playlist masih kosong',
                message: 'Tambahkan lagu dari pencarian, favorit, atau riwayat untuk mulai membangun playlist ini.',
                actionLabel: 'Tambah lagu',
                onAction: () => unawaited(_showAddSongsSheet(playlist)),
              ),
            ),
          );
        }
        final song = playlist.songs[index - 1];
        return _playlistSongRow(playlist, song, index - 1, scheme);
      },
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

    Widget destination(
      int index,
      String label,
      IconData icon,
      IconData activeIcon,
    ) {
      final selected = index == 3;
      return Expanded(
        child: InkWell(
          onTap: () => onSelect(index),
          borderRadius: BorderRadius.circular(19),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
            child: AnimatedContainer(
              duration: MediaQuery.of(context).disableAnimations
                  ? Duration.zero
                  : const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: selected
                    ? scheme.primaryContainer.withValues(alpha: 0.82)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(19),
              ),
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? activeIcon : icon,
                    size: 21,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: selected
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return MusicGlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      radius: 25,
      blur: 18,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            destination(0, 'Beranda', Icons.home_outlined, Icons.home_rounded),
            destination(
              1,
              'Jelajah',
              Icons.explore_outlined,
              Icons.explore_rounded,
            ),
            destination(2, 'Radio', Icons.radio_outlined, Icons.radio_rounded),
            destination(
              3,
              'Koleksi',
              Icons.library_music_outlined,
              Icons.library_music_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
