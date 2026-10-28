import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeChoice { system, dark, amoled, light, pink }

enum DataSaverMode { off, saver, superSaver }

extension DataSaverModeX on DataSaverMode {
  String get label {
    switch (this) {
      case DataSaverMode.off:
        return 'Mati';
      case DataSaverMode.saver:
        return 'Hemat';
      case DataSaverMode.superSaver:
        return 'Super hemat';
    }
  }

  String get description {
    switch (this) {
      case DataSaverMode.off:
        return 'Tanpa pembatasan tambahan pada request aplikasi.';
      case DataSaverMode.saver:
        return 'Kurangi prefetch, hasil pencarian, radio, dan data pendukung.';
      case DataSaverMode.superSaver:
        return 'Paling irit: hentikan prefetch agresif dan tunda data sampai diminta.';
    }
  }
}

class AppSettingsController {
  AppSettingsController._();

  static final AppSettingsController instance = AppSettingsController._();

  static const _themeKey = 'app_theme_choice_v1';
  static const _dataSaverKey = 'data_saver_v1';
  static const _dataSaverModeKey = 'data_saver_mode_v1';
  static const _prefetchWifiOnlyKey = 'prefetch_wifi_only_v1';
  static const _bufferAlertSecondsKey = 'buffer_alert_seconds_v1';
  static const _hidePauseOverlayKey = 'hide_pause_overlay_v1';
  static const _cropBrandingKey = 'crop_video_branding_v1';
  static const _autoUpdateEnabledKey = 'app_auto_update_enabled_v1';
  static const _autoInstallUpdatesKey = 'app_auto_install_updates_v1';
  static const _backgroundDownloadUpdatesKey = 'app_background_download_updates_v1';

  final ValueNotifier<AppThemeChoice> theme =
      ValueNotifier(AppThemeChoice.dark);
  final ValueNotifier<bool> dataSaver = ValueNotifier(false);
  final ValueNotifier<DataSaverMode> dataSaverMode =
      ValueNotifier(DataSaverMode.off);
  final ValueNotifier<bool> prefetchWifiOnly = ValueNotifier(true);
  final ValueNotifier<int> bufferAlertSeconds = ValueNotifier(8);

  /// Tutup overlay "video lainnya" bawaan YouTube saat pause dengan thumbnail.
  final ValueNotifier<bool> hidePauseOverlay = ValueNotifier(true);

  /// Zoom video sedikit supaya judul/watermark di tepi ikut terpotong.
  final ValueNotifier<bool> cropVideoBranding = ValueNotifier(false);

  /// Check GitHub Releases when the app opens. Defaults to true to preserve
  /// the previous launch-check behavior while allowing the user to opt out.
  final ValueNotifier<bool> autoUpdateEnabled = ValueNotifier(true);

  /// Automatically download a verified update and open Android's installer UI.
  /// Android/Play Protect still controls the final installation confirmation.
  final ValueNotifier<bool> autoInstallUpdates = ValueNotifier(false);

  /// Download a verified APK quietly after the launch check, without opening a
  /// modal or installer. User installs it later from the update screen.
  final ValueNotifier<bool> backgroundDownloadUpdates = ValueNotifier(false);

  final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  Future<void> load() async {
    try {
      final prefs = await _prefsFuture;
      final rawTheme = prefs.getString(_themeKey) ?? AppThemeChoice.dark.name;
      theme.value = AppThemeChoice.values.firstWhere(
        (value) => value.name == rawTheme,
        orElse: () => AppThemeChoice.dark,
      );
      final rawMode = prefs.getString(_dataSaverModeKey);
      final legacySaver = prefs.getBool(_dataSaverKey) ?? false;
      dataSaverMode.value = DataSaverMode.values.firstWhere(
        (value) => value.name == rawMode,
        orElse: () => legacySaver ? DataSaverMode.saver : DataSaverMode.off,
      );
      dataSaver.value = dataSaverMode.value != DataSaverMode.off;
      prefetchWifiOnly.value = prefs.getBool(_prefetchWifiOnlyKey) ?? true;
      bufferAlertSeconds.value = (prefs.getInt(_bufferAlertSecondsKey) ?? 8).clamp(3, 30).toInt();
      hidePauseOverlay.value = prefs.getBool(_hidePauseOverlayKey) ?? true;
      cropVideoBranding.value = prefs.getBool(_cropBrandingKey) ?? false;
      autoUpdateEnabled.value = prefs.getBool(_autoUpdateEnabledKey) ?? true;
      autoInstallUpdates.value = prefs.getBool(_autoInstallUpdatesKey) ?? false;
      backgroundDownloadUpdates.value =
          prefs.getBool(_backgroundDownloadUpdatesKey) ?? false;
      // The silent background-download mode and auto-open-installer mode are
      // mutually exclusive, so an update never unexpectedly opens a system UI.
      if (autoInstallUpdates.value && backgroundDownloadUpdates.value) {
        backgroundDownloadUpdates.value = false;
        await prefs.setBool(_backgroundDownloadUpdatesKey, false);
      }
    } catch (_) {
      // Default aman: dark + data saver mati.
    }
  }

