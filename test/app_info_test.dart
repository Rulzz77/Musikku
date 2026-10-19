
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/app_info.dart';

void main() {
  test('app version and build metadata are populated', () {
    expect(appName, 'MusikKu');
    expect(appVersion, '4.8.13');
    expect(appBuildNumber, '67');

    expect(appVersion, isNotEmpty);
    expect(appBuildNumber, isNotEmpty);
  });
}
