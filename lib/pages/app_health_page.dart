import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart' as app_info;
import '../services/app_health_monitor.dart';
import '../services/native_playback_diagnostics.dart';
import '../widgets/flow_components.dart';
import '../widgets/music_design.dart';

/// Log diagnostik lokal untuk membantu mencari penyebab playback gagal.
/// Data tidak dikirim ke server; pengguna bisa menyalin atau menghapusnya.
class AppHealthPage extends StatefulWidget {
  const AppHealthPage({super.key});

  @override
  State<AppHealthPage> createState() => _AppHealthPageState();
}

class _AppHealthPageState extends State<AppHealthPage> {
  late Future<List<Map<String, dynamic>>> _eventsFuture;
  late Future<AudioOutputSnapshot> _audioOutputsFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _loadMergedEvents();
    _audioOutputsFuture = NativePlaybackDiagnostics.getAudioOutputs();
  }

  Future<List<Map<String, dynamic>>> _loadMergedEvents() async {
    final flutterEvents = await AppHealthMonitor.instance.load();
    final nativeEvents = await NativePlaybackDiagnostics.getNativeHealthEvents();
    final combined = <Map<String, dynamic>>[...flutterEvents, ...nativeEvents];
    DateTime timestamp(Map<String, dynamic> item) =>
        DateTime.tryParse(item['time']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    combined.sort((a, b) => timestamp(b).compareTo(timestamp(a)));
    return combined.take(80).toList(growable: false);
  }

  String get _platformName {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  void _refresh() {
    setState(() {
      _eventsFuture = _loadMergedEvents();
      _audioOutputsFuture = NativePlaybackDiagnostics.getAudioOutputs();
    });
  }

  void _refreshAudioOutputs() {
    setState(() => _audioOutputsFuture = NativePlaybackDiagnostics.getAudioOutputs());
  }

  IconData _eventIcon(Map<String, dynamic> event) {
    final kind = (event['kind']?.toString() ?? '').toLowerCase();
    if (kind.contains('playback') || kind.contains('audio')) {
      return Icons.music_off_rounded;
    }
    return Icons.bug_report_outlined;
  }

  String _formatTime(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    if (parsed == null) return 'Waktu tidak diketahui';
    final local = parsed.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    final sec = local.second.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min:$sec';
  }

  Future<void> _copyReport(List<Map<String, dynamic>> events) async {
    final lines = <String>[
      '${app_info.appName} ${app_info.appVersion} (Build ${app_info.appBuildNumber})',
      'Platform: $_platformName',
      'Log tersimpan: ${events.length}',
      'Dibuat: ${DateTime.now().toIso8601String()}',
      '',
    ];
    for (final event in events) {
      lines.add('[${_formatTime(event['time'])}] ${event['kind'] ?? 'Event'}');
      final error = event['error']?.toString() ?? '';
      if (error.isNotEmpty) lines.add(error);
      final stack = event['stack']?.toString() ?? '';
      if (stack.isNotEmpty) lines.add(stack);
      lines.add('');
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Laporan diagnostik disalin.')),
    );
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus log diagnostik?'),
        content: const Text('Log error yang tersimpan secara lokal akan dihapus. Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await AppHealthMonitor.instance.clear();
    await NativePlaybackDiagnostics.clearNativeHealthEvents();
    if (!mounted) return;
    setState(() => _eventsFuture = Future.value(const <Map<String, dynamic>>[]));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log diagnostik sudah dihapus.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostik MusikKu'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang log',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: MusicBackdrop(child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _eventsFuture,
        builder: (context, snapshot) {
          final events = snapshot.data ?? const <Map<String, dynamic>>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              const FlowPageHero(
                icon: Icons.health_and_safety_rounded,
                eyebrow: 'SYSTEM CENTER',
                title: 'Kesehatan aplikasi',
                subtitle: 'Pantau kondisi pemutar, perangkat audio, dan log masalah yang tersimpan lokal.',
              ),
              const SizedBox(height: 14),
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 1000 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: MediaQuery.sizeOf(context).width >= 1000 ? 2.55 : 2.05,
                children: [
                  _HealthMetricCard(
                    icon: Icons.receipt_long_rounded,
                    label: 'Log tersimpan',
                    value: '${events.length}',
                    scheme: scheme,
                  ),
                  _HealthMetricCard(
                    icon: events.isEmpty ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                    label: 'Ringkasan log',
                    value: events.isEmpty ? 'Tidak ada' : 'Ada catatan',
                    scheme: scheme,
                  ),
                  _HealthMetricCard(
                    icon: Icons.devices_rounded,
                    label: 'Platform',
                    value: _platformName,
                    scheme: scheme,
                  ),
                  _HealthMetricCard(
                    icon: Icons.verified_rounded,
                    label: 'Versi',
                    value: app_info.appVersion,
                    scheme: scheme,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.health_and_safety_rounded, color: scheme.primary, size: 28),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Status aplikasi', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _InfoRow(label: 'Aplikasi', value: '${app_info.appName} ${app_info.appVersion} · Build ${app_info.appBuildNumber}'),
                      _InfoRow(label: 'Platform', value: _platformName),
                      _InfoRow(label: 'Log tersimpan', value: snapshot.connectionState == ConnectionState.waiting ? 'Memuat…' : '${events.length} / 80'),
                      const SizedBox(height: 12),
                      Text(
                        'Log disimpan di perangkat ini. MusikKu tidak mengirim laporan ini ke server. Error dapat mencakup informasi teknis; periksa sebelum membagikannya.',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.speaker_group_rounded, color: scheme.primary, size: 25),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text('Perangkat audio tersedia', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                            ),
                            IconButton(
                              tooltip: 'Periksa perangkat audio lagi',
                              onPressed: _refreshAudioOutputs,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Daftar output yang terdeteksi Android, bukan kepastian perangkat yang sedang membawa suara.',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.35),
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<AudioOutputSnapshot>(
                          future: _audioOutputsFuture,
                          builder: (context, routeSnapshot) {
                            if (routeSnapshot.connectionState == ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            final outputs = routeSnapshot.data;
                            if (outputs == null || !outputs.supported) {
                              return Text(
                                outputs?.error ?? 'Pemeriksaan output audio tidak tersedia pada perangkat ini.',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                              );
                            }
                            if (outputs.devices.isEmpty) {
                              return Text(
                                'Android belum melaporkan perangkat output audio.',
                                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                              );
                            }
                            return Column(
                              children: [
                                for (final device in outputs.devices)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: Icon(
                                      device.type.toLowerCase().contains('bluetooth')
                                          ? Icons.bluetooth_audio_rounded
                                          : device.type.toLowerCase().contains('head')
                                              ? Icons.headphones_rounded
                                              : device.type.toLowerCase().contains('speaker')
                                                  ? Icons.speaker_rounded
                                                  : Icons.audio_file_rounded,
                                      color: scheme.primary,
                                    ),
                                    title: Text(device.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    subtitle: Text(device.type),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(child: Text('Log terbaru', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                  TextButton.icon(
                    onPressed: events.isEmpty ? null : () => _copyReport(events),
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: const Text('Salin laporan'),
                  ),
                ],
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snapshot.hasError)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: const Text('Log gagal dimuat'),
                    subtitle: const Text('Coba muat ulang halaman ini.'),
                    trailing: IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
                  ),
                )
              else if (events.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: scheme.primary, size: 34),
                        const SizedBox(height: 10),
                        const Text('Belum ada error tercatat', style: TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 5),
                        Text('Jika pemutaran gagal, detail yang tersedia akan muncul di sini.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              else
                for (final event in events)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ExpansionTile(
                      leading: Icon(
                        _eventIcon(event),
                        color: scheme.error,
                      ),
                      title: Text(event['kind']?.toString() ?? 'Event', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(_formatTime(event['time']), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SelectableText(
                            event['error']?.toString() ?? 'Tidak ada detail error.',
                            style: const TextStyle(fontSize: 12, height: 1.35),
                          ),
                        ),
                        if ((event['stack']?.toString() ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              event['stack'].toString(),
                              style: TextStyle(fontSize: 10, height: 1.3, color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              if (events.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _clearLogs,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Hapus semua log'),
                ),
              ],
            ],
          );
        },
      )),
    );
  }
}


class _HealthMetricCard extends StatelessWidget {
  const _HealthMetricCard({required this.icon, required this.label, required this.value, required this.scheme});
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.42)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [Icon(icon, color: scheme.primary, size: 18), const SizedBox(width: 7), Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w700))) ]),
          const SizedBox(height: 7),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: scheme.onSurface)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 115, child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
