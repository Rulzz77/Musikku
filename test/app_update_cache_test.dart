import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/app_update_service.dart';

void main() {
  group('cached update APK validation', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('musikku-update-cache-test-');
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('accepts a complete APK candidate with matching size and ZIP signature', () async {
      final file = File('${directory.path}/app-release.apk');
      final bytes = <int>[0x50, 0x4B, 0x03, 0x04, 0x11, 0x22, 0x33, 0x44];
      await file.writeAsBytes(bytes, flush: true);
      final release = AppUpdateRelease(
        version: '4.6.7',
        tagName: 'v4.6.7',
        title: 'MusikKu 4.6.7',
        notes: '',
        releasePageUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/tag/v4.6.7',
        apkUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/download/v4.6.7/app-release.apk',
        apkFileName: 'app-release.apk',
        apkSize: bytes.length,
        sha256Digest: sha256.convert(bytes).toString(),
        publishedAt: null,
      );

      expect(await AppUpdateService.isValidCachedApk(file, release), isTrue);
    });


    test('rejects a cached APK when only a local checksum exists', () async {
      final file = File('${directory.path}/app-release.apk');
      final bytes = <int>[0x50, 0x4B, 0x03, 0x04, 0x11, 0x22, 0x33, 0x44];
      await file.writeAsBytes(bytes, flush: true);
      await File('${file.path}.sha256').writeAsString(sha256.convert(bytes).toString());
      final release = AppUpdateRelease(
        version: '4.6.7',
        tagName: 'v4.6.7',
        title: 'MusikKu 4.6.7',
        notes: '',
        releasePageUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/tag/v4.6.7',
        apkUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/download/v4.6.7/app-release.apk',
        apkFileName: 'app-release.apk',
        apkSize: bytes.length,
        sha256Digest: null,
        publishedAt: null,
      );

      expect(await AppUpdateService.isValidCachedApk(file, release), isFalse);
    });

    test('rejects an APK candidate with a mismatched expected size', () async {
      final file = File('${directory.path}/app-release.apk');
      await file.writeAsBytes(<int>[0x50, 0x4B, 0x03, 0x04, 0xAA, 0xBB]);
      final release = AppUpdateRelease(
        version: '4.6.7',
        tagName: 'v4.6.7',
        title: 'MusikKu 4.6.7',
        notes: '',
        releasePageUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/tag/v4.6.7',
        apkUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/download/v4.6.7/app-release.apk',
        apkFileName: 'app-release.apk',
        apkSize: 100,
        sha256Digest: sha256.convert(<int>[0x50, 0x4B, 0x03, 0x04, 0xAA, 0xBB]).toString(),
        publishedAt: null,
      );

      expect(await AppUpdateService.isValidCachedApk(file, release), isFalse);
    });

    test('rejects a file that is not an APK/ZIP', () async {
      final file = File('${directory.path}/not-an-apk.apk');
      await file.writeAsBytes(<int>[0x00, 0x01, 0x02, 0x03]);
      final release = AppUpdateRelease(
        version: '4.6.7',
        tagName: 'v4.6.7',
        title: 'MusikKu 4.6.7',
        notes: '',
        releasePageUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/tag/v4.6.7',
        apkUrl: 'https://github.com/Rulzz77/flutter_application_5/releases/download/v4.6.7/app-release.apk',
        apkFileName: 'app-release.apk',
        apkSize: 4,
        sha256Digest: sha256.convert(<int>[0x00, 0x01, 0x02, 0x03]).toString(),
        publishedAt: null,
      );

      expect(await AppUpdateService.isValidCachedApk(file, release), isFalse);
    });
  });
}
