import 'dart:convert';

import 'package:http/http.dart' as http;

/// Satu pesan live chat.
class LiveChatMessage {
  final String id;
  final String author;
  final String avatarUrl;
  final String text;

  /// Nominal Super Chat (mis. "Rp50.000"); kosong untuk chat biasa.
  final String amount;
  final bool isOwner;
  final bool isModerator;
  final bool isMember;

  /// Posisi pesan di video (ms). Hanya dipakai untuk chat ulang (replay).
  final int offsetMs;

  /// Waktu pesan dari server (kalau tersedia).
  final DateTime? sentAt;

  const LiveChatMessage({
    required this.id,
    required this.author,
    required this.avatarUrl,
    required this.text,
    this.amount = '',
    this.isOwner = false,
    this.isModerator = false,
    this.isMember = false,
    this.offsetMs = 0,
    this.sentAt,
  });
}

class LiveChatBatch {
  final List<LiveChatMessage> messages;
  final String? nextContinuation;
  final int pollMillis;

  /// true bila permintaan gagal (jaringan/server) -- BUKAN berarti siaran
  /// berakhir. Pemanggil sebaiknya mencoba lagi, bukan berhenti.
  final bool failed;

  const LiveChatBatch({
    required this.messages,
    required this.nextContinuation,
    required this.pollMillis,
    this.failed = false,
  });
}

/// Hasil membuka chat: token awal + apakah ini chat ulang (replay).
class LiveChatSession {
  final String continuation;
  final bool isReplay;

  const LiveChatSession(this.continuation, {required this.isReplay});
}

class LiveChatOpenResult {
  final LiveChatSession? session;

  /// true bila gagal karena jaringan/server (bukan "video memang tak punya chat").
  final bool failed;

  const LiveChatOpenResult({this.session, this.failed = false});
}

/// Live chat lewat endpoint InnerTube yang sama dengan situs YouTube.
/// Tidak butuh login/OAuth/API key pribadi, dan hanya aktif untuk siaran
/// langsung (bukan replay).
class YoutubeLiveChatService {
  static const _apiKey = String.fromEnvironment('YOUTUBE_API_KEY');
  static const _base = 'https://www.youtube.com/youtubei/v1';
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  static const Map<String, dynamic> _context = {
    'client': {
      'clientName': 'WEB',
      'clientVersion': '2.20250101.01.00',
      'hl': 'id',
      'gl': 'ID',
    },
  };

