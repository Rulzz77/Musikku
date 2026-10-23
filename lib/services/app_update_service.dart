import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';

enum AppUpdateStatus {
  available,
  upToDate,
  noRelease,
  releaseMissingApk,
  releaseMissingDigest,
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.tagName,
    required this.title,
    required this.notes,
    required this.releasePageUrl,
    required this.apkUrl,
    required this.apkFileName,
    required this.apkSize,
    required this.sha256Digest,
    required this.publishedAt,
  });

  final String version;
  final String tagName;
  final String title;
  final String notes;
  final String releasePageUrl;
  final String? apkUrl;
  final String apkFileName;
  final int apkSize;
  final String? sha256Digest;
  final DateTime? publishedAt;

  bool get hasApk => apkUrl != null && apkUrl!.isNotEmpty;
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.release,
  });

  final AppUpdateStatus status;
  final String currentVersion;
  final AppUpdateRelease? release;

  bool get updateAvailable => status == AppUpdateStatus.available;
}

class AppUpdateService {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  static const String owner = 'Rulzz77';
  static const String repository = 'flutter_application_5';
  static const String releasesPageUrl =
      'https://github.com/Rulzz77/flutter_application_5/releases';
  static const String _latestReleaseApi =
      'https://api.github.com/repos/Rulzz77/flutter_application_5/releases/latest';
  static const int _maxApkSizeBytes = 250 * 1024 * 1024;
  static const MethodChannel _installerChannel =
      MethodChannel('musikku/app_update');

  final http.Client _client = http.Client();
  Future<AppUpdateCheckResult>? _inFlightCheck;
  final Map<String, Future<File>> _inFlightDownloads = <String, Future<File>>{};

  /// Coalesce automatic, Settings, and Hub-triggered checks while one request
  /// is already running. This avoids duplicate GitHub calls and modal races.
  Future<AppUpdateCheckResult> checkForUpdate() {
    final active = _inFlightCheck;
    if (active != null) return active;

    final request = _performCheckForUpdate();
    _inFlightCheck = request;
    return request.whenComplete(() {
      if (identical(_inFlightCheck, request)) _inFlightCheck = null;
    });
  }

  Future<AppUpdateCheckResult> _performCheckForUpdate() async {
    final response = await _client
        .get(
          Uri.parse(_latestReleaseApi),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2026-03-10',
            'User-Agent': 'MusikKu-Updater',
          },
        )
        .timeout(const Duration(seconds: 18));

