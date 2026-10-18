import '../models/youtube_account_models.dart';
import '../models/youtube_search_result.dart';

/// Narrow contract used by the YouTube library repository. The concrete Google
/// account service and tests can implement this without coupling consumers to
/// OAuth, persistence, or HTTP implementation details.
abstract interface class YoutubeLibraryApi {
  Future<List<YoutubeChannelSummary>> subscriptions({int maxResults = 50});
  Future<List<YoutubeSearchResult>> likedVideos({int maxResults = 50});
  Future<List<YoutubePlaylistSummary>> playlists({int maxResults = 50});
  Future<List<YoutubeSearchResult>> subscriptionFeed(
    List<YoutubeChannelSummary> channels, {
    int channelLimit = 20,
    int perChannel = 3,
  });
  Future<List<YoutubeSearchResult>> playlistItems(
    String playlistId, {
    int maxResults = 50,
  });
}
