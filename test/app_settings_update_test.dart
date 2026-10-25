import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_5/services/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('background download and auto-open installer are mutually exclusive', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = AppSettingsController.instance;
    await settings.load();

    expect(settings.backgroundDownloadUpdates.value, isFalse);
    expect(settings.autoInstallUpdates.value, isFalse);

    await settings.setBackgroundDownloadUpdates(true);
    expect(settings.backgroundDownloadUpdates.value, isTrue);
    expect(settings.autoInstallUpdates.value, isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('app_background_download_updates_v1'), isTrue);

    await settings.setAutoInstallUpdates(true);
    expect(settings.autoInstallUpdates.value, isTrue);
    expect(settings.backgroundDownloadUpdates.value, isFalse);
    expect(preferences.getBool('app_background_download_updates_v1'), isFalse);
  });
}
