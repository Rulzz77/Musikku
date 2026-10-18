import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/services/youtube_account_response_parser.dart';
import 'package:flutter_application_5/services/youtube_search_response_parser.dart';

void main() {
  group('YouTube response parsers', () {
    test('decodes HTML entities in search results', () {
      final tracks = YoutubeSearchResponseParser.parseSearchItems([
        {
          'id': {'videoId': 'video-123'},
          'snippet': {
            'title': 'A &amp; B &#39;Live&#39;',
            'channelTitle': 'Artis &quot;Resmi&quot;',
            'publishedAt': '2026-01-01T00:00:00Z',
            'channelId': 'channel-1',
            'thumbnails': {
              'high': {'url': 'https://img.example/high.jpg'},
            },
          },
        },
      ]);

      expect(tracks, hasLength(1));
      expect(tracks.single.videoId, 'video-123');
      expect(tracks.single.title, "A & B 'Live'");
      expect(tracks.single.channelTitle, 'Artis "Resmi"');
      expect(tracks.single.thumbnailUrl, 'https://img.example/high.jpg');
      expect(tracks.single.channelId, 'channel-1');
    });

    test('maps playlist items into track models', () {
      final tracks = YoutubeAccountResponseParser.playlistItemsToTracks({
        'items': [
          {
            'snippet': {
              'title': 'Lagu Favorit',
              'videoOwnerChannelTitle': 'Nama Artis',
              'videoOwnerChannelId': 'channel-9',
              'publishedAt': '2026-02-01T00:00:00Z',
              'thumbnails': {
                'high': {'url': 'https://img.example/playlist.jpg'},
              },
            },
            'contentDetails': {'videoId': 'video-9'},
          },
        ],
      });

      expect(tracks, hasLength(1));
      expect(tracks.single.videoId, 'video-9');
      expect(tracks.single.title, 'Lagu Favorit');
      expect(tracks.single.channelTitle, 'Nama Artis');
      expect(tracks.single.channelId, 'channel-9');
      expect(tracks.single.thumbnailUrl, 'https://img.example/playlist.jpg');
    });
  });
}
