import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Global request pacing and back-off for documented YouTube Data API calls.
///
/// This class does not bypass YouTube limits. It reduces request bursts and
/// prevents repeated calls while a rate/quota restriction is active.
class YoutubeApiLimitException implements Exception {
  const YoutubeApiLimitException(this.message);
  final String message;

  @override
  String toString() => message;
}

class YoutubeApiRequestGuard {
  YoutubeApiRequestGuard._();

  static const Duration _minimumSpacing = Duration(milliseconds: 500);
  static final Map<String, DateTime> _cooldowns = <String, DateTime>{};
  static final Map<String, String> _messages = <String, String>{};
  static final Map<String, DateTime> _nextRequestAt = <String, DateTime>{};
  static final Set<String> _persistedCooldownLoaded = <String>{};
  static final Map<String, Future<void>> _persistedCooldownLoads =
      <String, Future<void>>{};
  static String _persistKey(String scope) => 'youtube_api_cooldown_until_$scope';
  static String _persistMessageKey(String scope) => 'youtube_api_cooldown_message_$scope';

  static Future<void> _loadPersistedCooldown(String scope) {
    if (_persistedCooldownLoaded.contains(scope)) return Future<void>.value();
    final active = _persistedCooldownLoads[scope];
    if (active != null) return active;

    late final Future<void> loading;
    loading = (() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final millis = prefs.getInt(_persistKey(scope));
        final now = DateTime.now().toUtc();
        if (millis != null) {
          final until = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
          if (until.isAfter(now)) {
            _cooldowns[scope] = until;
            _messages[scope] = prefs.getString(_persistMessageKey(scope)) ??
                'YouTube sedang membatasi request kategori ini sementara.';
          } else {
            await prefs.remove(_persistKey(scope));
            await prefs.remove(_persistMessageKey(scope));
          }
        }
      } catch (_) {
        // Cooldown in-memory tetap melindungi sesi saat penyimpanan tidak tersedia.
      } finally {
        _persistedCooldownLoaded.add(scope);
        _persistedCooldownLoads.remove(scope);
      }
    })();
    _persistedCooldownLoads[scope] = loading;
    return loading;
  }

  static Future<void> _persistCooldown(String scope) async {
    try {
      final until = _cooldowns[scope];
      if (until == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_persistKey(scope), until.millisecondsSinceEpoch);
      await prefs.setString(
        _persistMessageKey(scope),
        _messages[scope] ?? 'YouTube sedang membatasi request kategori ini sementara.',
      );
    } catch (_) {
      // Jangan membuat error penyimpanan mengganggu pemutaran musik.
    }
  }

  /// Checks a cooldown and reserves a paced request start for [scope].
  /// Use separate `search` and `data` scopes because search.list has its own
  /// daily bucket, while channels/videos/playlists use the general bucket.
  static Future<void> beforeRequest(String scope) async {
    await _loadPersistedCooldown(scope);
    _throwIfCoolingDown(scope);
    final now = DateTime.now().toUtc();
    final next = _nextRequestAt[scope];
    final startAt = (next != null && next.isAfter(now)) ? next : now;
    _nextRequestAt[scope] = startAt.add(_minimumSpacing);
    final wait = startAt.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    _throwIfCoolingDown(scope);
  }

  static bool isCoolingDown(String scope) {
    final until = _cooldowns[scope];
    if (until == null) return false;
    if (!DateTime.now().toUtc().isBefore(until)) {
      _cooldowns.remove(scope);
      _messages.remove(scope);
      unawaited(_clearPersistedCooldown(scope));
      return false;
    }
    return true;
  }

  static DateTime? cooldownUntil(String scope) => _cooldowns[scope];

  static Future<void> _clearPersistedCooldown(String scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_persistKey(scope));
      await prefs.remove(_persistMessageKey(scope));
    } catch (_) {}
  }

  /// Records only documented quota/rate-limit responses. Other 403 responses,
  /// such as comments being disabled, do not pause unrelated requests.
  static void observeResponse({
    required String scope,
    required int statusCode,
    required String body,
    Map<String, String> headers = const <String, String>{},
  }) {
    final reason = _errorReason(body);
    final now = DateTime.now().toUtc();
    if (reason == 'quotaExceeded' || reason == 'dailyLimitExceeded') {
      final until = _nextPacificMidnightUtc(now);
      _cooldowns[scope] = until;
      _messages[scope] =
          'Kuota YouTube untuk kategori request ini sudah habis. Request dihentikan sampai reset kuota sekitar ${until.toIso8601String()} (waktu Pasifik).';
      unawaited(_persistCooldown(scope));
      return;
    }

    final rateLimited = statusCode == 429 ||
        reason == 'rateLimitExceeded' ||
        reason == 'userRateLimitExceeded';
    if (!rateLimited) return;

    String? rawRetryAfter;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'retry-after') {
        rawRetryAfter = entry.value;
        break;
      }
    }
    var seconds = int.tryParse(rawRetryAfter ?? '');
    if (seconds == null && rawRetryAfter != null) {
      final date = DateTime.tryParse(rawRetryAfter)?.toUtc();
      if (date != null) seconds = date.difference(now).inSeconds;
    }
    // For 429 quota/rate errors, don't immediately re-fire the same request.
    final waitSeconds = (seconds ?? 30).clamp(30, 900).toInt();
    final until = now.add(Duration(seconds: waitSeconds));
    final existing = _cooldowns[scope];
    _cooldowns[scope] = existing != null && existing.isAfter(until)
        ? existing
        : until;
    _messages[scope] =
        'YouTube sedang membatasi request. MusikKu menghentikan request kategori ini sementara; coba lagi setelah ${_cooldowns[scope]!.toLocal()}.';
    unawaited(_persistCooldown(scope));
  }

  static void _throwIfCoolingDown(String scope) {
    if (!isCoolingDown(scope)) return;
    throw YoutubeApiLimitException(
      _messages[scope] ?? 'Request YouTube sementara dihentikan karena limit.',
    );
  }

  static String _errorReason(String body) {
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map && decoded['error'] is Map
          ? decoded['error'] as Map
          : null;
      final errors = error?['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        return (errors.first as Map)['reason']?.toString() ?? '';
      }
      return error?['status']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  static DateTime _nextPacificMidnightUtc(DateTime utcNow) {
    final offsetHours = _isPacificDaylightTime(utcNow) ? -7 : -8;
    final pacificNow = utcNow.add(Duration(hours: offsetHours));
    final nextLocalMidnight = DateTime.utc(
      pacificNow.year,
      pacificNow.month,
      pacificNow.day + 1,
    );
    return nextLocalMidnight.subtract(Duration(hours: offsetHours));
  }

  static bool _isPacificDaylightTime(DateTime utc) {
    int nthSunday(int month, int nth) {
      final first = DateTime.utc(utc.year, month, 1);
      final daysUntilSunday = (DateTime.sunday - first.weekday) % 7;
      return 1 + daysUntilSunday + (nth - 1) * 7;
    }

    // US Pacific DST: second Sunday in March, 02:00 PST (10:00 UTC),
    // through first Sunday in November, 02:00 PDT (09:00 UTC).
    final starts = DateTime.utc(utc.year, 3, nthSunday(3, 2), 10);
    final ends = DateTime.utc(utc.year, 11, nthSunday(11, 1), 9);
    return !utc.isBefore(starts) && utc.isBefore(ends);
  }

  /// Unit-test hook only; avoids leaking cooldown state between tests.
  static void resetForTests() {
    _cooldowns.clear();
    _messages.clear();
    _nextRequestAt.clear();
    _persistedCooldownLoaded.clear();
    _persistedCooldownLoads.clear();
  }
}
