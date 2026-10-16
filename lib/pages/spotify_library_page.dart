import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/spotify_service.dart';

class SpotifyLibraryPage extends StatefulWidget {
  final Future<void> Function(SpotifyTrack track) onSearchInMusikKu;

  const SpotifyLibraryPage({
    super.key,
    required this.onSearchInMusikKu,
  });

  @override
  State<SpotifyLibraryPage> createState() => _SpotifyLibraryPageState();
}

class _SpotifyLibraryPageState extends State<SpotifyLibraryPage> {
  final SpotifyService _spotify = SpotifyService.instance;
  SpotifyProfile? _profile;
  SpotifyPlaylist? _selectedPlaylist;
  SpotifyImportedPlaylist? _selectedImportedPlaylist;
  List<SpotifyPlaylist> _playlists = const <SpotifyPlaylist>[];
  List<SpotifyTrack> _tracks = const <SpotifyTrack>[];
  List<SpotifyImportedPlaylist> _importedPlaylists = const <SpotifyImportedPlaylist>[];
  bool _showImported = false;
  bool _busy = false;
  bool _loadingTracks = false;
  String? _importingPlaylistId;
  String _error = '';
  String _trackError = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadImportedPlaylists());
    unawaited(_restoreSession());
  }

  Future<void> _loadImportedPlaylists() async {
    final imported = await _spotify.loadImportedPlaylists();
    if (mounted) setState(() => _importedPlaylists = imported);
  }

  bool _isImported(String playlistId) =>
      _importedPlaylists.any((item) => item.playlist.id == playlistId);

  Future<void> _restoreSession() async {
    if (!_spotify.isConfigured) return;
    setState(() => _busy = true);
    try {
      final restored = await _spotify.restoreSession();
      if (restored && mounted) await _loadConnectedData();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Sesi Spotify perlu dihubungkan ulang.';
          _profile = null;
          _playlists = const <SpotifyPlaylist>[];
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await _spotify.connect();
      await _loadConnectedData();
      if (mounted) _showMessage('Spotify berhasil dihubungkan.');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadConnectedData() async {
    final profile = await _spotify.getCurrentUser();
    final playlists = await _spotify.getMyPlaylists();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _playlists = playlists;
      _error = '';
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await _loadConnectedData();
      if (mounted) _showMessage('Library Spotify diperbarui.');
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPlaylist(SpotifyPlaylist playlist) async {
    setState(() {
      _selectedPlaylist = playlist;
      _tracks = const <SpotifyTrack>[];
      _loadingTracks = true;
      _trackError = '';
    });
    try {
      final tracks = await _spotify.getPlaylistItems(playlist.id);
      if (!mounted) return;
      setState(() => _tracks = tracks);
    } catch (error) {
      if (mounted) setState(() => _trackError = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _loadingTracks = false);
    }
  }

  Future<void> _importPlaylist(
    SpotifyPlaylist playlist, {
    List<SpotifyTrack>? tracks,
  }) async {
    if (_importingPlaylistId != null) return;
    setState(() => _importingPlaylistId = playlist.id);
    try {
      final items = tracks ?? await _spotify.getPlaylistItems(playlist.id);
      await _spotify.importPlaylist(playlist, items);
      final imported = await _spotify.loadImportedPlaylists();
      if (!mounted) return;
      setState(() {
        _importedPlaylists = imported;
        if (_selectedImportedPlaylist?.playlist.id == playlist.id) {
          _selectedImportedPlaylist = imported.firstWhere(
            (item) => item.playlist.id == playlist.id,
          );
        }
      });
      _showMessage('"${playlist.name}" diimpor ke Koleksi MusikKu (${items.length} lagu).');
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _importingPlaylistId = null);
    }
  }

  Future<void> _removeImportedPlaylist(SpotifyImportedPlaylist imported) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus playlist impor?'),
        content: Text('"${imported.playlist.name}" akan dihapus dari Koleksi MusikKu. Playlist asli Spotify tidak berubah.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus impor'),
          ),
        ],
      ),
    );
    if (shouldRemove != true) return;
    await _spotify.removeImportedPlaylist(imported.playlist.id);
    if (!mounted) return;
    setState(() {
      _importedPlaylists = _importedPlaylists
          .where((item) => item.playlist.id != imported.playlist.id)
          .toList();
      if (_selectedImportedPlaylist?.playlist.id == imported.playlist.id) {
        _selectedImportedPlaylist = null;
      }
    });
    _showMessage('Playlist impor dihapus dari MusikKu.');
  }

  Future<void> _openImportedPlaylist(SpotifyImportedPlaylist playlist) async {
    setState(() {
      _selectedPlaylist = null;
      _selectedImportedPlaylist = playlist;
      _tracks = playlist.tracks;
      _loadingTracks = false;
      _trackError = '';
    });
  }

  Future<void> _refreshImportedPlaylist(SpotifyImportedPlaylist imported) async {
    if (_profile == null) {
      _showMessage('Hubungkan akun Spotify untuk memperbarui playlist ini.');
      return;
    }
    await _importPlaylist(imported.playlist);
  }

  Future<void> _openSpotify(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host != 'open.spotify.com') {
      _showMessage('Tautan Spotify tidak valid.');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showMessage('Spotify tidak bisa dibuka di perangkat ini.');
    } catch (_) {
      if (mounted) _showMessage('Spotify tidak bisa dibuka di perangkat ini.');
    }
  }

  Future<void> _openDeveloperDashboard() async {
    try {
      await launchUrl(Uri.parse('https://developer.spotify.com/dashboard'), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _showMessage('Spotify Developer Dashboard tidak bisa dibuka.');
    }
  }

  Future<void> _disconnect() async {
    await _spotify.disconnect();
    if (!mounted) return;
    setState(() {
      _profile = null;
      _selectedPlaylist = null;
      _selectedImportedPlaylist = null;
      _playlists = const <SpotifyPlaylist>[];
      _tracks = const <SpotifyTrack>[];
      _error = '';
      _trackError = '';
    });
    _showMessage('Akun Spotify terputus dari MusikKu.');
  }

  Future<void> _searchInMusikKu(SpotifyTrack track) async {
    final callback = widget.onSearchInMusikKu;
    Navigator.of(context).pop();
    await callback(track);
  }

  String _friendlyError(Object error) {
    if (error is SpotifyIntegrationException) return error.message;
    final message = error.toString();
    if (message.toLowerCase().contains('cancel')) return 'Proses Spotify dibatalkan.';
    return 'Spotify belum bisa dimuat. Periksa koneksi dan konfigurasi akun, lalu coba lagi.';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedTitle = _selectedImportedPlaylist?.playlist.name ?? _selectedPlaylist?.name;
    final hasSelection = selectedTitle != null;
    return Scaffold(
      appBar: AppBar(
        leading: !hasSelection
            ? null
            : IconButton(
                tooltip: 'Kembali ke library',
                onPressed: () => setState(() {
                  _selectedPlaylist = null;
                  _selectedImportedPlaylist = null;
                  _tracks = const <SpotifyTrack>[];
                  _trackError = '';
                }),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Row(
          children: [
            const SpotifyBrandMark(size: 28),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                selectedTitle ?? (_showImported ? 'Playlist MusikKu' : 'Spotify Library'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        actions: [
          if (!hasSelection)
            IconButton(
              tooltip: _showImported ? 'Lihat playlist Spotify' : 'Lihat playlist impor MusikKu',
              onPressed: () => setState(() => _showImported = !_showImported),
              icon: Icon(_showImported ? Icons.cloud_download_rounded : Icons.library_music_rounded),
            ),
          if (_profile != null && !_showImported && !hasSelection)
            IconButton(
              tooltip: 'Perbarui library',
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          if (_profile != null && !_showImported && !hasSelection)
            PopupMenuButton<String>(
              tooltip: 'Akun Spotify',
              onSelected: (value) {
                if (value == 'disconnect') unawaited(_disconnect());
              },
              itemBuilder: (_) => const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'disconnect',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.link_off_rounded),
                    title: Text('Putuskan Spotify'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_selectedImportedPlaylist != null) {
      return _importedPlaylistDetails(scheme, _selectedImportedPlaylist!);
    }
    if (_showImported) return _importedCollection(scheme);
    if (_selectedPlaylist != null) return _playlistDetails(scheme, _selectedPlaylist!);
    if (!_spotify.isConfigured) return _configurationRequired(scheme);
    if (_busy && _profile == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_profile == null) return _connectView(scheme);
    return _playlistCollection(scheme);
  }

  Widget _configurationRequired(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        const Center(child: SpotifyBrandMark(size: 72)),
        const SizedBox(height: 18),
        const Text('Hubungkan library Spotify', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.6)),
        const SizedBox(height: 8),
        Text(
          'Satu konfigurasi lagi diperlukan sebelum akun Spotify bisa dihubungkan.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('1. Spotify Developer Dashboard', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text('Buat aplikasi Web API dan salin Client ID.'),
                SizedBox(height: 14),
                Text('2. Redirect URI', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                SelectableText(SpotifyService.registeredRedirectUri),
                SizedBox(height: 14),
                Text('3. GitHub Actions', style: TextStyle(fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text('Simpan Client ID sebagai Repository Variable bernama SPOTIFY_CLIENT_ID, lalu buat ulang APK.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _openDeveloperDashboard,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Buka Spotify Developer Dashboard'),
        ),
      ],
    );
  }

  Widget _connectView(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 22),
        const Center(child: SpotifyBrandMark(size: 82)),
        const SizedBox(height: 20),
        const Text('Playlist Spotify kamu, di satu tempat.', textAlign: TextAlign.center, style: TextStyle(fontSize: 25, height: 1.08, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
        const SizedBox(height: 10),
        Text(
          'Impor playlist ke Koleksi MusikKu. Daftar lagu disimpan di perangkat dan bisa dicari untuk diputar melalui sumber MusikKu yang tersedia — bukan diputar lewat Spotify.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 18),
        if (_error.isNotEmpty) _errorCard(_error),
        FilledButton.icon(
          onPressed: _busy ? null : _connect,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link_rounded),
          label: Text(_busy ? 'Menghubungkan…' : 'Hubungkan Spotify'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1DB954),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'MusikKu mengimpor metadata playlist dan lagu ke library lokal. Tidak ada pemutaran audio Spotify di halaman ini.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _importedCollection(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              const Icon(Icons.library_music_rounded, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Koleksi MusikKu', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('${_importedPlaylists.length} playlist diimpor • tersimpan di perangkat', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Ini salinan metadata playlist dan daftar lagunya, bukan file audio Spotify. Ketuk lagu untuk mencari versi yang tersedia di MusikKu.',
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4, fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (_importedPlaylists.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 44),
            child: Column(
              children: [
                Icon(Icons.download_for_offline_outlined, size: 52, color: scheme.onSurfaceVariant),
                const SizedBox(height: 10),
                const Text('Belum ada playlist impor', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 6),
                Text('Buka tab Spotify lalu tekan ikon impor pada playlist yang kamu inginkan.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => setState(() => _showImported = false),
                  icon: const Icon(Icons.cloud_download_rounded),
                  label: const Text('Pilih playlist Spotify'),
                ),
              ],
            ),
          )
        else
          for (final item in _importedPlaylists)
            Card(
              margin: const EdgeInsets.only(bottom: 9),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                onTap: () => unawaited(_openImportedPlaylist(item)),
                contentPadding: const EdgeInsets.all(10),
                leading: _artwork(item.playlist.imageUrl, size: 62),
                title: Text(item.playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('${item.tracks.length} lagu • Diimpor ${_formatImportedDate(item.importedAt)}', maxLines: 2, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'remove') unawaited(_removeImportedPlaylist(item));
                    if (action == 'update') unawaited(_refreshImportedPlaylist(item));
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    if (_profile != null)
                      const PopupMenuItem<String>(value: 'update', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.sync_rounded), title: Text('Perbarui dari Spotify'))),
                    const PopupMenuItem<String>(value: 'remove', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline_rounded), title: Text('Hapus dari MusikKu'))),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 12),
        _attribution(scheme),
      ],
    );
  }

  String _formatImportedDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return 'tanggal tidak diketahui';
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  Widget _importedPlaylistDetails(ColorScheme scheme, SpotifyImportedPlaylist imported) {
    final playlist = imported.playlist;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
          child: Row(
            children: [
              _artwork(playlist.imageUrl, size: 100),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SpotifyAttribution(compact: true),
                    const SizedBox(height: 7),
                    Text(playlist.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, height: 1.1)),
                    const SizedBox(height: 5),
                    Text('${imported.tracks.length} lagu • ${playlist.ownerName.isEmpty ? 'Playlist Spotify' : playlist.ownerName}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _profile == null || _importingPlaylistId == playlist.id
              ? null
              : () => unawaited(_refreshImportedPlaylist(imported)),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Perbarui daftar lagu'),
        ),
        OutlinedButton.icon(
          onPressed: () => unawaited(_openSpotify(playlist.spotifyUrl)),
          icon: const Icon(Icons.link_rounded),
          label: const Text('Lihat sumber playlist Spotify'),
        ),
        const SizedBox(height: 8),
        Text('Pilih lagu untuk mencari versi yang tersedia di MusikKu. Lagu tidak diputar melalui Spotify.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4)),
        const SizedBox(height: 16),
        Row(children: [const Expanded(child: Text('Daftar lagu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))), Text('${imported.tracks.length}', style: TextStyle(color: scheme.onSurfaceVariant))]),
        const SizedBox(height: 8),
        if (imported.tracks.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Playlist ini tidak memiliki lagu yang bisa diimpor.'))
        else
          for (var index = 0; index < imported.tracks.length; index++)
            _trackTile(imported.tracks[index], index + 1, scheme),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => unawaited(_removeImportedPlaylist(imported)),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Hapus playlist dari MusikKu'),
        ),
        const SizedBox(height: 12),
        _attribution(scheme),
      ],
    );
  }

  Widget _playlistCollection(ColorScheme scheme) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1DB954).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                const SpotifyBrandMark(size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_profile?.displayName ?? 'Akun Spotify', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text('${_playlists.length} playlist Spotify • ${_importedPlaylists.length} sudah diimpor ke MusikKu', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            _errorCard(_error),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: Text('Playlist kamu', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.4))),
              TextButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text('Sinkronkan'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_busy)
            const Padding(padding: EdgeInsets.all(22), child: Center(child: CircularProgressIndicator()))
          else if (_playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Column(
                children: [
                  Icon(Icons.queue_music_rounded, size: 44, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 8),
                  const Text('Belum ada playlist yang terlihat.', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Tarik layar ke bawah untuk memuat ulang.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            )
          else
            for (final playlist in _playlists) _playlistCard(playlist, scheme),
          const SizedBox(height: 14),
          _attribution(scheme),
        ],
      ),
    );
  }

  Widget _playlistCard(SpotifyPlaylist playlist, ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : () => unawaited(_openPlaylist(playlist)),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              _artwork(playlist.imageUrl, size: 70),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                      [if (playlist.ownerName.isNotEmpty) playlist.ownerName, '${playlist.trackCount} lagu'].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _isImported(playlist.id) ? 'Perbarui impor di MusikKu' : 'Impor ke MusikKu',
                onPressed: _importingPlaylistId == playlist.id
                    ? null
                    : () => unawaited(_importPlaylist(playlist)),
                icon: _importingPlaylistId == playlist.id
                    ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_isImported(playlist.id) ? Icons.library_add_check_rounded : Icons.download_for_offline_rounded),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playlistDetails(ColorScheme scheme, SpotifyPlaylist playlist) {
    return RefreshIndicator(
      onRefresh: () => _openPlaylist(playlist),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                _artwork(playlist.imageUrl, size: 104),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SpotifyAttribution(compact: true),
                      const SizedBox(height: 8),
                      Text(playlist.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, height: 1.1)),
                      const SizedBox(height: 5),
                      Text('${playlist.trackCount} lagu${playlist.ownerName.isNotEmpty ? ' • ${playlist.ownerName}' : ''}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (playlist.description.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(playlist.description, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _importingPlaylistId == playlist.id || _loadingTracks
                ? null
                : () => unawaited(_importPlaylist(
                    playlist,
                    tracks: _tracks.isEmpty ? null : _tracks,
                  )),
            icon: _importingPlaylistId == playlist.id
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(_isImported(playlist.id) ? Icons.library_add_check_rounded : Icons.download_rounded),
            label: Text(_importingPlaylistId == playlist.id
                ? 'Mengimpor…'
                : _isImported(playlist.id) ? 'Perbarui impor di MusikKu' : 'Impor playlist ke MusikKu'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(_openSpotify(playlist.spotifyUrl)),
              icon: const Icon(Icons.link_rounded, size: 17),
              label: const Text('Sumber playlist: Spotify'),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(child: Text('Daftar lagu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              Text('${_tracks.length} lagu', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          if (_loadingTracks)
            const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator()))
          else if (_trackError.isNotEmpty)
            _errorCard(_trackError)
          else if (_tracks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Daftar lagu kosong atau Spotify tidak mengizinkan aplikasi membaca isi playlist ini. Isi playlist hanya tersedia untuk playlist yang kamu miliki atau kamu kolaborasi.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            )
          else
            for (var index = 0; index < _tracks.length; index++) _trackTile(_tracks[index], index + 1, scheme),
          const SizedBox(height: 14),
          _attribution(scheme),
        ],
      ),
    );
  }

  Widget _trackTile(SpotifyTrack track, int index, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 20, child: Text('$index', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11), textAlign: TextAlign.center)),
              const SizedBox(width: 8),
              _artwork(track.imageUrl, size: 48),
            ],
          ),
          title: Text(
            '${track.name}${track.isExplicit ? '  E' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            [track.artistLabel, if (track.albumName.isNotEmpty) track.albumName].join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5),
          ),
          trailing: IconButton(
            tooltip: 'Cari versi di MusikKu',
            onPressed: () => unawaited(_searchInMusikKu(track)),
            icon: const Icon(Icons.search_rounded),
          ),
          onTap: () => unawaited(_searchInMusikKu(track)),
        ),
      ),
    );
  }

  Widget _artwork(String url, {required double size}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? Container(
                color: const Color(0xFF1DB954).withValues(alpha: 0.12),
                alignment: Alignment.center,
                child: const Icon(Icons.music_note_rounded, color: Color(0xFF1DB954)),
              )
            : Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFF1DB954).withValues(alpha: 0.12),
                  alignment: Alignment.center,
                  child: const Icon(Icons.music_note_rounded, color: Color(0xFF1DB954)),
                ),
              ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, height: 1.35))),
          ],
        ),
      ),
    );
  }

  Widget _attribution(ColorScheme scheme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SpotifyBrandMark(size: 20),
        const SizedBox(width: 6),
        Text('Data dan artwork disediakan oleh Spotify', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5)),
      ],
    );
  }
}