  final http.Client _client = http.Client();

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_base/$path?key=$_apiKey&prettyPrint=false'),
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent': _userAgent,
              'Origin': 'https://www.youtube.com',
              'X-Youtube-Client-Name': '1',
              'X-Youtube-Client-Version': '2.20250101.01.00',
            },
            body: jsonEncode({'context': _context, ...body}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// Membuka chat sebuah video. Mencoba ulang bila jaringan/server gagal.
  /// - session != null  : ada chat (live atau chat ulang/replay)
  /// - session == null && !failed : video ini memang tidak punya chat
  /// - session == null && failed  : gagal terhubung (boleh dicoba lagi nanti)
  Future<LiveChatOpenResult> open(String videoId) async {
    if (videoId.trim().isEmpty) return const LiveChatOpenResult();
    for (var attempt = 0; attempt < 3; attempt++) {
      final data = await _post('next', {'videoId': videoId});
      if (data == null) {
        await Future<void>.delayed(Duration(milliseconds: 700 * (attempt + 1)));
        continue;
      }
      final renderer = _findKey(data, 'liveChatRenderer');
      if (renderer is! Map) return const LiveChatOpenResult();
      final isReplay = renderer['isReplay'] == true;
      final token = _initialToken(renderer);
      if (token == null) return const LiveChatOpenResult();
      return LiveChatOpenResult(
        session: LiveChatSession(token, isReplay: isReplay),
      );
    }
    return const LiveChatOpenResult(failed: true);
  }

  /// Token awal dari liveChatRenderer. Untuk chat ulang, bila daftar
  /// `continuations` kosong, ambil dari menu "Chat teratas / Chat langsung".
  String? _initialToken(Map renderer) {
    final continuations = renderer['continuations'];
    if (continuations is List) {
      for (final item in continuations) {
        final token = _continuationToken(item);
        if (token != null) return token;
      }
    }
    final header = renderer['header'];
    final headerRenderer =
        header is Map ? header['liveChatHeaderRenderer'] : null;
    final selector =
        headerRenderer is Map ? headerRenderer['viewSelector'] : null;
    final menu = selector is Map ? selector['sortFilterSubMenuRenderer'] : null;
    final items = menu is Map ? menu['subMenuItems'] : null;
    if (items is List) {
      for (final item in items.reversed) {
        if (item is! Map) continue;
        final cont = item['continuation'];
        final token = _continuationToken(cont);
        if (token != null) return token;
      }
    }
    return null;
  }

  /// Backward-compatible: hanya token untuk chat live (bukan replay).
  Future<String?> openLiveChat(String videoId) async {
    final result = await open(videoId);
    final session = result.session;
    if (session == null || session.isReplay) return null;
    return session.continuation;
  }

  Future<LiveChatBatch> poll(String continuation) async {
    final data = await _post('live_chat/get_live_chat', {
      'continuation': continuation,
    });
    return _parseBatch(data, replay: false);
  }

  /// Chat ulang. [offsetMs] = posisi putar video saat ini.
  Future<LiveChatBatch> pollReplay(String continuation, int offsetMs) async {
    final data = await _post('live_chat/get_live_chat_replay', {
      'continuation': continuation,
      'currentPlayerState': {'playerOffsetMs': offsetMs.toString()},
    });
    return _parseBatch(data, replay: true);
  }

  LiveChatBatch _parseBatch(Map<String, dynamic>? data, {required bool replay}) {
    final root = data?['continuationContents'];
    final live = root is Map ? root['liveChatContinuation'] : null;
    if (live is! Map) {
      // Gagal/tidak ada isi: JANGAN dianggap siaran berakhir.
      return const LiveChatBatch(
        messages: [],
        nextContinuation: null,
        pollMillis: 5000,
        failed: true,
      );
    }

    final messages = <LiveChatMessage>[];
    final actions = live['actions'];
    if (actions is List) {
      for (final action in actions) {
        if (action is! Map) continue;
        if (replay) {
          final wrapper = action['replayChatItemAction'];
          if (wrapper is! Map) continue;
          final offset =
              int.tryParse(wrapper['videoOffsetTimeMsec']?.toString() ?? '') ??
                  0;
          final inner = wrapper['actions'];
          if (inner is! List) continue;
          for (final sub in inner) {
            if (sub is! Map) continue;
            final add = sub['addChatItemAction'];
            final item = add is Map ? add['item'] : null;
            if (item is! Map) continue;
            final parsed = _parseItem(item, offsetMs: offset);
            if (parsed != null) messages.add(parsed);
          }
        } else {
          final add = action['addChatItemAction'];
          final item = add is Map ? add['item'] : null;
          if (item is! Map) continue;
          final parsed = _parseItem(item);
          if (parsed != null) messages.add(parsed);
        }
      }
    }

    String? next;
    var poll = replay ? 1000 : 5000;
    final continuations = live['continuations'];
    if (continuations is List) {
      for (final item in continuations) {
        final token = _continuationToken(item);
        if (token == null) continue;
        next = token;
        if (item is Map) {
          for (final value in item.values) {
            if (value is Map && value['timeoutMs'] is num) {
              poll = (value['timeoutMs'] as num).toInt();
            }
          }
        }
        break;
      }
    }

    return LiveChatBatch(
      messages: messages,
      nextContinuation: next,
      pollMillis: poll.clamp(1000, 15000),
    );
  }

  void close() => _client.close();

  // ---------------------------------------------------------------- parsing

  String? _continuationToken(dynamic item) {
    if (item is! Map) return null;
    for (final key in const [
      'invalidationContinuationData',
      'timedContinuationData',
      'reloadContinuationData',
      'liveChatReplayContinuationData',
      'playerSeekContinuationData',
    ]) {
      final inner = item[key];
      if (inner is Map) {
        final token = inner['continuation']?.toString() ?? '';
        if (token.isNotEmpty) return token;
      }
    }
    return null;
  }

  LiveChatMessage? _parseItem(Map item, {int offsetMs = 0}) {
    Map? renderer;
    var amount = '';
    if (item['liveChatTextMessageRenderer'] is Map) {
      renderer = item['liveChatTextMessageRenderer'] as Map;
    } else if (item['liveChatPaidMessageRenderer'] is Map) {
      renderer = item['liveChatPaidMessageRenderer'] as Map;
      amount = _runsToText(renderer['purchaseAmountText']);
    } else if (item['liveChatPaidStickerRenderer'] is Map) {
      renderer = item['liveChatPaidStickerRenderer'] as Map;
      amount = _runsToText(renderer['purchaseAmountText']);
    }
    if (renderer == null) return null;

    final id = renderer['id']?.toString() ?? '';
    if (id.isEmpty) return null;

    var isOwner = false;
    var isModerator = false;
    var isMember = false;
    final badges = renderer['authorBadges'];
    if (badges is List) {
      for (final badge in badges) {
        final r = badge is Map ? badge['liveChatAuthorBadgeRenderer'] : null;
        if (r is! Map) continue;
        final icon = r['icon'];
        final type = icon is Map ? icon['iconType']?.toString() : null;
        if (type == 'OWNER') isOwner = true;
        if (type == 'MODERATOR') isModerator = true;
        if (type == null && r['customThumbnail'] != null) isMember = true;
      }
    }

    var avatar = '';
    final photo = renderer['authorPhoto'];
    final thumbs = photo is Map ? photo['thumbnails'] : null;
    if (thumbs is List && thumbs.isNotEmpty && thumbs.first is Map) {
      avatar = (thumbs.first as Map)['url']?.toString() ?? '';
    }

    final text = _runsToText(renderer['message']);
    if (text.isEmpty && amount.isEmpty) return null;

    final timestampUsec = int.tryParse(renderer['timestampUsec']?.toString() ?? '');
    final sentAt = timestampUsec == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(timestampUsec, isUtc: true);

    return LiveChatMessage(
      id: id,
      author: _runsToText(renderer['authorName']).ifEmpty('Pengguna'),
      avatarUrl: avatar,
      text: text,
      amount: amount,
      isOwner: isOwner,
      isModerator: isModerator,
      isMember: isMember,
      offsetMs: offsetMs,
      sentAt: sentAt,
    );
  }

  String _runsToText(dynamic node) {
    if (node is! Map) return '';
    final simple = node['simpleText'];
    if (simple != null) return simple.toString();
    final runs = node['runs'];
    if (runs is! List) return '';
    final buffer = StringBuffer();
    for (final run in runs) {
      if (run is! Map) continue;
      if (run['text'] != null) {
        buffer.write(run['text']);
      } else if (run['emoji'] is Map) {
        final emoji = run['emoji'] as Map;
        final id = emoji['emojiId']?.toString() ?? '';
        // Emoji unicode asli: emojiId berisi karakternya. Emoji custom
        // channel memakai ID panjang, jadi pakai nama pendeknya.
        if (id.isNotEmpty && id.runes.length <= 4 && !id.contains('/')) {
          buffer.write(id);
        } else {
          final shortcuts = emoji['shortcuts'];
          if (shortcuts is List && shortcuts.isNotEmpty) {
            buffer.write(shortcuts.first);
          }
        }
      }
    }
    return buffer.toString();
  }

  dynamic _findKey(dynamic node, String key, [int depth = 0]) {
    if (depth > 24) return null;
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final value in node.values) {
        final found = _findKey(value, key, depth + 1);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findKey(value, key, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
