import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Penyimpanan diagnostik lokal untuk crash Flutter dan event ANR yang
/// terdeteksi native. Tidak mengirim telemetry ke server.
class AppHealthMonitor {
  AppHealthMonitor._();
  static final AppHealthMonitor instance = AppHealthMonitor._();

  static const _eventsKey = 'health_events_v1';
  static const _maxEvents = 80;

  Future<void> record({required String kind, required Object error, StackTrace? stack}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<String>.from(prefs.getStringList(_eventsKey) ?? const <String>[]);
      final record = <String, dynamic>{
        'time': DateTime.now().toIso8601String(),
        'kind': kind,
        'error': '$error',
        'stack': stack?.toString() ?? '',
        'platform': Platform.operatingSystem,
      };
      current.add(jsonEncode(record));
      final start = current.length > _maxEvents ? current.length - _maxEvents : 0;
      await prefs.setStringList(_eventsKey, current.sublist(start));
    } catch (e) {
      debugPrint('HEALTH LOG ERROR: $e');
    }
  }

  Future<List<Map<String, dynamic>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_eventsKey) ?? const <String>[])
          .map((raw) {
            try {
              final decoded = jsonDecode(raw);
              return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
            } catch (_) {
              return <String, dynamic>{};
            }
          })
          .where((e) => e.isNotEmpty)
          .toList(growable: false)
          .reversed
          .toList(growable: false);
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_eventsKey);
  }
}