class SpotifyAttribution extends StatelessWidget {
  final bool compact;
  const SpotifyAttribution({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpotifyBrandMark(size: compact ? 16 : 22),
        const SizedBox(width: 5),
        Text('Spotify', style: TextStyle(fontWeight: FontWeight.w900, fontSize: compact ? 11 : 13)),
      ],
    );
  }
}

/// Small Spotify attribution mark; artwork itself is displayed without overlays.
class SpotifyBrandMark extends StatelessWidget {
  final double size;
  const SpotifyBrandMark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SpotifyBrandPainter()),
      );
}

class _SpotifyBrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF1DB954));
    final stroke = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * 0.075;
    final lines = <Path>[
      Path()
        ..moveTo(center.dx - radius * 0.56, center.dy - radius * 0.26)
        ..quadraticBezierTo(center.dx, center.dy - radius * 0.50, center.dx + radius * 0.57, center.dy - radius * 0.16),
      Path()
        ..moveTo(center.dx - radius * 0.46, center.dy - radius * 0.02)
        ..quadraticBezierTo(center.dx, center.dy - radius * 0.20, center.dx + radius * 0.46, center.dy + radius * 0.05),
      Path()
        ..moveTo(center.dx - radius * 0.34, center.dy + radius * 0.21)
        ..quadraticBezierTo(center.dx, center.dy + radius * 0.08, center.dx + radius * 0.31, center.dy + radius * 0.25),
    ];
    for (final path in lines) {
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
