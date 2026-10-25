import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/music_style_matcher.dart';
import 'package:flutter_application_5/services/radio_service.dart';
import 'package:flutter_application_5/services/playback_source_policy.dart';
import 'package:flutter_application_5/services/youtube_search_service.dart';

YoutubeSearchResult _video({
  required String id,
  required String title,
  required String channel,
  String description = '',
  int? viewCount,
  DateTime? publishedAt,
}) {
  return YoutubeSearchResult(
    videoId: id,
    title: title,
    channelTitle: channel,
    thumbnailUrl: '',
    description: description,
    viewCount: viewCount,
    publishedAt: publishedAt,
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
        'anti-hero taylor swift similar songs',
      );
    });

    test('detects Indonesian songs from known artist and title', () {
      final song = _video(
        id: 'indo-1',
        title: 'Hati-Hati di Jalan',
        channel: 'Tulus',
      );

      expect(MusicStyleMatcher.languageFromVideo(song), 'indonesian');
      expect(
        MusicStyleMatcher.recommendationSeedFor(song),
        'hati-hati di jalan tulus similar songs',
      );
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

    test('Radio prefers recognized compatible styles over unknown metadata when available', () {
      final englishPop = _video(
        id: 'known-pop-en',
        title: 'Popular English Pop Song',
        channel: 'Taylor Swift',
      );
      final indonesianPop = _video(
        id: 'known-pop-id',
        title: 'Pop Indonesia Populer',
        channel: 'Armada',
      );
      final unknownStyle = _video(
        id: 'unknown-style',
        title: 'A Song With No Recognized Genre',
        channel: 'Unknown Artist',
      );

      final ranked = MusicStyleMatcher.rankForRadio(
        [unknownStyle, englishPop, indonesianPop],
        targetStyle: 'pop',
        allowCrossLanguage: true,
      );

      expect(ranked.map((video) => video.videoId).toSet(),
          {'known-pop-en', 'known-pop-id'});
    });

    test('Radio excludes unknown styles when a known related style is available', () {
      final knownPop = _video(
        id: 'one-known-pop',
        title: 'Popular Pop Song',
        channel: 'Unknown Artist',
      );
      final unknownStyle = _video(
        id: 'one-unknown-style',
        title: 'A Song With No Recognized Genre',
        channel: 'Unknown Artist',
      );

      final ranked = MusicStyleMatcher.rankForRadio(
        [unknownStyle, knownPop],
        targetStyle: 'pop',
        allowCrossLanguage: true,
      );

      expect(ranked.map((video) => video.videoId).toSet(),
          {'one-known-pop'});
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

    test('Radio keeps YouTube relevance order when compatibility scores tie', () {
      final first = _video(
        id: 'relevance-first',
        title: 'Connected Pop Song One',
        channel: 'Armada',
      );
      final second = _video(
        id: 'relevance-second',
        title: 'Connected Pop Song Two',
        channel: 'Armada',
      );
      final ranked = MusicStyleMatcher.rankForRadio(
        [first, second],
        targetStyle: 'pop',
      );
      expect(ranked.map((video) => video.videoId), [
        'relevance-first',
        'relevance-second',
      ]);
    });

    test('Radio relevance score ignores raw view-count popularity', () {
      final lowViews = _video(
        id: 'low-views',
        title: 'Connected Pop Song',
        channel: 'Armada',
        viewCount: 100,
      );
      final highViews = _video(
        id: 'high-views',
        title: 'Connected Pop Song',
        channel: 'Armada',
        viewCount: 90000000,
      );
      expect(
        MusicStyleMatcher.radioSimilarityScore(
          video: lowViews,
          targetStyle: 'pop',
        ),
        MusicStyleMatcher.radioSimilarityScore(
          video: highViews,
          targetStyle: 'pop',
        ),
      );
    });

    test('track-based Radio seed is tied to current title and artist', () {
      final song = _video(
        id: 'english-track',
        title: 'Anti-Hero',
        channel: 'Taylor Swift',
      );
      final seed = MusicStyleMatcher.recommendationSeedFor(song);
      expect(seed, 'anti-hero taylor swift similar songs');
      expect(seed, isNot(contains('popular')));
    });

    test('song radio seed keeps the current title and artist for relevant Next', () {
      final song = _video(
        id: 'anti-hero',
        title: 'Anti-Hero (Official Music Video)',
        channel: 'Taylor Swift - Topic',
      );
      final seed = RadioService.songRadioSearchSeedFor(song);
      // Keep exact normalized output: uppercase initials must not be lost
      // while stripping the YouTube "- Topic" channel suffix.
      expect(seed, 'anti-hero taylor swift similar songs');
      expect(seed, contains('anti-hero'));
      expect(seed, contains('taylor swift'));
      expect(seed, contains('similar songs'));
      expect(seed, isNot(contains('popular pop songs')));
    });

    test('large radio pools do not dilute one known matching style with unknowns', () {
      final knownPop = _video(
        id: 'known-pop',
        title: 'Pop Ballad Official Audio',
        channel: 'Unknown Artist',
      );
      final unknown = List<YoutubeSearchResult>.generate(
        8,
        (index) => _video(
          id: 'unknown-$index',
          title: 'Track With Unrecognized Metadata $index',
          channel: 'Unknown Channel $index',
        ),
      );

      final ranked = MusicStyleMatcher.rankForRadio(
        [knownPop, ...unknown],
        targetStyle: 'pop',
        allowCrossLanguage: true,
      );
      expect(ranked.map((video) => video.videoId), ['known-pop']);
    });

    test('an explicit broad language/genre query becomes a stable seed', () {
      expect(MusicStyleMatcher.hasExplicitStyleHint('Pop DJ Inggris'), isTrue);
      expect(MusicStyleMatcher.hasExplicitLanguageHint('Pop DJ Inggris'), isTrue);
      expect(
        MusicStyleMatcher.recommendationSeed(
          style: MusicStyleMatcher.styleFromText('Pop DJ Inggris'),
          language: MusicStyleMatcher.languageFromText('Pop DJ Inggris'),
        ),
        'English pop DJ remix songs similar',
      );
    });
  });

  group('Playback source isolation', () {
    test('explicit playlist preserves order and mixed local/YouTube sources', () {
      final remoteOne = _video(id: 'remote-1', title: 'Remote Song', channel: 'Artist A');
      final localOne = YoutubeSearchResult(
        videoId: 'local:local-one',
        title: 'Local Song',
        channelTitle: 'Local files',
        thumbnailUrl: '',
        sourceType: 'local',
        mediaUri: 'file:///music/local-one.mp3',
      );
      final remoteTwo = _video(id: 'remote-2', title: 'Remote Song 2', channel: 'Artist B');
      final items = PlaybackSourcePolicy.explicitPlaylistItems([
        remoteOne,
        localOne,
        remoteTwo,
        remoteOne,
      ]);

      expect(items.map((item) => item.videoId), [
        'remote-1',
        'local:local-one',
        'remote-2',
      ]);
      expect(items.map((item) => item.isLocal), [false, true, false]);
    });
  });

  group('RadioService no-repeat history', () {
    test('filters a played video ID and alternate upload of the same song', () {
      final radio = RadioService(
        YoutubeSearchService(),
        currentVideoId: () => null,
      );
      final played = _video(
        id: 'anti-hero-original',
        title: 'Anti-Hero (Official Music Video)',
        channel: 'Taylor Swift',
      );
      final alternateUpload = _video(
        id: 'anti-hero-reupload',
        title: 'Anti-Hero - Taylor Swift (Official Audio)',
        channel: 'Taylor Swift Topic',
      );
      final differentSong = _video(
        id: 'cruel-summer',
        title: 'Cruel Summer (Official Audio)',
        channel: 'Taylor Swift',
      );

      radio.markPlayed(played);
      expect(radio.wasPlayedRecently(played), isTrue);
      expect(radio.wasPlayedRecently(alternateUpload), isTrue);
      expect(radio.wasPlayedRecently(differentSong), isFalse);
      radio.dispose();
    });

    test('fallback candidate list excludes played songs and duplicate uploads', () {
      final radio = RadioService(
        YoutubeSearchService(),
        currentVideoId: () => null,
      );
      final played = _video(
        id: 'played-1',
        title: 'Anti-Hero (Official Music Video)',
        channel: 'Taylor Swift',
      );
      final playedAlternate = _video(
        id: 'played-reupload',
        title: 'Anti-Hero - Taylor Swift (Official Audio)',
        channel: 'Taylor Swift Topic',
      );
      final fresh = _video(
        id: 'fresh-song',
        title: 'Cruel Summer (Official Audio)',
        channel: 'Taylor Swift',
      );
      final freshAlternate = _video(
        id: 'fresh-song-reupload',
        title: 'Cruel Summer - Taylor Swift (Official Music Video)',
        channel: 'Taylor Swift Topic',
      );

      radio.markPlayed(played);
      final filtered = radio.filterUnplayedCandidates([
        played,
        playedAlternate,
        fresh,
        freshAlternate,
      ]);

      expect(filtered.map((video) => video.videoId), ['fresh-song']);
      expect(
        radio.filterUnplayedCandidates([played, playedAlternate]),
        isEmpty,
        reason: 'Radio must stop gracefully instead of replaying stale tracks.',
      );
      radio.dispose();
    });
  });

}
