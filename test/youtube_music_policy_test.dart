import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/youtube_music_policy.dart';

void main() {
  YoutubeSearchResult video({
    String title = 'Contoh Lagu Resmi',
    String description = '',
    String channelTitle = 'Penyanyi Resmi',
    String categoryId = '10',
    String sourceType = 'youtube',
    double? durationSeconds,
  }) {
    return YoutubeSearchResult(
      videoId: 'video-test-001',
      title: title,
      description: description,
      channelTitle: channelTitle,
      thumbnailUrl: '',
      categoryId: categoryId,
      sourceType: sourceType,
      durationSeconds: durationSeconds,
    );
  }

  group('YoutubeMusicPolicy.isMusicChannelUpload', () {
    test('accepts a cover when YouTube labels it Entertainment', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(title: 'Sisa Rasa - Mahalini (Cover by Naya)', categoryId: '24'),
          channelTitle: 'Naya Acoustic',
          channelDescription: 'Penyanyi independen, cover lagu akustik.',
        ),
        isTrue,
      );
    });

    test('accepts ordinary song titles from a music-oriented channel even without category 10', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(title: 'Sisa Rasa', categoryId: '24'),
          channelTitle: 'Naya Putri',
          channelDescription: 'Vocalist and singer-songwriter sharing acoustic music.',
        ),
        isTrue,
      );
    });

    test('accepts a cover whose song title contains an ambiguous common word', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(title: 'Talking to the Moon (Cover)', categoryId: '24'),
          channelTitle: 'Rina Acoustic',
          channelDescription: 'Penyanyi independen.',
        ),
        isTrue,
      );
    });

    test('accepts cover uploads with missing category metadata', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(title: 'Tak Ingin Usai (Cover Lagu)', categoryId: ''),
          channelTitle: 'Dina',
        ),
        isTrue,
      );
    });

    test('uses video description to recognize a cover with a plain title', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(
            title: 'Sisa Rasa',
            description: 'Cover lagu akustik dinyanyikan oleh penyanyi independen.',
            categoryId: '24',
          ),
          channelTitle: 'Naya',
        ),
        isTrue,
      );
    });

    test('does not treat background-music credits alone as a cover signal', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(
            title: 'Jalan-jalan ke Bandung',
            description: 'Background music by an independent composer.',
            categoryId: '24',
          ),
          channelTitle: 'Naya',
        ),
        isFalse,
      );
    });

    test('rejects Shorts even when the title otherwise says cover', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(title: 'Perfect (Cover) #Shorts', categoryId: '24'),
          channelTitle: 'Rina Acoustic',
          channelDescription: 'Penyanyi dan cover lagu.',
        ),
        isFalse,
      );
    });

    test('still rejects obviously non-music channel uploads', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(title: 'Review gadget terbaru', categoryId: '24'),
          channelTitle: 'Tech Review Indonesia',
          channelDescription: 'Review gadget dan berita teknologi.',
        ),
        isFalse,
      );
    });

    test('rejects a short non-music upload even on a subscribed channel', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(
            title: 'Momen tidak biasa',
            categoryId: '10',
            durationSeconds: 110,
          ),
          channelTitle: 'Random Creator',
          channelDescription: 'Konten sehari-hari dan hiburan.',
        ),
        isFalse,
      );
    });

    test('does not require an official artist/channel marker', () {
      expect(
        YoutubeMusicPolicy.isMusicChannelUpload(
          video(title: 'Perfect (Cover)', categoryId: '24'),
          channelTitle: 'Rina Acoustic',
          channelDescription: 'Nyanyian dan cover lagu dari rumah.',
        ),
        isTrue,
      );
    });
  });

  group('YoutubeMusicPolicy.isLikelyMusicChannelProfile', () {
    test('recognizes profile signals for cover and independent music channels', () {
      expect(
        YoutubeMusicPolicy.isLikelyMusicChannelProfile(
          'Rina Acoustic',
          'Penyanyi independen yang membagikan cover lagu.',
        ),
        isTrue,
      );
    });

    test('does not identify a generic news channel as music by profile alone', () {
      expect(
        YoutubeMusicPolicy.isLikelyMusicChannelProfile(
          'Berita Hari Ini',
          'Berita nasional dan laporan harian.',
        ),
        isFalse,
      );
    });
  });

  group('YoutubeMusicPolicy.isMusicCatalogItem', () {
    test('accepts a music-category upload with ordinary song metadata', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(),
          requireCategoryId: true,
        ),
        isTrue,
      );
    });

    test('rejects a missing category when verification is required', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(categoryId: ''),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('rejects obvious Shorts labels', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(title: 'Lagu viral #Shorts'),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('rejects obvious non-music uploads', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(title: 'Interview dengan artis'),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('matches non-music labels as words instead of broad substrings', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(title: 'Newsboys - He Reigns', channelTitle: 'Newsboys Official'),
          requireCategoryId: true,
        ),
        isTrue,
      );
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(title: 'Podcast interview bersama penyanyi'),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('does not reject local music because it has no YouTube category', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(categoryId: '', sourceType: 'local'),
          requireCategoryId: true,
        ),
        isTrue,
      );
    });

    test('rejects a short video with no music signals even if category says Music', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(
            title: 'Kucing jatuh lalu kabur',
            channelTitle: 'Random Viral Channel',
            categoryId: '10',
            durationSeconds: 125,
          ),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('does not accept a generic short merely because the channel says Music', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(
            title: 'Momen tidak biasa',
            channelTitle: 'Music Channel Official',
            categoryId: '10',
            durationSeconds: 110,
          ),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });


    test('rejects a non-music short even when title mentions an instrument', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(
            title: 'Guitar prank fails',
            channelTitle: 'Random Viral Channel',
            categoryId: '10',
            durationSeconds: 95,
          ),
          requireCategoryId: true,
        ),
        isFalse,
      );
    });

    test('does not accept a generic short only because subscribed channel profile says music', () {
      expect(
        YoutubeMusicPolicy.isLikelyNonMusicShort(
          video(
            title: 'Momen tidak biasa',
            channelTitle: 'Music Channel Official',
            categoryId: '10',
            durationSeconds: 110,
          ),
          channelTitle: 'Music Channel Official',
          channelDescription: 'Channel musik dan hiburan sehari-hari.',
        ),
        isTrue,
      );
    });

    test('keeps a short official audio track with clear music signals', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(
            title: 'Sisa Rasa (Official Audio)',
            channelTitle: 'Mahalini',
            categoryId: '10',
            durationSeconds: 150,
          ),
          requireCategoryId: true,
        ),
        isTrue,
      );
    });

    test('keeps a short Art Track title when the channel is YouTube Topic', () {
      expect(
        YoutubeMusicPolicy.isMusicCatalogItem(
          video(
            title: 'Ariana Grande - 7 rings',
            channelTitle: 'Ariana Grande - Topic',
            categoryId: '10',
            durationSeconds: 170,
          ),
          requireCategoryId: true,
        ),
        isTrue,
      );
    });
  });
  group('YoutubeMusicPolicy.classifyShortsProbeStatus', () {
    test('requires page metadata for a 200 response', () {
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(200), isNull);
    });

    test('classifies explicit redirect targets and leaves unknown targets ambiguous', () {
      expect(
        YoutubeMusicPolicy.classifyShortsProbeStatus(302, location: 'https://www.youtube.com/watch?v=abc'),
        isFalse,
      );
      expect(
        YoutubeMusicPolicy.classifyShortsProbeStatus(303, location: '/shorts/abc'),
        isTrue,
      );
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(302), isNull);
    });

    test('leaves throttled and error responses ambiguous', () {
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(403), isNull);
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(405), isNull);
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(429), isNull);
      expect(YoutubeMusicPolicy.classifyShortsProbeStatus(503), isNull);
    });

    test('uses a canonical Shorts route when the response status is 200', () {
      expect(
        YoutubeMusicPolicy.classifyShortsPageHtml(
          '<link rel="canonical" href="https://www.youtube.com/shorts/abc123">',
        ),
        isTrue,
      );
    });

    test('keeps ordinary watch pages when canonical route says watch', () {
      expect(
        YoutubeMusicPolicy.classifyShortsPageHtml(
          '<link rel="canonical" href="https://www.youtube.com/watch?v=abc123">',
        ),
        isFalse,
      );
    });

    test('leaves HTML without route metadata ambiguous', () {
      expect(YoutubeMusicPolicy.classifyShortsPageHtml('<html>blocked</html>'), isNull);
    });
  });


  test('detects Shorts marker in video description without network probing', () {
    expect(
      YoutubeMusicPolicy.isLikelyShortForm(
        video(
          title: 'Sisa Rasa - Cover',
          description: 'Lagu akustik #Shorts',
          categoryId: '24',
        ),
      ),
      isTrue,
    );
  });

}
