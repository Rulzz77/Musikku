import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/listening_stat.dart';
import '../models/queue_item.dart';
import '../models/youtube_search_result.dart';

/// Penyimpanan lokal HP.
/// Tidak membutuhkan akun/backend.
class StorageService {
  StorageService();

  final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  Map<String, ListeningStat>? _statsCache;
  Future<void>? _statsLoadFuture;
  Future<void> _statsWriteChain = Future<void>.value();
  Timer? _statsFlushTimer;
  bool _statsDirty = false;
  static const String _favoritesKey = 'favorites_v2';
  static const String _playlistsKey = 'playlists_v1';
  static const String _historyKey = 'search_history_v2';
  static const String _queueKey = 'queue_v3_clean';
  static const String _recentlyPlayedKey = 'recently_played_v1';
  static const String _lastPlayedKey = 'last_played_v1';
  static const String _lastPositionKey = 'last_position_seconds_v1';
  static const String _lastDurationKey = 'last_duration_seconds_v1';
  static const String _lastPlaybackSnapshotKey = 'last_playback_snapshot_v3';
  static const String _watchProgressKey = 'watch_progress_v1';
  static const String _crossfadeSecondsKey = 'crossfade_seconds_v1';
  static const String _equalizerPresetKey = 'equalizer_preset_v1';
  static const String _equalizerTrackPresetsKey = 'equalizer_track_presets_v1';
  static const String _listeningStatsKey = 'listening_stats_v1';
  static const String _themeKey = 'app_theme_choice_v1';
  static const String _dataSaverKey = 'data_saver_v1';
  static const String _dataSaverModeKey = 'data_saver_mode_v1';
  static const String _likedKey = 'liked_v1';
  static const String _dislikedKey = 'disliked_v1';
  static const String _blockedChannelKeysKey = 'blocked_channel_keys_v1';

  static const int maxHistory = 12;
  static const int maxRecentlyPlayed = 30;


  Future<Set<String>> loadLikedIds() async => _loadIdSet(_likedKey);

  Future<void> saveLikedIds(Set<String> ids) async =>
      _saveIdSet(_likedKey, ids);

  Future<Set<String>> loadDislikedIds() async => _loadIdSet(_dislikedKey);

  Future<void> saveDislikedIds(Set<String> ids) async =>
      _saveIdSet(_dislikedKey, ids);

  /// Identitas channel yang tidak ingin muncul pada rekomendasi Radio.
  Future<Set<String>> loadBlockedChannelKeys() async =>
      _loadIdSet(_blockedChannelKeysKey);

  Future<void> saveBlockedChannelKeys(Set<String> keys) async =>
      _saveIdSet(_blockedChannelKeysKey, keys);

  Future<void> saveFeedback({
    required String videoId,
    bool? liked,
    bool? disliked,
  }) async {
    final likedIds = await loadLikedIds();
    final dislikedIds = await loadDislikedIds();

    if (liked == true) {
      likedIds.add(videoId);
      dislikedIds.remove(videoId);
    } else if (liked == false) {
      likedIds.remove(videoId);
    }

    if (disliked == true) {
      dislikedIds.add(videoId);
      likedIds.remove(videoId);
    } else if (disliked == false) {
      dislikedIds.remove(videoId);
    }

    await Future.wait([
      saveLikedIds(likedIds),
      saveDislikedIds(dislikedIds),
    ]);
  }

  Future<List<YoutubeSearchResult>> loadFavorites() async {
    return _loadVideos(_favoritesKey);
  }

  Future<void> saveFavorites(List<YoutubeSearchResult> favorites) async {
    await _saveVideos(_favoritesKey, favorites);
  }

  Future<List<Playlist>> loadPlaylists() async {
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_playlistsKey);

      if (raw == null || raw.isEmpty) {
        return <Playlist>[];
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return <Playlist>[];
      }

      final result = <Playlist>[];

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final playlist = Playlist.fromJson(Map<String, dynamic>.from(item));

