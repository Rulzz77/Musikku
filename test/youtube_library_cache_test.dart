import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/models/youtube_account_models.dart';
import 'package:flutter_application_5/services/youtube_library_cache.dart';

YoutubeSearchResult _video(String id) => YoutubeSearchResult(
      videoId: id,
      title: 'Track $id',
      channelTitle: 'MusikKu Test',
      thumbnailUrl: 'https://example.test/$id.jpg',
      categoryId: '10',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('YoutubeLibraryCache', () {
    test('round-trips all library sections for one normalized account', () async {
      const cache = YoutubeLibraryCache();
      await cache.saveSubscriptions(' MUSIC@example.com ', const [
        YoutubeChannelSummary(
          id: 'channel-1',
          title: 'Channel One',
          description: 'Music',
          thumbnailUrl: 'https://example.test/channel.jpg',
          uploadsPlaylistId: 'uploads-1',
          subscriberCount: 123,
        ),
      ]);
      await cache.saveLikedVideos('music@example.com', [_video('liked-1')]);
      await cache.savePlaylists('music@example.com', const [
        YoutubePlaylistSummary(
          id: 'playlist-1',
          title: 'Favorites',
          description: 'Favorite songs',
          privacyStatus: 'private',
          itemCount: 7,
          thumbnailUrl: 'https://example.test/playlist.jpg',
        ),
      ]);
      await cache.saveFeed('music@example.com', [_video('feed-1')]);

      final snapshot = await cache.load('music@example.com');

      expect(snapshot.hasData, isTrue);
      expect(snapshot.subscriptions?.single.id, 'channel-1');
      expect(snapshot.subscriptions?.single.subscriberCount, 123);
      expect(snapshot.likedVideos?.single.videoId, 'liked-1');
      expect(snapshot.playlists?.single.id, 'playlist-1');
      expect(snapshot.feed?.single.videoId, 'feed-1');
      expect(snapshot.updatedAt, isNotNull);
    });

    test('keeps cached data isolated between accounts', () async {
      const cache = YoutubeLibraryCache();
      await cache.saveLikedVideos('a@example.com', [_video('a-liked')]);
      await cache.saveLikedVideos('b@example.com', [_video('b-liked')]);

      final accountA = await cache.load('a@example.com');
      final accountB = await cache.load('b@example.com');

      expect(accountA.likedVideos?.single.videoId, 'a-liked');
      expect(accountB.likedVideos?.single.videoId, 'b-liked');
      expect((await cache.load('missing@example.com')).hasData, isFalse);
    });

    test('clears only the requested account', () async {
      const cache = YoutubeLibraryCache();
      await cache.saveLikedVideos('a@example.com', [_video('a-liked')]);
      await cache.saveLikedVideos('b@example.com', [_video('b-liked')]);

      await cache.clear('a@example.com');

      expect((await cache.load('a@example.com')).hasData, isFalse);
      expect(
        (await cache.load('b@example.com')).likedVideos?.single.videoId,
        'b-liked',
      );
    });

    test('returns a safe snapshot for a corrupted field', () async {
      const cache = YoutubeLibraryCache();
      final prefs = await SharedPreferences.getInstance();
      // This key is the legacy v1 format that the new service intentionally
      // preserves for upgrade compatibility.
      await prefs.setString('youtube_hub_cache_v1_bXVzaWNAZXhhbXBsZS5jb20_liked', '{bad json');

      final snapshot = await cache.load('music@example.com');

      expect(snapshot.hasData, isTrue);
      expect(snapshot.likedVideos, isEmpty);
    });
  });
}
