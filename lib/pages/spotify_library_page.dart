import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const MethodChannel _filePicker = MethodChannel('musikku/youtube_player');
  final SpotifyService _spotify = SpotifyService.instance;
  List<SpotifyImportedPlaylist> _playlists = const <SpotifyImportedPlaylist>[];
  SpotifyImportedPlaylist? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlaylists());
  }

  Future<void> _loadPlaylists() async {
    final playlists = await _spotify.loadImportedPlaylists();
    if (mounted) setState(() => _playlists = playlists);
  }

  Future<void> _importExportFile() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Android's existing document picker returns the selected JSON text.
      // This uses the native file picker already present in MusikKu.
      final raw = await _filePicker.invokeMethod<String>('importBackup');
      if (!mounted || raw == null || raw.trim().isEmpty) return;
      final count = await _spotify.importExportJson(raw);
      await _loadPlaylists();
      if (!mounted) return;
      setState(() => _selected = null);
      _showMessage('Berhasil mengimpor $count playlist dari file ekspor Spotify.');
    } on FormatException catch (error) {
      if (mounted) _showMessage(error.message.toString());
    } on PlatformException catch (error) {
      if (mounted) {
        if (error.code == 'FILE_PICKER') {
          _showMessage('Pemilih file tidak bisa dibuka. Coba lagi.');
        } else {
          _showMessage('File tidak bisa dibaca. Pilih file JSON ekspor Spotify.');
        }
      }
    } catch (error) {
      if (mounted) _showMessage('Impor gagal: ${error.toString()}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSpotifyPrivacy() async {
    final uri = Uri.parse('https://www.spotify.com/account/privacy/');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) _showMessage('Halaman akun Spotify tidak bisa dibuka.');
    } catch (_) {
      if (mounted) _showMessage('Halaman akun Spotify tidak bisa dibuka.');
    }
  }

  Future<void> _removePlaylist(SpotifyImportedPlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus playlist impor?'),
        content: Text('"${playlist.playlist.name}" akan dihapus dari Koleksi MusikKu. File ekspor asli tidak berubah.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _spotify.removeImportedPlaylist(playlist.playlist.id);
    if (!mounted) return;
    setState(() {
      _playlists = _playlists.where((item) => item.playlist.id != playlist.playlist.id).toList();
      if (_selected?.playlist.id == playlist.playlist.id) _selected = null;
    });
    _showMessage('Playlist dihapus dari MusikKu.');
  }

  Future<void> _searchTrack(SpotifyTrack track) async {
    Navigator.of(context).pop();
    await widget.onSearchInMusikKu(track);
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
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(
        leading: selected == null
            ? null
            : IconButton(
                tooltip: 'Kembali ke koleksi',
                onPressed: () => setState(() => _selected = null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Row(
          children: [
            const SpotifyBrandMark(size: 26),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                selected?.playlist.name ?? 'Impor Spotify',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        actions: [
          if (selected == null)
            IconButton(
              tooltip: 'Impor file ekspor Spotify',
              onPressed: _busy ? null : _importExportFile,
              icon: const Icon(Icons.file_open_rounded),
            ),
        ],
      ),
      body: selected == null ? _collection(scheme) : _playlistDetails(scheme, selected),
    );
  }

  Widget _collection(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFF183C2A), Color(0xFF17251E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SpotifyBrandMark(size: 30),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Playlist Spotify, masuk ke MusikKu.',
                      style: TextStyle(color: Colors.white, fontSize: 21, height: 1.12, fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Text(
                'Impor daftar playlist dan lagu secara lokal. Tanpa login Spotify API, Client ID, Redirect URI, atau akun Premium.',
                style: TextStyle(color: Color(0xFFE1EEE5), height: 1.42),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _busy ? null : _importExportFile,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.file_open_rounded),
          label: Text(_busy ? 'Mengimpor…' : 'Pilih file ekspor Spotify (.json)'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1DB954),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openSpotifyPrivacy,
          icon: const Icon(Icons.open_in_new_rounded),
          label: const Text('Buka halaman data akun Spotify'),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Cara mengambil file', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 9),
                const _Instruction(number: '1', text: 'Buka halaman privasi akun Spotify dan minta salinan Account data.'),
                const SizedBox(height: 8),
                const _Instruction(number: '2', text: 'Setelah unduhan ZIP tersedia, ekstrak file ZIP di perangkat.'),
                const SizedBox(height: 8),
                const _Instruction(number: '3', text: 'Tekan tombol impor lalu pilih file Playlist*.json, misalnya Playlist1.json.'),
                const SizedBox(height: 10),
                Text(
                  'MusikKu membaca nama playlist, judul lagu, artis, dan album. File ekspor biasanya tidak menyertakan URL cover; cover mungkin menggunakan ikon pengganti. Audio tidak ikut diimpor.',
                  style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('Playlist MusikKu', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
            Text('${_playlists.length}', style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 10),
        if (_playlists.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(18)),
            child: Column(
              children: [
                Icon(Icons.library_music_outlined, size: 44, color: scheme.onSurfaceVariant),
                const SizedBox(height: 10),
                const Text('Belum ada playlist impor', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 5),
                Text('Playlist yang berhasil diimpor akan tersimpan di sini.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
              ],
            ),
          )
        else
          for (final playlist in _playlists) _playlistCard(playlist, scheme),
      ],
    );
  }

  Widget _playlistCard(SpotifyImportedPlaylist imported, ColorScheme scheme) {
    final playlist = imported.playlist;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => setState(() => _selected = imported),
        contentPadding: const EdgeInsets.all(10),
        leading: _artwork(playlist.imageUrl, 62),
        title: Text(playlist.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${imported.tracks.length} lagu • Diimpor ${_formatDate(imported.importedAt)}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'open') setState(() => _selected = imported);
            if (value == 'remove') unawaited(_removePlaylist(imported));
          },
          itemBuilder: (_) => const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(value: 'open', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.open_in_new_rounded), title: Text('Buka playlist'))),
            PopupMenuItem<String>(value: 'remove', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.delete_outline_rounded), title: Text('Hapus dari MusikKu'))),
          ],
        ),
      ),
    );
  }

  Widget _playlistDetails(ColorScheme scheme, SpotifyImportedPlaylist imported) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              _artwork(imported.playlist.imageUrl, 92),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(imported.playlist.name, style: const TextStyle(fontSize: 20, height: 1.12, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('${imported.tracks.length} lagu • Impor lokal', style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Hapus playlist',
                onPressed: () => unawaited(_removePlaylist(imported)),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text('Pilih lagu untuk mencari versi yang tersedia di katalog MusikKu. Audio Spotify tidak ikut diimpor.', style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4, fontSize: 12)),
        const SizedBox(height: 10),
        if (imported.tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('Playlist ini tidak berisi lagu yang bisa dibaca.')),
          )
        else
          for (var i = 0; i < imported.tracks.length; i++) _trackTile(imported.tracks[i], i, scheme),
      ],
    );
  }

  Widget _trackTile(SpotifyTrack track, int index, ColorScheme scheme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 5),
      child: ListTile(
        onTap: () => unawaited(_searchTrack(track)),
        leading: SizedBox(
          width: 44,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 17, child: Text('${index + 1}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11))),
              Expanded(child: _artwork(track.imageUrl, 42)),
            ],
          ),
        ),
        title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(track.albumName.isEmpty ? track.artistLabel : '${track.artistLabel} • ${track.albumName}', maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.search_rounded),
      ),
    );
  }

  Widget _artwork(String url, double size) {
    final uri = Uri.tryParse(url);
    if (uri != null && uri.scheme == 'https' && (uri.host == 'i.scdn.co' || uri.host.endsWith('.scdn.co'))) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(size),
        ),
      );
    }
    return _placeholder(size);
  }

  Widget _placeholder(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1DB954).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(Icons.music_note_rounded, size: size * 0.48, color: const Color(0xFF1DB954)),
    );
  }

  String _formatDate(DateTime date) {
    if (date.millisecondsSinceEpoch == 0) return 'tanggal tidak diketahui';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _Instruction extends StatelessWidget {
  final String number;
  final String text;
  const _Instruction({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Color(0xFF1DB954), shape: BoxShape.circle),
          child: Text(number, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: scheme.onSurface, height: 1.35))),
      ],
    );
  }
}

class SpotifyBrandMark extends StatelessWidget {
  final double size;
  const SpotifyBrandMark({super.key, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SpotifyBrandPainter()),
    );
  }
}

class _SpotifyBrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF1DB954));
    final paint = Paint()
      ..color = const Color(0xFF102016)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * 0.075;
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromCenter(
        center: Offset(center.dx, center.dy + (i - 1) * radius * 0.23),
        width: radius * (1.15 - i * 0.20),
        height: radius * 0.42,
      );
      canvas.drawArc(rect, 3.55, 2.1, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
