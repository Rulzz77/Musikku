import 'dart:async';
import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_update_service.dart';

class AppUpdateSheet {
  const AppUpdateSheet._();

  static Future<void> show(
    BuildContext context, {
    AppUpdateCheckResult? initialResult,
    bool automaticPrompt = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AppUpdatePanel(
        initialResult: initialResult,
        automaticPrompt: automaticPrompt,
      ),
    );
  }
}

class AppUpdatePanel extends StatefulWidget {
  const AppUpdatePanel({
    super.key,
    this.initialResult,
    this.automaticPrompt = false,
  });

  final AppUpdateCheckResult? initialResult;
  final bool automaticPrompt;

  @override
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

class _AppUpdatePanelState extends State<AppUpdatePanel> {
  AppUpdateCheckResult? _result;
  bool _checking = false;
  bool _downloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _result = widget.initialResult;
    if (_result == null) {
      unawaited(_checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _checking = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await AppUpdateService.instance.checkForUpdate();
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadAndInstall() async {
    final release = _result?.release;
    if (release == null || !release.hasApk) return;

    setState(() {
      _error = null;
      _message = null;
    });

    try {
      // Periksa izin sebelum mengunduh agar pengguna tidak menghabiskan kuota
      // jika Android masih melarang pemasangan APK dari MusikKu.
      final canInstall = await AppUpdateService.instance.canInstallPackages();
      if (!canInstall) {
        await AppUpdateService.instance.requestInstallPermission();
        if (!mounted) return;
        setState(() {
          _message =
              'Aktifkan “Izinkan dari sumber ini” untuk MusikKu. Setelah kembali ke aplikasi, tekan tombol instal lagi.';
        });
        return;
      }

      setState(() {
        _downloading = true;
        _downloadedBytes = 0;
        _totalBytes = release.apkSize;
        _message = 'Menyiapkan unduhan APK…';
      });

      final file = await AppUpdateService.instance.downloadAndVerify(
        release,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadedBytes = received;
            if (total > 0) _totalBytes = total;
            _message = total > 0
                ? 'Mengunduh APK • ${_formatBytes(received)} dari ${_formatBytes(total)}'
                : 'Mengunduh APK • ${_formatBytes(received)}';
          });
        },
      );

      await AppUpdateService.instance.installApk(file.path);
      if (!mounted) return;
      setState(() {
        _message = 'Installer Android dibuka. Ikuti konfirmasi untuk memasang pembaruan.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openReleasesPage() async {
    try {
      await AppUpdateService.instance.openReleasesPage();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Tidak bisa membuka GitHub Releases: $error');
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final result = _result;
    final release = result?.release;
    final progress = _totalBytes > 0
        ? (_downloadedBytes / _totalBytes).clamp(0.0, 1.0).toDouble()
        : null;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          22 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.automaticPrompt &&
                _result?.status == AppUpdateStatus.available) ...[
              Text(
                'Versi baru ditemukan saat MusikKu dibuka.',
                style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(Icons.system_update_alt_rounded, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pembaruan MusikKu',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Versi terpasang: $appVersion',
                        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_checking) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              const Text('Memeriksa rilis terbaru di GitHub…'),
            ] else if (_error != null) ...[
              _StatusPanel(
                icon: Icons.error_outline_rounded,
                color: colors.error,
                title: 'Pemeriksaan gagal',
                message: _error!,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _checkForUpdate,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Coba lagi'),
              ),
            ] else if (result?.status == AppUpdateStatus.noRelease) ...[
              _StatusPanel(
                icon: Icons.cloud_upload_outlined,
                color: colors.primary,
                title: 'Belum ada rilis APK',
                message:
                    'Repository belum memiliki GitHub Release. Untuk rilis pertama, build APK versi updater ini lalu unggah app-release.apk ke GitHub Releases. Setelah itu MusikKu dapat mendeteksi versi berikutnya sendiri.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openReleasesPage,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Buka GitHub Releases'),
              ),
            ] else if (result?.status == AppUpdateStatus.upToDate) ...[
              _StatusPanel(
                icon: Icons.check_circle_outline_rounded,
                color: colors.primary,
                title: 'MusikKu sudah versi terbaru',
                message: 'Versi terpasang $appVersion. Tidak ada pembaruan yang lebih baru.',
              ),
              if (release != null && !release.hasApk) ...[
                const SizedBox(height: 8),
                Text(
                  'Rilis terbaru tidak menyediakan file APK, tetapi versinya tidak lebih baru dari aplikasi ini.',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ] else if (result?.status == AppUpdateStatus.releaseMissingApk) ...[
              _StatusPanel(
                icon: Icons.file_download_off_outlined,
                color: colors.error,
                title: 'Rilis baru belum memiliki APK yang cocok',
                message:
                    'Versi ${release?.version ?? ''} lebih baru, tetapi release tidak menyediakan APK yang cocok untuk arsitektur perangkat ini atau APK universal app-release.apk.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _openReleasesPage,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Buka GitHub Releases'),
              ),
            ] else if (result?.status == AppUpdateStatus.available && release != null) ...[
              _StatusPanel(
                icon: Icons.new_releases_outlined,
                color: colors.primary,
                title: 'Pembaruan tersedia • v${release.version}',
                message: release.title,
              ),
              const SizedBox(height: 12),
              if (release.apkFileName.isNotEmpty) ...[
                Text(
                  'Paket untuk perangkat: ${release.apkFileName}',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 3),
              ],
              if (release.apkSize > 0)
                Text(
                  'Ukuran APK: ${_formatBytes(release.apkSize)}',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
              if (release.publishedAt != null) ...[
                const SizedBox(height: 3),
                Text(
                  'Dirilis ${release.publishedAt!.day.toString().padLeft(2, '0')}/${release.publishedAt!.month.toString().padLeft(2, '0')}/${release.publishedAt!.year}',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
              ],
              if (release.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Catatan perubahan', style: TextStyle(fontWeight: FontWeight.w800, color: colors.onSurface)),
                const SizedBox(height: 5),
                Text(
                  release.notes,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13, height: 1.35),
                ),
              ],
              const SizedBox(height: 16),
              if (_downloading) ...[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(_message ?? 'Mengunduh APK…', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                const SizedBox(height: 8),
              ] else if (_message != null) ...[
                Text(_message!, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.35)),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _downloading ? null : _downloadAndInstall,
                  icon: Icon(_downloading
                      ? Icons.downloading_rounded
                      : _message?.startsWith('Aktifkan') == true
                          ? Icons.install_mobile_rounded
                          : Icons.download_rounded),
                  label: Text(_downloading
                      ? 'Mengunduh…'
                      : _message?.startsWith('Aktifkan') == true
                          ? 'Periksa izin & lanjutkan'
                          : 'Unduh & instal pembaruan'),
                ),
              ),
            ] else ...[
              _StatusPanel(
                icon: Icons.info_outline_rounded,
                color: colors.primary,
                title: 'Siap memeriksa pembaruan',
                message: 'Periksa apakah versi terbaru tersedia di GitHub Releases.',
              ),
            ],
            if (!_checking && _error == null && result?.status != AppUpdateStatus.available) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _checkForUpdate,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Periksa lagi'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Android tetap menampilkan konfirmasi instalasi. File APK diperiksa sebelum installer dibuka; update memerlukan tanda tangan aplikasi yang sama dengan versi terpasang.',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(message, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
