import 'package:flutter/services.dart';

class DataUsageSnapshot {
  const DataUsageSnapshot({
    required this.supported,
    required this.todayRxBytes,
    required this.todayTxBytes,
    required this.totalRxBytes,
    required this.totalTxBytes,
    required this.date,
  });

  const DataUsageSnapshot.unavailable()
      : supported = false,
        todayRxBytes = 0,
        todayTxBytes = 0,
        totalRxBytes = 0,
        totalTxBytes = 0,
        date = '';

  final bool supported;
  final int todayRxBytes;
  final int todayTxBytes;
  final int totalRxBytes;
  final int totalTxBytes;
  final String date;

  int get todayTotalBytes => todayRxBytes + todayTxBytes;
  int get totalBytes => totalRxBytes + totalTxBytes;
}

class DataUsageService {
  DataUsageService._();

  static const MethodChannel _channel = MethodChannel('musikku/data_usage');

  static Future<DataUsageSnapshot> read() async {
    final values = await _channel.invokeMapMethod<String, dynamic>('getStats');
    if (values == null) return const DataUsageSnapshot.unavailable();

    int readInt(String key) {
      final value = values[key];
      if (value is int) return value < 0 ? 0 : value;
      if (value is num) return value.toInt().clamp(0, 1 << 62).toInt();
      return 0;
    }

    return DataUsageSnapshot(
      supported: values['supported'] == true,
      todayRxBytes: readInt('todayRxBytes'),
      todayTxBytes: readInt('todayTxBytes'),
      totalRxBytes: readInt('totalRxBytes'),
      totalTxBytes: readInt('totalTxBytes'),
      date: values['date']?.toString() ?? '',
    );
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    double value = bytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unitIndex]}';
  }
}
