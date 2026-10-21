import 'dart:async';

import 'package:flutter/services.dart';

import '../models/native_youtube_state.dart';
import '../models/youtube_player_debug.dart';

class NativeYoutubeController {
  static const MethodChannel _methods =
      MethodChannel('musikku/youtube_player');

  static const EventChannel _events =
      EventChannel('musikku/youtube_player/events');
  static const MethodChannel _newPipe = MethodChannel('musikku/newpipe');

  NativeYoutubeState _lastState = const NativeYoutubeState();
  bool _usingYoutubeAudio = false;
  String _activeVideoId = ''; // Prevent stale Media3 source controls after resolver errors.
  // Guard async stream resolution: a slow previous search must never replace
  // the song the user selected most recently.
  int _youtubeAudioLoadGeneration = 0;

  NativeYoutubeState get lastState => _lastState;
  bool get isUsingYoutubeAudio => _usingYoutubeAudio;

  // ========================================================
  // PLAYBACK INTENT (optimistic UI)
  // ========================================================
  //
  // Saat user menekan Play/Pause, ikon langsung berubah mengikuti niat user
  // ([_intent]). Niat ini dihapus begitu native MEMBENARKANNYA (playing /
  // paused), atau setelah [_intentTimeout]. Event native yang bertentangan
  // dan datang telat TIDAK boleh mengubah niat, itu penyebab bug ikon
  // nyangkut di Pause sebelumnya.

  static const Duration _intentTimeout = Duration(milliseconds: 1500);

  bool? _intent;
  Timer? _intentTimer;

  void _setIntent(bool playing) {
    _intentTimer?.cancel();
    _intent = playing;

    _intentTimer = Timer(_intentTimeout, () {
      if (_intent == null) {
        return;
      }

      _intent = null;
      _emit(_lastState);
    });
  }

  void _clearIntent() {
    _intentTimer?.cancel();
    _intentTimer = null;
    _intent = null;
  }

  bool _confirmsIntent(bool wantPlaying, NativePlaybackState s) {
    if (wantPlaying) {
      return s == NativePlaybackState.playing ||
          s == NativePlaybackState.buffering;
    }

    return s == NativePlaybackState.paused ||
        s == NativePlaybackState.ended ||
        s == NativePlaybackState.error;
  }

  // ========================================================
  // STATE STREAM
  // ========================================================

  /// Satu stream bersama untuk semua listener (HomePage & FullPlayerPage).
  /// Hanya ada SATU listener ke EventChannel native; kalau tiap akses membuat
  /// receiveBroadcastStream() baru, listener baru menggantikan listener lama
  /// di sisi native dan auto-next di HomePage berhenti.
  final StreamController<NativeYoutubeState> _out =
      StreamController<NativeYoutubeState>.broadcast();

  StreamSubscription<dynamic>? _nativeSub;

  Stream<NativeYoutubeState> get stateStream {
    _nativeSub ??= _events.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: _out.addError,
    );

