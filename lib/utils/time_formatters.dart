String formatRelativeTime(DateTime? value) {
  if (value == null) return '';

  final local = value.toLocal();
  final now = DateTime.now();
  var delta = now.difference(local);

  if (delta.isNegative) {
    delta = Duration.zero;
  }

  if (delta.inSeconds < 45) return 'baru saja';
  if (delta.inMinutes < 60) return '${delta.inMinutes} mnt lalu';
  if (delta.inHours < 24) return '${delta.inHours} jam lalu';
  if (delta.inDays < 7) return '${delta.inDays} hari lalu';
  if (delta.inDays < 30) return '${delta.inDays ~/ 7} minggu lalu';
  if (delta.inDays < 365) return '${delta.inDays ~/ 30} bulan lalu';
  return '${delta.inDays ~/ 365} tahun lalu';
}

String formatClockTime(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String formatVideoOffset(int milliseconds) {
  final safe = milliseconds < 0 ? 0 : milliseconds;
  final totalSeconds = safe ~/ 1000;
  final seconds = totalSeconds % 60;
  final totalMinutes = totalSeconds ~/ 60;
  final minutes = totalMinutes % 60;
  final hours = totalMinutes ~/ 60;

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatDateTimeCompact(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  final date = '${local.day.toString().padLeft(2, '0')} ${months[local.month - 1]} ${local.year}';
  return '$date, ${formatClockTime(local)}';
}