        if (playlist.id.isNotEmpty) {
          result.add(playlist);
        }
      }

      return result;
    } catch (e) {
      debugPrint('LOAD PLAYLISTS ERROR: $e');
      return <Playlist>[];
    }
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    try {
      final prefs = await _prefsFuture;

      await prefs.setString(
        _playlistsKey,
        jsonEncode(playlists.map((p) => p.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('SAVE PLAYLISTS ERROR: $e');
    }
  }

  Future<List<String>> loadHistory() async {
    try {
      final prefs = await _prefsFuture;
      return List<String>.from(
        prefs.getStringList(_historyKey) ?? const <String>[],
      );
    } catch (e) {
      debugPrint('LOAD SEARCH HISTORY ERROR: $e');
      return <String>[];
    }
  }

  Future<void> saveHistory(List<String> history) async {
    try {
      final prefs = await _prefsFuture;
      await prefs.setStringList(_historyKey, history);
    } catch (e) {
      debugPrint('SAVE SEARCH HISTORY ERROR: $e');
    }
  }

  Future<List<QueueItem>> loadQueue() async {
    try {
      final videos = await _loadVideos(_queueKey);
      return videos.map((video) => QueueItem(video: video)).toList();
    } catch (e) {
      debugPrint('LOAD QUEUE ERROR: $e');
      return <QueueItem>[];
    }
  }

  Future<void> saveQueue(List<QueueItem> queue) async {
    await _saveVideos(
      _queueKey,
      queue.map((item) => item.video).toList(),
    );
  }

  Future<List<YoutubeSearchResult>> loadRecentlyPlayed() async {
    return _loadVideos(_recentlyPlayedKey);
  }

  Future<void> saveRecentlyPlayed(
    List<YoutubeSearchResult> videos,
  ) async {
    final limited = videos.take(maxRecentlyPlayed).toList();
    await _saveVideos(_recentlyPlayedKey, limited);
  }

  Future<Map<String, double>> loadWatchProgress() async {
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_watchProgressKey);

      if (raw == null || raw.isEmpty) {
        return <String, double>{};
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, double>{};
      }

      final result = <String, double>{};
      decoded.forEach((key, value) {
        final id = key.toString();
        if (id.isEmpty) {
          return;
        }

        final progress = value is Map
            ? (value['progress'] as num?)?.toDouble()
            : (value as num?)?.toDouble();

        if (progress != null && progress.isFinite) {
          result[id] = progress.clamp(0.0, 1.0).toDouble();
        }
      });

      return result;
    } catch (e) {
      debugPrint('LOAD WATCH PROGRESS ERROR: $e');
      return <String, double>{};
    }
  }

  Future<Map<String, double>> loadWatchDurations() async {
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_watchProgressKey);
      if (raw == null || raw.isEmpty) return <String, double>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, double>{};
      final result = <String, double>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          final duration = (value['duration'] as num?)?.toDouble();
          if (duration != null && duration > 0 && duration.isFinite) {
            result[key.toString()] = duration;
          }
        }
      });
      return result;
    } catch (e) {
      debugPrint('LOAD WATCH DURATIONS ERROR: $e');
      return <String, double>{};
    }
  }

  Future<void> saveWatchProgress(
    String videoId, {
    required double positionSeconds,
    required double durationSeconds,
  }) async {
    if (videoId.isEmpty || durationSeconds <= 0) {
      return;
    }

    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_watchProgressKey);
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);

      final data = <String, dynamic>{};
      if (decoded is Map) {
        data.addAll(Map<String, dynamic>.from(decoded));
      }

      var progress =
          (positionSeconds / durationSeconds).clamp(0.0, 1.0).toDouble();
      if (positionSeconds >= durationSeconds - 2.0) {
        progress = 1.0;
      }

      data[videoId] = {
        'progress': progress,
        'duration': durationSeconds,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      final entries = data.entries.toList();
      entries.sort((a, b) {
        final aTime = a.value is Map
            ? a.value['updatedAt']?.toString() ?? ''
            : '';
        final bTime = b.value is Map
            ? b.value['updatedAt']?.toString() ?? ''
            : '';
        return bTime.compareTo(aTime);
      });

      final limited = <String, dynamic>{};
      for (final entry in entries.take(200)) {
        limited[entry.key] = entry.value;
      }

      await prefs.setString(_watchProgressKey, jsonEncode(limited));
    } catch (e) {
      debugPrint('SAVE WATCH PROGRESS ERROR: $e');
    }
  }


  Future<int> loadCrossfadeSeconds() async {
    try {
      final prefs = await _prefsFuture;
      return (prefs.getInt(_crossfadeSecondsKey) ?? 0).clamp(0, 6);
    } catch (e) {
      debugPrint('LOAD CROSSFADE ERROR: $e');
      return 0;
    }
  }

  Future<void> saveCrossfadeSeconds(int seconds) async {
    try {
      final prefs = await _prefsFuture;
      await prefs.setInt(_crossfadeSecondsKey, seconds.clamp(0, 6));
    } catch (e) {
      debugPrint('SAVE CROSSFADE ERROR: $e');
    }
  }

  Future<String> loadEqualizerPreset() async {
    try {
      final prefs = await _prefsFuture;
      return prefs.getString(_equalizerPresetKey) ?? 'Flat';
    } catch (e) {
      debugPrint('LOAD EQUALIZER ERROR: $e');
      return 'Flat';
    }
  }

  Future<void> saveEqualizerPreset(String preset) async {
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(_equalizerPresetKey, preset);
    } catch (e) {
      debugPrint('SAVE EQUALIZER ERROR: $e');
    }
  }

  Future<String> loadEqualizerPresetForTrack(String videoId) async {
    final id = videoId.trim();
    if (id.isEmpty) return loadEqualizerPreset();
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_equalizerTrackPresetsKey);
      if (raw == null || raw.isEmpty) return await loadEqualizerPreset();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return await loadEqualizerPreset();
      final value = decoded[id]?.toString();
      if (value == null || value.isEmpty) return await loadEqualizerPreset();
      return value;
    } catch (e) {
      debugPrint('LOAD TRACK EQ ERROR: $e');
      return loadEqualizerPreset();
    }
  }

  Future<void> saveEqualizerPresetForTrack(String videoId, String preset) async {
    final id = videoId.trim();
    if (id.isEmpty) return saveEqualizerPreset(preset);
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_equalizerTrackPresetsKey);
      final decoded = raw == null || raw.isEmpty ? null : jsonDecode(raw);
      final map = <String, dynamic>{};
      if (decoded is Map) map.addAll(Map<String, dynamic>.from(decoded));
      map[id] = preset;
      // Jaga backup dan SharedPreferences tetap kecil.
      if (map.length > 300) {
        final keys = map.keys.toList();
        for (final oldKey in keys.take(map.length - 300)) {
          map.remove(oldKey);
        }
      }
      await prefs.setString(_equalizerTrackPresetsKey, jsonEncode(map));
    } catch (e) {
      debugPrint('SAVE TRACK EQ ERROR: $e');
    }
  }

  Future<void> saveLastPlayed(
    YoutubeSearchResult video, {
    required double positionSeconds,
    double durationSeconds = 0.0,
  }) async {
    try {
      final prefs = await _prefsFuture;

      final safePosition =
          positionSeconds.clamp(0.0, 86400.0).toDouble();

      // Satu snapshot untuk menghindari kondisi video sudah tersimpan
      // tetapi posisi belum tersimpan (atau sebaliknya).
      final safeDuration =
          durationSeconds.isFinite
              ? durationSeconds.clamp(0.0, 86400.0).toDouble()
              : 0.0;

      final snapshot = <String, dynamic>{
        'video': video.toJson(),
        'positionSeconds': safePosition,
        'durationSeconds': safeDuration,
        'savedAt': DateTime.now().toIso8601String(),
      };

      await prefs.setString(
        _lastPlaybackSnapshotKey,
        jsonEncode(snapshot),
      );

      // Tetap tulis key lama agar data versi sebelumnya tetap kompatibel.
      await prefs.setString(
        _lastPlayedKey,
        jsonEncode(video.toJson()),
      );

      await prefs.setDouble(
        _lastPositionKey,
        safePosition,
      );

      if (safeDuration > 0) {
        await prefs.setDouble(
          _lastDurationKey,
          safeDuration,
        );
      }
    } catch (e) {
      debugPrint('SAVE LAST PLAYED ERROR: $e');
    }
  }

  Future<YoutubeSearchResult?> loadLastPlayed() async {
    try {
      final prefs = await _prefsFuture;

      // Prioritaskan snapshot baru yang berisi lagu + posisi secara atomik.
      final snapshotRaw =
          prefs.getString(_lastPlaybackSnapshotKey);

      if (snapshotRaw != null && snapshotRaw.isNotEmpty) {
        final snapshot = jsonDecode(snapshotRaw);

        if (snapshot is Map && snapshot['video'] is Map) {
          final video = YoutubeSearchResult.fromJson(
            Map<String, dynamic>.from(snapshot['video'] as Map),
          );

          if (video.videoId.isNotEmpty) {
            return video;
          }
        }
      }

      // Fallback untuk data yang dibuat oleh versi lama aplikasi.
      final raw = prefs.getString(_lastPlayedKey);

      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return null;
      }

      final video = YoutubeSearchResult.fromJson(
        Map<String, dynamic>.from(decoded),
      );

      return video.videoId.isEmpty ? null : video;
    } catch (e) {
      debugPrint('LOAD LAST PLAYED ERROR: $e');
      return null;
    }
  }

  Future<double> loadLastPosition() async {
    try {
      final prefs = await _prefsFuture;

      final snapshotRaw =
          prefs.getString(_lastPlaybackSnapshotKey);

      if (snapshotRaw != null && snapshotRaw.isNotEmpty) {
        final snapshot = jsonDecode(snapshotRaw);

        if (snapshot is Map) {
          final value = snapshot['positionSeconds'];

          if (value is num) {
            return value
                .clamp(0.0, 86400.0)
                .toDouble();
          }
        }
      }

      // Fallback untuk snapshot versi lama.
      return (prefs.getDouble(_lastPositionKey) ?? 0.0)
          .clamp(0.0, 86400.0)
          .toDouble();
    } catch (e) {
      debugPrint('LOAD LAST POSITION ERROR: $e');
      return 0.0;
    }
  }


  Future<double> loadLastDuration() async {
    try {
      final prefs = await _prefsFuture;

      final snapshotRaw = prefs.getString(_lastPlaybackSnapshotKey);

      if (snapshotRaw != null && snapshotRaw.isNotEmpty) {
        final snapshot = jsonDecode(snapshotRaw);

        if (snapshot is Map) {
          final value = snapshot['durationSeconds'];

          if (value is num && value > 0) {
            return value.clamp(0.0, 86400.0).toDouble();
          }
        }
      }

      return (prefs.getDouble(_lastDurationKey) ?? 0.0)
          .clamp(0.0, 86400.0)
          .toDouble();
    } catch (e) {
      debugPrint('LOAD LAST DURATION ERROR: $e');
      return 0.0;
    }
  }


  Future<Map<String, ListeningStat>> _ensureStatsCache() async {
    if (_statsCache != null) {
      return _statsCache!;
    }

    if (_statsLoadFuture != null) {
      await _statsLoadFuture;
      return _statsCache ?? <String, ListeningStat>{};
    }

    _statsLoadFuture = () async {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_listeningStatsKey);
      final loaded = <String, ListeningStat>{};

      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map) {
                final stat = ListeningStat.fromJson(
                  Map<String, dynamic>.from(item),
                );
                if (stat.videoId.isNotEmpty) {
                  loaded[stat.videoId] = stat;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('LOAD LISTENING STATS ERROR: $e');
        }
      }

      _statsCache = loaded;
    }();

    try {
      await _statsLoadFuture;
    } finally {
      _statsLoadFuture = null;
    }

    return _statsCache ?? <String, ListeningStat>{};
  }

  Future<List<ListeningStat>> loadListeningStats() async {
    final stats = await _ensureStatsCache();
    final result = stats.values.toList();
    result.sort((a, b) {
      final ad = a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return result;
  }

  Future<void> _writeStatsNow() async {
    if (!_statsDirty) return;

    final stats = _statsCache ?? <String, ListeningStat>{};
    final list = stats.values.toList();
    list.sort((a, b) {
      final ad = a.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.lastPlayedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    final prefs = await _prefsFuture;
    await prefs.setString(
      _listeningStatsKey,
      jsonEncode(list.take(200).map((e) => e.toJson()).toList()),
    );
    _statsDirty = false;
  }

  void _scheduleStatsFlush() {
    _statsFlushTimer?.cancel();
    _statsFlushTimer = Timer(const Duration(seconds: 3), () {
      _statsWriteChain = _statsWriteChain.then((_) => _writeStatsNow());
    });
  }

  Future<void> flushPendingWrites() async {
    _statsFlushTimer?.cancel();
    _statsFlushTimer = null;
    _statsWriteChain = _statsWriteChain.then((_) => _writeStatsNow());
    await _statsWriteChain;
  }

  Future<void> recordListening({
    required YoutubeSearchResult video,
    required double deltaSeconds,
    required bool newPlay,
  }) async {
    if (video.videoId.isEmpty || deltaSeconds <= 0 && !newPlay) return;

    final stats = await _ensureStatsCache();
    final current = stats[video.videoId];
    stats[video.videoId] = ListeningStat(
      videoId: video.videoId,
      title: video.title,
      artist: video.channelTitle,
      thumbnailUrl: video.coverUrl,
      playCount: (current?.playCount ?? 0) + (newPlay ? 1 : 0),
      skipCount: current?.skipCount ?? 0,
      listenedSeconds: (current?.listenedSeconds ?? 0) +
          deltaSeconds.clamp(0.0, 30.0).toDouble(),
      lastPlayedAt: DateTime.now(),
    );
    _statsDirty = true;
    _scheduleStatsFlush();
  }

  Future<void> recordSkip(YoutubeSearchResult video) async {
    if (video.videoId.isEmpty) return;

    final stats = await _ensureStatsCache();
    final current = stats[video.videoId];
    stats[video.videoId] = ListeningStat(
      videoId: video.videoId,
      title: video.title,
      artist: video.channelTitle,
      thumbnailUrl: video.coverUrl,
      playCount: current?.playCount ?? 0,
      skipCount: (current?.skipCount ?? 0) + 1,
      listenedSeconds: current?.listenedSeconds ?? 0.0,
      lastPlayedAt: DateTime.now(),
    );
    _statsDirty = true;
    _scheduleStatsFlush();
  }

  Future<String> exportBackupJson() async {
    final prefs = await _prefsFuture;
    final data = <String, dynamic>{
      'version': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'favorites': await loadFavorites().then((v) => v.map((e) => e.toJson()).toList()),
      'playlists': await loadPlaylists().then((v) => v.map((e) => e.toJson()).toList()),
      'history': await loadHistory(),
      'queue': await loadQueue().then((v) => v.map((e) => e.video.toJson()).toList()),
      'recentlyPlayed': await loadRecentlyPlayed().then((v) => v.map((e) => e.toJson()).toList()),
      'watchProgress': jsonDecode(prefs.getString(_watchProgressKey) ?? '{}'),
      'listeningStats': await loadListeningStats().then((v) => v.map((e) => e.toJson()).toList()),
      'lastPlayed': jsonDecode(prefs.getString(_lastPlayedKey) ?? 'null'),
      'lastPlaybackSnapshot': jsonDecode(prefs.getString(_lastPlaybackSnapshotKey) ?? 'null'),
      'lastPosition': await loadLastPosition(),
      'lastDuration': await loadLastDuration(),
      'crossfadeSeconds': await loadCrossfadeSeconds(),
      'equalizerPreset': await loadEqualizerPreset(),
      'equalizerTrackPresets': jsonDecode(prefs.getString(_equalizerTrackPresetsKey) ?? '{}'),
      'themeChoice': prefs.getString(_themeKey) ?? 'dark',
      'dataSaver': prefs.getBool(_dataSaverKey) ?? false,
      'dataSaverMode': prefs.getString(_dataSaverModeKey) ??
          ((prefs.getBool(_dataSaverKey) ?? false) ? 'saver' : 'off'),
      'likedIds': (await loadLikedIds()).toList(),
      'dislikedIds': (await loadDislikedIds()).toList(),
      'blockedChannelKeys': (await loadBlockedChannelKeys()).toList(),
    };
    return jsonEncode(data);
  }

  Future<void> restoreBackupJson(String raw) async {
    await flushPendingWrites();
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['version'] == null) {
      throw const FormatException('File backup MusikKu tidak valid.');
    }
    final prefs = await _prefsFuture;
    Future<void> write(String key, dynamic value) async {
      await prefs.setString(key, jsonEncode(value));
    }
    if (decoded['favorites'] is List) await write(_favoritesKey, decoded['favorites']);
    if (decoded['playlists'] is List) await write(_playlistsKey, decoded['playlists']);
    if (decoded['history'] is List) await prefs.setStringList(_historyKey, List<String>.from(decoded['history'].map((e) => e.toString())));
    if (decoded['queue'] is List) await write(_queueKey, decoded['queue']);
    if (decoded['recentlyPlayed'] is List) await write(_recentlyPlayedKey, decoded['recentlyPlayed']);
    if (decoded['watchProgress'] is Map) await write(_watchProgressKey, decoded['watchProgress']);
    if (decoded['listeningStats'] is List) await write(_listeningStatsKey, decoded['listeningStats']);
    _statsFlushTimer?.cancel();
    _statsFlushTimer = null;
    _statsCache = null;
    _statsDirty = false;
    if (decoded['lastPlayed'] is Map) await prefs.setString(_lastPlayedKey, jsonEncode(decoded['lastPlayed']));
    if (decoded['lastPlaybackSnapshot'] is Map) {
      await prefs.setString(_lastPlaybackSnapshotKey, jsonEncode(decoded['lastPlaybackSnapshot']));
    }
    if (decoded['lastPosition'] is num) await prefs.setDouble(_lastPositionKey, decoded['lastPosition'].toDouble());
    if (decoded['lastDuration'] is num) await prefs.setDouble(_lastDurationKey, decoded['lastDuration'].toDouble());
    if (decoded['crossfadeSeconds'] is num) await prefs.setInt(_crossfadeSecondsKey, decoded['crossfadeSeconds'].toInt().clamp(0, 6).toInt());
    if (decoded['equalizerPreset'] is String) await prefs.setString(_equalizerPresetKey, decoded['equalizerPreset']);
    if (decoded['equalizerTrackPresets'] is Map) await prefs.setString(_equalizerTrackPresetsKey, jsonEncode(decoded['equalizerTrackPresets']));
    if (decoded['themeChoice'] is String) await prefs.setString(_themeKey, decoded['themeChoice']);
    if (decoded['dataSaverMode'] is String) {
      await prefs.setString(_dataSaverModeKey, decoded['dataSaverMode']);
      await prefs.setBool(_dataSaverKey, decoded['dataSaverMode'] != 'off');
    } else if (decoded['dataSaver'] is bool) {
      await prefs.setBool(_dataSaverKey, decoded['dataSaver']);
      await prefs.setString(
        _dataSaverModeKey,
        decoded['dataSaver'] == true ? 'saver' : 'off',
      );
    }
    if (decoded['likedIds'] is List) await _saveIdSet(_likedKey, Set<String>.from(decoded['likedIds'].map((e) => e.toString())));
    if (decoded['dislikedIds'] is List) await _saveIdSet(_dislikedKey, Set<String>.from(decoded['dislikedIds'].map((e) => e.toString())));
    if (decoded['blockedChannelKeys'] is List) {
      await _saveIdSet(
        _blockedChannelKeysKey,
        Set<String>.from(decoded['blockedChannelKeys'].map((e) => e.toString())),
      );
    }
  }

  Future<Set<String>> _loadIdSet(String key) async {
    try {
      final prefs = await _prefsFuture;
      return (prefs.getStringList(key) ?? const <String>[])
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('LOAD ID SET ERROR [$key]: $e');
      return <String>{};
    }
  }

  Future<void> _saveIdSet(String key, Set<String> ids) async {
    try {
      final prefs = await _prefsFuture;
      await prefs.setStringList(key, ids.take(1000).toList());
    } catch (e) {
      debugPrint('SAVE ID SET ERROR [$key]: $e');
    }
  }

  Future<List<YoutubeSearchResult>> _loadVideos(String key) async {
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(key);

      if (raw == null || raw.isEmpty) {
        return <YoutubeSearchResult>[];
      }

      final decoded = jsonDecode(raw);

      if (decoded is! List) {
        return <YoutubeSearchResult>[];
      }

      final result = <YoutubeSearchResult>[];

      for (final item in decoded) {
        if (item is! Map) {
          continue;
        }

        final video = YoutubeSearchResult.fromJson(
          Map<String, dynamic>.from(item),
        );

        if (video.videoId.isNotEmpty) {
          result.add(video);
        }
      }

      return result;
    } catch (e) {
      debugPrint('LOAD VIDEOS ERROR [$key]: $e');
      return <YoutubeSearchResult>[];
    }
  }

  Future<void> _saveVideos(
    String key,
    List<YoutubeSearchResult> videos,
  ) async {
    try {
      final prefs = await _prefsFuture;

      await prefs.setString(
        key,
        jsonEncode(videos.map((video) => video.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('SAVE VIDEOS ERROR [$key]: $e');
    }
  }
}
