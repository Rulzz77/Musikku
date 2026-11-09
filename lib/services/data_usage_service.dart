import 'package:flutter/services.dart';

/// Ringkasan pemakaian data jaringan aplikasi, dibaca dari sisi native.
class DataUsageSnapshot {
  const DataUsageSnapshot({
    required this.supported,
    required this.todayRxBytes,
    required this.todayTxBytes,
    required this.totalRxBytes,
    required this.totalTxBytes,
    required this.date,
  });

  /// Dipakai ketika platform tidak mengembalikan data.
  const DataUsageSnapshot.unavailable()
      : supported = false,
        todayRxBytes = 0,
        todayTxBytes = 0,
        totalRxBytes = 0,
        totalTxBytes = 0,
        date = '';

  final bool supported;

  /// Byte diterima (Rx) dan dikirim (Tx) pada [date].
  final int todayRxBytes;
  final int todayTxBytes;

  /// Akumulasi sejak pencatatan dimulai.
  final int totalRxBytes;
  final int totalTxBytes;

  final String date;

  int get todayTotalBytes => todayRxBytes + todayTxBytes;
  int get totalBytes => totalRxBytes + totalTxBytes;
}

class DataUsageService {
  DataUsageService._();

  static const MethodChannel _channel = MethodChannel('musikku/data_usage');

  /// Batas atas aman untuk byte yang dibaca dari native.
  static const int _maxBytes = 1 << 62;

  static Future<DataUsageSnapshot> read() async {
    final values = await _channel.invokeMapMethod<String, dynamic>('getStats');
    if (values == null) return const DataUsageSnapshot.unavailable();

    return DataUsageSnapshot(
      supported: values['supported'] == true,
      todayRxBytes: _readBytes(values['todayRxBytes']),
      todayTxBytes: _readBytes(values['todayTxBytes']),
      totalRxBytes: _readBytes(values['totalRxBytes']),
      totalTxBytes: _readBytes(values['totalTxBytes']),
      date: values['date']?.toString() ?? '',
    );
  }

  /// Mengubah nilai dari native menjadi jumlah byte yang tidak negatif.
  /// Nilai non-numerik dianggap 0.
  static int _readBytes(Object? value) => switch (value) {
        int v => v < 0 ? 0 : v,
        num v => v.toInt().clamp(0, _maxBytes).toInt(),
        _ => 0,
      };

  /// Contoh: 512 -> "512 B", 1536 -> "1.5 KB", 250 MB -> "250 MB".
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';

    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }

    final digits = value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unitIndex]}';
  }
}