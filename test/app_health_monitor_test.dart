import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_5/services/app_health_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores playback failure locally and redacts URL query secrets', () async {
    final monitor = AppHealthMonitor.instance;
    await monitor.record(
      kind: 'PlaybackFailure',
      error: 'stream failed https://example.test/audio?token=super-secret-value',
    );

    final events = await monitor.load();
    expect(events, hasLength(1));
    expect(events.single['kind'], 'PlaybackFailure');
    expect(events.single['error'], isNot(contains('super-secret-value')));
    expect(events.single['error'], contains('[QUERY_REDACTED]'));
  });

  test('clear removes local diagnostic events', () async {
    final monitor = AppHealthMonitor.instance;
    await monitor.record(kind: 'TestError', error: 'test failure');
    expect(await monitor.load(), hasLength(1));

    await monitor.clear();

    expect(await monitor.load(), isEmpty);
  });
}
