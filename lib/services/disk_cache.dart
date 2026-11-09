import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache kecil di penyimpanan HP (SharedPreferences) dengan batas jumlah
/// entri dan masa berlaku, supaya tidak menumpuk dan tidak membebani RAM.
///
/// Nilai harus bisa di-encode JSON (List / Map / String / num / bool).
///
/// Penulisan diserialkan per namespace: `put` membaca lalu menulis indeks,
/// jadi dua penulisan bersamaan tanpa antrean bisa saling menimpa indeks dan
/// meninggalkan entri yatim yang tidak pernah dibuang.
class DiskCache {
  const DiskCache({
    required this.namespace,
    required this.maxEntries,
    required this.ttl,
  });

  final String namespace;
  final int maxEntries;
  final Duration ttl;

  // Nama field di dalam JSON yang disimpan per entri.
  static const String _keyField = 'k';
  static const String _savedAtField = 't';
  static const String _valueField = 'v';

  // Antrean tulis per namespace. Nilainya tidak pernah berisi error.
  static final Map<String, Future<void>> _writeQueues = <String, Future<void>>{};

  String get _indexKey => 'cache_index_$namespace';

  static String _normalize(String key) => key.toLowerCase().trim();

  // FNV-1a 32-bit: stabil antar-sesi (String.hashCode tidak dijamin).
  static String _hash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  String _entryKey(String normalizedKey) =>
      'cache_${namespace}_${_hash(normalizedKey)}';

  /// Batas umur efektif: [maxAge] hanya boleh memperketat [ttl], bukan melonggarkannya.
  Duration _effectiveTtl(Duration? maxAge) =>
      maxAge != null && maxAge < ttl ? maxAge : ttl;

  /// Mengembalikan nilai tersimpan, atau null jika tidak ada, kedaluwarsa,
  /// rusak, atau bentrok hash dengan key lain.
  Future<Object?> get(String key, {Duration? maxAge}) async {
    try {
      final normalized = _normalize(key);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_entryKey(normalized));
      if (raw == null) return null;

      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded[_keyField] != normalized) return null;

      final savedAt = decoded[_savedAtField];
      if (savedAt is! int) return null;

      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(savedAt),
      );
      if (age > _effectiveTtl(maxAge)) return null;

      return decoded[_valueField];
    } catch (e) {
      debugPrint('DISK CACHE READ ERROR [$namespace]: $e');
      return null;
    }
  }

  Future<void> put(String key, Object value) =>
      putAll(<String, Object>{key: value});

  /// Menulis banyak entri sekaligus dengan satu kali pembaruan indeks.
  /// Entri yang gagal di-encode dilewati tanpa menggagalkan entri lain.
  Future<void> putAll(Map<String, Object> entries) {
    if (entries.isEmpty) return Future<void>.value();

    final previous = _writeQueues[namespace] ?? Future<void>.value();
    final next = previous.then((_) => _putAllNow(entries));
    _writeQueues[namespace] = next;
    return next;
  }

  Future<void> _putAllNow(Map<String, Object> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final index = List<String>.from(
        prefs.getStringList(_indexKey) ?? const <String>[],
      );

      for (final entry in entries.entries) {
        try {
          final normalized = _normalize(entry.key);
          final entryKey = _entryKey(normalized);

          await prefs.setString(
            entryKey,
            jsonEncode({
              _keyField: normalized,
              _savedAtField: DateTime.now().millisecondsSinceEpoch,
              _valueField: entry.value,
            }),
          );

          // Urutan indeks = urutan tulis; entri yang ditulis ulang pindah ke akhir.
          index
            ..remove(entryKey)
            ..add(entryKey);
        } catch (e) {
          debugPrint('DISK CACHE ENTRY WRITE ERROR [$namespace]: $e');
        }
      }

      // Buang entri tertua supaya ukuran penyimpanan tetap terkendali.
      while (index.length > maxEntries) {
        await prefs.remove(index.removeAt(0));
      }

      await prefs.setStringList(_indexKey, index);
    } catch (e) {
      // Antrean tidak boleh pernah berisi error, supaya penulisan berikutnya
      // tetap berjalan.
      debugPrint('DISK CACHE WRITE ERROR [$namespace]: $e');
    }
  }
}