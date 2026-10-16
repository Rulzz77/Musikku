import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/radio_service.dart';
import 'package:flutter_application_5/services/youtube_search_service.dart';

YoutubeSearchResult song(String id) => YoutubeSearchResult(
      videoId: id,
      title: 'Track $id',
      channelTitle: 'Artist $id',
      thumbnailUrl: '',
    );

class _ControlledSearchService implements YoutubeSearchService {
  final List<Completer<RadioPage>> pending = <Completer<RadioPage>>[];
  final List<String> queries = <String>[];

  @override
  Future<RadioPage> searchLatest(String query, {String? pageToken}) {
    queries.add(query);
    final request = Completer<RadioPage>();
    pending.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('RadioService asynchronous refill', () {
    test('restart with the same seed discards old response and keeps new fetch registered', () async {
      final search = _ControlledSearchService();
      final radio = RadioService(
        search,
        currentVideoId: () => null,
      );

      radio.start('my mix');
      await Future<void>.delayed(Duration.zero);
      expect(search.pending, hasLength(1));

      radio.restart('my mix');
      final freshFetch = radio.refill();
      await Future<void>.delayed(Duration.zero);
      expect(search.pending, hasLength(2));

      // The old request finishes first even though the new request is active.
      search.pending[0].complete(RadioPage(
        results: <YoutubeSearchResult>[song('stale')],
        nextPageToken: 'stale-page',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(radio.poolLength, 0, reason: 'stale response must not enter the restarted pool');
      final joinedFetch = radio.refill();
      expect(identical(joinedFetch, freshFetch), isTrue,
          reason: 'old completion must not clear the new in-flight handle');
      expect(search.pending, hasLength(2), reason: 'no duplicate request should be started');

      search.pending[1].complete(RadioPage(
        results: <YoutubeSearchResult>[song('fresh')],
      ));
      await freshFetch;

      expect(radio.poolLength, 1);
      expect(radio.take(random: false)?.videoId, 'fresh');
      radio.dispose();
    });


    test('dispose invalidates an in-flight response', () async {
      final search = _ControlledSearchService();
      final radio = RadioService(
        search,
        currentVideoId: () => null,
      );

      radio.start('dispose mix');
      await Future<void>.delayed(Duration.zero);
      expect(search.pending, hasLength(1));
      final pendingFetch = radio.refill();

      radio.dispose();
      search.pending.single.complete(RadioPage(
        results: <YoutubeSearchResult>[song('after-dispose')],
      ));
      await pendingFetch;

      expect(radio.poolLength, 0,
          reason: 'a disposed radio must not accept a late response');
    });

    test('changing seed prevents a previous seed response from entering the pool', () async {
      final search = _ControlledSearchService();
      final radio = RadioService(
        search,
        currentVideoId: () => null,
      );

      radio.start('old mix');
      await Future<void>.delayed(Duration.zero);
      expect(search.pending, hasLength(1));

      radio.start('new mix');
      await Future<void>.delayed(Duration.zero);
      expect(search.pending, hasLength(2));

      search.pending[0].complete(RadioPage(
        results: <YoutubeSearchResult>[song('old')],
      ));
      await Future<void>.delayed(Duration.zero);
      expect(radio.poolLength, 0);

      search.pending[1].complete(RadioPage(
        results: <YoutubeSearchResult>[song('new')],
      ));
      // The new fetch was started by start(), so wait for its registered Future.
      await radio.refill();

      expect(radio.poolLength, 1);
      expect(radio.take(random: false)?.videoId, 'new');
      radio.dispose();
    });
  });
}
