import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores user-selected cover images independently from the source metadata.
/// Files live in the app documents directory; this service only stores paths.
class TrackArtworkService {
  TrackArtworkService._();

  static const String _key = 'custom_track_artwork_v1';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<Map<String, String>> _read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map((key, value) => MapEntry(key.toString(), value.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  static Future<String?> pathFor(String videoId) async {
    if (videoId.trim().isEmpty) return null;
    final map = await _read();
    final path = map[videoId];
    if (path == null || path.isEmpty) return null;
    try {
      if (await File(path).exists()) return path;
    } catch (_) {}
    map.remove(videoId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
    return null;
  }

  static Future<void> setArtwork(String videoId, String path) async {
    final id = videoId.trim();
    final file = File(path);
    if (id.isEmpty || !await file.exists()) {
      throw ArgumentError('Lagu atau file artwork tidak valid.');
    }
    final map = await _read();
    map[id] = file.path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
    revision.value++;
  }

  static Future<void> clearArtwork(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return;
    final map = await _read();
    map.remove(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
    revision.value++;
  }

  static Future<bool> hasArtwork(String videoId) async =>
      (await pathFor(videoId)) != null;
}
