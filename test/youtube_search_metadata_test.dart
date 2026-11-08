import 'package:flutter_application_5/services/youtube_search_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('youtube_explode search metadata parsing', () {
    test('parses SearchVideo duration in MM:SS and HH:MM:SS forms', () {
      expect(YoutubeSearchMetadata.parseDurationSeconds('4:32'), 272);
      expect(YoutubeSearchMetadata.parseDurationSeconds('1:02:03'), 3723);
      expect(YoutubeSearchMetadata.parseDurationSeconds('00:31'), 31);
      expect(YoutubeSearchMetadata.parseDurationSeconds('15:00'), 900);
      expect(YoutubeSearchMetadata.parseDurationSeconds('15:01'), 901);
      expect(YoutubeSearchMetadata.parseDurationSeconds('LIVE'), isNull);
    });

    test('preserves direct SearchVideo viewCount values', () {
      expect(YoutubeSearchMetadata.parseViewCount(1250000), 1250000);
      expect(YoutubeSearchMetadata.parseViewCount('1.2M views'), 1200000);
      expect(YoutubeSearchMetadata.parseViewCount('85.4K'), 85400);
      expect(YoutubeSearchMetadata.parseViewCount('unknown'), isNull);
    });

    test('parses relative YouTube upload dates', () {
      final now = DateTime.utc(2026, 11, 8, 12);
      expect(
        YoutubeSearchMetadata.parseRelativeUploadDate('2 weeks ago', now: now),
        DateTime.utc(2026, 10, 25, 12),
      );
      expect(
        YoutubeSearchMetadata.parseRelativeUploadDate('3 hari yang lalu', now: now),
        DateTime.utc(2026, 11, 5, 12),
      );
    });
  });
}
