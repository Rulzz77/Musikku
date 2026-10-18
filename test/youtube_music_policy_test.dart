import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/youtube_music_policy.dart';

YoutubeSearchResult video({
  String title = 'Judul lagu',
  String channel = 'Artis resmi',
  String category = '10',
  String sourceType = 'youtube',
  String videoId = 'video-1',
}) => YoutubeSearchResult(
      videoId: videoId,
      title: title,
      channelTitle: channel,
      thumbnailUrl: '',
      categoryId: category,
      sourceType: sourceType,
    );

void main() {
  group('YoutubeMusicPolicy', () {
    test('accepts normal category-10 tracks', () {
      final track = video();

      expect(YoutubeMusicPolicy.isMusicCandidate(track), isTrue);
      expect(YoutubeMusicPolicy.isMusicCatalogItem(track, requireCategoryId: true), isTrue);
    });

    test('rejects Shorts and obvious non-music uploads', () {
      final short = video(title: 'DJ Remix #Shorts');
      final podcast = video(title: 'Podcast interview artis');

      expect(YoutubeMusicPolicy.isLikelyShortForm(short), isTrue);
      expect(YoutubeMusicPolicy.isMusicCatalogItem(short), isFalse);
      expect(YoutubeMusicPolicy.isLikelyNonMusicVideo(podcast), isTrue);
      expect(YoutubeMusicPolicy.isMusicCandidate(podcast), isFalse);
    });

    test('requires category 10 only when requested and always accepts local tracks', () {
      final otherCategory = video(category: '22');
      final local = video(category: '22', sourceType: 'local', videoId: 'local:42');

      expect(YoutubeMusicPolicy.isMusicCatalogItem(otherCategory), isFalse);
      expect(YoutubeMusicPolicy.isMusicCatalogItem(local, requireCategoryId: true), isTrue);
    });
  });
}
