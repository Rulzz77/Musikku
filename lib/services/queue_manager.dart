import 'dart:math';

import '../models/queue_item.dart';
import '../models/youtube_search_result.dart';

/// Informasi yang dibutuhkan untuk mengembalikan item antrean ke posisi semula.
class QueueRemoval {
  const QueueRemoval({required this.item, required this.index});

  final QueueItem item;
  final int index;
}

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

  /// Menghapus item sekaligus menyimpan posisi supaya dapat di-undo.
  QueueRemoval? removeWithIndex(String videoId) {
    final index = _queue.indexWhere((item) => item.id == videoId);
    if (index < 0) return null;
    return QueueRemoval(item: _queue.removeAt(index), index: index);
  }

  /// Memulihkan item di posisi sebelumnya tanpa menghapus item lain yang
  /// mungkin ditambahkan setelah penghapusan. Menolak ID kosong/duplikat.
  bool restoreAtIndex(QueueItem item, int index) {
    if (item.id.isEmpty || contains(item.id)) return false;
    final safeIndex = index.clamp(0, _queue.length).toInt();
    _queue.insert(safeIndex, item);
    return true;
  }

  bool remove(String videoId) => removeWithIndex(videoId) != null;

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

  /// Ambil lagu pertama yang cocok dengan predicate tanpa mengganggu item lain.
  /// Dipakai agar Shuffle tidak mencampur sumber YouTube dan file lokal.
  QueueItem? takeFirstMatching(
    bool Function(YoutubeSearchResult video) matches,
  ) {
    final index = _queue.indexWhere((item) => matches(item.video));
    if (index < 0) return null;
    return _queue.removeAt(index);
  }

  /// Ambil secara acak hanya dari sumber yang cocok; item sumber lain tetap
  /// berada di antrean dan tidak ikut teracak ke sesi pemutaran ini.
  QueueItem? takeRandomMatching(
    bool Function(YoutubeSearchResult video) matches,
  ) {
    final matchingIndexes = <int>[];
    for (var i = 0; i < _queue.length; i++) {
      if (matches(_queue[i].video)) matchingIndexes.add(i);
    }
    if (matchingIndexes.isEmpty) return null;
    final index = matchingIndexes[_random.nextInt(matchingIndexes.length)];
    return _queue.removeAt(index);
  }

  /// Smart Shuffle terbatas pada item yang kompatibel. Kandidat yang tak cocok
  /// tidak ikut dinilai dan tidak dihapus dari antrean.
  QueueItem? takeSmartMatching({
    required bool Function(YoutubeSearchResult video) matches,
    required double Function(YoutubeSearchResult) score,
  }) {
    final scored = _queue
        .where((item) => matches(item.video))
        .map((item) => (item: item, score: score(item.video)))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) return null;
    final topCount = scored.length < 5 ? scored.length : 5;
    final candidates = scored.take(topCount).toList();
    final selected = candidates[_random.nextInt(candidates.length)].item;
    _queue.removeWhere((item) => item.id == selected.id);
    return selected;
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