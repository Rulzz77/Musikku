import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/queue_item.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/queue_manager.dart';

YoutubeSearchResult song(String id, {String? title}) {
  return YoutubeSearchResult(
    videoId: id,
    title: title ?? 'Title $id',
    channelTitle: 'Test Artist',
    thumbnailUrl: '',
  );
}

void main() {
  group('QueueManager', () {
    late QueueManager queue;

    setUp(() {
      queue = QueueManager();
    });

    test('starts empty and returns an immutable item snapshot', () {
      expect(queue.isEmpty, isTrue);
      expect(queue.length, 0);
      expect(queue.peekFirst(), isNull);
      expect(queue.takeFirst(), isNull);
      expect(
        () => queue.items.add(QueueItem(video: song('x'))),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('add prevents duplicate video IDs', () {
      expect(queue.add(song('a')), isTrue);
      expect(queue.add(song('b')), isTrue);
      expect(queue.add(song('a', title: 'Duplicate')), isFalse);
      expect(queue.items.map((item) => item.id), ['a', 'b']);
    });

    test('addNext moves an existing item to the front without duplication', () {
      queue.add(song('a'));
      queue.add(song('b'));
      queue.add(song('c'));

      queue.addNext(song('b', title: 'Updated B'));

      expect(queue.items.map((item) => item.id), ['b', 'a', 'c']);
      expect(queue.length, 3);
      expect(queue.peekFirst()?.title, 'Updated B');
    });

    test('restore drops empty and duplicate IDs while preserving order', () {
      queue.restore([
        QueueItem(video: song('a')),
        QueueItem(video: song('')),
        QueueItem(video: song('b')),
        QueueItem(video: song('a', title: 'Duplicate A')),
      ]);

      expect(queue.items.map((item) => item.id), ['a', 'b']);
    });

    test('move changes order and ignores invalid indices', () {
      queue.add(song('a'));
      queue.add(song('b'));
      queue.add(song('c'));

      queue.move(oldIndex: 0, newIndex: 2);
      expect(queue.items.map((item) => item.id), ['b', 'c', 'a']);

      queue.move(oldIndex: -1, newIndex: 1);
      queue.move(oldIndex: 1, newIndex: 99);
      expect(queue.items.map((item) => item.id), ['b', 'c', 'a']);
    });

    test('takeFirst removes only the first item', () {
      queue.add(song('a'));
      queue.add(song('b'));

      expect(queue.takeFirst()?.id, 'a');
      expect(queue.items.map((item) => item.id), ['b']);
      expect(queue.takeFirst()?.id, 'b');
      expect(queue.takeFirst(), isNull);
    });

    test('takeRandom removes exactly one existing item', () {
      queue.add(song('a'));
      queue.add(song('b'));
      queue.add(song('c'));

      final selected = queue.takeRandom();

      expect(selected, isNotNull);
      expect(['a', 'b', 'c'], contains(selected!.id));
      expect(queue.length, 2);
      expect(queue.contains(selected.id), isFalse);
    });

    test('takeSmart selects from the five highest-scored candidates', () {
      for (var i = 1; i <= 7; i++) {
        queue.add(song('$i'));
      }

      final selected = queue.takeSmart(
        score: (video) => double.parse(video.videoId),
      );

      expect(selected, isNotNull);
      expect(['3', '4', '5', '6', '7'], contains(selected!.id));
      expect(queue.length, 6);
      expect(queue.contains(selected.id), isFalse);
    });

    test('remove and clear update queue state', () {
      queue.add(song('a'));
      queue.add(song('b'));

      expect(queue.remove('missing'), isFalse);
      expect(queue.remove('a'), isTrue);
      expect(queue.items.map((item) => item.id), ['b']);

      queue.clear();
      expect(queue.isEmpty, isTrue);
    });
  });
}
