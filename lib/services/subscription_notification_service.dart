import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/youtube_search_result.dart';

class SubscriptionNotificationService {
  static final instance = SubscriptionNotificationService._();
  SubscriptionNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// ID video baru yang belum dilihat (dipakai untuk badge di lonceng).
  final ValueNotifier<Set<String>> unreadIds = ValueNotifier<Set<String>>(<String>{});

  Future<void> loadUnread() async {
    final prefs = await SharedPreferences.getInstance();
    unreadIds.value = (prefs.getStringList('yt_unread_videos') ?? <String>[]).toSet();
  }

  Future<void> markAllRead() async {
    unreadIds.value = <String>{};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('yt_unread_videos', <String>[]);
  }

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('app_icon');
    final settings = InitializationSettings(android: android);
    await _plugin.initialize(settings: settings);
    _initialized = true;
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'youtube_subscriptions',
        'Video dari subscription',
        description: 'Video baru dari channel yang kamu subscribe.',
        importance: Importance.defaultImportance,
      ),
    );
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'youtube_live',
        'Siaran langsung',
        description: 'Channel yang kamu subscribe sedang live.',
        importance: Importance.high,
      ),
    );
  }

  /// Mencatat channel subscribe yang BARU mulai live untuk badge lonceng di
  /// dalam aplikasi. Notifikasi sistem (yang tetap muncul saat aplikasi
  /// ditutup) dikirim oleh worker native, bukan di sini. Setiap siaran hanya
  /// dicatat sekali. Daftar [live] yang pertama kali dilihat (saat app
  /// baru diinstal) hanya dicatat tanpa notifikasi supaya tidak membanjiri.
  Future<bool> notifyLive(List<YoutubeSearchResult> live) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList('yt_notified_live') ?? <String>[]).toSet();
    final seeded = prefs.getBool('yt_live_seeded') ?? false;
    if (live.isEmpty) {
      // Pengecekan pertama selesai walau tidak ada yang live: sejak sekarang
      // live berikutnya yang muncul harus diberi notifikasi.
      if (!seeded) await prefs.setBool('yt_live_seeded', true);
      return false;
    }
    final fresh = live.where((v) => !seen.contains(v.videoId)).toList();
    if (fresh.isEmpty) return false;

    seen.addAll(fresh.map((e) => e.videoId));
    await prefs.setStringList('yt_notified_live', seen.toList().reversed.take(100).toList());
    if (!seeded) {
      await prefs.setBool('yt_live_seeded', true);
      return false;
    }

    final unread = <String>{...unreadIds.value, ...fresh.map((e) => e.videoId)};
    unreadIds.value = unread;
    await prefs.setStringList('yt_unread_videos', unread.take(99).toList());
    return true;
  }

  Future<bool> syncAndNotify(List<YoutubeSearchResult> latest) async {
    if (latest.isEmpty) return false;
    await init();
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList('yt_notified_videos') ?? <String>[]).toSet();
    final seeded = prefs.getBool('yt_notifications_seeded') ?? false;
    if (!seeded) {
      seen.addAll(latest.map((e) => e.videoId));
      await prefs.setBool('yt_notifications_seeded', true);
      await prefs.setStringList('yt_notified_videos', seen.take(200).toList());
      return false;
    }
    var notified = false;
    final newIds = <String>{};
    for (final video in latest.take(30)) {
      if (seen.contains(video.videoId)) continue;
      seen.add(video.videoId);
      notified = true;
      newIds.add(video.videoId);
    }
    await prefs.setStringList('yt_notified_videos', seen.toList().reversed.take(200).toList());
    if (newIds.isNotEmpty) {
      final unread = <String>{...unreadIds.value, ...newIds};
      unreadIds.value = unread;
      await prefs.setStringList('yt_unread_videos', unread.take(99).toList());
    }
    return notified;
  }
}
