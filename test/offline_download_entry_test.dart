import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_5/models/youtube_search_result.dart';
import 'package:flutter_application_5/services/offline_download_service.dart';

void main() {
  YoutubeSearchResult song() => const YoutubeSearchResult(
        videoId: 'abcdefghijk',
        title: 'Test song',
        channelTitle: 'Test artist',
        thumbnailUrl: '',
      );

  test('restored download byte counts are clamped to non-negative values', () {
    final entry = OfflineDownloadEntry.fromJson({
      'song': song().toJson(),
      'status': 'paused',
      'downloadedBytes': -100,
      'totalBytes': -1,
    });

    expect(entry.downloadedBytes, 0);
    expect(entry.totalBytes, 0);
  });

  test('unknown persisted download status safely restores as paused', () {
    final entry = OfflineDownloadEntry.fromJson({
      'song': song().toJson(),
      'status': 'future-status',
      'downloadedBytes': '128',
      'totalBytes': '256',
    });

    expect(entry.status, OfflineDownloadStatus.paused);
    expect(entry.downloadedBytes, 128);
    expect(entry.totalBytes, 256);
  });

  test('enqueue result reports duplicate playlist rows separately', () {
    const result = OfflineEnqueueResult(
      added: 3,
      alreadyQueued: 1,
      alreadyDownloaded: 2,
      failed: 0,
      duplicateInput: 4,
    );

    expect(result.added, 3);
    expect(result.duplicateInput, 4);
  });
}
