import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Mengambil foto profil channel untuk kartu video.
///
/// Permintaan dikumpulkan sebentar lalu dikirim sekaligus (maks. 50 channel
/// per panggilan channels.list = 1 unit kuota), dan hasilnya disimpan di HP
/// supaya channel yang sama tidak diminta lagi. Tidak butuh login.
///
/// Perbaikan:
/// - Kalau sebuah video belum punya channelId (mis. data lama dari cache),
///   channelId dicari dulu lewat videoId (videos.list, 1 unit / 50 video).
/// - Kegagalan jaringan/kuota TIDAK lagi ditandai "sudah dicoba" selamanya:
///   akan dicoba ulang otomatis (maks. [_maxRetries] kali).
class ChannelAvatarService extends ChangeNotifier {
  ChannelAvatarService._();
  static final ChannelAvatarService instance = ChannelAvatarService._();

  static const String _apiKey = String.fromEnvironment('YOUTUBE_API_KEY');
  static const String _prefsKey = 'channel_avatars_v1';
  static const int _maxEntries = 400;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 20);

  /// Urutan penyisipan dipertahankan: yang tertua dibuang saat penuh.
  final Map<String, String> _urls = <String, String>{};
  final Set<String> _pending = <String>{};
  final Set<String> _pendingVideos = <String>{};

  /// videoId -> channelId (hasil videos.list), hanya untuk sesi ini.
  final Map<String, String> _videoChannel = <String, String>{};

  /// Channel yang SUDAH dijawab server (termasuk yang memang tak punya foto),
  /// supaya tidak diulang terus-menerus.
  final Set<String> _done = <String>{};
  final Map<String, int> _failCount = <String, int>{};
  final Set<String> _videoTried = <String>{};

  Timer? _timer;
  Timer? _retryTimer;
  Future<void>? _loading;

  /// Foto untuk channel. [videoId] dipakai bila channelId belum diketahui.
  String? urlFor(String channelId, {String videoId = ''}) {
    final id = channelId.isNotEmpty ? channelId : (_videoChannel[videoId] ?? '');
    if (id.isEmpty) return null;
    return _urls[id];
  }

  /// Minta foto channel. Aman dipanggil berkali-kali.
  void request(String channelId, {String videoId = ''}) {
    if (_apiKey.isEmpty) {
      debugPrint('CHANNEL AVATAR: YOUTUBE_API_KEY kosong, foto channel tidak diambil.');
      return;
    }
    if (channelId.isNotEmpty) {
      if (_urls.containsKey(channelId) || _done.contains(channelId)) return;
      _pending.add(channelId);
    } else if (videoId.isNotEmpty) {
      final known = _videoChannel[videoId];
      if (known != null) {
        if (_urls.containsKey(known) || _done.contains(known)) return;
        _pending.add(known);
      } else {
        if (_videoTried.contains(videoId)) return;
        _pendingVideos.add(videoId);
      }
    } else {
      return;
    }
    _timer ??= Timer(const Duration(milliseconds: 150), () => unawaited(_flush()));
  }

  Future<void> _ensureLoaded() {
    return _loading ??= () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_prefsKey);
        if (raw == null || raw.isEmpty) return;
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final url = entry.value?.toString() ?? '';
            if (url.isNotEmpty) _urls[entry.key.toString()] = url;
          }
        }
      } catch (_) {
        // Cache rusak: abaikan, akan terisi ulang.
      }
    }();
  }

  Future<http.Response?> _get(String path, Map<String, String> params) async {
    try {
      final uri = Uri.parse('https://www.googleapis.com/youtube/v3/$path')
          .replace(queryParameters: {...params, 'key': _apiKey});
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) {
        debugPrint('CHANNEL AVATAR $path HTTP ${response.statusCode}');
        return null;
      }
      return response;
    } catch (e) {
      debugPrint('CHANNEL AVATAR $path error: $e');
      return null;
    }
  }

  /// Cari channelId dari videoId untuk video yang datanya belum lengkap.
  Future<void> _resolveVideos(List<String> videoIds) async {
    for (var i = 0; i < videoIds.length; i += 50) {
      final chunk = videoIds.sublist(i, i + 50 > videoIds.length ? videoIds.length : i + 50);
      final response = await _get('videos', {
        'part': 'snippet',
        'id': chunk.join(','),
        'maxResults': '50',
      });
      if (response == null) {
        // Gagal: boleh dicoba lagi nanti.
        for (final id in chunk) {
          final count = (_failCount['v:$id'] ?? 0) + 1;
          _failCount['v:$id'] = count;
          if (count < _maxRetries) {
            _pendingVideos.add(id);
          } else {
            _videoTried.add(id);
          }
        }
        if (_pendingVideos.isNotEmpty) _scheduleRetry();
        continue;
      }
      _videoTried.addAll(chunk);
      try {
        final data = jsonDecode(response.body);
        final items = data is Map ? data['items'] : null;
        if (items is! List) continue;
        for (final item in items) {
          if (item is! Map) continue;
          final id = item['id']?.toString() ?? '';
          final snippet = item['snippet'];
          final channelId = snippet is Map ? snippet['channelId']?.toString() ?? '' : '';
          if (id.isNotEmpty && channelId.isNotEmpty) {
            _videoChannel[id] = channelId;
            _pending.add(channelId);
          }
        }
      } catch (_) {}
    }
  }

  void _scheduleRetry() {
    _retryTimer ??= Timer(_retryDelay, () {
      _retryTimer = null;
      if (_pending.isNotEmpty || _pendingVideos.isNotEmpty) {
        _timer ??= Timer(const Duration(milliseconds: 50), () => unawaited(_flush()));
      }
    });
  }

  Future<void> _flush() async {
    _timer = null;
    await _ensureLoaded();

    if (_pendingVideos.isNotEmpty) {
      final videoIds = _pendingVideos.toList();
      _pendingVideos.clear();
      await _resolveVideos(videoIds);
    }

    final ids = _pending.where((id) => !_urls.containsKey(id)).toList();
    _pending.clear();
    // Data dari penyimpanan HP mungkin baru saja dimuat: beri tahu pendengar.
    if (ids.isEmpty) {
      notifyListeners();
      return;
    }

    var changed = false;
    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.sublist(i, i + 50 > ids.length ? ids.length : i + 50);
      final response = await _get('channels', {
        'part': 'snippet',
        'id': chunk.join(','),
        'maxResults': '50',
      });
      if (response == null) {
        // Gagal jaringan/kuota: jadwalkan ulang, jangan dianggap selesai.
        for (final id in chunk) {
          final count = (_failCount[id] ?? 0) + 1;
          _failCount[id] = count;
          if (count < _maxRetries) {
            _pending.add(id);
          } else {
            _done.add(id);
          }
        }
        if (_pending.isNotEmpty) _scheduleRetry();
        continue;
      }
      try {
        final data = jsonDecode(response.body);
        final items = data is Map ? data['items'] : null;
        _done.addAll(chunk);
        if (items is! List) continue;
        for (final item in items) {
          if (item is! Map) continue;
          final id = item['id']?.toString() ?? '';
          final snippet = item['snippet'];
          final thumbs = snippet is Map ? snippet['thumbnails'] : null;
          final url = _pick(thumbs);
          if (id.isNotEmpty && url.isNotEmpty) {
            _urls.remove(id);
            _urls[id] = url;
            changed = true;
          }
        }
      } catch (_) {
        // Respons rusak: kartu tetap memakai huruf.
      }
    }

    if (!changed) {
      notifyListeners();
      return;
    }
    while (_urls.length > _maxEntries) {
      _urls.remove(_urls.keys.first);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_urls));
    } catch (_) {}
  }

  static String _pick(dynamic thumbnails) {
    if (thumbnails is! Map) return '';
    for (final key in const ['medium', 'default', 'high']) {
      final entry = thumbnails[key];
      if (entry is Map) {
        final url = entry['url']?.toString() ?? '';
        if (url.isNotEmpty) return url;
      }
    }
    return '';
  }
}
