import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/music_title_formatter.dart';

void main() {
  group('MusicTitleFormatter.clean', () {
    test('removes common bracketed YouTube metadata', () {
      expect(
        MusicTitleFormatter.clean("Iqro' (Official Music Video) [1080p]"),
        "Iqro'",
      );
    });

    test('removes trailing official audio label and decodes entities', () {
      expect(
        MusicTitleFormatter.clean('<b>Song &amp; Me</b> | Official Audio'),
        'Song & Me',
      );
    });

    test('removes lyric/video markup while retaining meaningful separators', () {
      expect(
        MusicTitleFormatter.clean('Guyon Waton - Wirang [Lirik Video]'),
        'Guyon Waton - Wirang',
      );
      expect(
        MusicTitleFormatter.clean('Denny Caknan feat. Rafiq - Laut Kidul | Crito Mustahil'),
        'Denny Caknan feat. Rafiq - Laut Kidul | Crito Mustahil',
      );
    });

    test('preserves meaningful version words and apostrophes', () {
      expect(MusicTitleFormatter.clean("Iqro' - Remix"), "Iqro' - Remix");
      expect(MusicTitleFormatter.clean("Iqro'"), "Iqro'");
      expect(MusicTitleFormatter.clean('Song (feat. Artist)'), 'Song (feat. Artist)');
    });

    test('removes promotional hashtags at the end only', () {
      expect(MusicTitleFormatter.clean('Song #shorts #viral'), 'Song');
    });
  });
}
