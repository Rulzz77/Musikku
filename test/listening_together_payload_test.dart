import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/listening_together_service.dart';

void main() {
  group('unwrapRealtimeBroadcastPayload', () {
    test('unwraps Supabase Realtime v2 payload envelope', () {
      final result = unwrapRealtimeBroadcastPayload(<String, dynamic>{
        'type': 'broadcast',
        'event': 'music_state',
        'payload': <String, dynamic>{
          'type': 'state',
          'videoId': 'sample-video',
          'positionMs': 12000,
        },
      });

      expect(result['type'], 'state');
      expect(result['videoId'], 'sample-video');
      expect(result['positionMs'], 12000);
    });

    test('accepts a direct event body for compatibility', () {
      final result = unwrapRealtimeBroadcastPayload(<String, dynamic>{
        'type': 'room_join',
        'clientId': 'guest-1',
        'code': '12345678',
      });

      expect(result['type'], 'room_join');
      expect(result['clientId'], 'guest-1');
      expect(result['code'], '12345678');
    });
  });
}
