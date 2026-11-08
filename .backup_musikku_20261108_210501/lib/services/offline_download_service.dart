import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_search_result.dart';
import 'offline_download_validation.dart';

enum OfflineDownloadStatus { queued, downloading, paused, completed, failed }

class OfflineEnqueueResult {
  const OfflineEnqueueResult({
    required this.added,
    required this.alreadyQueued,
    required this.alreadyDownloaded,
    required this.failed,
    this.duplicateInput = 0,
  });

  final int added;
  final int alreadyQueued;
  final int alreadyDownloaded;
  final int failed;
  final int duplicateInput;
}

class OfflineDownloadEntry {
  const OfflineDownloadEntry({
    required this.song,
    required this.status,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.filePath = '',
    this.errorMessage = '',
  });

  final YoutubeSearchResult song;
  final OfflineDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final String filePath;
  final String errorMessage;

  double get progress => totalBytes <= 0
      ? 0.0
      : (downloadedBytes / totalBytes).clamp(0.0, 1.0).toDouble();

  OfflineDownloadEntry copyWith({
    OfflineDownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    String? filePath,
    String? errorMessage,
  }) {
    return OfflineDownloadEntry(
      song: song,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      filePath: filePath ?? this.filePath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'song': song.toJson(),
        'status': status.name,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'filePath': filePath,
        'errorMessage': errorMessage,
      };

  factory OfflineDownloadEntry.fromJson(Map<String, dynamic> json) {
    final rawSong = json['song'];
    if (rawSong is! Map) {
      throw const FormatException('Data lagu unduhan tidak valid.');
    }
    final statusName = json['status']?.toString() ?? 'paused';
    final status = OfflineDownloadStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => OfflineDownloadStatus.paused,
    );
    return OfflineDownloadEntry(
      song: YoutubeSearchResult.fromJson(Map<String, dynamic>.from(rawSong)),
      status: status,
      downloadedBytes: _readNonNegativeInt(json['downloadedBytes']),
      totalBytes: _readNonNegativeInt(json['totalBytes']),
      filePath: json['filePath']?.toString() ?? '',
      errorMessage: json['errorMessage']?.toString() ?? '',
    );
  }

  static int _readNonNegativeInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed == null || parsed < 0 ? 0 : parsed;
  }
}

/// Downloads audio only for sources for which the app owner has the required
/// written authorization. Android resolves the current stream through the
/// existing musikku/newpipe bridge; no youtube_explode_dart API is used here.
class OfflineDownloadService extends ChangeNotifier {
  OfflineDownloadService._();

  static final OfflineDownloadService instance = OfflineDownloadService._();

  static const MethodChannel _newPipe = MethodChannel('musikku/newpipe');
  static const MethodChannel _storageChannel = MethodChannel('musikku/storage');
  static const MethodChannel _foregroundChannel =
      MethodChannel('musikku/offline_download_foreground');
  static const String _storageKey = 'musikku_offline_downloads_v1';
  static const int _minimumFreeSpaceReserveBytes = 48 * 1024 * 1024;
  static const int _maximumTrackBytes = 768 * 1024 * 1024;
  static const int _storageRecheckIntervalBytes = 8 * 1024 * 1024;
  static const Duration _requestTimeout = Duration(seconds: 35);
  static const Duration _streamIdleTimeout = Duration(seconds: 45);
  static const Duration _redirectDrainTimeout = Duration(seconds: 4);

  final Map<String, OfflineDownloadEntry> _items =
      <String, OfflineDownloadEntry>{};
  final Queue<String> _queue = Queue<String>();
  final http.Client _client = IOClient(
    HttpClient()
      ..connectionTimeout = _requestTimeout
      ..idleTimeout = _streamIdleTimeout
      ..maxConnectionsPerHost = 2,
  );

  Future<void>? _initializeFuture;
  Directory? _downloadDirectory;
  SharedPreferences? _preferences;
  bool _processing = false;
  bool _paused = false;
  String? _activeVideoId;
  StreamSubscription<List<int>>? _activeSubscription;
  IOSink? _activeSink;
  Future<void> _persistQueue = Future<void>.value();
  Timer? _progressPersistTimer;
  DateTime _lastForegroundUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _foregroundServiceRequested = false;

  bool get isPaused => _paused;
  bool get isProcessing => _processing;
  List<OfflineDownloadEntry> get items {
    final result = _items.values.toList(growable: false);
    result.sort((a, b) {
      final order = <OfflineDownloadStatus, int>{
        OfflineDownloadStatus.downloading: 0,
        OfflineDownloadStatus.queued: 1,
        OfflineDownloadStatus.failed: 2,
        OfflineDownloadStatus.paused: 3,
        OfflineDownloadStatus.completed: 4,
      };
      final stateOrder = order[a.status]!.compareTo(order[b.status]!);
      if (stateOrder != 0) return stateOrder;
      return a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
    });
    return result;
  }

  int get totalDownloadedBytes => _items.values
      .where((item) => item.status == OfflineDownloadStatus.completed)
      .fold<int>(0, (total, item) => total + item.downloadedBytes);

  OfflineDownloadEntry? itemFor(String videoId) => _items[videoId];

  bool isActiveDownload(String videoId) => _activeVideoId == videoId;

  Future<int> getAvailableStorageBytes() => _availableStorageBytes();

