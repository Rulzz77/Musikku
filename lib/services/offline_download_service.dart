import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_search_result.dart';

enum OfflineDownloadStatus { queued, downloading, paused, completed, failed }

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
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      filePath: json['filePath']?.toString() ?? '',
      errorMessage: json['errorMessage']?.toString() ?? '',
    );
  }
}

/// Downloads audio only for sources for which the app owner has the required
/// written authorization. Android resolves the current stream through the
/// existing musikku/newpipe bridge; no youtube_explode_dart API is used here.
class OfflineDownloadService extends ChangeNotifier {
  OfflineDownloadService._();

  static final OfflineDownloadService instance = OfflineDownloadService._();

  static const MethodChannel _newPipe = MethodChannel('musikku/newpipe');
  static const String _storageKey = 'musikku_offline_downloads_v1';

  final Map<String, OfflineDownloadEntry> _items =
      <String, OfflineDownloadEntry>{};
  final Queue<String> _queue = Queue<String>();
  final http.Client _client = http.Client();

  Future<void>? _initializeFuture;
  Directory? _downloadDirectory;
  SharedPreferences? _preferences;
  bool _processing = false;
  bool _paused = false;
  String? _activeVideoId;
  StreamSubscription<List<int>>? _activeSubscription;
  IOSink? _activeSink;

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

  Future<void> initialize() => _initializeFuture ??= _loadSavedItems();

