import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/queue_item.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/queue_manager.dart';

YoutubeSearchResult song(String id) => YoutubeSearchResult(
      videoId: id,
      title: 'Track $id',
      channelTitle: 'MusikKu test',
      thumbnailUrl: '',
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
  });
}
