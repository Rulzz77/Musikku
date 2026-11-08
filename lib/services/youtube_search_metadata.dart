/// Pure parsers for the lightweight objects returned by youtube_explode_dart
/// search. SearchVideo uses different field types from the full Video model:
/// duration is text (MM:SS / HH:MM:SS) and viewCount is a direct integer.
class YoutubeSearchMetadata {
  const YoutubeSearchMetadata._();

  static double? parseDurationSeconds(Object? raw) {
    if (raw == null) return null;
    if (raw is Duration) {
      return raw.isNegative ? null : raw.inMilliseconds / 1000.0;
    }
    if (raw is num) {
      final value = raw.toDouble();
      return value > 0 && value.isFinite ? value : null;
    }

    final text = raw.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'live') return null;
    final parts = text.split(':');
    if (parts.length < 2 || parts.length > 3) return null;

    final values = <int>[];
    for (final part in parts) {
      final parsed = int.tryParse(part.trim());
      if (parsed == null || parsed < 0) return null;
      values.add(parsed);
    }

    int seconds;
    if (values.length == 2) {
      if (values[1] >= 60) return null;
      seconds = values[0] * 60 + values[1];
    } else {
      if (values[1] >= 60 || values[2] >= 60) return null;
      seconds = values[0] * 3600 + values[1] * 60 + values[2];
    }
    return seconds > 0 ? seconds.toDouble() : null;
  }

  static int? parseViewCount(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      final value = raw.toInt();
      return value >= 0 ? value : null;
    }

    final text = raw.toString().trim().toLowerCase().replaceAll(',', '');
    if (text.isEmpty) return null;
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*([kmb])?').firstMatch(text);
    if (match == null) return null;
    final value = double.tryParse(match.group(1) ?? '');
    if (value == null || !value.isFinite) return null;
    final multiplier = switch (match.group(2)) {
      'k' => 1000.0,
      'm' => 1000000.0,
      'b' => 1000000000.0,
      _ => 1.0,
    };
    final count = (value * multiplier).round();
    return count >= 0 ? count : null;
  }

  static DateTime? parseRelativeUploadDate(
    String raw, {
    DateTime? now,
  }) {
    final match = RegExp(
      r'(?:streamed\s+)?(\d+)\s*(second|minute|hour|day|week|month|year|detik|menit|jam|hari|minggu|bulan|tahun)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final amount = int.tryParse(match.group(1) ?? '');
    if (amount == null || amount < 0) return null;
    final unit = (match.group(2) ?? '').toLowerCase();
    final span = switch (unit) {
      'second' || 'detik' => Duration(seconds: amount),
      'minute' || 'menit' => Duration(minutes: amount),
      'hour' || 'jam' => Duration(hours: amount),
      'day' || 'hari' => Duration(days: amount),
      'week' || 'minggu' => Duration(days: amount * 7),
      'month' || 'bulan' => Duration(days: amount * 30),
      _ => Duration(days: amount * 365),
    };
    return (now ?? DateTime.now()).subtract(span);
  }
}