    return _out.stream;
  }

  void _emit(NativeYoutubeState raw) {
    final state = NativeYoutubeState(
      playbackState: raw.playbackState,
      position: raw.position,
      duration: raw.duration,
      videoId: raw.videoId,
      bufferedFraction: raw.bufferedFraction,
      bufferedAhead: raw.bufferedAhead,
      networkRxBytes: raw.networkRxBytes,
      networkType: raw.networkType,
      requestedPlaying: _intent,
    );

    _lastState = state;

    if (!_out.isClosed) {
      _out.add(state);
    }
  }

  void _onNativeEvent(dynamic event) {
    if (event is! Map) {
      _emit(const NativeYoutubeState(
        playbackState: NativePlaybackState.unknown,
      ));
      return;
    }

    final rawState = (event['state'] ?? event['event'] ?? '').toString();
    final state = _parseState(rawState);

    final position = (event['position'] as num?)?.toDouble() ?? 0.0;
    final duration = (event['duration'] as num?)?.toDouble() ?? 0.0;

    final wanted = _intent;

    if (wanted != null && _confirmsIntent(wanted, state)) {
      _clearIntent();
    }

    _emit(NativeYoutubeState(
      playbackState: state,
      position: Duration(milliseconds: (position * 1000).round()),
      duration: Duration(milliseconds: (duration * 1000).round()),
      videoId: event['videoId']?.toString() ?? '',
      bufferedFraction: (event['bufferedFraction'] as num?)?.toDouble() ?? 0.0,
      bufferedAhead: Duration(
        milliseconds: ((((event['bufferedAheadSeconds'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 86400.0)) * 1000).round(),
      ),
      networkRxBytes: (event['networkRxBytes'] as num?)?.toInt() ?? 0,
      networkType: event['networkType']?.toString() ?? 'unknown',
    ));
  }

  static NativePlaybackState _parseState(String raw) {
    switch (raw) {
      case 'unstarted':
        return NativePlaybackState.unstarted;
      case 'ended':
        return NativePlaybackState.ended;
      case 'playing':
        return NativePlaybackState.playing;
      case 'paused':
        return NativePlaybackState.paused;
      case 'buffering':
        return NativePlaybackState.buffering;
      case 'cued':
        return NativePlaybackState.cued;
      case 'error':
        return NativePlaybackState.error;
      default:
        return NativePlaybackState.unknown;
    }
  }

  void dispose() {
    _youtubeAudioLoadGeneration++;
    _intentTimer?.cancel();
    _nativeSub?.cancel();
    _out.close();
  }

  // ========================================================
  // LOAD VIDEO
  // ========================================================

  Future<void> loadVideoById({
    required String videoId,
    double startSeconds = 0.0,
  }) async {
    _youtubeAudioLoadGeneration++; // invalidate an older audio extraction
    _activeVideoId = videoId;
    _usingYoutubeAudio = false;
    _setIntent(true);

    final safeStart = startSeconds.isFinite && startSeconds > 0
        ? startSeconds
        : 0.0;

    PlatformException? lastError;

    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        await _methods.invokeMethod(
          'loadVideo',
          {
            'videoId': videoId,
            'startSeconds': safeStart,
          },
        );
        return;
      } on PlatformException catch (e) {
        if (e.code != 'PLAYER_NOT_READY') {
          rethrow;
        }

        lastError = e;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }

    if (lastError != null) {
      throw lastError;
    }
  }

  /// Eksperimen audio-only untuk track YouTube.
  /// Resolusi stream dilakukan di native NewPipe bridge; pemutaran audio
  /// ditangani ExoPlayer di PlaybackService agar kontrol layar kunci dan
  /// background tidak bergantung pada lifecycle WebView.
  Future<void> loadYoutubeAudioTrack({
    required String videoId,
    required String title,
    required String artist,
    required String thumbnailUrl,
    double startSeconds = 0.0,
    double durationSeconds = 0.0,
    bool playing = true,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
      throw ArgumentError.value(videoId, 'videoId', 'ID YouTube tidak valid');
    }

    final generation = ++_youtubeAudioLoadGeneration;
    _activeVideoId = videoId;
    _usingYoutubeAudio = false;
    _setIntent(playing);

    final safeStart = startSeconds.isFinite && startSeconds > 0
        ? startSeconds
        : 0.0;
    final safeDuration = durationSeconds.isFinite && durationSeconds > 0
        ? durationSeconds
        : 0.0;

    // Audio-only: pause the previous source first. Do not load/prepare a
    // YouTube video surface, which was the source of overlapping sound and
    // state events that could cause the queue to skip unexpectedly.
    try {
      await _methods.invokeMethod('pauseActiveAudio');
    } catch (_) {}

    _emit(NativeYoutubeState(
      playbackState: NativePlaybackState.buffering,
      position: Duration(milliseconds: (safeStart * 1000).round()),
      duration: Duration(milliseconds: (safeDuration * 1000).round()),
      videoId: videoId,
    ));

    Map<String, dynamic>? resolved;
    Object? resolveFailure;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (generation != _youtubeAudioLoadGeneration) return;
      try {
        resolved = await _newPipe.invokeMapMethod<String, dynamic>(
          'resolveAudio',
          {'videoId': videoId},
        );
        resolveFailure = null;
        break;
      } catch (error) {
        if (generation != _youtubeAudioLoadGeneration) return;
        resolveFailure = error;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
        }
      }
    }

    if (generation != _youtubeAudioLoadGeneration) return;
    if (resolveFailure != null) {
      _usingYoutubeAudio = false;
      _clearIntent();
      _emit(NativeYoutubeState(
        playbackState: NativePlaybackState.error,
        position: Duration(milliseconds: (safeStart * 1000).round()),
        duration: Duration(milliseconds: (safeDuration * 1000).round()),
        videoId: videoId,
      ));
      throw resolveFailure;
    }

    final streamUrl = resolved?['streamUrl']?.toString().trim() ?? '';
    if (streamUrl.isEmpty || !streamUrl.startsWith('https://')) {
      _usingYoutubeAudio = false;
      _clearIntent();
      _emit(NativeYoutubeState(
        playbackState: NativePlaybackState.error,
        position: Duration(milliseconds: (safeStart * 1000).round()),
        duration: Duration(milliseconds: (safeDuration * 1000).round()),
        videoId: videoId,
      ));
      throw PlatformException(
        code: 'AUDIO_STREAM_UNAVAILABLE',
        message: 'Sumber audio tidak tersedia untuk lagu ini.',
      );
    }

    final rawHeaders = resolved?['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final key = entry.key?.toString().trim() ?? '';
        final value = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && value.isNotEmpty) headers[key] = value;
      }
    }

    try {
      if (generation != _youtubeAudioLoadGeneration) return;
      _usingYoutubeAudio = true;
      await _methods.invokeMethod('loadYoutubeAudio', {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'streamUrl': streamUrl,
        'headers': headers,
        'startSeconds': safeStart,
        'durationSeconds': safeDuration,
        'playing': playing,
      });
      if (generation == _youtubeAudioLoadGeneration) {
        _usingYoutubeAudio = true;
      }
    } catch (_) {
      if (generation == _youtubeAudioLoadGeneration) {
        _usingYoutubeAudio = false;
        _clearIntent();
        _emit(NativeYoutubeState(
          playbackState: NativePlaybackState.error,
          position: Duration(milliseconds: (safeStart * 1000).round()),
          duration: Duration(milliseconds: (safeDuration * 1000).round()),
          videoId: videoId,
        ));
      }
      rethrow;
    }
  }

  // ========================================================
  // LOCAL MUSIC
  // ========================================================

  Future<void> loadLocalTrack({
    required String mediaId,
    required String title,
    required String artist,
    required String mediaUri,
    double startSeconds = 0.0,
    double durationSeconds = 0.0,
  }) async {
    _youtubeAudioLoadGeneration++; // invalidate a pending YouTube resolver
    _activeVideoId = 'local:$mediaId';
    _usingYoutubeAudio = false;
    _setIntent(true);
    await _methods.invokeMethod(
      'loadLocal',
      {
        'mediaId': mediaId,
        'title': title,
        'artist': artist,
        'mediaUri': mediaUri,
        'startSeconds': startSeconds,
        'durationSeconds': durationSeconds,
      },
    );
  }

  // ========================================================
  // PLAY
  // ========================================================

  Future<void> playVideo() async {
    _setIntent(true);
    await _methods.invokeMethod('play', {'videoId': _activeVideoId});
  }

  // ========================================================
  // PAUSE
  // ========================================================

  Future<void> pauseVideo() async {
    _setIntent(false);
    await _methods.invokeMethod('pause', {'videoId': _activeVideoId});
  }

  Future<void> setPlayerUiVisible(bool visible) async {
    try {
      await _methods.invokeMethod('setPlayerUiVisible', {'visible': visible});
    } catch (_) {
      // Versi native lama tetap boleh berjalan tanpa kontrol UI tambahan.
    }
  }

  /// 0 = mati, 1 = Hemat, 2 = Super hemat. Native menurunkan kualitas saat
  /// memakai paket data dan saat aplikasi di background (video tak terlihat).
  Future<void> setDataSaverLevel(int level) async {
    try {
      await _methods.invokeMethod('setDataSaverLevel', {'level': level});
    } catch (_) {
      // Versi native lama tetap boleh berjalan tanpa fitur ini.
    }
  }

  Future<void> setPlaybackQuality(String quality) async {
    await _methods.invokeMethod(
      'setPlaybackQuality',
      {'quality': quality},
    );
  }

  Future<void> setCaptionSettings({
    required bool enabled,
    String language = 'id',
  }) async {
    await _methods.invokeMethod(
      'setCaptionSettings',
      {
        'enabled': enabled,
        'language': language.trim().isEmpty ? 'id' : language.trim(),
      },
    );
  }

  Future<List<Map<String, String>>> getHealthEvents() async {
    try {
      final raw = await _methods.invokeMethod<dynamic>('getHealthEvents');
      if (raw is List) {
        return raw.whereType<Map>().map((item) => Map<String, String>.from(
          item.map((key, value) => MapEntry(key.toString(), value.toString())),
        )).toList(growable: false);
      }
    } catch (_) {}
    return const <Map<String, String>>[];
  }

  Future<void> clearHealthEvents() async {
    try {
      await _methods.invokeMethod('clearHealthEvents');
    } catch (_) {}
  }

  Future<String> getNetworkType() async {
    try {
      final value = await _methods.invokeMethod<String>('getNetworkType');
      return value?.isNotEmpty == true ? value! : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<YoutubePlayerDebugSnapshot> getPlayerDebugSnapshot() async {
    try {
      final raw = await _methods.invokeMethod<dynamic>(
        'getPlayerDebugSnapshot',
      );

      if (raw is Map) {
        return YoutubePlayerDebugSnapshot.fromMap(raw);
      }

      return const YoutubePlayerDebugSnapshot(error: 'invalid_response');
    } on PlatformException catch (e) {
      return YoutubePlayerDebugSnapshot(
        error: '${e.code}: ${e.message ?? 'unknown'}',
      );
    } catch (e) {
      return YoutubePlayerDebugSnapshot(error: e.toString());
    }
  }

  /// zoom 1.0 = normal; >1.0 memperbesar video agar tepinya terpotong.
  Future<void> setVideoCrop(double zoom) async {
    try {
      await _methods.invokeMethod('setVideoCrop', {'zoom': zoom});
    } catch (_) {
      // Build native lama tanpa fitur crop tetap berjalan normal.
    }
  }

  Future<void> setLandscapeSystemUi(bool immersive) async {
    try {
      await _methods.invokeMethod('setLandscapeSystemUi', {'immersive': immersive});
    } catch (_) {
      // Fallback aman untuk build native lama.
    }
  }


  // ========================================================
  // SEEK
  // ========================================================

  Future<void> seekTo({
    required double seconds,
  }) async {
    await _methods.invokeMethod(
      'seek',
      {
        'seconds': seconds,
        'videoId': _activeVideoId,
      },
    );
  }

  // ========================================================
  // AUDIO VOLUME / EFFECTS
  // ========================================================

  Future<void> setVolume(int percent) async {
    final safe = percent.clamp(0, 100);
    await _methods.invokeMethod('setVolume', {'percent': safe, 'videoId': _activeVideoId});
  }

  Future<bool> setEqualizerPreset(String preset) async {
    final result = await _methods.invokeMethod<dynamic>(
      'setEqualizerPreset',
      {'preset': preset},
    );

    return result == true;
  }

  /// Apply five manual EQ bands in dB (-12..+12). Android may report false
  /// when the current device/output mix does not support an output EQ.
  Future<bool> setEqualizerBands(List<double> bandsDb) async {
    final safeBands = List<double>.generate(
      5,
      (index) => (index < bandsDb.length ? bandsDb[index] : 0.0)
          .clamp(-12.0, 12.0)
          .toDouble(),
    );
    final result = await _methods.invokeMethod<dynamic>(
      'setEqualizerBands',
      {'bandsDb': safeBands},
    );
    return result == true;
  }

  // ========================================================
  // CURRENT TIME
  // ========================================================

  Future<double> get currentTime async {
    final value =
        await _methods.invokeMethod<dynamic>(
      'currentTime',
      {'videoId': _activeVideoId},
    );

    return (value as num?)?.toDouble() ?? 0.0;
  }

  // ========================================================
  // NATIVE PERSISTED SNAPSHOT
  // ========================================================

  Future<Map<String, dynamic>> loadNativePlaybackSnapshot() async {
    final value = await _methods.invokeMethod<dynamic>(
      'getNativePlaybackSnapshot',
    );

    if (value is! Map) {
      return <String, dynamic>{};
    }

    return Map<String, dynamic>.from(value);
  }


  Future<void> exportBackup(String rawJson) async {
    await _methods.invokeMethod('exportBackup', {'json': rawJson});
  }

  Future<String?> importBackup() async {
    final value = await _methods.invokeMethod<dynamic>('importBackup');
    return value?.toString();
  }

  // ========================================================
  // START MEDIA NOTIFICATION
  // ========================================================

  Future<void> startNotification({
    required String videoId,
    required String title,
    required String artist,
    String thumbnailUrl = '',
    String mediaUri = '',
    required bool playing,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    await _methods.invokeMethod(
      'startNotification',
      {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'mediaUri': mediaUri,
        'playing': playing,
        'positionSeconds': position.inMilliseconds / 1000.0,
        'durationSeconds': duration.inMilliseconds / 1000.0,
      },
    );
  }

  // ========================================================
  // UPDATE MEDIA NOTIFICATION
  // ========================================================

  Future<void> updateNotification({
    required String videoId,
    required String title,
    required String artist,
    String thumbnailUrl = '',
    String mediaUri = '',
    required bool playing,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
  }) async {
    await _methods.invokeMethod(
      'updateNotification',
      {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'mediaUri': mediaUri,
        'playing': playing,
        'positionSeconds': position.inMilliseconds / 1000.0,
        'durationSeconds': duration.inMilliseconds / 1000.0,
      },
    );
  }

  // ========================================================
  // STOP MEDIA NOTIFICATION
  // ========================================================

  Future<void> stopNotification() async {
    await _methods.invokeMethod(
      'stopNotification',
    );
  }

  // ========================================================
  // MEDIA CONTROL CALLBACK
  // ========================================================

  void setNotificationCallbacks({
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    required Future<void> Function() onPlayPause,
    required Future<void> Function() onStop,
    void Function(bool pipEnabled)? onPipChanged,
    void Function()? onPipWillEnter,
    Future<void> Function(String? videoId, double? positionSeconds, bool shouldPlay)? onYoutubeAudioPlaybackError,
    void Function(String videoId, String error)? onYoutubeEmbedError,
  }) {
    _methods.setMethodCallHandler(
      (call) async {
        switch (call.method) {
          case 'notificationNext':
            await onNext();
            break;

          case 'notificationPrevious':
            await onPrevious();
            break;

          case 'notificationPlayPause':
            await onPlayPause();
            break;

          case 'notificationStop':
            await onStop();
            break;

          case 'youtubeAudioPlaybackError':
            final args = call.arguments;
            final map = args is Map ? args : const <Object?, Object?>{};
            final failedVideoId = map['videoId']?.toString();
            final rawPosition = map['positionSeconds'];
            final failedPosition = rawPosition is num ? rawPosition.toDouble() : null;
            final shouldPlay = map['shouldPlay'] == true;
            await onYoutubeAudioPlaybackError?.call(failedVideoId, failedPosition, shouldPlay);
            break;

          case 'youtubeEmbedError':
            final args = call.arguments;
            final map = args is Map ? args : const <Object?, Object?>{};
            onYoutubeEmbedError?.call(
              map['videoId']?.toString() ?? '',
              map['error']?.toString() ?? 'unknown',
            );
            break;

          case 'youtubePipWillEnter':
            onPipWillEnter?.call();
            break;

          case 'youtubePipChanged':
            onPipChanged?.call(call.arguments == true);
            break;


        }

        return null;
      },
    );
  }
}