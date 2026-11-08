/// Strict validation helpers for resumable, provider-authorized audio files.
/// Kept pure so the HTTP edge cases can be unit-tested without network access.
class ParsedContentRange {
  const ParsedContentRange({
    required this.start,
    required this.end,
    required this.total,
  });

  final int start;
  final int end;
  final int? total;

  int get length => end - start + 1;

  static ParsedContentRange? parse(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^\s*bytes\s+(\d+)-(\d+)/(\d+|\*)\s*$',
            caseSensitive: false)
        .firstMatch(value);
    if (match == null) return null;
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final totalText = match.group(3)!;
    final total = totalText == '*' ? null : int.tryParse(totalText);
    if (start == null || end == null || start < 0 || end < start) {
      return null;
    }
    if (totalText != '*' && (total == null || total <= end)) return null;
    return ParsedContentRange(start: start, end: end, total: total);
  }
}

bool isValidContentRangeResponse({
  required int requestedOffset,
  required String? contentRange,
  required int? contentLength,
}) {
  final range = ParsedContentRange.parse(contentRange);
  final total = range?.total;
  if (range == null ||
      range.start != requestedOffset ||
      total == null ||
      range.end != total - 1) {
    // The request uses `bytes=<offset>-` (open-ended). Accepting a shorter
    // 206 segment would make the caller treat an incomplete response as the
    // complete remainder or require a manual retry for every segment.
    return false;
  }
  if (contentLength != null &&
      contentLength >= 0 &&
      contentLength != range.length) {
    return false;
  }
  return true;
}

/// Detects an audio container from its magic bytes. This prevents an HTML
/// error page or JSON API response from being saved with an .m4a suffix.
String? detectAudioFileExtension(List<int> bytes) {
  if (bytes.length >= 12 &&
      bytes[4] == 0x66 && bytes[5] == 0x74 &&
      bytes[6] == 0x79 && bytes[7] == 0x70) {
    return 'm4a'; // ISO Base Media / M4A
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x1a && bytes[1] == 0x45 &&
      bytes[2] == 0xdf && bytes[3] == 0xa3) {
    return 'webm';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x4f && bytes[1] == 0x67 &&
      bytes[2] == 0x67 && bytes[3] == 0x53) {
    return 'ogg';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x66 && bytes[1] == 0x4c &&
      bytes[2] == 0x61 && bytes[3] == 0x43) {
    return 'flac';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 && bytes[1] == 0x49 &&
      bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x41 &&
      bytes[10] == 0x56 && bytes[11] == 0x45) {
    return 'wav';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
    return 'mp3';
  }
  if (bytes.length >= 2 && bytes[0] == 0xff &&
      (bytes[1] & 0xf6) == 0xf0) {
    return 'aac';
  }
  if (bytes.length >= 2 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0) {
    return 'mp3'; // MPEG audio frame sync
  }
  return null;
}

bool isPlausibleAudioContentType(String? contentType) {
  if (contentType == null || contentType.trim().isEmpty) return true;
  final normalized = contentType.split(';').first.trim().toLowerCase();
  if (normalized == 'application/octet-stream' ||
      normalized == 'binary/octet-stream' ||
      normalized == 'application/mp4' ||
      normalized == 'video/mp4' ||
      normalized == 'video/webm') {
    return true;
  }
  if (normalized.startsWith('audio/')) {
    return !normalized.contains('mpegurl') && !normalized.contains('playlist');
  }
  return false;
}

/// Stable identity for a selected audio format across signed-URL refreshes.
/// Signed CDN URLs are deliberately excluded because they expire frequently.
String audioStreamFingerprint(Map<String, dynamic> resolved) {
  final format = (resolved['format'] ?? '').toString().trim().toLowerCase();
  final codec = (resolved['codec'] ?? '').toString().trim().toLowerCase();
  final bitrateValue = resolved['bitrate'];
  final bitrate = bitrateValue is num
      ? bitrateValue.toInt()
      : int.tryParse('$bitrateValue') ?? 0;
  if (format.isEmpty && codec.isEmpty && bitrate <= 0) return '';
  return '$format|$codec|${bitrate > 0 ? bitrate : 0}';
}
