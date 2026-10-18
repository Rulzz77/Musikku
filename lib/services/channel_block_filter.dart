import '../models/youtube_search_result.dart';

/// Identitas channel yang disembunyikan dari rekomendasi Radio.
///
/// Channel ID menjadi kunci utama saat tersedia. Nama channel juga disimpan
/// sebagai fallback untuk metadata lama yang belum memiliki channelId.
/// Lagu lokal sengaja tidak ikut diblokir karena nama artis lokal bukan channel.
class ChannelBlockFilter {
  const ChannelBlockFilter._();

  static Set<String> keysFor(YoutubeSearchResult video) {
    if (video.isLocal) return <String>{};

    final keys = <String>{};
    final channelId = video.channelId.trim();
    if (channelId.isNotEmpty) {
      // Channel IDs are identifiers, not display text: preserve exact case.
      keys.add('id:$channelId');
      return keys;
    }

    // Metadata lama kadang tidak berisi channelId; nama hanya fallback.
    final channelName = normalizeChannelName(video.channelTitle);
    if (channelName.isNotEmpty) {
      keys.add('name:$channelName');
    }
    return keys;
  }

  static String normalizeChannelName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[.,:;|/\\()\[\]{}"!?_–—-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool isBlocked(YoutubeSearchResult video, Set<String> blockedKeys) {
    if (blockedKeys.isEmpty || video.isLocal) return false;
    return keysFor(video).any(blockedKeys.contains);
  }
}
