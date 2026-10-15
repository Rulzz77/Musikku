class YoutubeSearchResult {
  final String videoId;
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  final int? viewCount;
  final DateTime? publishedAt;

  /// 'youtube' atau 'local'. Local track tetap memakai model yang sama supaya
  /// Queue/Favorite/History/Playlist dan UI bisa berbagi satu tipe.
  final String sourceType;

  /// Untuk lagu lokal, URI MediaStore/file yang diputar native.
  final String mediaUri;

  /// Durasi sumber lokal dalam detik. YouTube tetap boleh null.
  final double? durationSeconds;

  /// Metadata tambahan lokal.
  final String album;
  final String localMediaId;

  /// Status siaran langsung: '' (video biasa), 'live' (sedang live),
  /// 'upcoming' (dijadwalkan), 'recording' (rekaman live yang sudah selesai).
  final String liveStatus;

  /// Jumlah penonton live saat ini (hanya untuk liveStatus == 'live').
  final int? concurrentViewers;

  /// Waktu mulai live (nyata kalau sudah mulai, jadwal kalau belum).
  final DateTime? liveStartTime;

  /// ID channel pemilik video (untuk foto profil dan membuka channel).
  final String channelId;

  bool get isLive => liveStatus == 'live';
  bool get isUpcoming => liveStatus == 'upcoming';
  bool get isLiveRecording => liveStatus == 'recording';

  bool get isLocal =>
      sourceType == 'local' || videoId.startsWith('local:');

  /// URL cover YouTube. Lagu lokal menggunakan artwork native melalui
  /// UnifiedArtwork widget dan tidak mengandalkan Image.network.
  String get coverUrl {
    final direct = thumbnailUrl.trim();

    if (direct.isNotEmpty) {
      return direct;
    }

    if (isLocal) {
      return '';
    }

    if (videoId.isNotEmpty) {
      return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }

    return '';
  }

  const YoutubeSearchResult({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    this.viewCount,
    this.publishedAt,
    this.sourceType = 'youtube',
    this.mediaUri = '',
    this.durationSeconds,
    this.album = '',
    this.localMediaId = '',
    this.liveStatus = '',
    this.concurrentViewers,
    this.liveStartTime,
    this.channelId = '',
  });

  YoutubeSearchResult copyWith({
    String? videoId,
    String? title,
    String? channelTitle,
    String? thumbnailUrl,
    int? viewCount,
    DateTime? publishedAt,
    String? sourceType,
    String? mediaUri,
    double? durationSeconds,
    String? album,
    String? localMediaId,
    String? liveStatus,
    int? concurrentViewers,
    DateTime? liveStartTime,
    String? channelId,
  }) {
    return YoutubeSearchResult(
      videoId: videoId ?? this.videoId,
      title: title ?? this.title,
      channelTitle: channelTitle ?? this.channelTitle,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      viewCount: viewCount ?? this.viewCount,
      publishedAt: publishedAt ?? this.publishedAt,
      sourceType: sourceType ?? this.sourceType,
      mediaUri: mediaUri ?? this.mediaUri,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      album: album ?? this.album,
      localMediaId: localMediaId ?? this.localMediaId,
      liveStatus: liveStatus ?? this.liveStatus,
      concurrentViewers: concurrentViewers ?? this.concurrentViewers,
      liveStartTime: liveStartTime ?? this.liveStartTime,
      channelId: channelId ?? this.channelId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'videoId': videoId,
      'title': title,
      'channelTitle': channelTitle,
      'thumbnailUrl': thumbnailUrl,
      'viewCount': viewCount,
      'publishedAt': publishedAt?.toIso8601String(),
      'sourceType': sourceType,
      'mediaUri': mediaUri,
      'durationSeconds': durationSeconds,
      'album': album,
      'localMediaId': localMediaId,
      'liveStatus': liveStatus,
      'concurrentViewers': concurrentViewers,
      'liveStartTime': liveStartTime?.toIso8601String(),
      'channelId': channelId,
    };
  }

  factory YoutubeSearchResult.fromJson(Map<String, dynamic> json) {
    final source = json['sourceType']?.toString() ?? 'youtube';
    final videoId = json['videoId']?.toString() ?? '';

    return YoutubeSearchResult(
      videoId: videoId,
      title: json['title']?.toString() ?? 'Tanpa judul',
      channelTitle: json['channelTitle']?.toString() ?? 'Unknown',
      thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
      viewCount: json['viewCount'] is num ? (json['viewCount'] as num).toInt() : null,
      publishedAt: DateTime.tryParse(json['publishedAt']?.toString() ?? ''),
      sourceType: source,
      mediaUri: json['mediaUri']?.toString() ?? '',
      durationSeconds: json['durationSeconds'] is num
          ? (json['durationSeconds'] as num).toDouble()
          : null,
      album: json['album']?.toString() ?? '',
      localMediaId: json['localMediaId']?.toString() ??
          (source == 'local' && videoId.startsWith('local:')
              ? videoId.substring('local:'.length)
              : ''),
      liveStatus: json['liveStatus']?.toString() ?? '',
      concurrentViewers: json['concurrentViewers'] is num
          ? (json['concurrentViewers'] as num).toInt()
          : null,
      liveStartTime: DateTime.tryParse(json['liveStartTime']?.toString() ?? ''),
      channelId: json['channelId']?.toString() ?? '',
    );
  }

  /// Mengubah resource `videos` dari YouTube Data API (part snippet,
  /// statistics, contentDetails, liveStreamingDetails) menjadi model ini.
  /// Mengembalikan null kalau resource tidak punya id video.
  static YoutubeSearchResult? fromVideoResource(
    Map<String, dynamic> item, {
    String Function(dynamic thumbnails)? pickThumbnail,
    String Function(String text)? decode,
  }) {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final snippet = item['snippet'] is Map
        ? Map<String, dynamic>.from(item['snippet'] as Map)
        : const <String, dynamic>{};
    final stats = item['statistics'] is Map
        ? Map<String, dynamic>.from(item['statistics'] as Map)
        : const <String, dynamic>{};
    final content = item['contentDetails'] is Map
        ? Map<String, dynamic>.from(item['contentDetails'] as Map)
        : const <String, dynamic>{};
    final liveDetails = item['liveStreamingDetails'] is Map
        ? Map<String, dynamic>.from(item['liveStreamingDetails'] as Map)
        : const <String, dynamic>{};

    final broadcast = snippet['liveBroadcastContent']?.toString() ?? 'none';
    var status = '';
    if (broadcast == 'live') {
      status = 'live';
    } else if (broadcast == 'upcoming') {
      status = 'upcoming';
    } else if (liveDetails['actualStartTime'] != null) {
      // Pernah live dan sudah selesai: ini rekaman live.
      status = 'recording';
    }

    final startRaw = status == 'upcoming'
        ? liveDetails['scheduledStartTime']
        : liveDetails['actualStartTime'];

    String thumb(dynamic raw) {
      if (pickThumbnail != null) return pickThumbnail(raw);
      if (raw is! Map) return '';
      for (final key in const ['maxres', 'high', 'standard', 'medium', 'default']) {
        final entry = raw[key];
        if (entry is Map) {
          final url = entry['url']?.toString() ?? '';
          if (url.isNotEmpty) return url;
        }
      }
      return '';
    }

    String text(String value) => decode == null ? value : decode(value);

    final duration = parseIsoDuration(content['duration']?.toString());

    return YoutubeSearchResult(
      videoId: id,
      title: text(snippet['title']?.toString() ?? 'Tanpa judul'),
      channelTitle: text(snippet['channelTitle']?.toString() ?? 'Channel'),
      thumbnailUrl: thumb(snippet['thumbnails']),
      viewCount: int.tryParse(stats['viewCount']?.toString() ?? ''),
      publishedAt: DateTime.tryParse(snippet['publishedAt']?.toString() ?? ''),
      durationSeconds: (status == 'live' || status == 'upcoming') ? null : duration,
      liveStatus: status,
      concurrentViewers: int.tryParse(liveDetails['concurrentViewers']?.toString() ?? ''),
      liveStartTime: DateTime.tryParse(startRaw?.toString() ?? ''),
      channelId: snippet['channelId']?.toString() ?? '',
    );
  }

  /// "PT1H2M3S" -> 3723 detik. null kalau tidak valid.
  static double? parseIsoDuration(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final match = RegExp(r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(iso);
    if (match == null) return null;
    int part(int i) => int.tryParse(match.group(i) ?? '') ?? 0;
    return (part(1) * 86400 + part(2) * 3600 + part(3) * 60 + part(4)).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is YoutubeSearchResult && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}


class YoutubeChannelSearchResult {
  final String channelId;
  final String title;
  final String description;
  final String thumbnailUrl;

  const YoutubeChannelSearchResult({
    required this.channelId,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
  });
}
