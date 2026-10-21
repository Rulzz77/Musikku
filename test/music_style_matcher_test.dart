import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/music_style_matcher.dart';

YoutubeSearchResult _video({
  required String id,
  required String title,
  required String channel,
  String description = '',
}) {
  return YoutubeSearchResult(
    videoId: id,
    title: title,
    channelTitle: channel,
    thumbnailUrl: '',
    description: description,
  );
}

void main() {
  group('MusicStyleMatcher cross-language Radio recommendations', () {
    test('detects English artist but keeps track Radio seed language-neutral', () {
      final song = _video(
        id: 'english-1',
        title: 'Anti-Hero',
        channel: 'Taylor Swift',
      );

      expect(MusicStyleMatcher.languageFromVideo(song), 'english');
      expect(MusicStyleMatcher.styleFromVideo(song), 'pop');
      expect(
        MusicStyleMatcher.recommendationSeedFor(song),
        'popular pop songs',
      );
    });

    test('detects Indonesian songs from known artist and title', () {
      final song = _video(
        id: 'indo-1',
        title: 'Hati-Hati di Jalan',
        channel: 'Tulus',
      );

      expect(MusicStyleMatcher.languageFromVideo(song), 'indonesian');
      expect(MusicStyleMatcher.recommendationSeedFor(song), 'popular pop songs');
    });

    test('Pop DJ is a related style to Pop', () {
      final song = _video(
        id: 'dj-1',
        title: 'Pop DJ Remix 2026',
        channel: 'DJ Music',
      );

      expect(MusicStyleMatcher.styleFromVideo(song), 'pop_dj');
      expect(MusicStyleMatcher.isCompatible(
        video: song,
        targetStyle: 'pop',
        targetLanguage: null,
      ), isTrue);
    });

    test('known Indonesian tracks do not cross into English-language radio', () {
      final song = _video(
        id: 'indo-2',
        title: 'Hati-Hati di Jalan',
        channel: 'Tulus',
      );

      expect(MusicStyleMatcher.isCompatible(
        video: song,
        targetStyle: 'pop',
        targetLanguage: 'english',
      ), isFalse);
    });


    test('K-pop is a style hint, not automatically an explicit language lock', () {
      expect(MusicStyleMatcher.hasExplicitLanguageFilter('K-pop playlist'), isFalse);
      expect(MusicStyleMatcher.hasExplicitLanguageFilter('lagu Inggris'), isTrue);
    });

    test('Radio can mix connected songs across languages', () {
      final englishPop = _video(
        id: 'english-pop',
        title: 'Popular English Pop Song',
        channel: 'Taylor Swift',
      );
      final indonesianPop = _video(
        id: 'indonesian-pop',
        title: 'Pop Indonesia Populer',
        channel: 'Armada',
      );

      // Explicit language filtering remains strict by default.
      expect(MusicStyleMatcher.isCompatible(
        video: indonesianPop,
        targetStyle: 'pop',
        targetLanguage: 'english',
      ), isFalse);

      // Automatic Radio softens language and keeps a genre-compatible result.
      expect(MusicStyleMatcher.isCompatible(
        video: indonesianPop,
        targetStyle: 'pop',
        targetLanguage: 'english',
        allowCrossLanguage: true,
      ), isTrue);
      final ranked = MusicStyleMatcher.rankForRadio(
        [englishPop, indonesianPop],
        targetStyle: 'pop',
        targetLanguage: 'english',
        allowCrossLanguage: true,
      );
      expect(ranked.map((video) => video.videoId).toSet(),
          {'english-pop', 'indonesian-pop'});
    });

    test('radio style score allows a related track in another language', () {
      final englishPop = _video(
        id: 'english-pop-score',
        title: 'Popular English Pop Song',
        channel: 'Taylor Swift',
      );
      final indonesianPop = _video(
        id: 'indonesian-pop-score',
        title: 'Pop Indonesia Populer',
        channel: 'Armada',
      );

      expect(MusicStyleMatcher.isCompatible(
        video: indonesianPop,
        targetStyle: 'pop',
        targetLanguage: 'english',
        allowCrossLanguage: true,
      ), isTrue);
      expect(
        MusicStyleMatcher.radioSimilarityScore(
          video: indonesianPop,
          targetStyle: 'pop',
          targetLanguage: 'english',
        ),
        greaterThan(30),
      );
      expect(
        MusicStyleMatcher.radioSimilarityScore(
          video: englishPop,
          targetStyle: 'pop',
          targetLanguage: 'english',
        ),
        greaterThan(
          MusicStyleMatcher.radioSimilarityScore(
            video: indonesianPop,
            targetStyle: 'pop',
            targetLanguage: 'english',
          ),
        ),
      );
    });

    test('track-based Radio seed does not hard-code its language', () {
      final song = _video(
        id: 'english-track',
        title: 'Anti-Hero',
        channel: 'Taylor Swift',
      );
      expect(MusicStyleMatcher.recommendationSeedFor(song), 'popular pop songs');
    });

    test('an explicit broad language/genre query becomes a stable seed', () {
      expect(MusicStyleMatcher.hasExplicitStyleHint('Pop DJ Inggris'), isTrue);
      expect(MusicStyleMatcher.hasExplicitLanguageHint('Pop DJ Inggris'), isTrue);
      expect(
        MusicStyleMatcher.recommendationSeed(
          style: MusicStyleMatcher.styleFromText('Pop DJ Inggris'),
          language: MusicStyleMatcher.languageFromText('Pop DJ Inggris'),
        ),
        'popular English pop DJ remix songs',
      );
    });
  });
}
