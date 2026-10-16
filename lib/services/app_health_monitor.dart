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

  String _redact(String raw, {required int maxLength}) {
    var value = raw;
    final querySecret = RegExp(
      r'([?&](?:key|api_key|access_token|refresh_token|token|client_secret)=)[^&#\s]+',
      caseSensitive: false,
    );
    value = value.replaceAllMapped(
      querySecret,
      (match) => '${match.group(1)}[REDACTED]',
    );
    value = value.replaceAll(
      RegExp(r'\bBearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
      'Bearer [REDACTED]',
    );
    value = value.replaceAll(
      RegExp(r'\bAIza[0-9A-Za-z_-]{20,}\b'),
      '[GOOGLE_API_KEY_REDACTED]',
    );
    value = value.replaceAll(
      RegExp(r'\bya29\.[0-9A-Za-z._-]{20,}\b'),
      '[OAUTH_TOKEN_REDACTED]',
    );
    // Signed media URLs can contain temporary credentials under vendor-specific
    // query names, so redact every URL query rather than guessing each name.
    value = value.replaceAllMapped(
      RegExp(r'(https?://[^\s?#]+)\?[^\s#]*', caseSensitive: false),
      (match) => '${match.group(1)}?[QUERY_REDACTED]',
    );
    return value.length <= maxLength ? value : value.substring(0, maxLength);
  }

  Future<void> record({required String kind, required Object error, StackTrace? stack}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = List<String>.from(prefs.getStringList(_eventsKey) ?? const <String>[]);
      final record = <String, dynamic>{
        'time': DateTime.now().toIso8601String(),
        'kind': kind,
        'error': _redact('$error', maxLength: 1200),
        'stack': _redact(stack?.toString() ?? '', maxLength: 4000),
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
