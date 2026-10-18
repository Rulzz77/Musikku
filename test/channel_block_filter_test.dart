import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/channel_block_filter.dart';

YoutubeSearchResult makeVideo({
  String channelId = '',
  String channelTitle = 'The Band - Official',
  String videoId = 'video-1',
  String sourceType = 'youtube',
}) {
  return YoutubeSearchResult(
    videoId: videoId,
    title: 'Song',
    channelTitle: channelTitle,
    thumbnailUrl: '',
    channelId: channelId,
    sourceType: sourceType,
  );
}

void main() {
  group('ChannelBlockFilter', () {
    test('matches YouTube channel IDs exactly', () {
      final video = makeVideo(channelId: 'UCAbC123');
      expect(ChannelBlockFilter.keysFor(video), contains('id:UCAbC123'));
      expect(ChannelBlockFilter.isBlocked(video, {'id:UCAbC123'}), isTrue);
      // IDs are case-sensitive identifiers, so do not lowercase them.
      expect(ChannelBlockFilter.isBlocked(video, {'id:ucabc123'}), isFalse);
    });

    test('falls back to normalized channel title when ID is missing', () {
      final video = makeVideo(channelTitle: 'The Band - Official!');
      expect(ChannelBlockFilter.keysFor(video), contains('name:the band official'));
      expect(ChannelBlockFilter.isBlocked(video, {'name:the band official'}), isTrue);
    });

    test('does not block local music by matching artist names', () {
      final local = makeVideo(
        channelTitle: 'The Band - Official',
        videoId: 'local:123',
        sourceType: 'local',
      );
      expect(ChannelBlockFilter.keysFor(local), isEmpty);
      expect(ChannelBlockFilter.isBlocked(local, {'name:the band official'}), isFalse);
    });

    test('does not block a channel unless a matching key exists', () {
      final video = makeVideo(channelId: 'UCDifferent');
      expect(ChannelBlockFilter.isBlocked(video, {'id:UCOther'}), isFalse);
    });
  });
}
