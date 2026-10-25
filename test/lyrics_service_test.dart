import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/lyrics_service.dart';

void main() {
  group('LyricsService.parseSyncedLyrics', () {
    test('expands multiple timestamps on one LRC line', () {
      final lines = LyricsService.parseSyncedLyrics(
        '[ar:Artist]\n[ti:Track]\n[00:01.20][00:03.40]Hello there\n[00:05.5]Goodbye',
      );

      expect(lines, hasLength(3));
      expect(lines[0].time, const Duration(milliseconds: 1200));
      expect(lines[1].time, const Duration(milliseconds: 3400));
      expect(lines[0].text, 'Hello there');
      expect(lines[1].text, 'Hello there');
      expect(lines[2].time, const Duration(milliseconds: 5500));
      expect(lines[2].text, 'Goodbye');
    });

    test('sorts timestamps and skips metadata and empty lines', () {
      final lines = LyricsService.parseSyncedLyrics(
        '[ti:Track]\n[00:04.00]Second\n[00:02.00]First\n[00:01.00]\nplain text',
      );

      expect(lines, hasLength(2));
      expect(lines.first.text, 'First');
      expect(lines.last.text, 'Second');
    });

    test('applies a positive LRC offset in milliseconds', () {
      final lines = LyricsService.parseSyncedLyrics(
        '[offset:500]\n[00:01.20]Later',
      );
      expect(lines.single.time, const Duration(milliseconds: 1700));
    });

    test('clamps timestamps below zero after a negative LRC offset', () {
      final lines = LyricsService.parseSyncedLyrics(
        '[offset:-250]\n[00:00.10]Earlier\n[00:01.00]Later',
      );
      expect(lines.first.time, Duration.zero);
      expect(lines.last.time, const Duration(milliseconds: 750));
    });
  });

  group('LyricsService.metadataMatchScoreForTesting', () {
    test('prefers exact track and artist metadata', () {
      expect(LyricsService.metadataMatchScoreForTesting('Kangen', 'Kangen'), 100);
      expect(LyricsService.metadataMatchScoreForTesting('Dewa 19', 'Dewa 19'), 100);
      expect(LyricsService.metadataMatchScoreForTesting('Kangen', 'Lagu Lain'), 0);
    });
  });
}
