import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache kecil di penyimpanan HP (SharedPreferences) dengan batas jumlah
/// entri dan masa berlaku, supaya tidak menumpuk dan tidak membebani RAM.
///
/// Nilai harus bisa di-encode JSON (List / Map / String / num / bool).
class DiskCache {
  final String namespace;
  final int maxEntries;
  final Duration ttl;

  const DiskCache({
    required this.namespace,
    required this.maxEntries,
    required this.ttl,
  });

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

  Future<Object?> get(String key, {Duration? maxAge}) async {
    try {
      final normalized = _normalize(key);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_entryKey(normalized));

      if (raw == null) {
        return null;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! Map || decoded['k'] != normalized) {
        return null;
      }

      final savedAt = decoded['t'];

      if (savedAt is! int) {
        return null;
      }

      final limit = maxAge != null && maxAge < ttl ? maxAge : ttl;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(savedAt),
      );

      if (age > limit) {
        return null;
      }

      return decoded['v'];
    } catch (e) {
      debugPrint('DISK CACHE READ ERROR [$namespace]: $e');
      return null;
    }
  }

  Future<void> put(String key, Object value) async {
    try {
      final normalized = _normalize(key);
      final prefs = await SharedPreferences.getInstance();
      final entryKey = _entryKey(normalized);

      await prefs.setString(
        entryKey,
        jsonEncode({
          'k': normalized,
          't': DateTime.now().millisecondsSinceEpoch,
          'v': value,
        }),
      );

      final index = List<String>.from(
        prefs.getStringList(_indexKey) ?? const <String>[],
      )
        ..remove(entryKey)
        ..add(entryKey);

      // Buang entri tertua supaya ukuran penyimpanan tetap terkendali.
      while (index.length > maxEntries) {
        await prefs.remove(index.removeAt(0));
      }

      await prefs.setStringList(_indexKey, index);
    } catch (e) {
      debugPrint('DISK CACHE WRITE ERROR [$namespace]: $e');
    }
  }
}
