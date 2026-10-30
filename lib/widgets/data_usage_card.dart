import 'dart:async';

import 'package:flutter/material.dart';

import '../services/data_usage_service.dart';

/// Live, app-UID traffic counter. Includes both received and sent bytes over
/// Wi-Fi and mobile networks; it is not the carrier's mobile-data-only meter.
class DataUsageCard extends StatefulWidget {
  const DataUsageCard({super.key});

  @override
  State<DataUsageCard> createState() => _DataUsageCardState();
}

class _DataUsageCardState extends State<DataUsageCard> {
  DataUsageSnapshot? _snapshot;
  bool _loading = true;
  bool _refreshing = false;
  bool _failed = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await DataUsageService.read();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final snapshot = _snapshot;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.58)),
      ),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.data_usage_rounded, color: scheme.primary, size: 21),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Konsumsi data',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Perbarui konsumsi data',
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_refresh()),
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (_failed || snapshot == null)
            Text(
              'Data penggunaan belum bisa dibaca. Coba tekan perbarui.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            )
          else if (!snapshot.supported)
            Text(
              'Penghitung trafik aplikasi tidak tersedia di perangkat ini.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            )
          else ...[
            Text(
              DataUsageService.formatBytes(snapshot.todayTotalBytes),
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 27,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
            Text(
              'Total digunakan hari ini',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TrafficValue(
                    icon: Icons.south_rounded,
                    color: scheme.primary,
                    label: 'Diterima',
                    value: DataUsageService.formatBytes(snapshot.todayRxBytes),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TrafficValue(
                    icon: Icons.north_rounded,
                    color: scheme.secondary,
                    label: 'Dikirim',
                    value: DataUsageService.formatBytes(snapshot.todayTxBytes),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total tercatat',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                ),
                Text(
                  DataUsageService.formatBytes(snapshot.totalBytes),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Perkiraan trafik MusikKu melalui Wi-Fi + seluler, termasuk streaming, pencarian, dan cover. Bukan penghitung kuota seluler operator.',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficValue extends StatelessWidget {
  const _TrafficValue({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }
}
