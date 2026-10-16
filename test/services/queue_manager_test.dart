import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/queue_item.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/queue_manager.dart';

YoutubeSearchResult song(String id) => YoutubeSearchResult(
      videoId: id,
      title: 'Track $id',
      channelTitle: 'Artist',
      thumbnailUrl: '',
    );

void main() {
  group('QueueManager', () {
    test('rejects duplicate songs added to the queue', () {
      final queue = QueueManager();
      expect(queue.add(song('a')), isTrue);
      expect(queue.add(song('a')), isFalse);
      expect(queue.items.map((item) => item.id), ['a']);
    });

    test('addNext moves an existing song to the front without duplicates', () {
      final queue = QueueManager();
      queue.restore([QueueItem(video: song('a')), QueueItem(video: song('b'))]);

      queue.addNext(song('b'));

      expect(queue.items.map((item) => item.id), ['b', 'a']);
    });

    test('restore drops blank IDs and duplicate IDs', () {
      final queue = QueueManager();
      queue.restore([
        QueueItem(video: song('a')),
        QueueItem(video: song('')),
        QueueItem(video: song('a')),
        QueueItem(video: song('b')),
      ]);

      expect(queue.items.map((item) => item.id), ['a', 'b']);
    });

    test('takeFirst removes the first item and returns null when empty', () {
      final queue = QueueManager();
      queue.restore([QueueItem(video: song('a')), QueueItem(video: song('b'))]);

      expect(queue.takeFirst()?.id, 'a');
      expect(queue.items.map((item) => item.id), ['b']);
      queue.clear();
      expect(queue.takeFirst(), isNull);
    });

    test('move respects the final destination index', () {
      final queue = QueueManager();
      queue.restore([
        QueueItem(video: song('a')),
        QueueItem(video: song('b')),
        QueueItem(video: song('c')),
      ]);

      queue.move(oldIndex: 0, newIndex: 2);
      expect(queue.items.map((item) => item.id), ['b', 'c', 'a']);
      queue.move(oldIndex: -1, newIndex: 0);
      queue.move(oldIndex: 0, newIndex: 99);
      expect(queue.items.map((item) => item.id), ['b', 'c', 'a']);
    });
  });
}