    if (response.statusCode == 404) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.noRelease,
        currentVersion: appVersion,
      );
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 403 || response.statusCode == 429) {
        throw const AppUpdateException(
          'GitHub membatasi pemeriksaan sementara. Coba lagi beberapa saat.',
        );
      }
      throw AppUpdateException(
        'Pemeriksaan update gagal (HTTP ${response.statusCode}).',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const AppUpdateException('GitHub mengirim JSON yang tidak valid.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AppUpdateException('Respons rilis GitHub tidak valid.');
    }

    final tagName = (decoded['tag_name'] as String? ?? '').trim();
    final title = (decoded['name'] as String? ?? tagName).trim();
    final version = _versionFrom(tagName.isNotEmpty ? tagName : title);
    if (version.isEmpty) {
      throw const AppUpdateException(
        'Tag versi pada GitHub Release tidak terbaca. Gunakan format v4.2.0.',
      );
    }

    final assets = decoded['assets'];
    Map<String, dynamic>? apkAsset;
    if (assets is List) {
      final apkAssets = assets.whereType<Map<String, dynamic>>().where((asset) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final contentType = (asset['content_type'] as String? ?? '').toLowerCase();
        return name.endsWith('.apk') ||
            contentType == 'application/vnd.android.package-archive';
      }).toList();

      // New releases include split APKs to reduce download size. Prefer the
      // split matching this device's ABI; keep app-release.apk as a universal
      // fallback for older installs and devices where ABI detection fails.
      final supportedAbis = await _getSupportedAbis();
      for (final abi in supportedAbis) {
        final expectedName = 'app-${abi.toLowerCase()}-release.apk';
        for (final asset in apkAssets) {
          final assetName = (asset['name'] as String? ?? '').toLowerCase();
          if (assetName == expectedName) {
            apkAsset = asset;
            break;
          }
        }
        if (apkAsset != null) break;
      }

      apkAsset ??= _firstAssetNamed(apkAssets, 'app-release.apk');
    }

    final rawHtmlUrl = (decoded['html_url'] as String? ?? '').trim();
    final htmlUrl = _isAllowedReleasePage(rawHtmlUrl) ? rawHtmlUrl : releasesPageUrl;
    final rawApkUrl = apkAsset?['browser_download_url'] as String?;
    final safeApkUrl = _isAllowedReleaseAsset(rawApkUrl) ? rawApkUrl : null;
    final sizeValue = apkAsset?['size'];
    final size = sizeValue is int ? sizeValue : int.tryParse('$sizeValue') ?? 0;
    if (size < 0 || size > _maxApkSizeBytes) {
      throw const AppUpdateException('Ukuran APK pada metadata rilis tidak wajar.');
    }
    final digestValue = apkAsset?['digest'] as String?;
    String? sha256Digest;
    if (digestValue != null && digestValue.isNotEmpty) {
      final match = RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(digestValue);
      if (match == null) {
        throw const AppUpdateException('Digest SHA-256 pada metadata rilis tidak valid.');
      }
      sha256Digest = match.group(1)!.toLowerCase();
    }
    final publishedAtRaw = decoded['published_at'] as String?;
    final notes = (decoded['body'] as String? ?? '').trim();

    final release = AppUpdateRelease(
      version: version,
      tagName: tagName,
      title: title.isNotEmpty ? title : 'MusikKu $version',
      notes: notes,
      releasePageUrl: htmlUrl,
      apkUrl: safeApkUrl,
      apkFileName: (apkAsset?['name'] as String? ?? '').trim(),
      apkSize: size,
      sha256Digest: sha256Digest,
      publishedAt: DateTime.tryParse(publishedAtRaw ?? '')?.toLocal(),
    );

    final comparison = compareVersions(version, appVersion);
    if (comparison <= 0) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.upToDate,
        currentVersion: appVersion,
        release: release,
      );
    }

    if (!release.hasApk) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.releaseMissingApk,
        currentVersion: appVersion,
        release: release,
      );
    }

    // Do not offer an automated APK install unless the release API provides
    // its remote SHA-256 digest. A digest created locally after download only
    // detects later cache corruption; it cannot authenticate the first payload.
    if (release.sha256Digest == null) {
      return AppUpdateCheckResult(
        status: AppUpdateStatus.releaseMissingDigest,
        currentVersion: appVersion,
        release: release,
      );
    }

    return AppUpdateCheckResult(
      status: AppUpdateStatus.available,
      currentVersion: appVersion,
      release: release,
    );
  }

  static Map<String, dynamic>? _firstAssetNamed(
    List<Map<String, dynamic>> assets,
    String expectedName,
  ) {
    for (final asset in assets) {
      if ((asset['name'] as String? ?? '').toLowerCase() ==
          expectedName.toLowerCase()) {
        return asset;
      }
    }
    return null;
  }

  Future<List<String>> _getSupportedAbis() async {
    try {
      final values = await _installerChannel.invokeMethod<List<dynamic>>(
        'getSupportedAbis',
      );
      return values
              ?.whereType<String>()
              .map((abi) => abi.trim().toLowerCase())
              .where((abi) => abi.isNotEmpty)
              .toList(growable: false) ??
          const <String>[];
    } on PlatformException {
      // Existing/older native bridge: use universal app-release.apk fallback.
      return const <String>[];
    } on MissingPluginException {
      return const <String>[];
    }
  }

  /// A valid APK is kept in private application storage until a newer update
  /// replaces it. This survives app restarts and in-place APK updates, unlike
  /// the OS-managed temporary cache directory.
  Future<Directory> _getUpdateDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory('${supportDirectory.path}/apk_updates');
    await directory.create(recursive: true);
    return directory;
  }

  static String _cacheFileNameFor(AppUpdateRelease release) {
    final safeVersion = release.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final rawAssetName = release.apkFileName.isNotEmpty
        ? release.apkFileName
        : 'app-release.apk';
    final assetWithoutExtension = rawAssetName.replaceFirst(
      RegExp(r'\.apk$', caseSensitive: false),
      '',
    );
    final safeAssetName = assetWithoutExtension.replaceAll(
      RegExp(r'[^0-9A-Za-z._-]'),
      '_',
    );
    final identity = release.sha256Digest != null && release.sha256Digest!.length >= 12
        ? release.sha256Digest!.substring(0, 12).toLowerCase()
        : 'size${release.apkSize}';
    return 'MusikKu-$safeVersion-$safeAssetName-$identity.apk';
  }

  /// Finds a complete, verified APK for the requested release without making
  /// a network request. Invalid or incomplete cached files are removed.
  Future<File?> findCachedApk(AppUpdateRelease release) async {
    if (!release.hasApk ||
        release.sha256Digest == null ||
        !_isAllowedReleaseAsset(release.apkUrl)) {
      return null;
    }
    final directory = await _getUpdateDirectory();
    final file = File('${directory.path}/${_cacheFileNameFor(release)}');
    if (!await file.exists()) return null;

    if (await isValidCachedApk(file, release)) {
      await _removeOlderCachedApks(directory, file);
      return file;
    }

    try {
      await file.delete();
      final marker = File('${file.path}.sha256');
      if (await marker.exists()) await marker.delete();
    } on FileSystemException {
      // A failed cleanup must not make a bad cache candidate look valid.
    }
    return null;
  }

  /// Shared validation for both freshly downloaded and previously cached APKs.
  /// Public to keep cache validation covered by a small, deterministic test.
  static Future<bool> isValidCachedApk(
    File file,
    AppUpdateRelease release,
  ) async {
    try {
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length < 4 || length > _maxApkSizeBytes) return false;
      if (release.apkSize > 0 && length != release.apkSize) return false;

      final handle = await file.open(mode: FileMode.read);
      final signature = await handle.read(4);
      await handle.close();
      if (signature.length < 4 ||
          signature[0] != 0x50 ||
          signature[1] != 0x4B) {
        return false;
      }

      final remoteDigest = release.sha256Digest?.toLowerCase();
      if (remoteDigest == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(remoteDigest)) {
        return false;
      }
      final actualDigest = await _sha256ForFile(file);
      return actualDigest == remoteDigest;
    } on FileSystemException {
      return false;
    }
  }

  static Future<String> _sha256ForFile(File file) async {
    final output = _DigestOutput();
    final converter = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      converter.add(chunk);
    }
    converter.close();
    return output.digest?.toString().toLowerCase() ?? '';
  }

  static Future<void> _removeOlderCachedApks(
    Directory directory,
    File keep,
  ) async {
    if (!await directory.exists()) return;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File &&
          entry.path != keep.path &&
          entry.path.toLowerCase().endsWith('.apk')) {
        try {
          await entry.delete();
          final marker = File('${entry.path}.sha256');
          if (await marker.exists()) await marker.delete();
        } on FileSystemException {
          // Best-effort storage cleanup; never delete the selected APK.
        }
      }
    }
  }

  Future<File> downloadAndVerify(
    AppUpdateRelease release, {
    required void Function(int receivedBytes, int totalBytes) onProgress,
    void Function(int cachedBytes)? onCacheHit,
  }) {
    final url = release.apkUrl;
    if (url == null || !_isAllowedReleaseAsset(url)) {
      throw const AppUpdateException(
        'Rilis belum memiliki URL APK GitHub yang valid.',
      );
    }
    if (release.sha256Digest == null ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(release.sha256Digest!)) {
      throw const AppUpdateException(
        'Checksum SHA-256 dari metadata GitHub tidak tersedia atau tidak valid. APK tidak diunduh demi keamanan.',
      );
    }
    if (release.apkSize < 0 || release.apkSize > _maxApkSizeBytes) {
      throw const AppUpdateException('Ukuran APK melebihi batas keamanan 250 MB.');
    }

    // A tap or route race must not start a second transfer for the same asset.
    final key = _cacheFileNameFor(release);
    final active = _inFlightDownloads[key];
    if (active != null) return active;

    final request = _downloadAndVerifyInternal(
      release,
      onProgress: onProgress,
      onCacheHit: onCacheHit,
    );
    _inFlightDownloads[key] = request;
    return request.whenComplete(() {
      if (identical(_inFlightDownloads[key], request)) {
        _inFlightDownloads.remove(key);
      }
    });
  }

  Future<File> _downloadAndVerifyInternal(
    AppUpdateRelease release, {
    required void Function(int receivedBytes, int totalBytes) onProgress,
    void Function(int cachedBytes)? onCacheHit,
  }) async {
    final cachedFile = await findCachedApk(release);
    if (cachedFile != null) {
      onCacheHit?.call(await cachedFile.length());
      return cachedFile;
    }

    final url = release.apkUrl!;
    final updateDirectory = await _getUpdateDirectory();
    final file = File('${updateDirectory.path}/${_cacheFileNameFor(release)}');
    final partialFile = File('${file.path}.part');
    if (await partialFile.exists()) await partialFile.delete();

    final response = await _sendVerifiedAssetRequest(url);
    if (response.statusCode != 200) {
      await response.stream.listen((_) {}).cancel();
      throw AppUpdateException('Download APK gagal (HTTP ${response.statusCode}).');
    }

    final totalBytes = release.apkSize > 0
        ? release.apkSize
        : response.contentLength ?? 0;
    if (totalBytes > _maxApkSizeBytes) {
      await response.stream.listen((_) {}).cancel();
      throw const AppUpdateException('Ukuran APK melebihi batas keamanan 250 MB.');
    }

    var received = 0;
    final sink = partialFile.openWrite();
    try {
      onProgress(0, totalBytes);
      await for (final chunk in response.stream.timeout(const Duration(seconds: 20))) {
        final nextReceived = received + chunk.length;
        if (nextReceived > _maxApkSizeBytes ||
            (totalBytes > 0 && nextReceived > totalBytes)) {
          throw const AppUpdateException(
            'Ukuran APK melebihi ukuran yang diizinkan. Unduhan dibatalkan.',
          );
        }
        sink.add(chunk);
        received = nextReceived;
        onProgress(received, totalBytes);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();
      if (await partialFile.exists()) await partialFile.delete();
      rethrow;
    }

    if (received < 4 || (totalBytes > 0 && received != totalBytes)) {
      if (await partialFile.exists()) await partialFile.delete();
      throw const AppUpdateException(
        'Ukuran APK yang terunduh tidak cocok. Coba download ulang.',
      );
    }

    final signatureHandle = await partialFile.open(mode: FileMode.read);
    final signature = await signatureHandle.read(4);
    await signatureHandle.close();
    if (signature.length < 4 || signature[0] != 0x50 || signature[1] != 0x4B) {
      await partialFile.delete();
      throw const AppUpdateException(
        'File dari GitHub bukan APK/ZIP yang valid. File dihapus demi keamanan.',
      );
    }

    // Compare the complete download against the SHA-256 supplied by GitHub's
    // release metadata before making it visible as a completed cache item.
    final actualDigest = await _sha256ForFile(partialFile);
    if (actualDigest != release.sha256Digest!.toLowerCase()) {
      await partialFile.delete();
      throw const AppUpdateException(
        'Verifikasi SHA-256 gagal. APK tidak akan diinstal.',
      );
    }

    // Rename only after verification, so an interrupted transfer never appears
    // as a completed cache item. The cached APK lives in files/apk_updates and
    // survives app restarts and normal in-place application updates.
    if (await file.exists()) await file.delete();
    final verifiedFile = await partialFile.rename(file.path);
    await _removeOlderCachedApks(updateDirectory, verifiedFile);
    return verifiedFile;
  }

  Future<bool> canInstallPackages() async {
    try {
      return await _installerChannel.invokeMethod<bool>('canInstallPackages') ?? false;
    } on PlatformException catch (error) {
      throw AppUpdateException('Tidak bisa memeriksa izin instalasi: ${error.message ?? error.code}');
    } on MissingPluginException {
      throw const AppUpdateException(
        'Jembatan installer Android belum terpasang. Build ulang APK updater terlebih dahulu.',
      );
    }
  }

  Future<void> requestInstallPermission() async {
    await _installerChannel.invokeMethod<void>('requestInstallPermission');
  }

  Future<void> installApk(String path) async {
    await _installerChannel.invokeMethod<void>(
      'installApk',
      <String, Object?>{'path': path},
    );
  }

  Future<void> openReleasesPage() async {
    await _installerChannel.invokeMethod<void>('openReleasesPage');
  }

  /// Follow only the HTTPS redirect hosts used by GitHub Release assets.
  /// This prevents a compromised/malformed release response from redirecting
  /// the APK download to an arbitrary host.
  Future<http.StreamedResponse> _sendVerifiedAssetRequest(String rawUrl) async {
    var current = Uri.parse(rawUrl);
    const maxRedirects = 4;

    for (var redirectCount = 0; redirectCount <= maxRedirects; redirectCount++) {
      final isFirstHop = redirectCount == 0;
      final validHop = isFirstHop
          ? _isAllowedReleaseAsset(current.toString())
          : _isAllowedDownloadRedirect(current);
      if (!validHop) {
        throw const AppUpdateException(
          'URL unduhan/redirect APK tidak termasuk host tepercaya.',
        );
      }

      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['Accept'] = 'application/octet-stream'
        ..headers['User-Agent'] = 'MusikKu-Updater';

      final http.StreamedResponse response;
      try {
        response = await _client.send(request).timeout(const Duration(seconds: 45));
      } on TimeoutException {
        throw const AppUpdateException('Download APK terlalu lama merespons.');
      }

      if (!const <int>{301, 302, 303, 307, 308}.contains(response.statusCode)) {
        return response;
      }

      final location = response.headers['location'];
      await response.stream.listen((_) {}).cancel();
      if (location == null || location.trim().isEmpty || redirectCount >= maxRedirects) {
        throw const AppUpdateException('Redirect unduhan APK tidak valid atau terlalu banyak.');
      }

      final next = current.resolve(location.trim());
      if (!_isAllowedDownloadRedirect(next)) {
        throw const AppUpdateException(
          'GitHub mengarahkan unduhan ke host yang tidak tepercaya.',
        );
      }
      current = next;
    }

    throw const AppUpdateException('Redirect unduhan APK melebihi batas.');
  }

  static bool _isAllowedDownloadRedirect(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.fragment.isNotEmpty) {
      return false;
    }

    if (uri.host == 'github.com') {
      return uri.path.toLowerCase().startsWith(
        '/rulzz77/flutter_application_5/releases/download/',
      );
    }

    // Current GitHub Release asset delivery domains. Keep this exact allowlist
    // narrow rather than permitting arbitrary *.githubusercontent.com hosts.
    return const <String>{
      'release-assets.githubusercontent.com',
      'objects.githubusercontent.com',
      'github-releases.githubusercontent.com',
    }.contains(uri.host.toLowerCase());
  }

  static bool _isAllowedReleasePage(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.path.toLowerCase().startsWith('/rulzz77/flutter_application_5/releases');
  }

  static bool _isAllowedReleaseAsset(String? value) {
    if (value == null || value.isEmpty) return false;
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host == 'github.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        uri.path.toLowerCase().startsWith('/rulzz77/flutter_application_5/releases/download/');
  }

  static String _versionFrom(String value) {
    final match = RegExp(r'\d+(?:\.\d+){1,3}').firstMatch(value);
    return match?.group(0) ?? '';
  }

  static int compareVersions(String first, String second) {
    List<int> parts(String value) {
      final cleaned = _versionFrom(value);
      if (cleaned.isEmpty) return const [0, 0, 0];
      return cleaned.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    }

    final a = parts(first);
    final b = parts(second);
    // `_versionFrom` accepts up to four numeric components, so compare all of
    // them. Previously the loop stopped after major/minor/patch and treated
    // `2.5.15.1` as equal to `2.5.15`, which could hide a published update.
    final componentCount = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < componentCount; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class _DigestOutput implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

