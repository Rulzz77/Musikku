import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Saran pencarian (autocomplete) dari endpoint suggest YouTube.
class SearchSuggestService {
  final Map<String, List<String>> _cache = {};

  Future<List<String>> suggest(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final cached = _cache[q.toLowerCase()];
    if (cached != null) return cached;
    try {
      final uri = Uri.https('suggestqueries.google.com', '/complete/search', {
        'client': 'firefox',
        'ds': 'yt',
        'hl': 'id',
        'q': q,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return const [];
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is List && data.length > 1 && data[1] is List) {
        final list = (data[1] as List)
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .take(10)
            .toList(growable: false);
        _cache[q.toLowerCase()] = list;
        return list;
      }
    } catch (_) {}
    return const [];
  }
}
