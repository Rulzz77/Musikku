import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_update_service.dart';

class AppUpdateSheet {
  const AppUpdateSheet._();

  // Protect all entry points (automatic launch check + Settings + Hub button)
  // from stacking multiple update sheets on top of each other.
  static bool _isShowing = false;

  // A launch check can race when two HomePage states are created close together.
  // Remember automatic prompts by release version for this process as a second
  // guard, even if a competing check finishes after the first sheet was closed.
  static final Set<String> _automaticPromptedVersions = <String>{};

  static Future<void> show(
    BuildContext context, {
    AppUpdateCheckResult? initialResult,
    bool automaticPrompt = false,
    bool automaticInstall = false,
  }) async {
    if (_isShowing) return;

    final promptVersion = automaticPrompt ? initialResult?.release?.version : null;
    if (promptVersion != null && !_automaticPromptedVersions.add(promptVersion)) {
      return;
    }

    _isShowing = true;
    try {
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        showDragHandle: false,
        builder: (context) => AppUpdatePanel(
          initialResult: initialResult,
          automaticPrompt: automaticPrompt,
          automaticInstall: automaticInstall,
        ),
      );
    } catch (_) {
      // Allow a retry if Navigator/route setup prevented the sheet from opening.
      if (promptVersion != null) {
        _automaticPromptedVersions.remove(promptVersion);
      }
      rethrow;
    } finally {
      _isShowing = false;
    }
  }
}

class AppUpdatePanel extends StatefulWidget {
  const AppUpdatePanel({
    super.key,
    this.initialResult,
    this.automaticPrompt = false,
    this.automaticInstall = false,
  });

  final AppUpdateCheckResult? initialResult;
  final bool automaticPrompt;
  final bool automaticInstall;

  @override
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

class _AppUpdatePanelState extends State<AppUpdatePanel> with WidgetsBindingObserver {
  /// Pesan izin pemasangan selalu diawali kata ini; dipakai untuk mengubah
  /// label tombol menjadi "Periksa izin & lanjutkan".
  static const String _permissionMessagePrefix = 'Aktifkan';

  AppUpdateCheckResult? _result;
  bool _checking = false;
  bool _downloading = false;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _error;
  String? _message;
  File? _cachedApkFile;
  int? _cachedApkSize;
  bool _usingCachedApk = false;
  bool _awaitingInstallPermissionReturn = false;
  bool _autoInstallStarted = false;

  bool get _needsInstallPermission =>
      _message?.startsWith(_permissionMessagePrefix) == true;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _result = widget.initialResult;

    final initialRelease = _result?.release;
    if (initialRelease != null && _result?.updateAvailable == true) {
      unawaited(_refreshCachedApk(initialRelease));
    }

