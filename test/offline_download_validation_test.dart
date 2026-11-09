import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/offline_download_validation.dart';

void main() {
  group('ParsedContentRange', () {
    test('parses a valid partial response', () {
      final value = ParsedContentRange.parse('bytes 100-199/1000');
      expect(value, isNotNull);
      expect(value!.start, 100);
      expect(value.end, 199);
      expect(value.length, 100);
      expect(value.total, 1000);
    });

    test('rejects malformed, reversed, and impossible ranges', () {
      expect(ParsedContentRange.parse(null), isNull);
      expect(ParsedContentRange.parse('items 1-4/5'), isNull);
      expect(ParsedContentRange.parse('bytes 8-7/10'), isNull);
      expect(ParsedContentRange.parse('bytes 0-10/10'), isNull);
    });

    test('resume requires exact byte offset and response length', () {
      expect(
        isValidContentRangeResponse(
          requestedOffset: 100,
          contentRange: 'bytes 100-999/1000',
          contentLength: 900,
        ),
        isTrue,
      );
      expect(
        isValidContentRangeResponse(
          requestedOffset: 100,
          contentRange: 'bytes 99-999/1000',
          contentLength: 901,
        ),
        isFalse,
      );
      expect(
        isValidContentRangeResponse(
          requestedOffset: 100,
          contentRange: 'bytes 100-999/1000',
          contentLength: 899,
        ),
        isFalse,
      );
      expect(
        isValidContentRangeResponse(
          requestedOffset: 100,
          contentRange: 'bytes 100-199/*',
          contentLength: 100,
        ),
        isFalse,
      );
      // An open-ended request must receive the complete remainder, not a
      // smaller 206 segment that could be mistaken for a finished file.
      expect(
        isValidContentRangeResponse(
          requestedOffset: 100,
          contentRange: 'bytes 100-199/1000',
          contentLength: 100,
        ),
        isFalse,
      );
      expect(
        isValidContentRangeResponse(
          requestedOffset: 0,
          contentRange: 'bytes 0-999/1000',
          contentLength: 1000,
        ),
        isTrue,
      );
    });
  });

  group('stream identity', () {
    test('uses stable format codec and bitrate, not expiring URL data', () {
      expect(
        audioStreamFingerprint(const {
          'streamUrl': 'https://r1.googlevideo.com/a?expire=123',
          'format': 'm4a',
          'codec': 'mp4a.40.2',
          'bitrate': 128000,
        }),
        'm4a|mp4a.40.2|128000',
      );
      expect(
        audioStreamFingerprint(const {
          'streamUrl': 'https://r2.googlevideo.com/b?expire=999',
          'format': 'm4a',
          'codec': 'mp4a.40.2',
          'bitrate': 128000,
        }),
        audioStreamFingerprint(const {
          'streamUrl': 'https://r3.googlevideo.com/c',
          'format': 'm4a',
          'codec': 'mp4a.40.2',
          'bitrate': 128000,
        }),
      );
      expect(
        audioStreamFingerprint(const {'format': 'webm', 'codec': 'opus', 'bitrate': 96000}),
        isNot(audioStreamFingerprint(const {'format': 'm4a', 'codec': 'aac', 'bitrate': 128000})),
      );
      expect(audioStreamFingerprint(const <String, dynamic>{}), isEmpty);
    });
  });

  group('audio file validation', () {
    test('recognizes common audio container signatures', () {
      expect(detectAudioFileExtension([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70, 0x4d, 0x34, 0x41, 0x20]), 'm4a');
      expect(detectAudioFileExtension([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]), isNull);
      expect(detectAudioFileExtension([0x1a, 0x45, 0xdf, 0xa3]), 'webm');
      expect(detectAudioFileExtension([0x4f, 0x67, 0x67, 0x53]), 'ogg');
      expect(detectAudioFileExtension([0x66, 0x4c, 0x61, 0x43]), 'flac');
      expect(detectAudioFileExtension([0x49, 0x44, 0x33]), 'mp3');
      expect(detectAudioFileExtension([0xff, 0xf1]), 'aac');
    });

    test('rejects HTML and JSON payloads', () {
      expect(detectAudioFileExtension('<html>'.codeUnits), isNull);
      expect(detectAudioFileExtension('{"error":true}'.codeUnits), isNull);
    });

    test('rejects non-audio MIME types', () {
      expect(isPlausibleAudioContentType('audio/mp4'), isTrue);
      expect(isPlausibleAudioContentType('application/octet-stream'), isTrue);
      expect(isPlausibleAudioContentType('text/html'), isFalse);
      expect(isPlausibleAudioContentType('application/json'), isFalse);
      expect(isPlausibleAudioContentType('application/vnd.apple.mpegurl'), isFalse);
    });
  });
}
