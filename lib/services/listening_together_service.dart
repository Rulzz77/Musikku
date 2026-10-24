import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase Realtime v2 may pass the broadcast body inside an outer `payload`
/// field. Older versions and test doubles can pass the body directly. Normalize
/// both shapes before reading room events so join/state messages aren't ignored.
Map<String, dynamic> unwrapRealtimeBroadcastPayload(
  Map<String, dynamic> frame,
) {
  final nested = frame['payload'];
  if (nested is Map) {
    return Map<String, dynamic>.from(nested);
  }
  return Map<String, dynamic>.from(frame);
}

/// Sinkronisasi sesi mendengarkan tanpa akun.
///
/// Jika SUPABASE_URL dan SUPABASE_PUBLISHABLE_KEY disediakan saat build,
/// kamar menggunakan Supabase Realtime sehingga bisa lintas jaringan. Tanpa
/// konfigurasi online, layanan mempertahankan mode LAN/hotspot lokal.
class ListeningTogetherService {
  static const int defaultPort = 41773;
  static const int _discoveryPort = 41774;
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  bool get onlineConfigured {
    if (!_supabaseUrl.startsWith('https://') || _supabasePublishableKey.isEmpty) {
      return false;
    }
    if (_supabasePublishableKey.startsWith('sb_publishable_')) return true;
    // Allow legacy public anon JWT keys, but reject service_role/secret keys.
    final parts = _supabasePublishableKey.split('.');
    if (parts.length != 3) return false;
    try {
      final claims = jsonDecode(utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      ));
      return claims is Map && claims['role'] == 'anon';
    } catch (_) {
      return false;
    }
  }

  final ValueNotifier<String> status = ValueNotifier<String>('Belum terhubung');
  final ValueNotifier<int> peerCount = ValueNotifier<int>(0);
  final ValueNotifier<String> inviteAddress = ValueNotifier<String>('');
  final ValueNotifier<String> roomCode = ValueNotifier<String>('');
  final StreamController<Map<String, dynamic>> _messages =
      StreamController<Map<String, dynamic>>.broadcast();

  ServerSocket? _server;
  RawDatagramSocket? _discoverySocket;
  Socket? _client;
  final Set<Socket> _peers = <Socket>{};
  final Map<Socket, StreamSubscription<String>> _subscriptions =
      <Socket, StreamSubscription<String>>{};
  bool _hosting = false;
  bool _joined = false;
  bool _disposed = false;

  SupabaseClient? _onlineClient;
  RealtimeChannel? _onlineChannel;
  Timer? _onlineHeartbeatTimer;
  bool _onlineMode = false;
  String _onlineClientId = '';
  Completer<bool>? _onlineJoinCompleter;
  bool _onlineJoinAccepted = false;
  final Set<String> _onlinePeers = <String>{};
  final Map<String, DateTime> _onlinePeerLastSeen = <String, DateTime>{};

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  bool get isHost => _hosting;
  bool get isGuest => _joined;
  bool get isConnected => _hosting || _joined;

  Future<String> hostRoom() async {
    await closeRoom();
    if (onlineConfigured) return _hostOnlineRoom();
    return _hostLocalRoom();
  }

  Future<String> _hostLocalRoom() async {
    final server = await ServerSocket.bind(
      InternetAddress.anyIPv4,
      defaultPort,
      shared: true,
    );
    _server = server;
    roomCode.value = (Random.secure().nextInt(90000000) + 10000000).toString();
    _hosting = true;
    server.listen(
      _handleIncomingPeer,
      onError: (Object error) {
        status.value = 'Kamar bermasalah: $error';
      },
      onDone: () {
        if (!_disposed && _hosting) {
          status.value = 'Koneksi kamar ditutup';
        }
      },
    );
    await _startDiscoveryResponder();

    final addresses = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && !address.isLinkLocal) {
            addresses.add(address.address);
          }
        }
      }
    } catch (_) {
      // Keep the room alive if Android cannot enumerate interfaces. Automatic
      // UDP discovery can still find the room on networks that permit broadcast.
    }
    addresses.sort((a, b) {
      final aPrivate = _isPrivateIpv4(a) ? 0 : 1;
      final bPrivate = _isPrivateIpv4(b) ? 0 : 1;
      return aPrivate.compareTo(bPrivate);
    });
    final host = addresses.isEmpty ? '' : addresses.first;
    final endpoint = host.isEmpty ? '' : '$host:$defaultPort';
    inviteAddress.value = endpoint;
    status.value = host.isEmpty
        ? 'Kamar aktif, alamat jaringan belum ditemukan'
        : 'Kamar aktif • menunggu teman';
    return endpoint;
  }

  Future<void> joinRoom(String rawAddress, {required String code}) async {
    final inputText = rawAddress.trim();
    final invite = _parseOnlineInvite(inputText);
    if (invite != null) {
      if (!onlineConfigured) {
        throw StateError(
          'Mode online belum dikonfigurasi. Isi SUPABASE_URL dan '
          'SUPABASE_PUBLISHABLE_KEY saat build aplikasi.',
        );
      }
      final embeddedPin = invite['code'] ?? '';
      final pin = (embeddedPin.isNotEmpty ? embeddedPin : code).trim();
      if (!RegExp(r'^\d{8}$').hasMatch(pin)) {
        throw const FormatException('Undangan tidak berisi kode kamar yang valid.');
      }
      await closeRoom();
      await _joinOnlineRoom(invite['room']!, pin);
      return;
    }

    final pin = code.trim();
    if (!RegExp(r'^\d{8}$').hasMatch(pin)) {
      throw const FormatException('Masukkan kode kamar 8 digit dari host.');
    }
    await closeRoom();
    var input = rawAddress.trim();
    input = input.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '');
    input = input.split('/').first.trim();
    if (input.isEmpty) {
      throw const FormatException('Masukkan alamat kamar dari host.');
    }

    var host = input;
    var port = defaultPort;
    final colon = input.lastIndexOf(':');
    if (colon > 0 && input.indexOf(':') == colon) {
      final parsedPort = int.tryParse(input.substring(colon + 1));
      if (parsedPort != null) {
        port = parsedPort;
        host = input.substring(0, colon);
      }
    }
    final parsedAddress = InternetAddress.tryParse(host);
    if (parsedAddress == null || parsedAddress.type != InternetAddressType.IPv4) {
      throw const FormatException('Alamat harus berupa IPv4, misalnya 192.168.1.8:41773.');
    }

    status.value = 'Menghubungkan ke $host:$port…';
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 6),
    );
    _client = socket;
    _joined = true;
    inviteAddress.value = '$host:$port';
    status.value = 'Terhubung • menunggu lagu dari host';
    _listenToSocket(socket, onHost: false);
    _write(socket, <String, dynamic>{'type': 'join', 'code': pin});
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

  Map<String, String>? _parseOnlineInvite(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri != null &&
        uri.scheme.toLowerCase() == 'musikku' &&
        uri.host.toLowerCase() == 'room') {
      final token = uri.queryParameters['room'] ?? '';
      final pin = uri.queryParameters['code'] ?? '';
      if (RegExp(r'^[a-f0-9]{32}$', caseSensitive: false).hasMatch(token)) {
        return <String, String>{'room': token.toLowerCase(), 'code': pin};
      }
    }
    final codeMatch = RegExp(r'^(\d{8})$').firstMatch(raw.trim());
    if (codeMatch != null) {
      final code = codeMatch.group(1)!;
      return <String, String>{'room': code, 'code': code};
    }
    final tokenMatch = RegExp(
      r'^(?:MKROOM:)?([a-f0-9]{32})$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (tokenMatch != null) {
      return <String, String>{'room': tokenMatch.group(1)!.toLowerCase(), 'code': ''};
    }
    return null;
  }

  Future<String> _hostOnlineRoom() async {
    // Use an 8-digit numeric code as the channel key. Guests need no LAN IP or
    // hidden room token; the code is enough to join from any internet network.
    final pin = (Random.secure().nextInt(90000000) + 10000000).toString();
    final token = pin;
    _onlineMode = true;
    _onlineClientId = _randomHexToken();
    _hosting = true;
    _joined = false;
    _onlinePeers.clear();
    _onlinePeerLastSeen.clear();
    roomCode.value = pin;
    inviteAddress.value = pin;
    status.value = 'Menghubungkan ke server online…';

    final channel = _createOnlineChannel(token, hosting: true);
    _onlineChannel = channel;
    try {
      await _subscribeOnlineChannel(channel);
      status.value = 'Kamar online aktif • menunggu teman';
      return inviteAddress.value;
    } catch (_) {
      await closeRoom();
      rethrow;
    }
  }

  Future<void> _joinOnlineRoom(String token, String pin) async {
    _onlineJoinAccepted = false;
    _onlineMode = true;
    _onlineClientId = _randomHexToken();
    _hosting = false;
    _joined = false;
    roomCode.value = pin;
    inviteAddress.value = pin;
    status.value = 'Menghubungkan ke kamar online…';

    final channel = _createOnlineChannel(token, hosting: false);
    _onlineChannel = channel;
    final joinCompleter = Completer<bool>();
    _onlineJoinCompleter = joinCompleter;
    try {
      await _subscribeOnlineChannel(channel);
      await _sendOnline('room_join', <String, dynamic>{
        'clientId': _onlineClientId,
        'code': pin,
      });
      final accepted = await joinCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
          'Host tidak merespons. Pastikan link undangan masih aktif.',
        ),
      );
      if (!accepted) {
        throw const FormatException('Kode kamar ditolak host.');
      }
      _onlineJoinAccepted = true;
      _onlineJoinCompleter = null;
      _onlineHeartbeatTimer?.cancel();
      _onlineHeartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!_joined || !_onlineMode) return;
        _sendOnlineUnawaited('room_heartbeat', <String, dynamic>{
          'clientId': _onlineClientId,
          'code': roomCode.value,
        });
      });
      status.value = 'Terhubung online • mengikuti host';
    } catch (_) {
      _onlineJoinCompleter = null;
      await closeRoom();
      rethrow;
    }
  }

  RealtimeChannel _createOnlineChannel(String token, {required bool hosting}) {
    final channel = _remoteClient.channel(
      'musikku_room_$token',
      opts: const RealtimeChannelConfig(private: false, self: false, ack: true),
    );

    channel.onBroadcast(event: 'music_state', callback: (payload) {
      if (hosting || !_onlineMode || !_joined || _disposed) return;
      final message = unwrapRealtimeBroadcastPayload(payload);
      if (!_messages.isClosed) _messages.add(message);
    });

    channel.onBroadcast(event: 'room_join', callback: (payload) {
      if (!hosting || !_onlineMode || !_hosting) return;
      final message = unwrapRealtimeBroadcastPayload(payload);
      final clientId = message['clientId']?.toString() ?? '';
      final incomingPin = message['code']?.toString() ?? '';
      if (clientId.isEmpty) return;
      final accepted = incomingPin == roomCode.value;
      if (accepted) {
        _onlinePeers.add(clientId);
        _onlinePeerLastSeen[clientId] = DateTime.now();
        _publishOnlinePeerCount();
      }
      _sendOnlineUnawaited('room_join_result', <String, dynamic>{
        'clientId': clientId,
        'accepted': accepted,
        'message': accepted ? 'Terhubung' : 'Kode kamar salah.',
      });
    });

    channel.onBroadcast(event: 'room_join_result', callback: (payload) {
      if (hosting || !_onlineMode) return;
      final message = unwrapRealtimeBroadcastPayload(payload);
      if (message['clientId']?.toString() != _onlineClientId) return;
      final accepted = message['accepted'] == true;
      if (accepted) {
        _joined = true;
        status.value = 'Terhubung online • mengikuti host';
      } else {
        status.value = message['message']?.toString() ?? 'Kode kamar ditolak host.';
      }
      final completer = _onlineJoinCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(accepted);
      }
    });

    channel.onBroadcast(event: 'room_heartbeat', callback: (payload) {
      if (!hosting || !_onlineMode || !_hosting) return;
      final message = unwrapRealtimeBroadcastPayload(payload);
      final clientId = message['clientId']?.toString() ?? '';
      if (clientId.isEmpty || !_onlinePeers.contains(clientId)) return;
      if (message['code']?.toString() != roomCode.value) return;
      _onlinePeerLastSeen[clientId] = DateTime.now();
    });

    channel.onBroadcast(event: 'room_leave', callback: (payload) {
      if (!hosting || !_onlineMode || !_hosting) return;
      final message = unwrapRealtimeBroadcastPayload(payload);
      final clientId = message['clientId']?.toString() ?? '';
      if (_onlinePeers.remove(clientId)) {
        _onlinePeerLastSeen.remove(clientId);
        _publishOnlinePeerCount();
      }
    });

    channel.onBroadcast(event: 'room_closed', callback: (payload) {
      if (hosting || !_onlineMode || !_joined) return;
      final message = unwrapRealtimeBroadcastPayload(payload);
      if (message['code']?.toString() != roomCode.value) return;
      _joined = false;
      _onlineHeartbeatTimer?.cancel();
      _onlineHeartbeatTimer = null;
      status.value = 'Host menutup kamar';
      if (!_messages.isClosed) _messages.add(<String, dynamic>{'type': 'room_closed'});
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
        // If Supabase automatically rejoined the WebSocket after a transient
        // loss, tell the host this guest is back. Initial join is still handled
        // by _joinOnlineRoom, because _onlineJoinAccepted remains false here.
        if (_onlineMode && !_hosting && _onlineJoinAccepted && !_disposed) {
          unawaited(_sendOnline('room_join', <String, dynamic>{
            'clientId': _onlineClientId,
            'code': roomCode.value,
          }).catchError((Object joinError) {
            if (!_disposed) status.value = 'Gagal menyambung ulang: $joinError';
          }));
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
    if (!_onlineMode || channel == null) return;
    final response = await channel.sendBroadcastMessage(
      event: event,
      payload: payload,
    );
    if (response.name != 'ok') {
      throw StateError('Pesan realtime gagal dikirim (${response.name}).');
    }
  }

  void _sendOnlineUnawaited(String event, Map<String, dynamic> payload) {
    unawaited(_sendOnline(event, payload).catchError((Object error) {
      if (!_disposed) status.value = 'Gangguan koneksi realtime: $error';
    }));
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
    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    final stale = _onlinePeerLastSeen.entries
        .where((entry) => entry.value.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final clientId in stale) {
      _onlinePeerLastSeen.remove(clientId);
      _onlinePeers.remove(clientId);
    }
    if (stale.isNotEmpty) _publishOnlinePeerCount();
  }

  Future<void> _startDiscoveryResponder() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      _discoverySocket = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          final packet = datagram!;
          try {
            final decoded = jsonDecode(utf8.decode(packet.data));
            if (decoded is! Map || decoded['type'] != 'probe' || !_hosting) continue;
            final response = utf8.encode(jsonEncode(<String, dynamic>{
              'type': 'room',
              'name': 'Kamar MusikKu',
              'port': defaultPort,
            }));
            socket.send(response, packet.address, packet.port);
          } catch (_) {
            // Discovery is best-effort. Ignore unrelated or malformed packets.
          }
        }
      });
    } catch (_) {
      // Some access points block broadcast discovery; the manual address path
      // remains available and hosting itself must still work.
    }
  }

  Future<ListeningRoomEndpoint?> discoverRoom({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      status.value = 'Mencari kamar di jaringan Wi-Fi…';
      final scanner = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket = scanner;
      scanner.broadcastEnabled = true;
      final completer = Completer<ListeningRoomEndpoint?>();
      subscription = scanner.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = scanner.receive()) != null) {
          final packet = datagram!;
          try {
            final decoded = jsonDecode(utf8.decode(packet.data));
            if (decoded is! Map || decoded['type'] != 'room') continue;
            final port = (decoded['port'] as num?)?.toInt() ?? defaultPort;
            if (!completer.isCompleted) {
              completer.complete(ListeningRoomEndpoint(
                address: '${packet.address.address}:$port',
                name: decoded['name']?.toString() ?? 'Kamar MusikKu',
              ));
            }
          } catch (_) {
            // Ignore non-room packets.
          }
        }
      });
      scanner.send(
        utf8.encode(jsonEncode(<String, dynamic>{'type': 'probe'})),
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
      return await completer.future.timeout(timeout, onTimeout: () => null);
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }

  void _handleIncomingPeer(Socket socket) {
    _listenToSocket(socket, onHost: true);
  }

  void _listenToSocket(Socket socket, {required bool onHost}) {
    final subscription = socket
        // Socket emits Uint8List chunks; cast to List<int> so Utf8Decoder's
        // transformer input type matches on strict Dart SDK versions.
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.isEmpty) return;
        try {
          final decoded = jsonDecode(line);
          if (decoded is! Map) return;
          final message = Map<String, dynamic>.from(decoded);
          if (onHost) {
            if (message['type'] == 'join') {
              if (message['code']?.toString() != roomCode.value) {
                _write(socket, <String, dynamic>{
                  'type': 'rejected',
                  'message': 'Kode kamar salah. Masukkan kode 8 digit dari host.',
                });
                unawaited(() async {
                  try {
                    await socket.flush();
                    await socket.close();
                  } catch (_) {
                    socket.destroy();
                  }
                }());
                return;
              }
              _peers.add(socket);
              peerCount.value = _peers.length;
              status.value = _peers.isEmpty
                  ? 'Kamar aktif • menunggu teman'
                  : '${_peers.length} perangkat tersambung';
              _write(socket, <String, dynamic>{'type': 'ready'});
            }
          } else {
            if (message['type'] == 'ready') {
              status.value = 'Terhubung • mengikuti pemutaran host';
            } else if (message['type'] == 'rejected') {
              _joined = false;
              if (identical(_client, socket)) _client = null;
              _subscriptions.remove(socket);
              status.value = message['message']?.toString() ?? 'Kode kamar ditolak host.';
              socket.destroy();
              return;
            }
            if (!_messages.isClosed) _messages.add(message);
          }
        } on FormatException {
          // Abaikan satu paket rusak; koneksi tetap bisa menerima paket berikutnya.
        } catch (_) {
          // Pesan dari perangkat lain tidak boleh menjatuhkan sesi.
        }
      },
      onError: (Object _) => _dropSocket(socket, onHost: onHost),
      onDone: () => _dropSocket(socket, onHost: onHost),
      cancelOnError: true,
    );
    _subscriptions[socket] = subscription;
  }

  void _dropSocket(Socket socket, {required bool onHost}) {
    _subscriptions.remove(socket);
    if (onHost) {
      final removed = _peers.remove(socket);
      if (removed && !_disposed) {
        peerCount.value = _peers.length;
        status.value = _peers.isEmpty
            ? 'Kamar aktif • menunggu teman'
            : '${_peers.length} perangkat tersambung';
      }
    } else if (identical(_client, socket)) {
      _client = null;
      _joined = false;
      if (!_disposed) status.value = 'Koneksi terputus';
    }
    socket.destroy();
  }

  void broadcastState(Map<String, dynamic> state) {
    if (!_hosting) return;
    final payload = <String, dynamic>{'type': 'state', ...state};
    if (_onlineMode) {
      _pruneOnlinePeers();
      _sendOnlineUnawaited('music_state', payload);
      return;
    }
    for (final peer in _peers.toList(growable: false)) {
      try {
        _write(peer, payload);
      } catch (_) {
        _dropSocket(peer, onHost: true);
      }
    }
  }

  void _write(Socket socket, Map<String, dynamic> message) {
    socket.add(utf8.encode('${jsonEncode(message)}\n'));
  }

  bool _isPrivateIpv4(String address) {
    if (address.startsWith('10.') || address.startsWith('192.168.')) return true;
    final parts = address.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]) ?? 0;
      return second >= 16 && second <= 31;
    }
    return false;
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
          });
        } else if (wasOnlineGuest) {
          await _sendOnline('room_leave', <String, dynamic>{
            'clientId': _onlineClientId,
          });
        }
      } catch (_) {
        // A closing/disconnected channel must not block local cleanup.
      }
    }
    _onlineHeartbeatTimer?.cancel();
    _onlineHeartbeatTimer = null;
    _onlineJoinCompleter = null;
    _onlineJoinAccepted = false;
    _onlineMode = false;
    _onlineClientId = '';
    _onlinePeers.clear();
    _onlinePeerLastSeen.clear();
    _onlineChannel = null;
    if (remoteChannel != null) {
      try {
        await _onlineClient?.removeChannel(remoteChannel);
      } catch (_) {}
    }

    _hosting = false;
    _joined = false;
    final server = _server;
    _server = null;
    if (server != null) {
      try {
        await server.close();
      } catch (_) {}
    }
    _discoverySocket?.close();
    _discoverySocket = null;

    final sockets = <Socket>{..._peers, ..._subscriptions.keys};
    if (_client != null) sockets.add(_client!);
    final subscriptions = _subscriptions.values.toList(growable: false);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }

    _peers.clear();
    _client = null;
    for (final socket in sockets) {
      socket.destroy();
    }
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
    peerCount.dispose();
    inviteAddress.dispose();
    roomCode.dispose();
  }
}

class ListeningRoomEndpoint {
  const ListeningRoomEndpoint({required this.address, required this.name});

  final String address;
  final String name;
}
