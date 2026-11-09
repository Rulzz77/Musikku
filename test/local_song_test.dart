import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/local_song.dart';

void main() {
  group('LocalSong', () {
    test('creates a stable local playback item with its media URI', () {
      const song = LocalSong(
        mediaId: '4321',
        title: 'Contoh Lagu',
        artist: 'Contoh Artis',
        album: 'Contoh Album',
        durationMs: 212000,
        uri: 'content://media/external/audio/media/4321',
      );

      final playable = song.toPlayable();

      expect(playable.videoId, 'local:4321');
      expect(playable.isLocal, isTrue);
      expect(playable.mediaUri, song.uri);
      expect(playable.localMediaId, song.mediaId);
      expect(playable.durationSeconds, 212);
      expect(playable.title, song.title);
      expect(playable.channelTitle, song.artist);
    });

    test('uses a readable artist fallback when metadata is missing', () {
      const song = LocalSong(
        mediaId: '99',
        title: 'Tanpa Artis',
        artist: '',
        album: '',
        durationMs: 90000,
        uri: 'content://media/external/audio/media/99',
      );

      expect(song.toPlayable().channelTitle, 'Artis tidak diketahui');
    });
  });
}
