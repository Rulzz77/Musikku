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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerLow,
            Color.lerp(scheme.surfaceContainerLow, scheme.primaryContainer, 0.22)!,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.065),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -25,
            top: -38,
            child: IgnorePointer(
              child: Icon(
                Icons.wifi_tethering_rounded,
                size: 132,
                color: scheme.primary.withValues(alpha: 0.055),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [scheme.primary, scheme.tertiary],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.data_usage_rounded,
                      color: scheme.onPrimary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NETWORK PULSE',
                          style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1.35,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Jejak penggunaan data',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Perbarui konsumsi data',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(_refresh()),
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 15),
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: Text(
                    DataUsageService.formatBytes(snapshot.todayTotalBytes),
                    key: ValueKey<int>(snapshot.todayTotalBytes),
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                Text(
                  'Total digunakan hari ini',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                ),
                const SizedBox(height: 13),
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
                const Divider(height: 22),
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
              const SizedBox(height: 9),
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
