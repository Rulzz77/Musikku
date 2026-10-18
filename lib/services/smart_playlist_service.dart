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
    final known = <String, YoutubeSearchResult>{};
    for (final song in <YoutubeSearchResult>[...catalog, ...recentlyPlayed, ...favorites]) {
      if (song.videoId.isNotEmpty) known[song.videoId] = song;
    }

    List<YoutubeSearchResult> uniqueTracks(Iterable<YoutubeSearchResult> songs) {
      final seen = <String>{};
      return songs
          .where((song) => song.videoId.isNotEmpty && seen.add(song.videoId))
          .take(limit)
          .toList(growable: false);
    }

    final result = <SmartPlaylist>[];
    final favoriteMix = uniqueTracks(favorites);
    if (favoriteMix.isNotEmpty) {
      result.add(SmartPlaylist(
        id: 'smart_favorites',
        title: 'Mix Favorit',
        subtitle: '${favoriteMix.length} lagu yang kamu simpan',
        songs: favoriteMix,
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
      for (final stat in listeningStats)
        if (stat.videoId.isNotEmpty) stat.videoId: stat,
    };
    final mostPlayed = known.values.where((song) {
      final stat = statsById[song.videoId];
      return stat != null && stat.playCount > 0;
    }).toList()
      ..sort((a, b) {
        final sa = statsById[a.videoId]!;
        final sb = statsById[b.videoId]!;
        final plays = sb.playCount.compareTo(sa.playCount);
        if (plays != 0) return plays;
        final listened = sb.listenedSeconds.compareTo(sa.listenedSeconds);
        if (listened != 0) return listened;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    final mostPlayedMix = uniqueTracks(mostPlayed);
    if (mostPlayedMix.isNotEmpty) {
      result.add(SmartPlaylist(
        id: 'smart_most_played',
        title: 'Paling Sering Diputar',
        subtitle: 'Diurutkan dari statistik pemutaran',
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
