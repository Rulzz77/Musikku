import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/listening_together_service.dart';

void main() {
  group('parseListeningRoomCode', () {
    test('accepts only an eight digit room code', () {
      expect(parseListeningRoomCode('58319427'), '58319427');
      expect(parseListeningRoomCode(' 58319427 '), '58319427');
      expect(parseListeningRoomCode('5831942'), isNull);
      expect(parseListeningRoomCode('583194270'), isNull);
      expect(parseListeningRoomCode('192.168.1.5:41773'), isNull);
      expect(parseListeningRoomCode('https://example.com/room/58319427'), isNull);
    });
  });

  group('shared playback synchronization', () {
    test(
      'loads the host track when restored metadata matches but native audio is not loaded',
      () {
        expect(
          shouldLoadListeningTogetherTrack(
            currentVideoId: 'dQw4w9WgXcQ',
            targetVideoId: 'dQw4w9WgXcQ',
            nativeStateVideoId: 'dQw4w9WgXcQ',
            nativeAudioLoaded: false,
          ),
          isTrue,
        );
      },
    );

    test(
      'loads the host track when the native player still holds a different song',
      () {
        expect(
          shouldLoadListeningTogetherTrack(
            currentVideoId: 'dQw4w9WgXcQ',
            targetVideoId: 'M7lc1UVf-VE',
            nativeStateVideoId: 'dQw4w9WgXcQ',
            nativeAudioLoaded: true,
          ),
          isTrue,
        );
      },
    );

    test(
      'keeps an already loaded matching native song instead of reloading every heartbeat',
      () {
        expect(
          shouldLoadListeningTogetherTrack(
            currentVideoId: 'dQw4w9WgXcQ',
            targetVideoId: 'dQw4w9WgXcQ',
            nativeStateVideoId: 'dQw4w9WgXcQ',
            nativeAudioLoaded: true,
          ),
          isFalse,
        );
      },
    );
  });

  group('shared YouTube track validation', () {
    test('accepts a standard YouTube video id only', () {
      expect(isValidSharedYouTubeVideoId('dQw4w9WgXcQ'), isTrue);
      expect(isValidSharedYouTubeVideoId('short'), isFalse);
      expect(isValidSharedYouTubeVideoId('local:track-1'), isFalse);
      expect(
        isValidSharedYouTubeVideoId('https://youtube.com/watch?v=dQw4w9WgXcQ'),
        isFalse,
      );
      expect(isValidSharedYouTubeVideoId('dQw4w9WgXcQxxx'), isFalse);
    });
  });

  group('listening room remote controls', () {
    test('allows supported shared-player actions', () {
      for (final action in <String>[
        'play_pause',
        'play_track',
        'stop',
        'next',
        'previous',
        'seek',
        'shuffle',
        'smart_shuffle',
        'loop',
      ]) {
        expect(isAllowedListeningRoomControlAction(action), isTrue, reason: action);
      }
    });

    test('rejects unknown or arbitrary remote actions', () {
      expect(isAllowedListeningRoomControlAction('delete_room'), isFalse);
      expect(isAllowedListeningRoomControlAction('execute'), isFalse);
      expect(isAllowedListeningRoomControlAction(''), isFalse);
    });
  });

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
