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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(17, 17, 17, 15),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(22),
          topRight: Radius.circular(7),
          bottomRight: Radius.circular(22),
          bottomLeft: Radius.circular(22),
        ),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.network_check_rounded, color: scheme.onPrimaryContainer, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NETWORK MONITOR', style: TextStyle(color: scheme.primary, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    const SizedBox(height: 3),
                    Text('Penggunaan data', style: TextStyle(color: scheme.onSurface, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Perbarui konsumsi data',
                onPressed: _refreshing ? null : () => unawaited(_refresh()),
                style: IconButton.styleFrom(backgroundColor: scheme.surfaceContainerHighest),
                icon: _refreshing
                    ? SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary))
                    : const Icon(Icons.refresh_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: LinearProgressIndicator(minHeight: 3))
          else if (_failed || snapshot == null)
            _DataNotice(icon: Icons.cloud_off_rounded, message: 'Data penggunaan belum bisa dibaca. Coba perbarui kembali.')
          else if (!snapshot.supported)
            _DataNotice(icon: Icons.info_outline_rounded, message: 'Penghitung trafik aplikasi tidak tersedia di perangkat ini.')
          else ...[
            Text('TOTAL HARI INI', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
            const SizedBox(height: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                DataUsageService.formatBytes(snapshot.todayTotalBytes),
                key: ValueKey<int>(snapshot.todayTotalBytes),
                style: TextStyle(color: scheme.onSurface, fontSize: 34, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -1.3),
              ),
            ),
            const SizedBox(height: 15),
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
                const SizedBox(width: 9),
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)))),
              child: Row(
                children: [
                  Expanded(child: Text('Akumulasi sejak pencatatan', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5))),
                  Text(DataUsageService.formatBytes(snapshot.totalBytes), style: TextStyle(color: scheme.onSurface, fontSize: 12, fontWeight: FontWeight.w900)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Perkiraan trafik MusikKu melalui Wi-Fi dan seluler. Ini bukan penghitung kuota dari operator.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10, height: 1.35),
          ),
        ],
      ),
    );
  }

}

class _DataNotice extends StatelessWidget {
  const _DataNotice({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: scheme.primary, size: 21),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4))),
      ],
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
