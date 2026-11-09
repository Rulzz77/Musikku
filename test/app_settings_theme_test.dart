import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/app_settings.dart';

void main() {
  group('AppSettingsController themeMode', () {
    final settings = AppSettingsController.instance;

    test('manual light mode always resolves to ThemeMode.light', () {
      settings.theme.value = AppThemeChoice.light;
      expect(settings.themeMode, ThemeMode.light);
    });

    test('dark and AMOLED resolve to ThemeMode.dark', () {
      settings.theme.value = AppThemeChoice.dark;
      expect(settings.themeMode, ThemeMode.dark);
      settings.theme.value = AppThemeChoice.amoled;
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.isAmoled, isTrue);
    });

    test('automatic mode follows the operating system', () {
      settings.theme.value = AppThemeChoice.system;
      expect(settings.themeMode, ThemeMode.system);
    });
  });
}