    if (_result == null) {
      unawaited(_checkForUpdate());
    } else if (widget.automaticPrompt &&
        widget.automaticInstall &&
        _result?.updateAvailable == true &&
        !_autoInstallStarted) {
      _autoInstallStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_downloadAndInstall());
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_awaitingInstallPermissionReturn ||
        !widget.automaticInstall) {
      return;
    }
    _awaitingInstallPermissionReturn = false;
    unawaited(_resumeAutomaticInstallAfterPermission());
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _resumeAutomaticInstallAfterPermission() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    try {
      final allowed = await AppUpdateService.instance.canInstallPackages();
      if (!mounted) return;
      if (allowed) {
        await _downloadAndInstall();
      } else {
        setState(() => _message =
            'Izin belum diaktifkan. Aktifkan izin pemasangan untuk MusikKu lalu tekan tombol instal.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
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
      setState(() {
        _result = result;
        _cachedApkFile = null;
        _cachedApkSize = null;
      });
      if (result.updateAvailable && result.release != null) {
        unawaited(_refreshCachedApk(result.release!));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _refreshCachedApk(AppUpdateRelease release) async {
    try {
      final file = await AppUpdateService.instance.findCachedApk(release);
      final size = file == null ? null : await file.length();
      if (!mounted ||
          _result?.release?.version != release.version ||
          _result?.release?.apkFileName != release.apkFileName) {
        return;
      }
      setState(() {
        _cachedApkFile = file;
        _cachedApkSize = size;
      });
    } catch (_) {
      // Failure to inspect cache should not block a normal verified download.
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
        if (widget.automaticInstall) _awaitingInstallPermissionReturn = true;
        await AppUpdateService.instance.requestInstallPermission();
        if (!mounted) return;
        setState(() {
          _message = widget.automaticInstall
              ? 'Aktifkan “Izinkan dari sumber ini” untuk MusikKu. Setelah kembali, MusikKu akan melanjutkan otomatis jika izin sudah aktif.'
              : 'Aktifkan “Izinkan dari sumber ini” untuk MusikKu. Setelah kembali ke aplikasi, tekan tombol instal lagi.';
        });
        return;
      }

      setState(() {
        _downloading = true;
        _usingCachedApk = _cachedApkFile != null;
        _downloadedBytes = _usingCachedApk ? (_cachedApkSize ?? 0) : 0;
        _totalBytes = release.apkSize > 0 ? release.apkSize : (_cachedApkSize ?? 0);
        _message = _usingCachedApk
            ? 'Memverifikasi APK yang sudah tersimpan…'
            : 'Menyiapkan unduhan APK…';
      });

      final file = await AppUpdateService.instance.downloadAndVerify(
        release,
        onCacheHit: (cachedBytes) {
          if (!mounted) return;
          setState(() {
            _usingCachedApk = true;
            _cachedApkSize = cachedBytes;
            _downloadedBytes = cachedBytes;
            if (_totalBytes <= 0) _totalBytes = cachedBytes;
            _message = 'APK pembaruan sudah tersimpan. Tidak mengunduh ulang.';
          });
        },
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _usingCachedApk = false;
            _cachedApkFile = null;
            _cachedApkSize = null;
            _downloadedBytes = received;
            if (total > 0) _totalBytes = total;
            _message = total > 0
                ? 'Mengunduh APK • ${_formatBytes(received)} dari ${_formatBytes(total)}'
                : 'Mengunduh APK • ${_formatBytes(received)}';
          });
        },
      );
      if (mounted) {
        setState(() {
          _cachedApkFile = file;
          _cachedApkSize = file.lengthSync();
        });
      }

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

  // ---------------------------------------------------------------------------
  // Formatting
  // ---------------------------------------------------------------------------

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showCheckAgain = !_checking &&
        _error == null &&
        _result?.status != AppUpdateStatus.available;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.surface.withValues(alpha: 0.98),
              colors.surfaceContainerLow.withValues(alpha: 0.98),
              colors.surface.withValues(alpha: 0.98),
            ],
          ),
          border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.19))),
        ),
        child: ConstrainedBox(
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
                  _buildAutomaticBanner(colors),
                  const SizedBox(height: 8),
                ],
                _buildHeader(colors),
                const SizedBox(height: 18),
                ..._buildBody(colors),
                if (showCheckAgain) ...[
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
                  'Android tetap menampilkan konfirmasi instalasi dan pemeriksaan Play Protect. File APK diperiksa sebelum installer dibuka; update memerlukan tanda tangan aplikasi yang sama dengan versi terpasang.',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutomaticBanner(ColorScheme colors) {
    return Text(
      widget.automaticInstall
          ? 'Versi baru ditemukan. Pembaruan akan diunduh dan installer Android dibuka otomatis.'
          : 'Versi baru ditemukan saat MusikKu dibuka.',
      style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildHeader(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.17),
            colors.surfaceContainerLow,
            colors.secondary.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            height: 50,
            width: 50,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [colors.primary, colors.secondary]),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.system_update_alt_rounded, color: colors.onPrimary, size: 26),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pembaruan MusikKu',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4),
                ),
                const SizedBox(height: 4),
                Text(
                  'Versi terpasang: $appVersion',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  'UPDATE CENTER  •  v$appVersion',
                  style: TextStyle(
                    color: colors.secondary,
                    fontSize: 9,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _releasesButton() {
    return OutlinedButton.icon(
      onPressed: _openReleasesPage,
      icon: const Icon(Icons.open_in_new_rounded),
      label: const Text('Buka GitHub Releases'),
    );
  }

  /// Isi utama sheet sesuai status pemeriksaan.
  List<Widget> _buildBody(ColorScheme colors) {
    final result = _result;
    final release = result?.release;

    if (_checking) {
      return const [
        LinearProgressIndicator(),
        SizedBox(height: 12),
        Text('Memeriksa rilis terbaru di GitHub…'),
      ];
    }

    if (_error != null) {
      return [
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
      ];
    }

    switch (result?.status) {
      case AppUpdateStatus.noRelease:
        return [
          _StatusPanel(
            icon: Icons.cloud_upload_outlined,
            color: colors.primary,
            title: 'Belum ada rilis APK',
            message:
                'Repository belum memiliki GitHub Release. Untuk rilis pertama, build APK versi updater ini lalu unggah app-release.apk ke GitHub Releases. Setelah itu MusikKu dapat mendeteksi versi berikutnya sendiri.',
          ),
          const SizedBox(height: 12),
          _releasesButton(),
        ];

      case AppUpdateStatus.upToDate:
        return [
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
        ];

      case AppUpdateStatus.releaseMissingApk:
        return [
          _StatusPanel(
            icon: Icons.file_download_off_outlined,
            color: colors.error,
            title: 'Rilis baru belum memiliki APK yang cocok',
            message:
                'Versi ${release?.version ?? ''} lebih baru, tetapi release tidak menyediakan APK yang cocok untuk arsitektur perangkat ini atau APK universal app-release.apk.',
          ),
          const SizedBox(height: 12),
          _releasesButton(),
        ];

      case AppUpdateStatus.releaseMissingDigest:
        return [
          _StatusPanel(
            icon: Icons.gpp_bad_outlined,
            color: colors.error,
            title: 'Checksum rilis tidak tersedia',
            message:
                'Versi ${release?.version ?? ''} tidak menyediakan SHA-256 dari metadata GitHub. Unduhan otomatis diblokir agar APK yang belum dapat diverifikasi tidak dipasang. Unggah kembali APK sebagai release asset yang memiliki digest SHA-256.',
          ),
          const SizedBox(height: 12),
          _releasesButton(),
        ];

      case AppUpdateStatus.available:
        if (release != null) return _buildAvailable(colors, release);
        break;

      default:
        break;
    }

    return [
      _StatusPanel(
        icon: Icons.info_outline_rounded,
        color: colors.primary,
        title: 'Siap memeriksa pembaruan',
        message: 'Periksa apakah versi terbaru tersedia di GitHub Releases.',
      ),
    ];
  }

  List<Widget> _buildAvailable(ColorScheme colors, AppUpdateRelease release) {
    final detailStyle = TextStyle(color: colors.onSurfaceVariant, fontSize: 12);
    final progress = _totalBytes > 0
        ? (_downloadedBytes / _totalBytes).clamp(0.0, 1.0).toDouble()
        : null;
    final publishedAt = release.publishedAt;

    return [
      _StatusPanel(
        icon: Icons.new_releases_outlined,
        color: colors.primary,
        title: 'Pembaruan tersedia • v${release.version}',
        message: release.title,
      ),
      const SizedBox(height: 12),
      if (release.apkFileName.isNotEmpty) ...[
        Text('Paket untuk perangkat: ${release.apkFileName}', style: detailStyle),
        const SizedBox(height: 3),
      ],
      if (release.apkSize > 0)
        Text('Ukuran APK: ${_formatBytes(release.apkSize)}', style: detailStyle),
      if (publishedAt != null) ...[
        const SizedBox(height: 3),
        Text('Dirilis ${_formatDate(publishedAt)}', style: detailStyle),
      ],
      if (release.notes.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          'Catatan perubahan',
          style: TextStyle(fontWeight: FontWeight.w800, color: colors.onSurface),
        ),
        const SizedBox(height: 5),
        Text(
          release.notes,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13, height: 1.35),
        ),
      ],
      const SizedBox(height: 16),
      if (_cachedApkFile != null && !_downloading) ...[
        _StatusPanel(
          icon: Icons.offline_pin_rounded,
          color: colors.primary,
          title: 'APK sudah tersimpan',
          message:
              'File ${_formatBytes(_cachedApkSize ?? 0)} sudah ada di perangkat. Tekan tombol di bawah untuk membuka installer tanpa mengunduh ulang.',
        ),
        const SizedBox(height: 12),
      ],
      if (_downloading) ...[
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 8),
        Text(_message ?? 'Mengunduh APK…', style: detailStyle),
        const SizedBox(height: 8),
      ] else if (_message != null) ...[
        Text(_message!, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12, height: 1.35)),
        const SizedBox(height: 10),
      ],
      _buildInstallButton(),
    ];
  }

  Widget _buildInstallButton() {
    final IconData icon;
    final String label;
    if (_downloading) {
      icon = _usingCachedApk ? Icons.verified_rounded : Icons.downloading_rounded;
      label = _usingCachedApk ? 'Menyiapkan APK tersimpan…' : 'Mengunduh…';
    } else if (_needsInstallPermission) {
      icon = Icons.install_mobile_rounded;
      label = 'Periksa izin & lanjutkan';
    } else if (_cachedApkFile != null) {
      icon = Icons.install_mobile_rounded;
      label = 'Instal APK tersimpan';
    } else {
      icon = Icons.download_rounded;
      label = 'Unduh & instal pembaruan';
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _downloading ? null : _downloadAndInstall,
        icon: Icon(icon),
        label: Text(label),
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