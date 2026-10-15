class ListeningStat {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final int playCount;
  final int skipCount;
  final double listenedSeconds;
  final DateTime? lastPlayedAt;

  const ListeningStat({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.playCount,
    this.skipCount = 0,
    required this.listenedSeconds,
    this.lastPlayedAt,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'playCount': playCount,
        'skipCount': skipCount,
        'listenedSeconds': listenedSeconds,
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
      };

  factory ListeningStat.fromJson(Map<String, dynamic> json) {
    return ListeningStat(
      videoId: json['videoId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Tanpa judul',
      artist: json['artist']?.toString() ?? 'Unknown',
      thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
      skipCount: (json['skipCount'] as num?)?.toInt() ?? 0,
      listenedSeconds:
          (json['listenedSeconds'] as num?)?.toDouble() ?? 0.0,
      lastPlayedAt: DateTime.tryParse(json['lastPlayedAt']?.toString() ?? ''),
    );
  }
}
