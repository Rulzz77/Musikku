/// Small data models returned by the authenticated YouTube account API.
/// Kept outside the service implementation so repositories and views can
/// depend on the model contracts without importing authentication internals.
library;

class YoutubeChannelSummary {
  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final String uploadsPlaylistId;
  final int? subscriberCount;

  const YoutubeChannelSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    required this.uploadsPlaylistId,
    this.subscriberCount,
  });
}

class YoutubeChannelDetails {
  final String id;
  final String title;
  final String handle;
  final String description;
  final String avatarUrl;
  final String bannerUrl;
  final int? subscriberCount;
  final bool hiddenSubscriberCount;
  final int? videoCount;
  final String uploadsPlaylistId;

  const YoutubeChannelDetails({
    required this.id,
    required this.title,
    this.handle = '',
    this.description = '',
    this.avatarUrl = '',
    this.bannerUrl = '',
    this.subscriberCount,
    this.hiddenSubscriberCount = false,
    this.videoCount,
    this.uploadsPlaylistId = '',
  });
}

class YoutubePlaylistSummary {
  final String id;
  final String title;
  final String description;
  final String privacyStatus;
  final int itemCount;
  final String thumbnailUrl;

  const YoutubePlaylistSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.privacyStatus,
    required this.itemCount,
    this.thumbnailUrl = '',
  });
}

