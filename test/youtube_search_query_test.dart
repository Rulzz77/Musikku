import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/youtube_search_query.dart';

void main() {
  group('YoutubeSearchQueryParser', () {
    test('adds Indonesia context to music queries and detects latest intent', () {
      final intent = YoutubeSearchQueryParser.interpret('  lagu dangdut terbaru  ');

      expect(intent.originalQuery, 'lagu dangdut terbaru');
      expect(intent.apiQuery, 'lagu dangdut terbaru Indonesia');
      expect(intent.musicContext, isTrue);
      expect(intent.latest, isTrue);
      expect(intent.label, 'musik • terbaru • Indonesia');
    });

    test('does not rewrite ordinary non-music queries', () {
      final intent = YoutubeSearchQueryParser.interpret('Taylor Swift');

      expect(intent.originalQuery, 'Taylor Swift');
      expect(intent.apiQuery, 'Taylor Swift');
      expect(intent.musicContext, isFalse);
      expect(intent.latest, isFalse);
      expect(intent.label, 'pencarian biasa');
    });

    test('does not duplicate Indonesia for an explicit Indonesia query', () {
      final intent = YoutubeSearchQueryParser.interpret('lagu pop Indonesia terbaru');

      expect(intent.apiQuery, 'lagu pop Indonesia terbaru');
      expect(intent.apiQuery.toLowerCase().split('indonesia').length - 1, 1);
    });
  });
}
