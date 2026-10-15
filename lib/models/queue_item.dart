import 'youtube_search_result.dart';

class QueueItem {
  final YoutubeSearchResult video;

  const QueueItem({
    required this.video,
  });

  String get id =>
      video.videoId;

  String get title =>
      video.title;

  String get author =>
      video.channelTitle;
}