import '../models/listening_stat.dart';
import '../models/youtube_search_result.dart';

/// A computed playlist. It is generated from local library/history and is not
/// persisted as a separate playlist, so its content naturally updates.
class SmartPlaylist {
  const SmartPlaylist({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.songs,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<YoutubeSearchResult> songs;
}

class SmartPlaylistService {
  const SmartPlaylistService._();

  static List<SmartPlaylist> build({
    required List<YoutubeSearchResult> favorites,
    required List<YoutubeSearchResult> recentlyPlayed,
    Iterable<ListeningStat> listeningStats = const <ListeningStat>[],
    Iterable<YoutubeSearchResult> catalog = const <YoutubeSearchResult>[],
    int maxSongs = 40,
  }) {
    final limit = maxSongs.clamp(1, 200).toInt();
    final statsList = listeningStats.toList(growable: false);
    final known = <String, YoutubeSearchResult>{};
    for (final song in <YoutubeSearchResult>[...catalog, ...recentlyPlayed, ...favorites]) {
      if (song.videoId.isNotEmpty) known[song.videoId] = song;
    }
    // Stats are the long-term listening library, not just the most recent 30
    // tracks. Rebuild YouTube song metadata from it so old repeat-listens can
    // still appear in the personalized mix after they leave recent history.
    for (final stat in statsList) {
      if (stat.videoId.isEmpty || stat.videoId.startsWith('local:')) continue;
      known.putIfAbsent(
        stat.videoId,
        () => YoutubeSearchResult(
          videoId: stat.videoId,
          title: stat.title.trim().isEmpty ? 'Tanpa judul' : stat.title,
          channelTitle: stat.artist.trim().isEmpty ? 'Artis tidak diketahui' : stat.artist,
          thumbnailUrl: stat.thumbnailUrl,
        ),
      );
    }

    List<YoutubeSearchResult> uniqueTracks(Iterable<YoutubeSearchResult> songs) {
      final seen = <String>{};
      return songs
          .where((song) => song.videoId.isNotEmpty && seen.add(song.videoId))
          .take(limit)
          .toList(growable: false);
    }

    final result = <SmartPlaylist>[];
    final favoriteTracks = uniqueTracks(favorites);
    if (favoriteTracks.isNotEmpty) {
      result.add(SmartPlaylist(
        id: 'smart_favorites',
        title: 'Favorit',
        subtitle: '${favoriteTracks.length} lagu yang kamu simpan',
        songs: favoriteTracks,
      ));
    }

    final recentMix = uniqueTracks(recentlyPlayed);
    if (recentMix.isNotEmpty) {
      result.add(SmartPlaylist(
        id: 'smart_recent',
        title: 'Baru Diputar',
        subtitle: 'Lanjutkan dari riwayat dengar',
        songs: recentMix,
      ));
    }

    final statsById = <String, ListeningStat>{
      for (final stat in statsList)
        if (stat.videoId.isNotEmpty) stat.videoId: stat,
    };
    // One play is not enough to qualify as a frequent-listening mix. Require
    // repeated starts and at least 30 seconds of real listening time so quick
    // skips do not get promoted as the user's favorites-by-habit.
    final mostPlayed = known.values.where((song) {
      final stat = statsById[song.videoId];
      return stat != null && stat.playCount >= 2 && stat.listenedSeconds >= 30;
    }).toList()
      ..sort((a, b) {
        final sa = statsById[a.videoId]!;
        final sb = statsById[b.videoId]!;
        final plays = sb.playCount.compareTo(sa.playCount);
        if (plays != 0) return plays;
        final listened = sb.listenedSeconds.compareTo(sa.listenedSeconds);
        if (listened != 0) return listened;
        final skipped = sa.skipCount.compareTo(sb.skipCount);
        if (skipped != 0) return skipped;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final mostPlayedMix = uniqueTracks(mostPlayed);
    if (mostPlayedMix.isNotEmpty) {
      result.insert(0, SmartPlaylist(
        id: 'smart_most_played',
        title: 'Mix Kamu',
        subtitle: 'Dibentuk dari lagu yang sering kamu putar',
        songs: mostPlayedMix,
      ));
    }

    // Rediscover prioritizes known tracks with the oldest playback timestamp.
    // If timestamps are unavailable, reverse a copy of history (oldest first).
    final recentIds = recentlyPlayed.take(4).map((song) => song.videoId).toSet();
    final rediscover = known.values.where((song) {
      final stat = statsById[song.videoId];
      return stat?.lastPlayedAt != null && !recentIds.contains(song.videoId);
    }).toList()
      ..sort((a, b) => statsById[a.videoId]!.lastPlayedAt!
          .compareTo(statsById[b.videoId]!.lastPlayedAt!));
    final rediscoverBase = rediscover.isNotEmpty
        ? rediscover
        : recentlyPlayed.length >= 3
            ? recentlyPlayed.reversed.toList()
            : const <YoutubeSearchResult>[];
    final rediscoverMix = uniqueTracks(rediscoverBase);
    if (rediscoverMix.isNotEmpty) {
      result.add(SmartPlaylist(
        id: 'smart_rediscover',
        title: 'Putar Lagi',
        subtitle: 'Lagu lama dari koleksimu',
        songs: rediscoverMix,
      ));
    }

    return result;
  }
}
