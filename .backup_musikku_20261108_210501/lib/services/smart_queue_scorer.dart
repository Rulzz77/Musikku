import 'dart:math' as math;

import '../models/listening_stat.dart';
import '../models/youtube_search_result.dart';

/// Smart Queue 2.0: deterministic ranking signals based on the listener's
/// own history and the musical context of the currently playing track.
///
/// Discovery remains the responsibility of RadioService. This class only
/// ranks candidates already discovered/cached by the app; it never performs
/// network requests and never uses chart popularity as the main signal.
class SmartQueueScorer {
  const SmartQueueScorer._();

  static const double dislikedScore = -1000.0;

  /// Infer a conservative mood tag from a track title. We intentionally use
  /// title-only, high-confidence phrases; channel descriptions often contain
  /// unrelated keywords and cause bad mood matches.
  static String? moodFor(YoutubeSearchResult video) {
    final text = normalizeArtist(video.title);
    if (text.isEmpty) {
      return null;
    }

    if (_matchesAny(text, const [
      'heartbreak',
      'broken heart',
      'sad song',
      'sad version',
      'patah hati',
      'lagu sedih',
      'galau',
      'kecewa',
      'air mata',
      'crying',
      'tears',
    ])) {
      return 'sad';
    }
    if (_matchesAny(text, const [
      'workout',
      'party anthem',
      'dance mix',
      'dance hit',
      'upbeat',
      'high energy',
      'energetic',
      'semangat',
      'party',
    ])) {
      return 'energetic';
    }
    if (_matchesAny(text, const [
      'feel good',
      'happy song',
      'lagu bahagia',
      'ceria',
      'gembira',
    ])) {
      return 'happy';
    }
    if (_matchesAny(text, const [
      'love song',
      'romantic',
      'lagu cinta',
      'lagu romantis',
      'wedding song',
    ])) {
      return 'romantic';
    }
    if (_matchesAny(text, const [
      'acoustic',
      'akustik',
      'chill',
      'mellow',
      'relaxing',
      'relax',
      'calm',
      'easy listening',
      'lofi',
      'lo fi',
    ])) {
      return 'chill';
    }
    return null;
  }

  /// A small mood contribution. It can soften language changes when the
  /// emotional character is a clear match, without overriding genre fit.
  static double moodAffinity({
    required YoutubeSearchResult current,
    required YoutubeSearchResult candidate,
  }) {
    final currentMood = moodFor(current);
    final candidateMood = moodFor(candidate);
    if (currentMood == null || candidateMood == null) {
      return 0.0;
    }
    if (currentMood == candidateMood) {
      return 7.0;
    }

    const related = <String, Set<String>>{
      'sad': {'chill', 'romantic'},
      'chill': {'sad', 'romantic'},
      'romantic': {'sad', 'chill'},
      'happy': {'energetic'},
      'energetic': {'happy'},
    };
    if (related[currentMood]?.contains(candidateMood) ?? false) {
      return 2.5;
    }
    return -3.0;
  }

  static bool _matchesAny(String text, Iterable<String> phrases) {
    final padded = ' $text ';
    return phrases.any((phrase) => padded.contains(' $phrase '));
  }

