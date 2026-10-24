import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Realtime v2 wraps the body sent by Dart clients in `payload`.
/// Keep support for direct payloads so older versions and unit tests can use
/// the same message handlers.
Map<String, dynamic> unwrapRealtimeBroadcastPayload(
  Map<String, dynamic> frame,
) {
  final nested = frame['payload'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  return Map<String, dynamic>.from(frame);
}

/// Pulls the latest playback snapshot out of a host heartbeat. This is a
/// recovery path for transiently missed `music_state` broadcasts; heartbeats
/// are already used to verify that the host is still online.
Map<String, dynamic>? listeningSnapshotFromHostHeartbeat(
  Map<String, dynamic> frame, {
  required String expectedRoomCode,
}) {
  final message = unwrapRealtimeBroadcastPayload(frame);
  if (message['code']?.toString() != expectedRoomCode) return null;
  final rawSnapshot = message['snapshot'];
  if (rawSnapshot is! Map) return null;
  final snapshot = Map<String, dynamic>.from(rawSnapshot);
  final type = snapshot['type']?.toString();
  if (type != 'state' && type != 'idle' && type != 'unsupported') return null;
  return snapshot;
}

/// Online room input is deliberately code-only: never interpret an IP address
/// as a valid room invitation.
String? parseListeningRoomCode(String raw) {
  final value = raw.trim();
  return RegExp(r'^\d{8}$').hasMatch(value) ? value : null;
}

/// YouTube video IDs are 11 URL-safe characters. Local IDs and arbitrary URLs
/// must never be accepted as remotely selected room tracks.
bool isValidSharedYouTubeVideoId(String raw) =>
    RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(raw.trim());

/// Returns true when the guest must load the host's track into its native
/// audio player. UI metadata alone is not proof that Media3 actually has the
/// source loaded: on startup `_currentVideo` and the state notifier can be
/// restored from disk while the native audio player is still empty.
bool shouldLoadListeningTogetherTrack({
  required String currentVideoId,
  required String targetVideoId,
  required String nativeStateVideoId,
  required bool nativeAudioLoaded,
}) {
  return currentVideoId != targetVideoId ||
      nativeStateVideoId != targetVideoId ||
      !nativeAudioLoaded;
}

const Set<String> listeningRoomControlActions = <String>{
  'play_pause',
  'play_track',
  'stop',
  'next',
  'previous',
  'seek',
  'shuffle',
  'smart_shuffle',
  'loop',
  'sync_request',
};

bool isAllowedListeningRoomControlAction(String action) =>
    listeningRoomControlActions.contains(action);

/// Keeps the newest host snapshot while a guest is loading an audio source.
/// Broadcast snapshots with no sequence (older clients) are accepted for
/// backwards compatibility; the current client always sends a sequence.
Map<String, dynamic> newestQueuedListeningState(
  Map<String, dynamic>? pending,
  Map<String, dynamic> incoming,
) {
  if (pending == null) return Map<String, dynamic>.from(incoming);
  final incomingSequence = (incoming['sequence'] as num?)?.toInt() ?? 0;
  final pendingSequence = (pending['sequence'] as num?)?.toInt() ?? 0;
  if (incomingSequence == 0 ||
      pendingSequence == 0 ||
      incomingSequence > pendingSequence) {
    return Map<String, dynamic>.from(incoming);
  }
  return pending;
}

/// Online synchronization for a shared music session.
///
/// The room is code-only and uses Supabase Realtime. No local sockets or IP
/// addresses are used, because those only work on the same LAN/hotspot.
class ListeningTogetherService {
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  bool get onlineConfigured {
    if (!_supabaseUrl.startsWith('https://') ||
        _supabasePublishableKey.isEmpty) {
      return false;
    }
    if (_supabasePublishableKey.startsWith('sb_publishable_')) return true;

    // Allow legacy public anon JWT keys, but never service_role/secret keys.
    final parts = _supabasePublishableKey.split('.');
    if (parts.length != 3) return false;
    try {
      final claims = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      return claims is Map && claims['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  final ValueNotifier<String> status = ValueNotifier<String>('Belum terhubung');
  /// Explains whether the guest actually receives/applies the host's player state.
  final ValueNotifier<String> syncStatus =
      ValueNotifier<String>('Belum ada sesi sinkronisasi');
  final ValueNotifier<int> peerCount = ValueNotifier<int>(0);
  final ValueNotifier<String> inviteAddress = ValueNotifier<String>('');
  final ValueNotifier<String> roomCode = ValueNotifier<String>('');
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();

  SupabaseClient? _onlineClient;
  RealtimeChannel? _onlineChannel;
  Timer? _heartbeatTimer;
  Timer? _hostWatchdogTimer;
  DateTime? _lastHostHeartbeatAt;
  bool _hosting = false;
  bool _joined = false;
  bool _onlineMode = false;
  bool _disposed = false;
  bool _onlineJoinAccepted = false;
  String _onlineClientId = '';
  Completer<bool>? _onlineJoinCompleter;
  final Set<String> _onlinePeers = <String>{};
  final Map<String, DateTime> _onlinePeerLastSeen = <String, DateTime>{};
  final Map<String, DateTime> _lastControlAt = <String, DateTime>{};
  Map<String, dynamic>? _latestHostPlaybackState;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  bool get isHost => _hosting;
  bool get isGuest => _joined;
  bool get isConnected => _hosting || _joined;

  Future<String> hostRoom() async {
    if (!onlineConfigured) {
      throw StateError(
        'Server online belum dikonfigurasi. Atur SUPABASE_URL dan '
        'SUPABASE_PUBLISHABLE_KEY di GitHub Actions lalu build APK baru.',
      );
    }
    await closeRoom();
    return _hostOnlineRoom();
  }

  /// Joins using the eight-digit room code only. Passing an IP/address is
  /// intentionally rejected so the UI cannot silently fall back to LAN mode.
  Future<void> joinRoom(String rawCode, {required String code}) async {
    if (!onlineConfigured) {
      throw StateError(
        'Server online belum dikonfigurasi. Atur SUPABASE_URL dan '
        'SUPABASE_PUBLISHABLE_KEY di GitHub Actions lalu build APK baru.',
      );
    }
    final parsedCode = parseListeningRoomCode(rawCode);
    if (parsedCode == null || (code.trim().isNotEmpty && code.trim() != parsedCode)) {
      throw const FormatException(
        'Masukkan kode kamar 8 digit. Alamat IP tidak digunakan.',
      );
    }
    await closeRoom();
    await _joinOnlineRoom(parsedCode);
  }

  SupabaseClient get _remoteClient => _onlineClient ??= SupabaseClient(
        _supabaseUrl,
        _supabasePublishableKey,
      );

  String _randomHexToken([int bytes = 16]) {
    final random = Random.secure();
    return List<String>.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      growable: false,
    ).join();
  }

  Future<String> _hostOnlineRoom() async {
    final pin = (Random.secure().nextInt(90000000) + 10000000).toString();
    _onlineMode = true;
    _onlineClientId = _randomHexToken();
    _hosting = true;
    _joined = false;
    _onlinePeers.clear();
    _onlinePeerLastSeen.clear();
    _lastControlAt.clear();
    _latestHostPlaybackState = null;
    roomCode.value = pin;
    inviteAddress.value = pin;
    status.value = 'Menghubungkan ke server online…';
    syncStatus.value = 'Menunggu musik dari host';

    final channel = _createOnlineChannel(pin, hosting: true);
    _onlineChannel = channel;
    try {
      await _subscribeOnlineChannel(channel);
      status.value = 'Kamar online aktif • menunggu teman';
      syncStatus.value = 'Kamar siap • pilih lagu YouTube untuk dibagikan';
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _pruneOnlinePeers();
        _sendOnlineUnawaited('room_host_heartbeat', <String, dynamic>{
          'code': roomCode.value,
          'sentAtMs': DateTime.now().millisecondsSinceEpoch,
          if (_latestHostPlaybackState != null)
            'snapshot': Map<String, dynamic>.from(_latestHostPlaybackState!),
        });
      });
      _sendOnlineUnawaited('room_host_heartbeat', <String, dynamic>{
        'code': roomCode.value,
        'sentAtMs': DateTime.now().millisecondsSinceEpoch,
        if (_latestHostPlaybackState != null)
          'snapshot': Map<String, dynamic>.from(_latestHostPlaybackState!),
      });
      return pin;
    } catch (error) {
      await closeRoom();
      throw StateError(
        'Gagal menghubungkan ke Supabase Realtime: $error. '
        'Periksa URL, publishable key, status project, dan koneksi internet.',
      );
    }
  }

  Future<void> _joinOnlineRoom(String pin) async {
    _onlineJoinAccepted = false;
    _onlineMode = true;
    _onlineClientId = _randomHexToken();
    _hosting = false;
    _joined = false;
    _onlinePeers.clear();
    roomCode.value = pin;
    inviteAddress.value = pin;
    status.value = 'Menghubungkan ke kamar online…';
    syncStatus.value = 'Menunggu status lagu dari host…';

    final channel = _createOnlineChannel(pin, hosting: false);
    _onlineChannel = channel;
    final completer = Completer<bool>();
    _onlineJoinCompleter = completer;
    try {
      await _subscribeOnlineChannel(channel);
      await _sendOnline('room_join', <String, dynamic>{
        'clientId': _onlineClientId,
        'code': pin,
      });
      final accepted = await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
          'Host tidak merespons. Periksa kode 8 digit dan pastikan host masih membuka kamar.',
        ),
      );
      if (!accepted) throw const FormatException('Kode kamar ditolak host.');

      _onlineJoinAccepted = true;
      _onlineJoinCompleter = null;
      _heartbeatTimer?.cancel();
      _lastHostHeartbeatAt = DateTime.now();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_joined || !_onlineMode) return;
        _sendOnlineUnawaited('room_heartbeat', <String, dynamic>{
          'clientId': _onlineClientId,
          'code': roomCode.value,
        });
      });
      _hostWatchdogTimer?.cancel();
      _hostWatchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_joined || !_onlineMode) return;
        final lastHeartbeat = _lastHostHeartbeatAt;
        if (lastHeartbeat == null ||
            DateTime.now().difference(lastHeartbeat) <= const Duration(seconds: 18)) {
          return;
        }
        _joined = false;
        status.value = 'Host terputus • sesi dengerin bareng dihentikan';
        if (!_messages.isClosed) _messages.add(<String, dynamic>{'type': 'room_closed'});
        unawaited(() async {
          await closeRoom();
          if (!_disposed) status.value = 'Host terputus • sesi dengerin bareng dihentikan';
        }());
      });
      status.value = 'Terhubung online • kontrol bersama aktif';
      syncStatus.value = 'Meminta status lagu terbaru dari host…';
      // Broadcast is not persisted. Ask for a fresh snapshot immediately instead
      // of making the guest wait for the next periodic heartbeat. A failed request
      // must not tear down a successfully joined room.
      try {
        await requestControl('sync_request');
      } catch (error) {
        syncStatus.value = 'Terhubung; menunggu pembaruan lagu (${error.runtimeType})';
      }
    } catch (_) {
      _onlineJoinCompleter = null;
      await closeRoom();
      rethrow;
    }
  }

  RealtimeChannel _createOnlineChannel(String pin, {required bool hosting}) {
    final channel = _remoteClient.channel(
      'musikku_room_$pin',
      opts: const RealtimeChannelConfig(private: false, self: false, ack: true),
    );

    channel.onBroadcast(event: 'music_state', callback: (frame) {
      if (hosting || !_onlineMode || !_joined || _disposed) return;
      final message = unwrapRealtimeBroadcastPayload(frame);
      if (!_messages.isClosed) _messages.add(message);
    });

    channel.onBroadcast(event: 'room_join', callback: (frame) {
      if (!hosting || !_onlineMode || !_hosting || _disposed) return;
      final message = unwrapRealtimeBroadcastPayload(frame);
      final clientId = message['clientId']?.toString() ?? '';
      final incomingPin = message['code']?.toString() ?? '';
      if (clientId.isEmpty || incomingPin != roomCode.value) return;

      _onlinePeers.add(clientId);
      _onlinePeerLastSeen[clientId] = DateTime.now();
      _publishOnlinePeerCount();
      _sendOnlineUnawaited('room_join_result', <String, dynamic>{
        'clientId': clientId,
        'accepted': true,
        'message': 'Terhubung',
      });
    });

    channel.onBroadcast(event: 'room_join_result', callback: (frame) {
      if (hosting || !_onlineMode || _disposed) return;
      final message = unwrapRealtimeBroadcastPayload(frame);
      if (message['clientId']?.toString() != _onlineClientId) return;
      final accepted = message['accepted'] == true;
      if (accepted) {
        _joined = true;
        status.value = 'Terhubung online • kontrol bersama aktif';
      }
      final completer = _onlineJoinCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(accepted);
      }
    });

    channel.onBroadcast(event: 'room_heartbeat', callback: (frame) {
      if (!hosting || !_onlineMode || !_hosting) return;
      final message = unwrapRealtimeBroadcastPayload(frame);
      final clientId = message['clientId']?.toString() ?? '';
      if (!_onlinePeers.contains(clientId) ||
          message['code']?.toString() != roomCode.value) {
        return;
      }
      _onlinePeerLastSeen[clientId] = DateTime.now();
    });

    channel.onBroadcast(event: 'room_leave', callback: (frame) {
      if (!hosting || !_onlineMode || !_hosting) return;
      final message = unwrapRealtimeBroadcastPayload(frame);
      final clientId = message['clientId']?.toString() ?? '';
      if (_onlinePeers.remove(clientId)) {
        _onlinePeerLastSeen.remove(clientId);
        _lastControlAt.remove(clientId);
        _publishOnlinePeerCount();
      }
    });

    channel.onBroadcast(event: 'room_control', callback: (frame) {
      if (!hosting || !_onlineMode || !_hosting || _disposed) return;
      final message = unwrapRealtimeBroadcastPayload(frame);
      final clientId = message['clientId']?.toString() ?? '';
      final action = message['action']?.toString() ?? '';
      if (!_onlinePeers.contains(clientId) ||
          message['code']?.toString() != roomCode.value ||
          !isAllowedListeningRoomControlAction(action)) {
        return;
      }
      final now = DateTime.now();
      final last = _lastControlAt[clientId];
      if (last != null && now.difference(last) < const Duration(milliseconds: 180)) {
        return;
      }
      _lastControlAt[clientId] = now;
      _onlinePeerLastSeen[clientId] = now;
      if (!_messages.isClosed) {
        final forwarded = <String, dynamic>{
          'type': 'control',
          'clientId': clientId,
          'action': action,
          if (message['positionMs'] is num)
            'positionMs': (message['positionMs'] as num).toInt(),
        };
        // Track metadata is copied field-by-field; arbitrary client fields are
        // never forwarded into the player command handler.
        if (action == 'play_track') {
          for (final key in const <String>[
            'videoId',
            'title',
            'artist',
            'thumbnailUrl',
            'durationSeconds',
          ]) {
            if (message.containsKey(key)) forwarded[key] = message[key];
          }
        }
        _messages.add(forwarded);
      }
    });

    channel.onBroadcast(event: 'room_host_heartbeat', callback: (frame) {
      if (hosting || !_onlineMode || !_joined || _disposed) return;
      final message = unwrapRealtimeBroadcastPayload(frame);
      if (message['code']?.toString() != roomCode.value) return;
      _lastHostHeartbeatAt = DateTime.now();

      // Host heartbeat is also a recovery transport for the latest player state.
      // If a `music_state` broadcast was dropped during join/reconnect, the
      // guest still receives the state through the heartbeat event.
      final snapshot = listeningSnapshotFromHostHeartbeat(
        frame,
        expectedRoomCode: roomCode.value,
      );
      if (snapshot != null && !_messages.isClosed) {
        _messages.add(snapshot);
      } else if (syncStatus.value.startsWith('Meminta status lagu')) {
        syncStatus.value = 'Host online • menunggu snapshot musik';
      }
    });

    channel.onBroadcast(event: 'room_closed', callback: (frame) {
      if (hosting || !_onlineMode || !_joined || _disposed) return;
      final message = unwrapRealtimeBroadcastPayload(frame);
      if (message['code']?.toString() != roomCode.value) return;
      _joined = false;
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      _hostWatchdogTimer?.cancel();
      _hostWatchdogTimer = null;
      status.value = 'Host menutup kamar';
      if (!_messages.isClosed) {
        _messages.add(<String, dynamic>{'type': 'room_closed'});
      }
      unawaited(() async {
        await closeRoom();
        if (!_disposed) status.value = 'Host menutup kamar';
      }());
    });

    return channel;
  }

  Future<void> _subscribeOnlineChannel(RealtimeChannel channel) async {
    final completer = Completer<void>();
    channel.subscribe((statusValue, error) {
      if (statusValue == RealtimeSubscribeStatus.subscribed) {
        if (!completer.isCompleted) completer.complete();
        if (_onlineMode && !_hosting && _onlineJoinAccepted && !_disposed) {
          _sendOnlineUnawaited('room_join', <String, dynamic>{
            'clientId': _onlineClientId,
            'code': roomCode.value,
          });
        }
        return;
      }
      if (!completer.isCompleted) {
        completer.completeError(StateError(
          'Server realtime gagal diakses (${statusValue.name})'
          '${error == null ? '' : ': $error'}',
        ));
      } else if (_onlineMode && !_disposed) {
        status.value = 'Koneksi server online terputus';
        if (_joined) {
          _joined = false;
          _heartbeatTimer?.cancel();
          _heartbeatTimer = null;
          _hostWatchdogTimer?.cancel();
          _hostWatchdogTimer = null;
          if (!_messages.isClosed) {
            _messages.add(<String, dynamic>{'type': 'room_closed'});
          }
        }
      }
    });
    await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw TimeoutException(
        'Server online tidak merespons. Periksa URL dan publishable key Supabase.',
      ),
    );
  }

  Future<void> _sendOnline(String event, Map<String, dynamic> payload) async {
    final channel = _onlineChannel;
    if (!_onlineMode || channel == null) {
      throw StateError('Channel kamar belum terhubung.');
    }
    final response = await channel.sendBroadcastMessage(
      event: event,
      payload: payload,
    );
    if (response.name != 'ok') {
      throw StateError('Pesan realtime gagal dikirim (${response.name}).');
    }
  }

  void _sendOnlineUnawaited(String event, Map<String, dynamic> payload) {
    // Keep failures observable without returning `null` from catchError on a
    // Future<ChannelResponse>, which can otherwise produce a second async type
    // error when the network request fails.
    unawaited(() async {
      try {
        await _sendOnline(event, payload);
      } catch (error) {
        if (!_disposed) status.value = 'Gangguan koneksi realtime: $error';
      }
    }());
  }

  Future<void> requestControl(String action, {int? positionMs}) async {
    if (!_onlineMode || !_joined || _hosting) {
      throw StateError('Gabung kamar online dulu untuk mengirim kontrol.');
    }
    if (!isAllowedListeningRoomControlAction(action)) {
      throw ArgumentError.value(action, 'action', 'Kontrol kamar tidak dikenal.');
    }
    await _sendOnline('room_control', <String, dynamic>{
      'clientId': _onlineClientId,
      'code': roomCode.value,
      'action': action,
      if (positionMs != null) 'positionMs': positionMs.clamp(0, 86400000),
    });
  }

  /// Requests that the host select and play a YouTube track. This lets a
  /// guest choose from search results without forking playback on their phone.
  Future<void> requestTrackSelection({
    required String videoId,
    required String title,
    required String artist,
    required String thumbnailUrl,
    double? durationSeconds,
  }) async {
    if (!_onlineMode || !_joined || _hosting) {
      throw StateError('Gabung kamar online dulu untuk memilih lagu bersama.');
    }
    final id = videoId.trim();
    if (!isValidSharedYouTubeVideoId(id)) {
      throw const FormatException('Hanya lagu/video YouTube yang bisa dipilih bersama.');
    }
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw const FormatException('Judul lagu tidak tersedia.');
    }
    final cleanArtist = artist.trim();
    final cleanThumbnail = thumbnailUrl.trim();
    final safeThumbnail = cleanThumbnail.startsWith('https://i.ytimg.com/') ||
            cleanThumbnail.startsWith('https://img.youtube.com/')
        ? cleanThumbnail
        : '';
    final safeDuration = durationSeconds != null &&
            durationSeconds.isFinite && durationSeconds > 0
        ? durationSeconds.clamp(0.0, 86400.0).toDouble()
        : null;

    await _sendOnline('room_control', <String, dynamic>{
      'clientId': _onlineClientId,
      'code': roomCode.value,
      'action': 'play_track',
      'videoId': id,
      'title': cleanTitle.substring(0, cleanTitle.length.clamp(0, 180).toInt()),
      'artist': cleanArtist.substring(0, cleanArtist.length.clamp(0, 160).toInt()),
      'thumbnailUrl': safeThumbnail,
      'durationSeconds': ?safeDuration,
    });
  }

  void broadcastState(Map<String, dynamic> state) {
    if (!_hosting || !_onlineMode) return;
    final payload = <String, dynamic>{'type': 'state', ...state};
    // Keep a compact copy for the host heartbeat, so a joining guest can
    // recover even if a transient music_state broadcast is missed.
    _latestHostPlaybackState = Map<String, dynamic>.from(payload);
    _sendOnlineUnawaited('music_state', payload);
  }

  void _publishOnlinePeerCount() {
    peerCount.value = _onlinePeers.length;
    if (_hosting && _onlineMode) {
      status.value = _onlinePeers.isEmpty
          ? 'Kamar online aktif • menunggu teman'
          : '${_onlinePeers.length} perangkat tersambung online';
    }
  }

  void _pruneOnlinePeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 18));
    final stale = _onlinePeerLastSeen.entries
        .where((entry) => entry.value.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final clientId in stale) {
      _onlinePeerLastSeen.remove(clientId);
      _onlinePeers.remove(clientId);
      _lastControlAt.remove(clientId);
    }
    if (stale.isNotEmpty) _publishOnlinePeerCount();
  }

  Future<void> closeRoom() async {
    final wasOnlineHost = _onlineMode && _hosting;
    final wasOnlineGuest = _onlineMode && _joined;
    final remoteChannel = _onlineChannel;
    if (remoteChannel != null && _onlineMode) {
      try {
        if (wasOnlineHost) {
          await _sendOnline('room_closed', <String, dynamic>{
            'code': roomCode.value,
          }).timeout(const Duration(seconds: 2));
        } else if (wasOnlineGuest) {
          await _sendOnline('room_leave', <String, dynamic>{
            'clientId': _onlineClientId,
            'code': roomCode.value,
          }).timeout(const Duration(seconds: 2));
        }
      } catch (_) {
        // A broken socket must not block local cleanup.
      }
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _hostWatchdogTimer?.cancel();
    _hostWatchdogTimer = null;
    _lastHostHeartbeatAt = null;
    _onlineJoinCompleter = null;
    _onlineJoinAccepted = false;
    _onlineMode = false;
    _onlineClientId = '';
    _onlinePeers.clear();
    _onlinePeerLastSeen.clear();
    _lastControlAt.clear();
    _latestHostPlaybackState = null;
    _onlineChannel = null;
    if (remoteChannel != null) {
      try {
        await _onlineClient?.removeChannel(remoteChannel);
      } catch (_) {}
    }

    _hosting = false;
    _joined = false;
    peerCount.value = 0;
    inviteAddress.value = '';
    roomCode.value = '';
    if (!_disposed) status.value = 'Belum terhubung';
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await closeRoom();
    _disposed = true;
    await _messages.close();
    await _onlineClient?.dispose();
    _onlineClient = null;
    status.dispose();
    syncStatus.dispose();
    peerCount.dispose();
    inviteAddress.dispose();
    roomCode.dispose();
  }
}