  /// Keeps Android's process at foreground-service priority while the Dart
  /// transfer loop is active. The service only owns the notification/lifecycle;
  /// the existing downloader remains the single owner of network/file IO.
  Future<void> _updateForegroundNotification({bool force = false}) async {
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastForegroundUpdate).inMilliseconds < 900) {
      return;
    }
    _lastForegroundUpdate = now;

    final active = _activeVideoId == null ? null : _items[_activeVideoId];
    final waiting = _items.values.where((entry) =>
        entry.status == OfflineDownloadStatus.queued ||
        entry.status == OfflineDownloadStatus.downloading).length;
    final downloaded = active?.downloadedBytes ?? 0;
    final total = active?.totalBytes ?? 0;
    try {
      final started = await _foregroundChannel.invokeMethod<bool>('update', <String, Object>{
        'title': active?.song.title ?? 'Menyiapkan unduhan',
        'artist': active?.song.channelTitle ?? '',
        'progress': active == null ? 0 : (active.progress * 100).round(),
        'downloadedBytes': downloaded,
        'totalBytes': total,
        'queueCount': waiting,
        'paused': _paused,
      });
      _foregroundServiceRequested = started == true;
    } on MissingPluginException {
      // iOS and older application builds do not provide this native channel.
    } on PlatformException catch (error) {
      debugPrint('OFFLINE FOREGROUND SERVICE ERROR: ${error.code} ${error.message}');
    } catch (error) {
      debugPrint('OFFLINE FOREGROUND SERVICE ERROR: $error');
    }
  }

  Future<void> _stopForegroundNotification() async {
    if (!Platform.isAndroid || !_foregroundServiceRequested) return;
    var stopped = false;
    try {
      stopped = await _foregroundChannel.invokeMethod<bool>('stop') == true;
    } on MissingPluginException {
      // The native service cannot exist in builds without this channel.
      stopped = true;
    } on PlatformException catch (error) {
      debugPrint('OFFLINE FOREGROUND STOP ERROR: ${error.code} ${error.message}');
    } catch (error) {
      debugPrint('OFFLINE FOREGROUND STOP ERROR: $error');
    }
    // Keep the requested flag on transient failures so a later completion or
    // queue reset can retry instead of silently leaving an ongoing FGS notice.
    if (stopped) _foregroundServiceRequested = false;
  }

  Future<bool> isOfflineFileUsable(String filePath) async {
    if (filePath.trim().isEmpty) return false;
    final file = File(filePath);
    if (!await _isManagedFileAsync(file) || !await file.exists()) return false;
    return await _detectFileExtension(file) != null;
  }

  Future<bool> hasUsableCompletedDownload(String videoId) async {
    await initialize();
    final entry = _items[videoId];
    return entry != null &&
        entry.status == OfflineDownloadStatus.completed &&
        await _hasUsableCompletedFile(entry);
  }

  Future<void> initialize() async {
    final inFlight = _initializeFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    final future = _loadSavedItems();
    _initializeFuture = future;
    try {
      await future;
    } catch (_) {
      // A transient storage/plugin failure must not permanently poison the
      // singleton. A later screen entry or retry can initialize it again.
      if (identical(_initializeFuture, future)) {
        _initializeFuture = null;
      }
      rethrow;
    }
  }

  Future<void> _loadSavedItems() async {
    if (!Platform.isAndroid) return;
    _preferences = await SharedPreferences.getInstance();
    final documents = await getApplicationDocumentsDirectory();
    _downloadDirectory = Directory('${documents.path}/MusikKu/Offline');
    await _downloadDirectory!.create(recursive: true);

    final raw = _preferences!.getString(_storageKey);

    try {
      if (raw != null && raw.isNotEmpty) {
        dynamic decoded;
        try {
          decoded = jsonDecode(raw);
        } catch (error) {
          // Treat malformed queue JSON as an empty queue, then still clean
          // orphaned partial files and restore the service to a usable state.
          debugPrint('OFFLINE DOWNLOAD JSON RESTORE ERROR: $error');
        }

        if (decoded is List) {
          for (final value in decoded) {
            if (value is! Map) continue;
            try {
              final item = OfflineDownloadEntry.fromJson(
                Map<String, dynamic>.from(value),
              );
              final id = item.song.videoId.trim();
              if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ||
                  _items.containsKey(id)) {
                continue;
              }

              if (item.status == OfflineDownloadStatus.completed) {
                final file = File(item.filePath);
                final managedPath = await _isManagedFileAsync(file);
                final exists = managedPath && await file.exists();
                final length = exists ? await file.length() : 0;
                final validAudio = exists &&
                    length >= 1024 &&
                    await _detectFileExtension(file) != null;
                if (validAudio) {
                  _items[id] = item.copyWith(
                    downloadedBytes: length,
                    totalBytes: length,
                  );
                } else {
                  final recovered = await _recoverCompletedFile(id);
                  if (recovered != null) {
                    final recoveredLength = await recovered.length();
                    _items[id] = item.copyWith(
                      status: OfflineDownloadStatus.completed,
                      downloadedBytes: recoveredLength,
                      totalBytes: recoveredLength,
                      filePath: recovered.path,
                      errorMessage: '',
                    );
                  } else {
                    _items[id] = item.copyWith(
                      status: OfflineDownloadStatus.paused,
                      downloadedBytes: 0,
                      totalBytes: 0,
                      filePath: '',
                      errorMessage:
                          'File offline hilang atau kosong. Silakan unduh ulang.',
                    );
                  }
                }
              } else {
                // Recover the narrow crash window after the validated `.part`
                // file was renamed but before completed state reached prefs.
                final recovered = await _recoverCompletedFile(id);
                if (recovered != null) {
                  final recoveredLength = await recovered.length();
                  _items[id] = item.copyWith(
                    status: OfflineDownloadStatus.completed,
                    downloadedBytes: recoveredLength,
                    totalBytes: recoveredLength,
                    filePath: recovered.path,
                    errorMessage: '',
                  );
                  continue;
                }

                final previousStatus = item.status;
                final restoredStatus =
                    previousStatus == OfflineDownloadStatus.failed
                        ? OfflineDownloadStatus.failed
                        : OfflineDownloadStatus.paused;
                final part = _partFile(id);
                final metadataTemp = _partMetadataTempFile(id);
                if (await metadataTemp.exists()) {
                  try {
                    await metadataTemp.delete();
                  } catch (_) {}
                }
                final partIsManaged = await _isManagedFileAsync(part);
                if (!partIsManaged && await part.exists()) {
                  await part.delete();
                }
                final partLength = partIsManaged && await part.exists()
                    ? await part.length()
                    : 0;
                _items[id] = item.copyWith(
                  status: restoredStatus,
                  downloadedBytes: partLength,
                  totalBytes: item.totalBytes >= partLength
                      ? item.totalBytes
                      : 0,
                  filePath: '',
                );
              }
            } catch (error) {
              // One corrupt preference entry must not hide every valid row.
              debugPrint('OFFLINE DOWNLOAD ENTRY RESTORE SKIPPED: $error');
            }
          }
        } else {
          debugPrint('OFFLINE DOWNLOAD RESTORE: saved queue is not a list.');
        }
      }

      // Run cleanup even for missing/malformed preferences so temporary files
      // left behind by a crash do not accumulate forever.
      await _cleanupOrphanTemporaryFiles();
      _paused = _items.values.any(
        (item) =>
            item.status == OfflineDownloadStatus.paused ||
            item.status == OfflineDownloadStatus.queued,
      );
      await _persist();
      notifyListeners();
    } catch (error) {
      debugPrint('OFFLINE DOWNLOAD RESTORE ERROR: $error');
      rethrow;
    }
  }

  Future<void> enqueue(YoutubeSearchResult song) async {
    await initialize();
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Download offline saat ini hanya tersedia di Android.',
      );
    }
    if (song.isLocal ||
        !RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(song.videoId)) {
      throw ArgumentError('Hanya lagu online dengan ID video yang valid.');
    }

    final existing = _items[song.videoId];
    // pauseAll() marks the active row as paused while its stream subscription
    // is suspended. Do not enqueue that same ID a second time.
    if (_activeVideoId == song.videoId) return;
    if (existing?.status == OfflineDownloadStatus.completed &&
        await _hasUsableCompletedFile(existing!)) {
      return;
    }
    if (existing?.status == OfflineDownloadStatus.queued ||
        existing?.status == OfflineDownloadStatus.downloading) {
      return;
    }

    _items[song.videoId] = OfflineDownloadEntry(
      song: song,
      status: OfflineDownloadStatus.queued,
      downloadedBytes: existing?.downloadedBytes ?? 0,
      totalBytes: existing?.totalBytes ?? 0,
      filePath: '',
    );
    if (!_queue.contains(song.videoId)) _queue.addLast(song.videoId);
    await _persist();
    notifyListeners();
    unawaited(_updateForegroundNotification(force: true));
    unawaited(_pumpQueue());
  }

  Future<OfflineEnqueueResult> enqueueAll(
    Iterable<YoutubeSearchResult> songs,
  ) async {
    await initialize();
    var added = 0;
    var alreadyQueued = 0;
    var alreadyDownloaded = 0;
    var failed = 0;
    var duplicateInput = 0;
    final seen = <String>{};

    for (final song in songs) {
      final id = song.videoId.trim();
      if (id.isEmpty) {
        failed++;
        continue;
      }
      if (!seen.add(id)) {
        duplicateInput++;
        continue;
      }
      final existing = _items[id];
      if (_activeVideoId == id ||
          _queue.contains(id) ||
          existing?.status == OfflineDownloadStatus.queued ||
          existing?.status == OfflineDownloadStatus.downloading) {
        alreadyQueued++;
        continue;
      }
      if (existing != null &&
          existing.status == OfflineDownloadStatus.completed &&
          await _hasUsableCompletedFile(existing)) {
        alreadyDownloaded++;
        continue;
      }

      try {
        await enqueue(song);
        added++;
      } catch (error) {
        failed++;
        debugPrint('OFFLINE QUEUE ADD FAILED (${song.videoId}): $error');
      }
    }

    return OfflineEnqueueResult(
      added: added,
      alreadyQueued: alreadyQueued,
      alreadyDownloaded: alreadyDownloaded,
      failed: failed,
      duplicateInput: duplicateInput,
    );
  }

  Future<void> pauseAll() async {
    await initialize();
    _paused = true;
    _activeSubscription?.pause();
    try {
      await _activeSink?.flush();
    } catch (_) {}
    final activeId = _activeVideoId;
    if (activeId != null && _items[activeId] != null) {
      _setItem(
        activeId,
        _items[activeId]!.copyWith(status: OfflineDownloadStatus.paused),
      );
    }
    for (final id in _queue) {
      final item = _items[id];
      if (item != null) {
        _setItem(id, item.copyWith(status: OfflineDownloadStatus.paused));
      }
    }
    await _persist();
    await _stopForegroundNotification();
    notifyListeners();
  }

  Future<void> resumeAll() async {
    await initialize();
    _paused = false;
    final activeId = _activeVideoId;
    if (activeId != null) {
      final active = _items[activeId];
      if (active != null) {
        _setItem(
          activeId,
          active.copyWith(status: OfflineDownloadStatus.downloading),
        );
      }
      // A request can still be resolving before its stream subscription exists.
      // Keep that worker as the sole owner of activeId; never enqueue it twice.
      _activeSubscription?.resume();
      await _updateForegroundNotification(force: true);
    }

    for (final item in _items.values.toList(growable: false)) {
      if (item.song.videoId == activeId) continue;
      if (item.status == OfflineDownloadStatus.paused ||
          item.status == OfflineDownloadStatus.queued) {
        if (!_queue.contains(item.song.videoId)) {
          _queue.addLast(item.song.videoId);
        }
        _setItem(
          item.song.videoId,
          item.copyWith(status: OfflineDownloadStatus.queued),
        );
      }
    }
    unawaited(_pumpQueue());
    await _persist();
    notifyListeners();
  }

  Future<void> retry(String videoId) async {
    final item = _items[videoId];
    if (item == null) return;
    await enqueue(item.song);
  }

  Future<void> delete(String videoId) async {
    await initialize();
    if (_activeVideoId == videoId) {
      throw StateError('Jeda antrean sebelum menghapus unduhan yang aktif.');
    }
    _queue.remove(videoId);
    final item = _items.remove(videoId);
    if (item != null) {
      if (item.filePath.isNotEmpty) {
        final file = File(item.filePath);
        // Never delete an arbitrary path restored from corrupted preferences.
        if (await _isManagedFileAsync(file) && await file.exists()) {
          await file.delete();
        }
      }
      final temporaryFiles = <File>[
        _partFile(videoId),
        _partMetadataFile(videoId),
        _partMetadataTempFile(videoId),
      ];
      for (final temporaryFile in temporaryFiles) {
        if (await _isManagedFileAsync(temporaryFile) &&
            await temporaryFile.exists()) {
          await temporaryFile.delete();
        }
      }
      await _persist();
      if (_queue.isEmpty && _activeVideoId == null) {
        await _stopForegroundNotification();
      }
      notifyListeners();
    }
  }

  Future<void> _pumpQueue() async {
    if (_processing || _paused || !Platform.isAndroid) return;
    _processing = true;
    if (!_paused && _queue.isNotEmpty) {
      await _updateForegroundNotification(force: true);
    }
    try {
      while (!_paused && _queue.isNotEmpty) {
        final id = _queue.removeFirst();
        final item = _items[id];
        if (item == null ||
            item.status == OfflineDownloadStatus.completed ||
            item.status == OfflineDownloadStatus.downloading) {
          continue;
        }
        await _downloadOne(id, item);
      }
    } finally {
      _processing = false;
      try {
        await _persist();
      } catch (persistError) {
        debugPrint('OFFLINE DOWNLOAD QUEUE PERSIST ERROR: $persistError');
      }
      if (_paused || _queue.isEmpty) {
        await _stopForegroundNotification();
      } else {
        await _updateForegroundNotification(force: true);
        unawaited(_pumpQueue());
      }
    }
  }

  Future<void> _downloadOne(
    String videoId,
    OfflineDownloadEntry initial,
  ) async {
    _activeVideoId = videoId;
    _setItem(
      videoId,
      initial.copyWith(
        status: OfflineDownloadStatus.downloading,
        errorMessage: '',
      ),
    );
    notifyListeners();
    unawaited(_updateForegroundNotification(force: true));

    var discardPartialOnFailure = false;
    try {
      // Persistence belongs inside the worker's guarded lifecycle. If storage
      // fails here, the active ID must still be cleared in the finally block.
      await _persist();
      final part = _partFile(videoId);
      if (!await _isManagedFileAsync(part)) {
        // The final component must not be an external symlink.
        if (await part.exists()) await part.delete();
        throw FileSystemException('Lokasi file sementara tidak aman.');
      }
      var offset = await part.exists() ? await part.length() : 0;
      if (offset > _maximumTrackBytes ||
          (offset >= 8 && await _detectFileExtension(part) == null)) {
        await part.delete();
        offset = 0;
      }

      var resolved = await _resolveAudio(videoId);
      var sourceFingerprint = audioStreamFingerprint(resolved);
      final metadataFile = _partMetadataFile(videoId);
      if (offset > 0) {
        final savedFingerprint = await _readPartFingerprint(metadataFile);
        // Never concatenate bytes from different audio formats/bitrates. Old
        // partial files without a sidecar are restarted once for safety.
        if (savedFingerprint == null || savedFingerprint != sourceFingerprint) {
          await part.delete();
          offset = 0;
        }
      }
      await _writePartFingerprint(metadataFile, sourceFingerprint);

      var streamUrl = resolved['streamUrl']?.toString().trim() ?? '';
      var uri = Uri.tryParse(streamUrl);
      if (uri == null || !_isAllowedStreamUri(uri)) {
        throw const FormatException('Alamat stream audio tidak valid.');
      }
      var headers = _sanitizeStreamHeaders(resolved['headers']);
      var response = await _sendDownloadRequest(uri, headers, offset);

      // Signed media URLs can expire while an item waits in the queue.
      // Resolve once and retry using the current partial-file offset.
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 410) {
        await _discardResponse(response);
        final renewed = await _resolveAudio(videoId);
        final renewedFingerprint = audioStreamFingerprint(renewed);
        if (offset > 0 && renewedFingerprint != sourceFingerprint) {
          // A refreshed URL selected a different codec/format/bitrate. Restart
          // rather than joining incompatible media segments.
          if (await part.exists()) await part.delete();
          offset = 0;
        }
        sourceFingerprint = renewedFingerprint;
        await _writePartFingerprint(metadataFile, sourceFingerprint);
        streamUrl = renewed['streamUrl']?.toString().trim() ?? '';
        uri = Uri.tryParse(streamUrl);
        if (uri == null || !_isAllowedStreamUri(uri)) {
          throw const FormatException('Stream unduhan tidak dapat diperbarui.');
        }
        headers = _sanitizeStreamHeaders(renewed['headers']);
        response = await _sendDownloadRequest(uri, headers, offset);
      }

      // A range request may be ignored by some CDNs. Restart from byte zero;
      // never append a complete 200 response to an existing partial file.
      if (offset > 0 && response.statusCode == 200) {
        // This is already a complete response from byte zero. Truncate the
        // partial file and consume this same body instead of downloading twice.
        await part.delete();
        offset = 0;
      } else if (response.statusCode == 416) {
        await _discardResponse(response);
        if (await part.exists()) await part.delete();
        offset = 0;
        response = await _sendDownloadRequest(uri, headers, 0);
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        await _discardResponse(response);
        throw HttpException('Server mengembalikan HTTP ${response.statusCode}.');
      }

      final encoding = response.headers['content-encoding']?.trim().toLowerCase();
      if (encoding != null && encoding.isNotEmpty && encoding != 'identity') {
        await _discardResponse(response);
        throw const FormatException(
          'Server mengubah encoding stream; unduhan tidak dapat dilanjutkan dengan aman.',
        );
      }
      if (!isPlausibleAudioContentType(response.headers['content-type'])) {
        await _discardResponse(response);
        throw const FormatException(
          'Respons server bukan file audio yang dikenali.',
        );
      }

      int expectedTotalBytes = 0;
      // This must remain mutable: an invalid 206 response can be discarded
      // and replaced with a fresh 200 response below. Reusing the old
      // Content-Length would compare the final file against the discarded
      // partial response and falsely mark a valid download as failed.
      var contentLength = response.contentLength;
      if (response.statusCode == 206) {
        if (!isValidContentRangeResponse(
          requestedOffset: offset,
          contentRange: response.headers['content-range'],
          contentLength: contentLength,
        )) {
          await _discardResponse(response);
          if (offset > 0) {
            if (await part.exists()) await part.delete();
            offset = 0;
            response = await _sendDownloadRequest(uri, headers, 0);
            contentLength = response.contentLength;
            if (response.statusCode != 200) {
              await _discardResponse(response);
              throw const HttpException(
                'Server mengirim rentang byte yang tidak cocok setelah memulai ulang.',
              );
            }
          } else {
            throw const HttpException(
              'Server mengirim rentang byte yang tidak valid.',
            );
          }
        }
      }

      final finalEncoding = response.headers['content-encoding']?.trim().toLowerCase();
      if (finalEncoding != null && finalEncoding.isNotEmpty && finalEncoding != 'identity') {
        await _discardResponse(response);
        throw const FormatException('Encoding stream tidak didukung untuk resume.');
      }
      if (!isPlausibleAudioContentType(response.headers['content-type'])) {
        await _discardResponse(response);
        throw const FormatException('Respons server bukan audio yang valid.');
      }

      if (response.statusCode == 206) {
        final parsedRange = ParsedContentRange.parse(
          response.headers['content-range'],
        );
        if (parsedRange == null || parsedRange.start != offset) {
          await _discardResponse(response);
          throw const HttpException('Content-Range tidak valid.');
        }
        expectedTotalBytes = parsedRange.total!;
      } else {
        expectedTotalBytes = contentLength != null && contentLength >= 0
            ? contentLength
            : 0;
      }

      if (expectedTotalBytes > _maximumTrackBytes ||
          offset > _maximumTrackBytes ||
          (contentLength != null && contentLength > _maximumTrackBytes)) {
        await _discardResponse(response);
        discardPartialOnFailure = true;
        throw const FileSystemException(
          'Ukuran lagu melebihi batas aman 768 MB.',
        );
      }

      final freeBefore = await _availableStorageBytes();
      final bytesStillNeeded = expectedTotalBytes > 0
          ? (expectedTotalBytes - offset).clamp(0, _maximumTrackBytes)
          : 0;
      if (freeBefore < _minimumFreeSpaceReserveBytes + bytesStillNeeded) {
        await _discardResponse(response);
        throw FileSystemException(
          'Ruang penyimpanan tidak cukup. Sisakan minimal '
          '${(_minimumFreeSpaceReserveBytes / 1000000).toStringAsFixed(0)} MB.',
        );
      }

      // Keep the visible and persisted progress aligned with the actual
      // partial file. This matters when a refreshed stream changes format or
      // the server forces a restart from byte zero.
      final progressEntry = _items[videoId];
      if (progressEntry != null &&
          (progressEntry.downloadedBytes != offset ||
              progressEntry.totalBytes != expectedTotalBytes)) {
        _setItem(
          videoId,
          progressEntry.copyWith(
            downloadedBytes: offset,
            totalBytes: expectedTotalBytes,
          ),
        );
        notifyListeners();
        await _persist();
      }

      var downloadedBytes = offset;
      var bytesSinceStorageCheck = 0;
      var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
      final sink = part.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      _activeSink = sink;
      final done = Completer<void>();

      final guardedStream = response.stream
          .timeout(_streamIdleTimeout,
              onTimeout: (sink) => sink.addError(
                    TimeoutException(
                      'Unduhan tidak menerima data selama ${_streamIdleTimeout.inSeconds} detik.',
                    ),
                  ))
          .asyncMap<List<int>>((chunk) async {
        downloadedBytes += chunk.length;
        bytesSinceStorageCheck += chunk.length;
        if (downloadedBytes > _maximumTrackBytes) {
          throw const FileSystemException('Ukuran lagu melebihi batas 768 MB.');
        }
        if (bytesSinceStorageCheck >= _storageRecheckIntervalBytes) {
          final available = await _availableStorageBytes();
          bytesSinceStorageCheck = 0;
          if (available < _minimumFreeSpaceReserveBytes) {
            throw const FileSystemException(
              'Penyimpanan hampir penuh. Unduhan dihentikan untuk melindungi data HP.',
            );
          }
        }
        return chunk;
      });

      _activeSubscription = guardedStream.listen(
        (chunk) {
          sink.add(chunk);
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds >= 180) {
            lastNotify = now;
            final current = _items[videoId];
            if (current != null) {
              _setItem(
                videoId,
                current.copyWith(
                  status: _paused
                      ? OfflineDownloadStatus.paused
                      : OfflineDownloadStatus.downloading,
                  downloadedBytes: downloadedBytes,
                  totalBytes: expectedTotalBytes,
                ),
              );
              notifyListeners();
              _scheduleProgressPersist();
              unawaited(_updateForegroundNotification());
            }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!done.isCompleted) done.completeError(error, stackTrace);
        },
        onDone: () async {
          try {
            await sink.flush();
            await sink.close();
            if (!done.isCompleted) done.complete();
          } catch (error, stackTrace) {
            if (!done.isCompleted) done.completeError(error, stackTrace);
          }
        },
        cancelOnError: true,
      );

      if (_paused) _activeSubscription?.pause();
      await done.future;
      _activeSubscription = null;
      _activeSink = null;

      final actualBytes = await part.length();
      if (actualBytes == 0) {
        discardPartialOnFailure = true;
        throw const FormatException('File audio yang diterima kosong.');
      }
      if (expectedTotalBytes > 0 && actualBytes != expectedTotalBytes) {
        throw HttpException(
          'Ukuran unduhan tidak cocok ($actualBytes dari $expectedTotalBytes byte).',
        );
      }

      final signature = await _detectFileExtension(part);
      if (signature == null) {
        discardPartialOnFailure = true;
        throw const FormatException(
          'File yang diterima bukan audio yang didukung. Unduhan ditolak.',
        );
      }

      final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final finalFile = File('${_downloadDirectory!.path}/$safeId.$signature');
      if (!await _isManagedFileAsync(finalFile)) {
        throw FileSystemException('Lokasi file offline tidak aman.');
      }
      if (await finalFile.exists()) await finalFile.delete();
      final savedFile = await part.rename(finalFile.path);
      // Cleanup is best-effort after the validated final file has been
      // atomically installed. A stale sidecar must not turn a successful
      // download into a failed row.
      try {
        if (await metadataFile.exists()) await metadataFile.delete();
      } catch (error) {
        debugPrint('OFFLINE DOWNLOAD METADATA CLEANUP ERROR: $error');
      }
      final metadataTemp = _partMetadataTempFile(videoId);
      try {
        if (await metadataTemp.exists()) await metadataTemp.delete();
      } catch (error) {
        debugPrint('OFFLINE DOWNLOAD TEMP METADATA CLEANUP ERROR: $error');
      }

      final current = _items[videoId];
      if (current != null) {
        _setItem(
          videoId,
          current.copyWith(
            status: OfflineDownloadStatus.completed,
            downloadedBytes: actualBytes,
            totalBytes: actualBytes,
            filePath: savedFile.path,
            errorMessage: '',
          ),
        );
      }
    } catch (error) {
      try {
        await _activeSubscription?.cancel();
      } catch (_) {}
      try {
        await _activeSink?.flush();
        await _activeSink?.close();
      } catch (_) {}
      _activeSink = null;
      final current = _items[videoId];
      if (current != null) {
        final part = _partFile(videoId);
        if (discardPartialOnFailure) {
          final temporaryFiles = <File>[
            part,
            _partMetadataFile(videoId),
            _partMetadataTempFile(videoId),
          ];
          for (final temporaryFile in temporaryFiles) {
            try {
              if (await _isManagedFileAsync(temporaryFile) &&
                  await temporaryFile.exists()) {
                await temporaryFile.delete();
              }
            } catch (cleanupError) {
              debugPrint('OFFLINE DOWNLOAD PART CLEANUP ERROR: $cleanupError');
            }
          }
        }
        var bytes = 0;
        try {
          if (await _isManagedFileAsync(part) && await part.exists()) {
            bytes = await part.length();
          }
        } catch (fileError) {
          // A filesystem error while reading progress must not escape this
          // catch block and abort the whole queue pump.
          debugPrint('OFFLINE DOWNLOAD PROGRESS RECOVERY ERROR: $fileError');
        }
        _setItem(
          videoId,
          current.copyWith(
            status: _paused
                ? OfflineDownloadStatus.paused
                : OfflineDownloadStatus.failed,
            downloadedBytes: bytes,
            errorMessage: error.toString().replaceFirst('Exception: ', ''),
          ),
        );
      }
    } finally {
      _activeSubscription = null;
      _activeSink = null;
      _activeVideoId = null;
      try {
        await _persist();
      } catch (persistError) {
        // A preferences failure must not strand the queue worker or prevent
        // the next song from starting; the next state transition retries it.
        debugPrint('OFFLINE DOWNLOAD FINAL PERSIST ERROR: $persistError');
      }
      notifyListeners();
    }
  }

  Future<http.StreamedResponse> _sendDownloadRequest(
    Uri initialUri,
    Map<String, String> headers,
    int offset,
  ) async {
    var currentUri = initialUri;
    for (var redirect = 0; redirect <= 5; redirect++) {
      if (!_isAllowedStreamUri(currentUri)) {
        throw const FormatException('Redirect stream tidak dipercaya.');
      }
      final request = http.Request('GET', currentUri)
        ..followRedirects = false
        ..maxRedirects = 0;
      request.headers.addAll(headers);
      request.headers['Accept-Encoding'] = 'identity';
      if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
      final response = await _client.send(request).timeout(_requestTimeout);
      if (!response.isRedirect) return response;

      final location = response.headers['location'];
      await _discardResponse(response);
      if (location == null || location.trim().isEmpty || redirect == 5) {
        throw const HttpException('Redirect stream tidak valid atau terlalu banyak.');
      }
      final nextUri = currentUri.resolve(location.trim());
      if (!_isAllowedStreamUri(nextUri)) {
        throw const FormatException('Redirect keluar dari host stream yang diizinkan.');
      }
      currentUri = nextUri;
    }
    throw const HttpException('Redirect stream tidak dapat diselesaikan.');
  }

  Future<void> _discardResponse(http.StreamedResponse response) async {
    try {
      await response.stream
          .timeout(_redirectDrainTimeout)
          .drain<void>();
    } catch (_) {}
  }

  Map<String, String> _sanitizeStreamHeaders(Object? rawHeaders) {
    if (rawHeaders is! Map) return <String, String>{};
    const allowed = <String>{'user-agent', 'referer', 'origin'};
    final safe = <String, String>{};
    for (final entry in rawHeaders.entries) {
      final key = entry.key?.toString().trim() ?? '';
      final value = entry.value?.toString().trim() ?? '';
      if (!allowed.contains(key.toLowerCase()) ||
          value.isEmpty ||
          value.length > 2048 ||
          value.contains('\r') ||
          value.contains('\n')) {
        continue;
      }
      safe[key] = value;
    }
    return safe;
  }

  Future<int> _availableStorageBytes() async {
    final available = await _storageChannel.invokeMethod<int>('getAvailableBytes');
    if (available == null || available < 0) {
      throw const FileSystemException(
        'Ruang penyimpanan perangkat tidak dapat diperiksa.',
      );
    }
    return available;
  }

  Future<String?> _detectFileExtension(File file) async {
    if (!await file.exists() || await file.length() < 1024) return null;
    final handle = await file.open(mode: FileMode.read);
    try {
      final bytes = await handle.read(32);
      return detectAudioFileExtension(bytes);
    } finally {
      await handle.close();
    }
  }

  Future<Map<String, dynamic>> _resolveAudio(String videoId) async {
    final result = await _newPipe.invokeMapMethod<String, dynamic>(
      'resolveAudio',
      <String, dynamic>{'videoId': videoId},
    );
    if (result == null) {
      throw const FormatException('Sumber audio tidak ditemukan.');
    }
    return result;
  }

  bool _isAllowedStreamUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return uri.scheme == 'https' &&
        (uri.port == -1 || uri.port == 443) &&
        uri.userInfo.isEmpty &&
        uri.fragment.isEmpty &&
        (host == 'googlevideo.com' || host.endsWith('.googlevideo.com'));
  }

  Future<File?> _recoverCompletedFile(String videoId) async {
    const extensions = <String>['m4a', 'webm', 'ogg', 'flac', 'wav', 'mp3', 'aac'];
    for (final extension in extensions) {
      final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final candidate = File('${_downloadDirectory!.path}/$safeId.$extension');
      if (!await _isManagedFileAsync(candidate) || !await candidate.exists()) {
        continue;
      }
      final length = await candidate.length();
      if (length >= 1024 && await _detectFileExtension(candidate) == extension) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> _cleanupOrphanTemporaryFiles() async {
    final directory = _downloadDirectory;
    if (directory == null || !await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      final isTemporary = name.endsWith('.part') ||
          name.endsWith('.part.meta') ||
          name.endsWith('.part.meta.tmp');
      if (!isTemporary) continue;
      final id = name
          .replaceFirst(RegExp(r'\.part(?:\.meta(?:\.tmp)?)?$'), '');
      final validId = RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);
      final savedEntry = validId ? _items[id] : null;
      final isStaleTempMetadata = name.endsWith('.part.meta.tmp');
      final isCompleted = savedEntry?.status == OfflineDownloadStatus.completed;
      // Keep only resumable .part + .part.meta files for non-completed rows.
      // Temp metadata, malformed IDs, orphan files, and leftovers from a
      // completed download can always be safely removed.
      if (validId && savedEntry != null && !isCompleted && !isStaleTempMetadata) {
        continue;
      }
      // Delete only the temporary entry itself, never follow a symlink target.
      try {
        await entity.delete();
      } catch (_) {}
    }
  }

  File _partFile(String videoId) {
    final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${_downloadDirectory!.path}/$safeId.part');
  }

  File _partMetadataFile(String videoId) {
    final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${_downloadDirectory!.path}/$safeId.part.meta');
  }

  File _partMetadataTempFile(String videoId) {
    final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${_downloadDirectory!.path}/$safeId.part.meta.tmp');
  }

  Future<String?> _readPartFingerprint(File metadata) async {
    if (!await _isManagedFileAsync(metadata) ||
        !await metadata.exists() ||
        await metadata.length() > 1024) {
      return null;
    }
    try {
      final decoded = jsonDecode(await metadata.readAsString());
      if (decoded is Map && decoded['fingerprint'] is String) {
        final value = (decoded['fingerprint'] as String).trim();
        return value.isEmpty ? null : value;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writePartFingerprint(File metadata, String fingerprint) async {
    final temp = File('${metadata.path}.tmp');
    if (!await _isManagedFileAsync(metadata)) {
      if (await FileSystemEntity.type(metadata.path, followLinks: false) ==
          FileSystemEntityType.link) {
        await metadata.delete();
      } else {
        throw FileSystemException('Lokasi metadata unduhan tidak aman.');
      }
    }
    if (!await _isManagedFileAsync(temp)) {
      if (await FileSystemEntity.type(temp.path, followLinks: false) ==
          FileSystemEntityType.link) {
        await temp.delete();
      } else {
        throw FileSystemException('Lokasi metadata sementara tidak aman.');
      }
    }
    await temp.writeAsString(
      jsonEncode(<String, String>{'fingerprint': fingerprint}),
      flush: true,
    );
    if (await metadata.exists()) await metadata.delete();
    await temp.rename(metadata.path);
  }

  void _setItem(String id, OfflineDownloadEntry entry) {
    _items[id] = entry;
  }

  Future<bool> _isManagedFileAsync(File file) async {
    final directory = _downloadDirectory;
    if (directory == null) return false;
    try {
      final root = await directory.resolveSymbolicLinks();
      final parent = await file.parent.resolveSymbolicLinks();
      if (parent != root) return false;
      final entityType = await FileSystemEntity.type(
        file.path,
        followLinks: false,
      );
      // Reject symlinks even when they target another path inside the folder.
      // This prevents one playlist entry from overwriting/deleting another file.
      if (entityType == FileSystemEntityType.link) return false;
      if (entityType == FileSystemEntityType.file) {
        final resolvedFile = await file.resolveSymbolicLinks();
        return resolvedFile.startsWith('$root${Platform.pathSeparator}');
      }
      return entityType == FileSystemEntityType.notFound;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _hasUsableCompletedFile(OfflineDownloadEntry entry) async {
    if (entry.filePath.trim().isEmpty) return false;
    final file = File(entry.filePath);
    if (!await _isManagedFileAsync(file) || !await file.exists()) return false;
    if (await file.length() <= 0) return false;
    return await _detectFileExtension(file) != null;
  }

  void _scheduleProgressPersist() {
    // Progress can change several times per second. Coalesce preference writes
    // to avoid repeatedly serializing the whole queue and stressing flash IO.
    if (_progressPersistTimer?.isActive == true) return;
    _progressPersistTimer = Timer(const Duration(milliseconds: 900), () {
      _progressPersistTimer = null;
      unawaited(
        _persist().catchError((Object error, StackTrace stackTrace) {
          debugPrint('OFFLINE DOWNLOAD PROGRESS PERSIST ERROR: $error');
        }),
      );
    });
  }

  Future<void> _persist() {
    _progressPersistTimer?.cancel();
    _progressPersistTimer = null;
    final prefs = _preferences;
    if (prefs == null) return Future<void>.value();
    // Snapshot immediately, then serialize writes so a slow earlier write
    // cannot overwrite a newer queue/progress state.
    final payload = jsonEncode(
      _items.values.map((item) => item.toJson()).toList(growable: false),
    );
    final write = _persistQueue.then<void>((_) async {
      await prefs.setString(_storageKey, payload);
    });
    _persistQueue = write.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('OFFLINE DOWNLOAD PERSIST ERROR: $error');
      },
    );
    return write;
  }

  @override
  void dispose() {
    _progressPersistTimer?.cancel();
    _activeSubscription?.pause();
    _client.close();
    super.dispose();
  }
}
