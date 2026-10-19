import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/youtube_music_policy.dart';

void main() {
  YoutubeSearchResult video({
    String title = 'Contoh Lagu Resmi',
    String channelTitle = 'Penyanyi Resmi',
    String categoryId = '10',
    String sourceType = 'youtube',
  }) {
    return YoutubeSearchResult(
      videoId: 'video-test-001',
      title: title,
      channelTitle: channelTitle,
      thumbnailUrl: '',
      categoryId: categoryId,
      sourceType: sourceType,
    );
  }

  group('YoutubeMusicPolicy.isMusicCatalogItem', () {
    test('accepts a music-category upload with ordinary song metadata', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(),
          requireCategoryId: true,
        ),
        isTrue,
      );
    });

    test('rejects a missing category when verification is required', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(categoryId: ''),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('rejects obvious Shorts labels', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(title: 'Lagu viral #Shorts'),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('rejects obvious non-music uploads', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(title: 'Interview dengan artis'),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('matches non-music labels as words instead of broad substrings', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(title: 'Newsboys - He Reigns', channelTitle: 'Newsboys Official'),
          requireCategoryId: true,
        ),
        isTrue,
      );
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(title: 'Podcast interview bersama penyanyi'),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('does not reject local music because it has no YouTube category', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(categoryId: '', sourceType: 'local'),
          requireCategoryId: true,
        ),
        isTrue,
      );
    });
  });
  group('YoutubeMusicPolicy.classifyShortsProbeStatus', () {
    test('requires page metadata for a 200 response', () {
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(200), isNull);
    });

    test('classifies explicit redirect targets and leaves unknown targets ambiguous', () {
      expect(
        YoutubeMusicPolicy.classifyShortsProbeStatus(302, location: 'https://www.youtube.com/watch?v=abc'),
        isFalse,
      );
      expect(
        YoutubeMusicPolicy.classifyShortsProbeStatus(303, location: '/shorts/abc'),
        isTrue,
      );
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(302), isNull);
    });

    test('leaves throttled and error responses ambiguous', () {
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(403), isNull);
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(405), isNull);
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(429), isNull);
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(503), isNull);
    });

    test('uses a canonical Shorts route when the response status is 200', () {
      expect(
        YoutubeMusicPolicy.classifyShortsPageHtml(
          '<link rel="canonical" href="https://www.youtube.com/shorts/abc123">',
        ),
        isTrue,
      );
    });

    test('keeps ordinary watch pages when canonical route says watch', () {
      expect(
        YoutubeMusicPolicy.classifyShortsPageHtml(
          '<link rel="canonical" href="https://www.youtube.com/watch?v=abc123">',
        ),
        isFalse,
      );
    });

    test('leaves HTML without route metadata ambiguous', () {
      expect(YoutubeMusicPolicy.classifyShortsPageHtml('<html>blocked</html>'), isNull);
    });
  });

}
