import 'dart:math';

import '../models/queue_item.dart';
import '../models/youtube_search_result.dart';

class QueueManager {
  final List<QueueItem> _queue = [];

  final Random _random = Random();

  List<QueueItem> get items =>
      List.unmodifiable(_queue);

  bool get isEmpty =>
      _queue.isEmpty;

  bool get isNotEmpty =>
      _queue.isNotEmpty;

  int get length =>
      _queue.length;

  bool contains(String videoId) {
    return _queue.any(
      (item) => item.id == videoId,
    );
  }

  void restore(Iterable<QueueItem> items) {
    _queue.clear();

    final seen = <String>{};

    for (final item in items) {
      if (item.id.isEmpty || !seen.add(item.id)) {
        continue;
      }

      _queue.add(item);
    }
  }

  bool add(
    YoutubeSearchResult video,
  ) {
    if (contains(video.videoId)) {
      return false;
    }

    _queue.add(
      QueueItem(
        video: video,
      ),
    );

    return true;
  }

  /// Taruh lagu di urutan pertama antrean ("putar berikutnya").
  /// Kalau sudah ada di antrean, cukup dipindah ke depan.
  void addNext(
    YoutubeSearchResult video,
  ) {
    final index = _queue.indexWhere(
      (item) => item.id == video.videoId,
    );

    if (index != -1) {
      _queue.removeAt(index);
    }

    _queue.insert(
      0,
      QueueItem(
        video: video,
      ),
    );
  }

  bool remove(
    String videoId,
  ) {
    final index =
        _queue.indexWhere(
      (item) => item.id == videoId,
    );

    if (index == -1) {
      return false;
    }

    _queue.removeAt(index);

    return true;
  }

  void clear() {
    _queue.clear();
  }

  QueueItem? takeFirst() {
    if (_queue.isEmpty) {
      return null;
    }

    return _queue.removeAt(0);
  }

  QueueItem? peekFirst() {
    if (_queue.isEmpty) {
      return null;
    }

    return _queue.first;
  }

  QueueItem? takeSmart({required double Function(YoutubeSearchResult) score}) {
    if (_queue.isEmpty) {
      return null;
    }

    final scored = _queue
        .map((item) => (item: item, score: score(item.video)))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final topCount = scored.length < 5 ? scored.length : 5;
    final candidates = scored.take(topCount).toList();
    final selected = candidates[_random.nextInt(candidates.length)].item;
    _queue.removeWhere((item) => item.id == selected.id);
    return selected;
  }

  QueueItem? takeRandom() {
    if (_queue.isEmpty) {
      return null;
    }

    final index =
        _random.nextInt(
      _queue.length,
    );

    return _queue.removeAt(index);
  }

  void move({
    required int oldIndex,
    required int newIndex,
  }) {
    if (oldIndex < 0 ||
        oldIndex >= _queue.length) {
      return;
    }

    if (newIndex < 0 ||
        newIndex >= _queue.length) {
      return;
    }

    final item =
        _queue.removeAt(oldIndex);

    _queue.insert(
      newIndex,
      item,
    );
  }
}