  /// Score a candidate. Higher is better. Values are intentionally bounded so
  /// one lifetime statistic cannot overpower genre/context compatibility.
  static double score({
    required YoutubeSearchResult video,
    ListeningStat? stat,
    bool isLiked = false,
    bool isDisliked = false,
    String? currentArtist,
    String? candidateArtist,
    int artistPlayCount = 0,
    int artistSkipCount = 0,
    bool artistHasLikedTrack = false,
    double musicalSimilarity = 0.0,
    YoutubeSearchResult? currentVideo,
    Iterable<String> recentArtistKeys = const <String>[],
    DateTime? now,
  }) {
    if (isDisliked) {
      return dislikedScore;
    }

    final clock = now ?? DateTime.now();
    var value = 10.0;

    // Musical fit is the strongest non-explicit signal. radioSimilarityScore
    // normally ranges from about 15 to 56 for compatible candidates.
    value += musicalSimilarity.clamp(-100.0, 56.0).toDouble() * 0.32;

    // Explicit feedback always outweighs passive listening history.
    if (isLiked) {
      value += 20.0;
    }

    if (stat != null) {
      final lifetimePlays = stat.playCount.clamp(0, 1000000).toInt();
      final plays = lifetimePlays.clamp(0, 50).toInt();
      final skips = stat.skipCount.clamp(0, 20).toInt();

      // Logarithmic preference avoids allowing a handful of lifetime-favourite
      // tracks to dominate every future queue.
      value += math.log(plays + 1) / math.ln2 * 1.35;

      // Use average listened time per play, rather than lifetime seconds. This
      // estimates completion without letting an old, frequently played track
      // accumulate an unlimited bonus.
      if (stat.listenedSeconds > 0) {
        final averageListened =
            stat.listenedSeconds / math.max(1, lifetimePlays);
        final expectedDuration = video.durationSeconds;
        final denominator = expectedDuration != null && expectedDuration > 0
            ? expectedDuration
            : 240.0;
        final completion = (averageListened / denominator)
            .clamp(0.0, 1.0)
            .toDouble();
        value += completion * 5.0;
      }

      if (skips > 0) {
        final totalSignals = math.max(1, plays + skips);
        final skipRate = (skips / totalSignals).clamp(0.0, 1.0).toDouble();
        value -= skipRate * 10.0;
        value -= math.min(skips, 6).toDouble() * 1.25;
      }

      final lastPlayed = stat.lastPlayedAt;
      if (lastPlayed != null) {
        final elapsedHours = clock.difference(lastPlayed).inMinutes / 60.0;
        if (elapsedHours >= 0 && elapsedHours < 6) {
          value -= 14.0;
        } else if (elapsedHours >= 6 && elapsedHours < 24) {
          value -= 10.0;
        } else if (elapsedHours >= 24 && elapsedHours < 72) {
          value -= 5.5;
        } else if (elapsedHours >= 72 && elapsedHours < 168) {
          value -= 2.0;
        }
      }
    }

    // Artist-level affinity is capped and logarithmic so the queue can learn
    // taste without getting trapped in one artist's catalogue.
    final artistPlays = artistPlayCount.clamp(0, 80).toInt();
    value += math.log(artistPlays + 1) / math.ln2 * 0.9;
    value -= artistSkipCount.clamp(0, 8).toInt() * 1.2;
    if (artistHasLikedTrack) {
      value += 3.5;
    }

    final candidateKey = normalizeArtist(candidateArtist ?? video.channelTitle);
    final activeArtist = normalizeArtist(currentArtist ?? currentVideo?.channelTitle ?? '');
    if (candidateKey.isNotEmpty && candidateKey == activeArtist) {
      value -= 10.0;
    }

    if (candidateKey.isNotEmpty) {
      final recentKeys = recentArtistKeys
          .map(normalizeArtist)
          .where((key) => key.isNotEmpty)
          .toList(growable: false);
      final occurrences = recentKeys.where((key) => key == candidateKey).length;
      value -= math.min(occurrences, 4).toDouble() * 4.0;
      if (recentKeys.isNotEmpty && recentKeys.last == candidateKey) {
        value -= 6.0;
      }
    }

    if (currentVideo != null) {
      value += moodAffinity(current: currentVideo, candidate: video);
    }

    // Popularity is deliberately only a tiny tie-breaker. A high view count
    // must not make an unrelated chart hit win over the listener's taste.
    final views = (video.viewCount ?? 0).clamp(0, 1000000000).toInt();
    if (views > 0) {
      value += (math.log(views + 1) / math.ln10 * 0.22)
          .clamp(0.0, 2.0)
          .toDouble();
    }

    final publishedAt = video.publishedAt ?? video.approxPublishedAt;
    if (publishedAt != null) {
      final ageDays = clock.difference(publishedAt).inDays;
      if (ageDays >= 0 && ageDays <= 14) {
        value += 1.0;
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
        .replaceAll(RegExp(r'[^a-z0-9\u0080-\uFFFF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
