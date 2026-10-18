import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/youtube_search_result.dart';
import '../models/youtube_account_models.dart';
import 'youtube_library_api.dart';
import 'youtube_library_cache.dart';


/// A partial result from a YouTube library refresh. Exactly one field is
/// normally populated, allowing the UI to render independent sections early.
class YoutubeLibraryUpdate {
  const YoutubeLibraryUpdate({
    this.subscriptions,
    this.likedVideos,
    this.playlists,
    this.feed,
  });

  final List<YoutubeChannelSummary>? subscriptions;
  final List<YoutubeSearchResult>? likedVideos;
  final List<YoutubePlaylistSummary>? playlists;
  final List<YoutubeSearchResult>? feed;
}

/// Repository boundary between UI and the Google/YouTube account APIs.
///
/// It owns request orchestration and persistence. Subscription, liked-video,
/// and playlist calls run concurrently; the subscription feed starts as soon
/// as the channel list is ready.
class YoutubeLibraryRepository {
  factory YoutubeLibraryRepository({
    required YoutubeLibraryApi account,
    YoutubeLibraryCache? cache,
  }) {
    return YoutubeLibraryRepository._(account, cache);
  }

  YoutubeLibraryRepository._(
    this._account,
    YoutubeLibraryCache? cache,
  ) : _cache = cache ?? const YoutubeLibraryCache();

  final YoutubeLibraryApi _account;
  final YoutubeLibraryCache _cache;
  final Map<String, int> _accountGenerations = <String, int>{};
  final Map<String, Future<void>> _cacheOperationTails =
      <String, Future<void>>{};

  String _identity(String email) => email.trim().toLowerCase();

  int _generationFor(String email) => _accountGenerations[_identity(email)] ?? 0;

  Future<YoutubeLibrarySnapshot> loadCached(String email) => _cache.load(email);

  Future<void> _enqueueCacheOperation(
    String email,
    Future<void> Function() operation,
  ) {
    final key = _identity(email);
    final previous = _cacheOperationTails[key] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => operation());
    _cacheOperationTails[key] = next;
    // Keep only in-flight operations; completed accounts should not accumulate
    // completed Future objects for the lifetime of the repository.
    unawaited(next.then<void>(
      (_) {
        if (identical(_cacheOperationTails[key], next)) {
          _cacheOperationTails.remove(key);
        }
      },
      onError: (Object _) {
        if (identical(_cacheOperationTails[key], next)) {
          _cacheOperationTails.remove(key);
        }
      },
    ));
    return next;
  }

  Future<void> _saveIfCurrent(
    String email,
    int generation,
    Future<void> Function() save, {
    bool Function()? isStillActive,
  }) {
    return _enqueueCacheOperation(email, () async {
      if (generation != _generationFor(email) ||
          !(isStillActive?.call() ?? true)) {
        return;
      }
      await save();
    });
  }

  Stream<YoutubeLibraryUpdate> refresh(
    String email, {
    bool Function()? isStillActive,
  }) {
    if (email.trim().isEmpty) return const Stream<YoutubeLibraryUpdate>.empty();

    final requestGeneration = _generationFor(email);
    bool isCurrent() =>
        requestGeneration == _generationFor(email) &&
        (isStillActive?.call() ?? true);
    final controller = StreamController<YoutubeLibraryUpdate>();
    final tasks = <Future<void>>[];

    Future<void> runSafely(String label, Future<void> Function() work) async {
      try {
        await work();
      } catch (error) {
        debugPrint('YOUTUBE LIBRARY REPOSITORY ($label): $error');
      }
    }

    tasks.add(runSafely('subscriptions', () async {
      final subscriptions = await _account.subscriptions();
      if (!isCurrent()) return;
      await _saveIfCurrent(
        email, requestGeneration, () => _cache.saveSubscriptions(email, subscriptions),
        isStillActive: isStillActive,
      );
      if (isCurrent() && !controller.isClosed) {
        controller.add(YoutubeLibraryUpdate(subscriptions: subscriptions));
      }
      if (subscriptions.isEmpty || !isCurrent()) return;

      final feed = await _account.subscriptionFeed(subscriptions);
      if (!isCurrent()) return;
      await _saveIfCurrent(
        email, requestGeneration, () => _cache.saveFeed(email, feed),
        isStillActive: isStillActive,
      );
      if (isCurrent() && !controller.isClosed) {
        controller.add(YoutubeLibraryUpdate(feed: feed));
      }
    }));

    tasks.add(runSafely('liked videos', () async {
      final liked = await _account.likedVideos();
      if (!isCurrent()) return;
      await _saveIfCurrent(
        email, requestGeneration, () => _cache.saveLikedVideos(email, liked),
        isStillActive: isStillActive,
      );
      if (isCurrent() && !controller.isClosed) {
        controller.add(YoutubeLibraryUpdate(likedVideos: liked));
      }
    }));

    tasks.add(runSafely('playlists', () async {
      final playlists = await _account.playlists();
      if (!isCurrent()) return;
      await _saveIfCurrent(
        email, requestGeneration, () => _cache.savePlaylists(email, playlists),
        isStillActive: isStillActive,
      );
      if (isCurrent() && !controller.isClosed) {
        controller.add(YoutubeLibraryUpdate(playlists: playlists));
      }
    }));

    unawaited(Future.wait<void>(tasks).whenComplete(() => controller.close()));
    return controller.stream;
  }

  Future<List<YoutubeSearchResult>> refreshFeed(
    String email,
    List<YoutubeChannelSummary> subscriptions, {
    bool Function()? isStillActive,
  }) async {
    if (email.trim().isEmpty || subscriptions.isEmpty) {
      return const <YoutubeSearchResult>[];
    }
    final requestGeneration = _generationFor(email);
    final feed = await _account.subscriptionFeed(subscriptions);
    final stillCurrent = requestGeneration == _generationFor(email) &&
        (isStillActive?.call() ?? true);
    if (!stillCurrent) return const <YoutubeSearchResult>[];
    await _saveIfCurrent(
      email, requestGeneration, () => _cache.saveFeed(email, feed),
      isStillActive: isStillActive,
    );
    if (requestGeneration != _generationFor(email) ||
        !(isStillActive?.call() ?? true)) {
      return const <YoutubeSearchResult>[];
    }
    return feed;
  }

  Future<List<YoutubeSearchResult>> loadPlaylistItems(String playlistId) =>
      _account.playlistItems(playlistId);

  Future<void> clearCached(String email) async {
    if (email.trim().isEmpty) return;
    final key = _identity(email);
    _accountGenerations[key] = (_accountGenerations[key] ?? 0) + 1;
    await _enqueueCacheOperation(email, () => _cache.clear(email));
  }
}
