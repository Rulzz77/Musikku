import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Saran pencarian (autocomplete) dari endpoint suggest YouTube.
///
/// Catatan: endpoint ini tidak resmi, jadi bisa berubah atau dibatasi
/// sewaktu-waktu. Semua kegagalan menghasilkan daftar kosong.
class SearchSuggestService {
  SearchSuggestService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  static const int _maxCacheEntries = 100;
  static const int _maxQueryLength = 100;
  static const int _maxSuggestions = 10;

  final http.Client _client;
  final bool _ownsClient;

  // LinkedHashMap menjaga urutan sisip, dipakai sebagai cache LRU sederhana.
  final LinkedHashMap<String, List<String>> _cache =
      LinkedHashMap<String, List<String>>();

  int _latestRequestId = 0;
  bool _disposed = false;

  /// Mengambil saran untuk [query].
  ///
  /// Panggilan diberi jeda [debounce]. Kalau ada panggilan yang lebih baru
  /// sebelum jeda habis atau sebelum respons datang, panggilan lama
  /// mengembalikan daftar kosong. Jadi di sisi UI, abaikan hasil kalau teks
  /// input sudah berubah dari [query]:
  ///
  /// ```dart
  /// final result = await service.suggest(text);
  /// if (!mounted || controller.text.trim() != text.trim()) return;
  /// setState(() => suggestions = result);
  /// ```
  ///
  /// Hasil dari cache dikembalikan langsung tanpa jeda.
  Future<List<String>> suggest(
    String query, {
    Duration debounce = const Duration(milliseconds: 250),
  }) async {
    if (_disposed) return const <String>[];

    var q = query.trim();
    if (q.isEmpty) return const <String>[];
    if (q.length > _maxQueryLength) q = q.substring(0, _maxQueryLength);

    final key = q.toLowerCase();
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached; // pindah ke posisi paling baru
      return cached;
    }

    final requestId = ++_latestRequestId;

    if (debounce > Duration.zero) {
      await Future<void>.delayed(debounce);
      if (_disposed || requestId != _latestRequestId) {
        return const <String>[];
      }
    }

    try {
      final uri = Uri.https('suggestqueries.google.com', '/complete/search', {
        'client': 'firefox',
        'ds': 'yt',
        'hl': 'id',
        'q': q,
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (_disposed || requestId != _latestRequestId) {
        return const <String>[];
      }
      if (res.statusCode != 200) return const <String>[];

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is List && data.length > 1 && data[1] is List) {
        final seen = <String>{};
        final list = <String>[];
        for (final item in data[1] as List) {
          final text = item.toString().trim();
          if (text.isEmpty) continue;
          if (!seen.add(text.toLowerCase())) continue;
          list.add(text);
          if (list.length >= _maxSuggestions) break;
        }
        final result = List<String>.unmodifiable(list);
        _cache[key] = result;
        while (_cache.length > _maxCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
        return result;
      }
    } catch (_) {
      // Jaringan/timeout/format tak terduga: tidak ada saran.
    }
    return const <String>[];
  }

  /// Batalkan semua permintaan yang masih menunggu (hasilnya jadi kosong).
  void cancelPending() {
    _latestRequestId++;
  }

  void clearCache() => _cache.clear();

  void dispose() {
    _disposed = true;
    _latestRequestId++;
    _cache.clear();
    if (_ownsClient) _client.close();
  }
}