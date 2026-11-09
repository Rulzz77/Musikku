import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/youtube_music_policy.dart';

YoutubeSearchResult _video({
  required String id,
  required String title,
  required String channel,
  String description = '',
  String artistName = '',
  String musicDataTitle = '',
  String musicDataArtist = '',
  double? duration = 240,
}) => YoutubeSearchResult(
      videoId: id,
      title: title,
      channelTitle: channel,
      description: description,
      artistName: artistName,
      musicDataTitle: musicDataTitle,
      musicDataArtist: musicDataArtist,
      durationSeconds: duration,
      thumbnailUrl: '',
    );

void main() {
  group('YouTube search query matching', () {
    test('finds a track when the query contains only its title', () {
      final result = _video(id: 'title-only',
          title: 'Kartonyono Medot Janji (Official Music Video)',
          channel: 'Musica Studios');
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'Kartonyono Medot Janji'), isTrue);
    });

    test('finds songs when the query contains only the artist name', () {
      final result = _video(id: 'artist-only',
          title: 'Nemen (Official Music Video)', channel: 'Guyon Waton - Topic');
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'Guyon Waton'), isTrue);
    });

    test('matches mixed artist and title tokens across fields', () {
      final result = _video(id: 'mixed-query',
          title: 'Sigar (Official Music Video)', channel: 'Denny Caknan Official');
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'Denny Caknan Sigar'), isTrue);
    });

    test('keeps one-character CJK title tokens searchable', () {
      final result = _video(id: 'cjk-query', title: '花 (Official Audio)',
          channel: 'Artist - Topic');
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: '花'), isTrue);
    });

    test('keeps one-character Latin song titles searchable', () {
      final result = _video(
        id: 'latin-one-character',
        title: 'A (Official Audio)',
        channel: 'Artist - Topic',
      );
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'A'), isTrue);
    });

    test('keeps NDX A.K.A. initialism separate from one-letter titles', () {
      final result = _video(
        id: 'ndx-alias-after-initialism',
        title: 'Kelingan Mantan (Official Music Video)',
        channel: 'NDX AKA - Topic',
      );
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'NDX A.K.A.'), isTrue);
    });


    test('matches title-only query through structured YouTube Music title', () {
      final result = _video(
        id: 'structured-title',
        title: 'Provided to YouTube by Musica Studios',
        channel: 'Musica Studios',
        musicDataTitle: 'Sigar',
        musicDataArtist: 'Denny Caknan',
      );
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'Sigar'), isTrue);
    });

    test('matches artist-only query through structured MusicData credit', () {
      final result = _video(
        id: 'structured-artist',
        title: 'Provided to YouTube by Musica Studios',
        channel: 'Musica Studios',
        musicDataTitle: 'Sigar',
        musicDataArtist: 'Denny Caknan',
      );
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'Denny Caknan'), isTrue);
    });

    test('matches punctuation variants of NDX A.K.A. artist search', () {
      final result = _video(
        id: 'ndx-alias',
        title: 'Kelingan Mantan (Official Music Video)',
        channel: 'NDX AKA - Topic',
      );
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'NDX A.K.A.'), isTrue);
    });

    test('does not accept unrelated artist or title query', () {
      final result = _video(id: 'unrelated',
          title: 'Nemen (Official Music Video)', channel: 'Guyon Waton - Topic');
      expect(YoutubeMusicPolicy.isOfficialMusicReleaseCandidateForQuery(
        result, query: 'Ariana Grande'), isFalse);
    });
  });
}
