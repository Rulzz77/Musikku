import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/queue_item.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/playback_source_policy.dart';
import 'package:flutter_application_5/services/queue_manager.dart';

YoutubeSearchResult song(String id) => YoutubeSearchResult(
      videoId: id,
      title: 'Track $id',
      channelTitle: 'MusikKu test',
      thumbnailUrl: '',
    );

YoutubeSearchResult localSong(String id) => YoutubeSearchResult(
      videoId: 'local:$id',
      title: 'Local $id',
      channelTitle: 'Local artist',
      thumbnailUrl: '',
      sourceType: 'local',
      localMediaId: id,
      mediaUri: 'content://media/$id',
    );

void main() {
  group('QueueManager', () {
    test('rejects duplicate entries', () {
      final queue = QueueManager();
      expect(queue.add(song('a')), isTrue);
      expect(queue.add(song('a')), isFalse);
      expect(queue.items.map((item) => item.id).toList(), ['a']);
    });

    test('addNext moves an existing item to the front', () {
      final queue = QueueManager();
      queue.add(song('a'));
      queue.add(song('b'));
      queue.addNext(song('b'));
      expect(queue.items.map((item) => item.id).toList(), ['b', 'a']);
    });

    test('restore drops duplicate and empty IDs', () {
      final queue = QueueManager();
      queue.restore([
        QueueItem(video: song('a')),
        QueueItem(video: song('a')),
        QueueItem(video: song('')),
        QueueItem(video: song('b')),
      ]);
      expect(queue.items.map((item) => item.id).toList(), ['a', 'b']);
    });

    test('move and takeFirst preserve the visible order', () {
      final queue = QueueManager();
      queue.add(song('a'));
      queue.add(song('b'));
      queue.add(song('c'));
      queue.move(oldIndex: 0, newIndex: 2);
      expect(queue.items.map((item) => item.id).toList(), ['b', 'c', 'a']);
      expect(queue.takeFirst()?.id, 'b');
      expect(queue.items.map((item) => item.id).toList(), ['c', 'a']);
    });

    test('shuffle candidate selection skips another source and preserves it', () {
      final queue = QueueManager();
      queue.add(song('yt-1'));
      queue.add(localSong('file-1'));
      queue.add(song('yt-2'));

      final selected = queue.takeRandomMatching((video) => !video.isLocal);

      expect(selected, isNotNull);
      expect(selected!.video.isLocal, isFalse);
      expect(queue.items.any((item) => item.video.videoId == 'local:file-1'), isTrue);
      expect(queue.length, 2);
    });

    test('smart shuffle scores only matching-source queue entries', () {
      final queue = QueueManager();
      queue.add(localSong('file-1'));
      queue.add(song('yt-1'));

      final selected = queue.takeSmartMatching(
        matches: (video) => video.isLocal,
        score: (_) => 100,
      );

      expect(selected?.video.isLocal, isTrue);
      expect(queue.items.map((item) => item.id).toList(), ['yt-1']);
    });

    test('first matching item leaves incompatible items in their original order', () {
      final queue = QueueManager();
      queue.add(localSong('file-1'));
      queue.add(song('yt-1'));
      queue.add(localSong('file-2'));

      final selected = queue.takeFirstMatching((video) => video.isLocal);

      expect(selected?.id, 'local:file-1');
      expect(queue.items.map((item) => item.id).toList(), ['yt-1', 'local:file-2']);
    });
  });

  group('PlaybackSourcePolicy', () {
    test('normalizes mixed lists to selected YouTube source and deduplicates', () {
      final selected = song('yt-2');
      final result = PlaybackSourcePolicy.sameSourceAs([
        song('yt-1'),
        localSong('file-1'),
        song('yt-1'),
        selected,
      ], selected: selected);

      expect(result.map((video) => video.videoId).toList(), ['yt-1', 'yt-2']);
      expect(result.every((video) => !video.isLocal), isTrue);
    });

    test('normalizes mixed lists to selected local source', () {
      final selected = localSong('file-2');
      final result = PlaybackSourcePolicy.sameSourceAs([
        song('yt-1'),
        localSong('file-1'),
        selected,
      ], selected: selected);

      expect(result.map((video) => video.videoId).toList(), [
        'local:file-1',
        'local:file-2',
      ]);
      expect(result.every((video) => video.isLocal), isTrue);
    });
  });
}
