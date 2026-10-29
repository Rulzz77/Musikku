import 'package:flutter/material.dart';

import '../models/youtube_search_result.dart';

/// Lencana kecil untuk video yang sedang live / dijadwalkan / rekaman live.
/// Tidak menampilkan apa pun untuk video biasa.
class LiveBadge extends StatelessWidget {
  final YoutubeSearchResult video;
  const LiveBadge({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    if (video.liveStatus.isEmpty) return const SizedBox.shrink();

    final String label;
    final Color background;
    final IconData? icon;
    if (video.isLive) {
      label = 'LIVE';
      background = const Color(0xFFE53935);
      icon = Icons.sensors_rounded;
    } else if (video.isUpcoming) {
      label = 'Terjadwal';
      background = const Color(0xCC37474F);
      icon = Icons.schedule_rounded;
    } else {
      label = 'Rekaman live';
      background = const Color(0xCC212121);
      icon = Icons.history_rounded;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: video.isLive
            ? [BoxShadow(color: background.withValues(alpha: 0.22), blurRadius: 8, spreadRadius: 0.3)]
            : const [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// "1,2 rb menonton" untuk live, "Dijadwalkan 5 Okt 19.00" untuk upcoming.
String liveMetaLine(YoutubeSearchResult video, String Function(int) formatCount) {
  if (video.isLive) {
    final viewers = video.concurrentViewers;
    return viewers == null ? 'Sedang live' : '${formatCount(viewers)} menonton';
  }
  if (video.isUpcoming) {
    final start = video.liveStartTime?.toLocal();
    if (start == null) return 'Live dijadwalkan';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final hh = start.hour.toString().padLeft(2, '0');
    final mm = start.minute.toString().padLeft(2, '0');
    return 'Dijadwalkan ${start.day} ${months[start.month - 1]} $hh.$mm';
  }
  return '';
}

/// 754 -> "12:34", 4000 -> "1:06:40".
String formatVideoDuration(double seconds) {
  final total = seconds.round();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final secs = total % 60;
  final ss = secs.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  return '$minutes:$ss';
}

/// Lencana durasi (menit:detik) di pojok thumbnail. Kosong untuk live,
/// jadwal live, atau video yang durasinya belum diketahui.
class DurationBadge extends StatelessWidget {
  final YoutubeSearchResult video;
  const DurationBadge({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    final seconds = video.durationSeconds;
    if (seconds == null || seconds <= 0 || video.isLive || video.isUpcoming) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        formatVideoDuration(seconds),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
