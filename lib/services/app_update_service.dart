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
}

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.version,
    required this.tagName,
    required this.title,
    required this.notes,
    required this.releasePageUrl,
    required this.apkUrl,
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

  Future<AppUpdateCheckResult> checkForUpdate() async {
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
        'Tag versi pada GitHub Release tidak terbaca. Gunakan format v2.5.11.',
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
      if (apkAssets.isNotEmpty) {
        apkAsset = apkAssets.firstWhere(
          (asset) =>
              (asset['name'] as String? ?? '').toLowerCase() == 'app-release.apk',
          orElse: () => apkAssets.first,
        );
      }
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

    return AppUpdateCheckResult(
      status: AppUpdateStatus.available,
      currentVersion: appVersion,
      release: release,
    );
  }

  Future<File> downloadAndVerify(
    AppUpdateRelease release, {
    required void Function(int receivedBytes, int totalBytes) onProgress,
  }) async {
    final url = release.apkUrl;
    if (url == null || !_isAllowedReleaseAsset(url)) {
      throw const AppUpdateException(
        'Rilis belum memiliki URL APK GitHub yang valid.',
      );
    }
    if (release.apkSize < 0 || release.apkSize > _maxApkSizeBytes) {
      throw const AppUpdateException('Ukuran APK melebihi batas keamanan 250 MB.');
    }

    final tempDirectory = await getTemporaryDirectory();
    final updateDirectory = Directory('${tempDirectory.path}/apk_updates');
    await updateDirectory.create(recursive: true);
    final safeVersion = release.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final file = File('${updateDirectory.path}/MusikKu-$safeVersion.apk');
    if (await file.exists()) {
      await file.delete();
    }

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
    final sink = file.openWrite();
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
      if (await file.exists()) await file.delete();
      rethrow;
    }

    if (received < 4 || (totalBytes > 0 && received != totalBytes)) {
      if (await file.exists()) await file.delete();
      throw const AppUpdateException(
        'Ukuran APK yang terunduh tidak cocok. Coba download ulang.',
      );
    }

    final randomAccess = await file.open(mode: FileMode.read);
    final signature = await randomAccess.read(4);
    await randomAccess.close();
    if (signature.length < 4 || signature[0] != 0x50 || signature[1] != 0x4B) {
      await file.delete();
      throw const AppUpdateException(
        'File dari GitHub bukan APK/ZIP yang valid. File dihapus demi keamanan.',
      );
    }

    if (release.sha256Digest != null) {
      final output = _DigestOutput();
      final converter = sha256.startChunkedConversion(output);
      await for (final chunk in file.openRead()) {
        converter.add(chunk);
      }
      converter.close();
      final actualDigest = output.digest?.toString().toLowerCase();
      if (actualDigest == null || actualDigest != release.sha256Digest) {
        await file.delete();
        throw const AppUpdateException(
          'Verifikasi SHA-256 gagal. APK tidak akan diinstal.',
        );
      }
    }

    return file;
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
    // Compare every parsed component. Release tags may contain a fourth
    // component (for example 2.5.14.1); ignoring it can hide an update.
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

