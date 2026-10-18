import 'dart:math' as math;

import '../models/listening_stat.dart';
import '../models/youtube_search_result.dart';

/// Scores a candidate for Smart Shuffle using the listener's local history.
///
/// This is intentionally deterministic: callers may add a small random jitter
/// after scoring so the best few candidates remain varied without losing the
/// personalization signal. No network access or persistent state is required.
class SmartQueueScorer {
  const SmartQueueScorer._();

  static double score({
    required YoutubeSearchResult video,
    ListeningStat? stat,
    bool isLiked = false,
    bool isDisliked = false,
    String? currentArtist,
    int artistPlayCount = 0,
    int artistSkipCount = 0,
    bool artistHasLikedTrack = false,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    var value = 10.0;

    // Explicit feedback is the strongest signal.
    if (isLiked) {
      value += 15.0;
    }
    if (isDisliked) {
      value -= 120.0;
    }

    // Track-level listening behaviour. Repeated skips should outweigh a few
    // casual plays; duration is capped so long sessions don't dominate forever.
    if (stat != null) {
      value += stat.playCount.clamp(0, 10).toDouble() * 1.35;
      value += (stat.listenedSeconds / 480.0).clamp(0.0, 4.0).toDouble();
      value -= stat.skipCount.clamp(0, 8).toDouble() * 5.5;

      final lastPlayed = stat.lastPlayedAt;
      if (lastPlayed != null) {
        final elapsedMinutes = clock.difference(lastPlayed).inMinutes;
        final elapsedHours = math.max(0.0, elapsedMinutes / 60.0).toDouble();
        // A 72-hour cooldown prevents a recently repeated track from winning
        // simply because its lifetime play count is high.
        if (elapsedHours < 72.0) {
          value -= (72.0 - elapsedHours) / 6.0;
        }
      }
    }

    // Learn a lightweight artist/channel affinity from the same on-device
    // listening stats. The caps keep one heavily played artist from monopolizing
    // the queue, while repeated skips reduce the chance of another track there.
    value += artistPlayCount.clamp(0, 20).toDouble() * 0.25;
    value -= artistSkipCount.clamp(0, 6).toDouble() * 1.75;
    if (artistHasLikedTrack) {
      value += 4.0;
    }

    final candidateArtist = normalizeArtist(video.channelTitle);
    final activeArtist = normalizeArtist(currentArtist ?? '');
    if (candidateArtist.isNotEmpty && candidateArtist == activeArtist) {
      value -= 11.0;
    }

    // Popularity and freshness are only tie-breakers; personal feedback remains
    // more influential than views or upload date.
    final views = (video.viewCount ?? 0).clamp(0, 1000000000).toInt();
    if (views > 0) {
      value += (math.log(views + 1) / math.ln10 * 0.7).clamp(0.0, 7.0).toDouble();
    }

    final publishedAt = video.publishedAt;
    if (publishedAt != null) {
      final ageDays = clock.difference(publishedAt).inDays;
      if (ageDays >= 0 && ageDays <= 14) {
        value += 3.0;
      } else if (ageDays > 14 && ageDays <= 60) {
        value += 1.25;
      }
    }

    return value;
  }

  /// Normalizes channel/artist display names for consistency checks.
  static String normalizeArtist(String value) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(
            r'\b(?:official|artist|channel|topic|vevo|records?|music|entertainment|audio|label)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
