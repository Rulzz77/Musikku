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
}