  Future<void> _loadSavedItems() async {
    if (!Platform.isAndroid) return;
    _preferences = await SharedPreferences.getInstance();
    final documents = await getApplicationDocumentsDirectory();
    _downloadDirectory = Directory('${documents.path}/MusikKu/Offline');
    await _downloadDirectory!.create(recursive: true);

    final raw = _preferences!.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final value in decoded) {
        if (value is! Map) continue;
        final item = OfflineDownloadEntry.fromJson(
          Map<String, dynamic>.from(value),
        );
        final id = item.song.videoId;
        if (id.isEmpty) continue;

        if (item.status == OfflineDownloadStatus.completed) {
          final file = File(item.filePath);
          if (item.filePath.isNotEmpty && await file.exists()) {
            _items[id] = item.copyWith(
              downloadedBytes: await file.length(),
              totalBytes: await file.length(),
            );
          } else {
            _items[id] = item.copyWith(
              status: OfflineDownloadStatus.paused,
              filePath: '',
              errorMessage: 'File offline tidak ditemukan. Silakan unduh ulang.',
            );
          }
        } else {
          final previousStatus = item.status;
          final restoredStatus = previousStatus == OfflineDownloadStatus.failed
              ? OfflineDownloadStatus.failed
              : OfflineDownloadStatus.paused;
          final part = _partFile(id);
          final partLength = await part.exists() ? await part.length() : 0;
          _items[id] = item.copyWith(
            status: restoredStatus,
            downloadedBytes: partLength,
          );
        }
      }
      _paused = _items.values.any((item) =>
          item.status == OfflineDownloadStatus.paused ||
          item.status == OfflineDownloadStatus.queued);
      await _persist();
      notifyListeners();
    } catch (error) {
      debugPrint('OFFLINE DOWNLOAD RESTORE ERROR: $error');
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
    if (existing?.status == OfflineDownloadStatus.completed &&
        existing!.filePath.isNotEmpty &&
        await File(existing.filePath).exists()) {
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
      filePath: existing?.filePath ?? '',
    );
    if (!_queue.contains(song.videoId)) _queue.addLast(song.videoId);
    await _persist();
    notifyListeners();
    unawaited(_pumpQueue());
  }

  Future<void> enqueueAll(Iterable<YoutubeSearchResult> songs) async {
    await initialize();
    for (final song in songs) {
      try {
        await enqueue(song);
      } catch (error) {
        debugPrint('OFFLINE QUEUE ADD FAILED (${song.videoId}): $error');
      }
    }
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
    notifyListeners();
  }

  Future<void> resumeAll() async {
    await initialize();
    _paused = false;
    final activeId = _activeVideoId;
    if (activeId != null && _activeSubscription != null) {
      final item = _items[activeId];
      if (item != null) {
        _setItem(
          activeId,
          item.copyWith(status: OfflineDownloadStatus.downloading),
        );
      }
      _activeSubscription!.resume();
    } else {
      for (final item in _items.values.toList(growable: false)) {
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
    }
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
        if (await file.exists()) await file.delete();
      }
      final part = _partFile(videoId);
      if (await part.exists()) await part.delete();
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _pumpQueue() async {
    if (_processing || _paused || !Platform.isAndroid) return;
    _processing = true;
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
      await _persist();
      if (!_paused && _queue.isNotEmpty) {
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
    await _persist();
    notifyListeners();

    try {
      final part = _partFile(videoId);
      var offset = await part.exists() ? await part.length() : 0;
      final resolved = await _resolveAudio(videoId);
      final streamUrl = resolved['streamUrl']?.toString().trim() ?? '';
      final uri = Uri.tryParse(streamUrl);
      if (uri == null || !_isAllowedStreamUri(uri)) {
        throw const FormatException('Alamat stream audio tidak valid.');
      }
      final headers = <String, String>{};
      final rawHeaders = resolved['headers'];
      if (rawHeaders is Map) {
        for (final entry in rawHeaders.entries) {
          final key = entry.key?.toString().trim() ?? '';
          final value = entry.value?.toString().trim() ?? '';
          if (key.isNotEmpty && value.isNotEmpty) headers[key] = value;
        }
      }

      var request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 5;
      request.headers.addAll(headers);
      if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
      var response = await _client.send(request);

      // Signed media URLs can expire while an item is waiting in the queue.
      // Resolve once more and retry with the existing byte offset.
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 410) {
        await response.stream.drain<void>();
        final renewed = await _resolveAudio(videoId);
        final renewedUri = Uri.tryParse(
          renewed['streamUrl']?.toString().trim() ?? '',
        );
        if (renewedUri == null || !_isAllowedStreamUri(renewedUri)) {
          throw const FormatException('Stream unduhan tidak dapat diperbarui.');
        }
        final renewedHeaders = <String, String>{};
        final renewedRawHeaders = renewed['headers'];
        if (renewedRawHeaders is Map) {
          for (final entry in renewedRawHeaders.entries) {
            final key = entry.key?.toString().trim() ?? '';
            final value = entry.value?.toString().trim() ?? '';
            if (key.isNotEmpty && value.isNotEmpty) renewedHeaders[key] = value;
          }
        }
        request = http.Request('GET', renewedUri)
          ..followRedirects = true
          ..maxRedirects = 5;
        request.headers.addAll(renewedHeaders);
        if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
        response = await _client.send(request);
      }

      if (offset > 0 && response.statusCode == 200) {
        // Server ignored the Range request: restart instead of corrupting file.
        await part.delete();
        offset = 0;
      } else if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.drain<void>();
        throw HttpException('Server mengembalikan HTTP ${response.statusCode}.');
      }

      final contentRange = response.headers['content-range'];
      final rangeTotal = contentRange == null
          ? null
          : RegExp(r'/([0-9]+)$').firstMatch(contentRange)?.group(1);
      final contentLength = response.contentLength;
      final parsedRangeTotal = rangeTotal == null
          ? null
          : int.tryParse(rangeTotal);
      final totalBytes = parsedRangeTotal ??
          (contentLength == null || contentLength < 0
              ? 0
              : offset + contentLength);
      var downloadedBytes = offset;
      final sink = part.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      _activeSink = sink;
      final done = Completer<void>();
      var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

      _activeSubscription = response.stream.listen(
        (chunk) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastNotify).inMilliseconds >= 160) {
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
                  totalBytes: totalBytes,
                ),
              );
              notifyListeners();
              unawaited(_persist());
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
      if (totalBytes > 0 && actualBytes < totalBytes) {
        throw HttpException(
          'Unduhan belum lengkap ($actualBytes dari $totalBytes byte).',
        );
      }
      if (actualBytes == 0) {
        throw const FormatException('File audio yang diterima kosong.');
      }

      final rawFormat = resolved['format']?.toString().toLowerCase() ?? 'm4a';
      final extension = RegExp(r'^[a-z0-9]{2,5}$').hasMatch(rawFormat)
          ? rawFormat
          : 'm4a';
      final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final finalFile = File('${_downloadDirectory!.path}/$safeId.$extension');
      if (await finalFile.exists()) await finalFile.delete();
      final savedFile = await part.rename(finalFile.path);

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
        await _activeSink?.flush();
        await _activeSink?.close();
      } catch (_) {}
      _activeSink = null;
      final current = _items[videoId];
      if (current != null) {
        final part = _partFile(videoId);
        final bytes = await part.exists() ? await part.length() : 0;
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
      await _persist();
      notifyListeners();
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
        (host == 'googlevideo.com' || host.endsWith('.googlevideo.com'));
  }

  File _partFile(String videoId) {
    final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${_downloadDirectory!.path}/$safeId.part');
  }

  void _setItem(String id, OfflineDownloadEntry entry) {
    _items[id] = entry;
  }

  Future<void> _persist() async {
    final prefs = _preferences;
    if (prefs == null) return;
    await prefs.setString(
      _storageKey,
      jsonEncode(_items.values.map((item) => item.toJson()).toList()),
    );
  }

  @override
  void dispose() {
    _activeSubscription?.pause();
    _client.close();
    super.dispose();
  }
}
