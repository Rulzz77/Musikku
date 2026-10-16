import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/app_update_service.dart';

void main() {
  group('AppUpdateService.compareVersions', () {
    test('compares major, minor, and patch components', () {
      expect(AppUpdateService.compareVersions('3.0.0', '2.9.99'), greaterThan(0));
      expect(AppUpdateService.compareVersions('2.6.0', '2.5.99'), greaterThan(0));
      expect(AppUpdateService.compareVersions('2.5.14', '2.5.15'), lessThan(0));
    });

    test('compares a fourth numeric component', () {
      expect(AppUpdateService.compareVersions('2.5.15.1', '2.5.15'), greaterThan(0));
      expect(AppUpdateService.compareVersions('2.5.15', '2.5.15.1'), lessThan(0));
      expect(AppUpdateService.compareVersions('2.5.15.0', '2.5.15'), 0);
    });

    test('accepts a v-prefixed release tag', () {
      expect(AppUpdateService.compareVersions('v2.5.16', '2.5.15'), greaterThan(0));
      expect(AppUpdateService.compareVersions('v2.5.18', '2.5.18'), 0);
    });

    test('compares the release version before its build number', () {
      expect(AppUpdateService.compareVersions('2.5.18+18', '2.5.17'), greaterThan(0));
      expect(AppUpdateService.compareVersions('2.5.18+18', '2.5.18'), 0);
    });
  });
}
