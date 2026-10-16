import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/app_info.dart';

void main() {
  test('application identity and release version are synchronized', () {
    expect(appName, 'MusikKu');
    expect(appVersion, '3.1.0');
    expect(appBuildNumber, '22');
  });
}
