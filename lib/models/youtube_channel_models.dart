/// Public metadata about a YouTube channel. No account login is required.
library;

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

