import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/playlist.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';

void main() {
  group('Playlist track identity', () {
    YoutubeSearchResult track({
      required String id,
      required String title,
      required String channel,
      String artist = '',
      String sourceChannel = '',
      String sourceVideoTitle = '',
      String spotifyTrackId = '',
      int? spotifyDurationMs,
      double? durationSeconds = 235,
      bool local = false,
    }) => YoutubeSearchResult(
          videoId: id,
          title: title,
          channelTitle: channel,
          artistName: artist,
          sourceChannelTitle: sourceChannel,
          sourceVideoTitle: sourceVideoTitle,
          spotifyTrackId: spotifyTrackId,
          spotifyDurationMs: spotifyDurationMs,
          durationSeconds: durationSeconds,
          thumbnailUrl: '',
          sourceType: local ? 'local' : 'youtube',
        );

    test('recognizes a Spotify-imported song from a different YouTube result ID', () {
      final imported = track(
        id: 'spotify-match-video',
        title: 'Cundamani',
        channel: 'Denny Caknan',
        artist: 'Denny Caknan',
        sourceChannel: 'Musica Studios',
        spotifyTrackId: 'spotify-cundamani-1',
        spotifyDurationMs: 235000,
      );
      final searchResult = track(
        id: 'another-youtube-video-id',
        title: 'Denny Caknan - Cundamani (Official Audio)',
        channel: 'Denny Caknan - Topic',
        durationSeconds: 235,
      );
      final playlist = Playlist(id: 'one', name: 'Impor Spotify', songs: [imported]);

      expect(playlist.containsTrack(searchResult), isTrue);
      expect(Playlist.sameTrack(imported, searchResult), isTrue);
    });

    test('does not mark the same title and artist when the recording duration differs', () {
      final imported = track(
        id: 'studio-cinta',
        title: 'Cinta',
        channel: 'Penyanyi A',
        artist: 'Penyanyi A',
        spotifyTrackId: 'spotify-cinta-studio',
        spotifyDurationMs: 220000,
        durationSeconds: 220,
      );
      final alternateRecording = track(
        id: 'live-cinta',
        title: 'Cinta',
        channel: 'Penyanyi A - Topic',
        durationSeconds: 278,
        sourceVideoTitle: 'Penyanyi A - Cinta (Official Audio)',
      );
      final playlist = Playlist(id: 'one', name: 'Mix', songs: [imported]);

      expect(playlist.containsTrack(alternateRecording), isFalse);
    });

    test('does not mark a same-title same-artist item when version tags differ', () {
      final imported = track(
        id: 'studio-song',
        title: 'Nemen',
        channel: 'Guyon Waton',
        artist: 'Guyon Waton',
        sourceVideoTitle: 'Nemen (Official Music Video)',
        spotifyTrackId: 'spotify-nemen-studio',
        spotifyDurationMs: 260000,
      );
      final liveVersion = track(
        id: 'live-song',
        title: 'Nemen (Official Live Music)',
        channel: 'Guyon Waton - Topic',
        artist: 'Guyon Waton',
        durationSeconds: 260,
      );
      final playlist = Playlist(id: 'one', name: 'Mix', songs: [imported]);

      expect(playlist.containsTrack(liveVersion), isFalse);
    });

    test('does not use title and artist alone when duration is missing', () {
      final imported = track(
        id: 'saved-song',
        title: 'Cinta',
        channel: 'Penyanyi A',
        artist: 'Penyanyi A',
        durationSeconds: null,
      );
      final unknownDuration = track(
        id: 'unknown-duration-song',
        title: 'Cinta',
        channel: 'Penyanyi A - Topic',
        durationSeconds: null,
      );
      final playlist = Playlist(id: 'one', name: 'Mix', songs: [imported]);

      expect(playlist.containsTrack(unknownDuration), isFalse);
    });

    test('different Spotify track IDs never collapse into one playlist item', () {
      final first = track(
        id: 'first-video',
        title: 'Cinta',
        channel: 'Penyanyi A',
        artist: 'Penyanyi A',
        spotifyTrackId: 'spotify-cinta-single',
        spotifyDurationMs: 220000,
      );
      final second = track(
        id: 'second-video',
        title: 'Cinta',
        channel: 'Penyanyi A',
        artist: 'Penyanyi A',
        spotifyTrackId: 'spotify-cinta-live',
        spotifyDurationMs: 220000,
      );
      final playlist = Playlist(id: 'one', name: 'Mix', songs: [first]);

      expect(playlist.containsTrack(second), isFalse);
    });

    test('does not mark a same-title song from a different artist as added', () {
      final imported = track(
        id: 'imported-id',
        title: 'Cinta',
        channel: 'Penyanyi A',
        artist: 'Penyanyi A',
      );
      final otherArtist = track(
        id: 'other-id',
        title: 'Cinta (Official Audio)',
        channel: 'Penyanyi B - Topic',
      );
      final playlist = Playlist(id: 'one', name: 'Impor Spotify', songs: [imported]);

      expect(playlist.containsTrack(otherArtist), isFalse);
    });

    test('recognizes artist-prefixed YouTube title when its upload channel is a label', () {
      final imported = track(
        id: 'imported-id',
        title: 'Celengan Rindu',
        channel: 'Fiersa Besari',
        artist: 'Fiersa Besari',
        sourceChannel: 'Musica Studios',
      );
      final labelResult = track(
        id: 'label-video-id',
        title: 'Fiersa Besari - Celengan Rindu (Official Music Video)',
        channel: 'Musica Studios',
      );
      final playlist = Playlist(id: 'one', name: 'Impor Spotify', songs: [imported]);

      expect(playlist.containsTrack(labelResult), isTrue);
    });


    test('recognizes a label-uploaded item from structured YouTube Music performer credits', () {
      final imported = track(
        id: 'spotify-import-video',
        title: 'Dumes',
        channel: 'OMWAWES, Guyon Waton',
        artist: 'OMWAWES',
        sourceChannel: 'Musica Studios',
      );
      final searchResult = YoutubeSearchResult(
        videoId: 'different-youtube-video',
        title: 'Dumes (Official Audio)',
        channelTitle: 'Musica Studios',
        description: 'Provided to YouTube by Musica Studios\n\n'
            'Dumes · OMWAWES · Guyon Waton\n'
            'Album: Dumes\n',
        thumbnailUrl: '',
        durationSeconds: 235,
      );
      final playlist = Playlist(id: 'one', name: 'Impor Spotify', songs: [imported]);

      expect(playlist.containsTrack(searchResult), isTrue);
    });

    test('matches a Spotify collaboration when YouTube surfaces the second credited artist', () {
      final imported = track(
        id: 'spotify-satru',
        title: 'Satru',
        channel: 'Denny Caknan, Happy Asmara',
        artist: 'Denny Caknan',
        spotifyTrackId: 'spotify-satru-2',
        spotifyDurationMs: 235000,
        sourceVideoTitle: 'Satru (Official Audio)',
      );
      final youtubeResult = track(
        id: 'youtube-satru-topic',
        title: 'Satru (Official Audio)',
        channel: 'Happy Asmara - Topic',
        artist: 'Happy Asmara',
      );
      final playlist = Playlist(
        id: 'one',
        name: 'Impor Spotify',
        songs: [imported],
      );

      expect(playlist.containsTrack(youtubeResult), isTrue);
    });

    test('does not mark same title from a label with no performer evidence as added', () {
      final imported = track(
        id: 'spotify-import-video',
        title: 'Dumes',
        channel: 'Guyon Waton',
        artist: 'Guyon Waton',
      );
      final unknownUpload = track(
        id: 'unknown-label-upload',
        title: 'Dumes (Official Audio)',
        channel: 'Musica Studios',
      );
      final playlist = Playlist(id: 'one', name: 'Impor Spotify', songs: [imported]);

      expect(playlist.containsTrack(unknownUpload), isFalse);
    });

    test('matches a label upload when the generated YouTube credit names the artist', () {
      final imported = track(
        id: 'spotify-import-video',
        title: 'Cundamani',
        channel: 'Denny Caknan',
        artist: 'Denny Caknan',
      );
      final labelSearchResult = YoutubeSearchResult(
        videoId: 'search-result-video',
        title: 'Cundamani (Official Audio)',
        channelTitle: 'Musica Studios',
        description: 'Provided to YouTube by Musica Studios\n\n'
            'Cundamani · Denny Caknan\n'
            'Album: Cundamani\n'
            'Auto-generated by YouTube.',
        thumbnailUrl: '',
        durationSeconds: 235,
      );
      final playlist = Playlist(
        id: 'one',
        name: 'Impor Spotify',
        songs: [imported],
      );

      expect(playlist.containsTrack(labelSearchResult), isTrue);
    });

    test('does not mark a non-identical cover as the imported original track', () {
      final imported = track(
        id: 'spotify-import-video',
        title: 'Cundamani',
        channel: 'Denny Caknan',
        artist: 'Denny Caknan',
      );
      final cover = track(
        id: 'cover-video',
        title: 'Cundamani Cover by Another Singer',
        channel: 'Another Singer',
        artist: 'Another Singer',
      );
      final playlist = Playlist(
        id: 'one',
        name: 'Impor Spotify',
        songs: [imported],
      );

      expect(playlist.containsTrack(cover), isFalse);
    });

    test('does not conflate different songs by the same artist', () {
      final imported = track(
        id: 'imported-id',
        title: 'Cundamani',
        channel: 'Denny Caknan',
        artist: 'Denny Caknan',
      );
      final differentSong = track(
        id: 'different-id',
        title: 'Cundamani 2',
        channel: 'Denny Caknan - Topic',
      );
      final playlist = Playlist(id: 'one', name: 'Impor Spotify', songs: [imported]);

      expect(playlist.containsTrack(differentSong), isFalse);
    });

    test('does not cross-match local files by title and artist only', () {
      final local = track(
        id: 'local:123',
        title: 'Cundamani',
        channel: 'Denny Caknan',
        artist: 'Denny Caknan',
        local: true,
      );
      final youtube = track(
        id: 'youtube-123',
        title: 'Cundamani',
        channel: 'Denny Caknan - Topic',
      );
      final playlist = Playlist(id: 'one', name: 'Lokal', songs: [local]);

      expect(playlist.containsTrack(youtube), isFalse);
    });
  });
}