  Future<void> setTheme(AppThemeChoice value) async {
    theme.value = value;
    final prefs = await _prefsFuture;
    await prefs.setString(_themeKey, value.name);
  }

  Future<void> setDataSaver(bool value) async {
    await setDataSaverMode(value ? DataSaverMode.saver : DataSaverMode.off);
  }

  Future<void> setDataSaverMode(DataSaverMode value) async {
    dataSaverMode.value = value;
    dataSaver.value = value != DataSaverMode.off;
    final prefs = await _prefsFuture;
    await prefs.setString(_dataSaverModeKey, value.name);
    // Keep the legacy boolean in sync for older code/backup files.
    await prefs.setBool(_dataSaverKey, dataSaver.value);
  }

  Future<void> setPrefetchWifiOnly(bool value) async {
    prefetchWifiOnly.value = value;
    final prefs = await _prefsFuture;
    await prefs.setBool(_prefetchWifiOnlyKey, value);
  }

  Future<void> setBufferAlertSeconds(int value) async {
    final safe = value.clamp(3, 30).toInt();
    bufferAlertSeconds.value = safe;
    final prefs = await _prefsFuture;
    await prefs.setInt(_bufferAlertSecondsKey, safe);
  }

  Future<void> setHidePauseOverlay(bool value) async {
    hidePauseOverlay.value = value;
    final prefs = await _prefsFuture;
    await prefs.setBool(_hidePauseOverlayKey, value);
  }

  Future<void> setCropVideoBranding(bool value) async {
    cropVideoBranding.value = value;
    final prefs = await _prefsFuture;
    await prefs.setBool(_cropBrandingKey, value);
  }

  Future<void> setAutoUpdateEnabled(bool value) async {
    autoUpdateEnabled.value = value;
    final prefs = await _prefsFuture;
    await prefs.setBool(_autoUpdateEnabledKey, value);
  }

  Future<void> setAutoInstallUpdates(bool value) async {
    autoInstallUpdates.value = value;
    final prefs = await _prefsFuture;
    await prefs.setBool(_autoInstallUpdatesKey, value);
    if (value && backgroundDownloadUpdates.value) {
      backgroundDownloadUpdates.value = false;
      await prefs.setBool(_backgroundDownloadUpdatesKey, false);
    }
  }

  Future<void> setBackgroundDownloadUpdates(bool value) async {
    backgroundDownloadUpdates.value = value;
    final prefs = await _prefsFuture;
    await prefs.setBool(_backgroundDownloadUpdatesKey, value);
    if (value && autoInstallUpdates.value) {
      autoInstallUpdates.value = false;
      await prefs.setBool(_autoInstallUpdatesKey, false);
    }
  }

  int get dataSaverLevel {
    switch (dataSaverMode.value) {
      case DataSaverMode.off:
        return 0;
      case DataSaverMode.saver:
        return 1;
      case DataSaverMode.superSaver:
        return 2;
    }
  }

  ThemeMode get themeMode {
    switch (theme.value) {
      case AppThemeChoice.system:
        return ThemeMode.system;
      case AppThemeChoice.light:
      case AppThemeChoice.pink:
        return ThemeMode.light;
      case AppThemeChoice.dark:
      case AppThemeChoice.amoled:
        return ThemeMode.dark;
    }
  }

  bool get isAmoled => theme.value == AppThemeChoice.amoled;

  bool get isPink => theme.value == AppThemeChoice.pink;
}
