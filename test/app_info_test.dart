
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/app_info.dart';

void main() {
  test('app version and build metadata are populated', () {
    expect(appName, 'MusikKu');
    expect(appVersion, '5.0.8');
    expect(appBuildNumber, '92');

    expect(appVersion, isNotEmpty);
    expect(appBuildNumber, isNotEmpty);
  });
}
