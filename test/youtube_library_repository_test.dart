import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/models/youtube_account_models.dart';
import 'package:flutter_application_5/services/youtube_library_api.dart';
import 'package:flutter_application_5/services/youtube_library_cache.dart';
import 'package:flutter_application_5/services/youtube_library_repository.dart';

class _FakeYoutubeLibraryApi implements YoutubeLibraryApi {
  final calls = <String>[];
  final subscriptionsResult = Completer<List<YoutubeChannelSummary>>();
  final likedResult = Completer<List<YoutubeSearchResult>>();
  final playlistsResult = Completer<List<YoutubePlaylistSummary>>();
  final feedResult = Completer<List<YoutubeSearchResult>>();
  final feedRequested = Completer<void>();

  @override
  Future<List<YoutubeChannelSummary>> subscriptions({int maxResults = 50}) {
    calls.add('subscriptions');
    return subscriptionsResult.future;
  }

  @override
  Future<List<YoutubeSearchResult>> likedVideos({int maxResults = 50}) {
    calls.add('likedVideos');
    return likedResult.future;
  }

  @override
  Future<List<YoutubePlaylistSummary>> playlists({int maxResults = 50}) {
    calls.add('playlists');
    return playlistsResult.future;
  }

  @override
  Future<List<YoutubeSearchResult>> subscriptionFeed(
    List<YoutubeChannelSummary> channels, {
    int channelLimit = 20,
    int perChannel = 3,
  }) {
    calls.add('subscriptionFeed');
    if (!feedRequested.isCompleted) feedRequested.complete();
    return feedResult.future;
  }

  @override
  Future<List<YoutubeSearchResult>> playlistItems(
    String playlistId, {
    int maxResults = 50,
  }) async => <YoutubeSearchResult>[];
}

YoutubeSearchResult _video(String id) => YoutubeSearchResult(
      videoId: id,
      title: 'Track $id',
      channelTitle: 'MusikKu Test',
      thumbnailUrl: '',
      categoryId: '10',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('YoutubeLibraryRepository', () {
    test('starts independent library requests concurrently and emits partial updates', () async {
      final api = _FakeYoutubeLibraryApi();
      final repository = YoutubeLibraryRepository(
        account: api,
        cache: const YoutubeLibraryCache(),
      );
      final likedUpdateReceived = Completer<void>();
      final updates = <YoutubeLibraryUpdate>[];
      final done = Completer<void>();
      repository.refresh('music@example.com').listen((update) {
        updates.add(update);
        if (update.likedVideos != null && !likedUpdateReceived.isCompleted) {
          likedUpdateReceived.complete();
        }
      }, onDone: () => done.complete());

      expect(api.calls, containsAll(<String>['subscriptions', 'likedVideos', 'playlists']));
      expect(api.calls, isNot(contains('subscriptionFeed')));

      api.likedResult.complete(<YoutubeSearchResult>[_video('liked-1')]);
      await likedUpdateReceived.future.timeout(const Duration(seconds: 2));
      // Liked videos can render while the other independent endpoints remain
      // unresolved; the repository does not wait for a global Future.wait first.
      expect(api.subscriptionsResult.isCompleted, isFalse);
      expect(api.playlistsResult.isCompleted, isFalse);
      expect(updates.single.likedVideos?.single.videoId, 'liked-1');

      api.subscriptionsResult.complete(const <YoutubeChannelSummary>[
        YoutubeChannelSummary(
          id: 'channel-1',
          title: 'Channel',
          description: '',
          thumbnailUrl: '',
          uploadsPlaylistId: 'uploads-1',
        ),
      ]);
      await api.feedRequested.future.timeout(const Duration(seconds: 2));
      expect(api.calls, contains('subscriptionFeed'));
      api.playlistsResult.complete(const <YoutubePlaylistSummary>[
        YoutubePlaylistSummary(
          id: 'playlist-1',
          title: 'Playlist',
          description: '',
          privacyStatus: 'private',
          itemCount: 1,
        ),
      ]);
      api.feedResult.complete(<YoutubeSearchResult>[_video('feed-1')]);
      await done.future.timeout(const Duration(seconds: 2));

      expect(updates.any((item) => item.subscriptions != null), isTrue);
      expect(updates.any((item) => item.playlists != null), isTrue);
      expect(updates.any((item) => item.feed?.single.videoId == 'feed-1'), isTrue);
      final cache = await repository.loadCached('music@example.com');
      expect(cache.likedVideos?.single.videoId, 'liked-1');
      expect(cache.feed?.single.videoId, 'feed-1');
    });

    test('clearing account cache invalidates in-flight refresh results', () async {
      final api = _FakeYoutubeLibraryApi();
      final repository = YoutubeLibraryRepository(
        account: api,
        cache: const YoutubeLibraryCache(),
      );
      final updates = <YoutubeLibraryUpdate>[];
      final done = Completer<void>();
      repository.refresh('music@example.com').listen(
        updates.add,
        onDone: () => done.complete(),
      );

      await repository.clearCached('music@example.com');
      api.subscriptionsResult.complete(const <YoutubeChannelSummary>[
        YoutubeChannelSummary(
          id: 'channel-1',
          title: 'Channel',
          description: '',
          thumbnailUrl: '',
          uploadsPlaylistId: 'uploads-1',
        ),
      ]);
      api.likedResult.complete(<YoutubeSearchResult>[_video('liked-1')]);
      api.playlistsResult.complete(const <YoutubePlaylistSummary>[
        YoutubePlaylistSummary(
          id: 'playlist-1',
          title: 'Playlist',
          description: '',
          privacyStatus: 'private',
          itemCount: 1,
        ),
      ]);
      await done.future.timeout(const Duration(seconds: 2));

      expect(updates, isEmpty);
      expect((await repository.loadCached('music@example.com')).hasData, isFalse);
    });
  });
}
