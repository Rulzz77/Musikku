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



/// Public playlist metadata owned by a YouTube channel.
class YoutubePublicPlaylist {
  final String id;
  final String title;
  final String description;
  final String thumbnailUrl;
  final int itemCount;
  final DateTime? publishedAt;

  const YoutubePublicPlaylist({
    required this.id,
    required this.title,
    this.description = '',
    this.thumbnailUrl = '',
    this.itemCount = 0,
    this.publishedAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'description': description,
        'thumbnailUrl': thumbnailUrl,
        'itemCount': itemCount,
        'publishedAt': publishedAt?.toIso8601String(),
      };

  factory YoutubePublicPlaylist.fromJson(Map<String, dynamic> json) =>
      YoutubePublicPlaylist(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Playlist',
        description: json['description']?.toString() ?? '',
        thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
        itemCount: json['itemCount'] is num
            ? (json['itemCount'] as num).toInt()
            : int.tryParse(json['itemCount']?.toString() ?? '') ?? 0,
        publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      );
}
