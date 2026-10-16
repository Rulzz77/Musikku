import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/app_update_service.dart';

void main() {
  group('AppUpdateService.compareVersions', () {
    test('compares ordinary semantic version components', () {
      expect(
        AppUpdateService.compareVersions('2.5.15', '2.5.14'),
        greaterThan(0),
      );
      expect(
        AppUpdateService.compareVersions('2.5.14', '2.5.15'),
        lessThan(0),
      );
      expect(AppUpdateService.compareVersions('2.5.14', 'v2.5.14'), 0);
    });

    test('compares fourth component instead of silently ignoring it', () {
      expect(
        AppUpdateService.compareVersions('2.5.14.1', '2.5.14'),
        greaterThan(0),
      );
      expect(
        AppUpdateService.compareVersions('2.5.14', '2.5.14.1'),
        lessThan(0),
      );
      expect(
        AppUpdateService.compareVersions('2.5.14.1', '2.5.14.1'),
        0,
      );
    });

    test('treats omitted trailing zero components as equivalent', () {
      expect(AppUpdateService.compareVersions('2.5.14.0', '2.5.14'), 0);
    });
  });
}
