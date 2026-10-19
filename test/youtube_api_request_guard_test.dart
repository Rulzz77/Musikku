import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/youtube_api_request_guard.dart';

void main() {
  setUp(YoutubeApiRequestGuard.resetForTests);

  test('429 only cools down the affected request category', () {
    YoutubeApiRequestGuard.observeResponse(
      scope: 'search',
      statusCode: 429,
      body: '{"error":{"errors":[{"reason":"rateLimitExceeded"}]}}',
    );

    expect(YoutubeApiRequestGuard.isCoolingDown('search'), isTrue);
    expect(YoutubeApiRequestGuard.isCoolingDown('data'), isFalse);
  });

  test('daily quota cooldown extends to the next Pacific midnight', () {
    YoutubeApiRequestGuard.observeResponse(
      scope: 'data',
      statusCode: 403,
      body: '{"error":{"errors":[{"reason":"quotaExceeded"}]}}',
    );

    final until = YoutubeApiRequestGuard.cooldownUntil('data');
    expect(until, isNotNull);
    expect(until!.isAfter(DateTime.now().toUtc()), isTrue);
    expect(until.difference(DateTime.now().toUtc()), lessThan(const Duration(hours: 27)));
  });

  test('a 403 unrelated to quota does not pause the API', () {
    YoutubeApiRequestGuard.observeResponse(
      scope: 'data',
      statusCode: 403,
      body: '{"error":{"errors":[{"reason":"commentsDisabled"}]}}',
    );

    expect(YoutubeApiRequestGuard.isCoolingDown('data'), isFalse);
  });
}
