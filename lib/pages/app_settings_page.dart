import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import 'app_health_page.dart';
import '../services/app_settings.dart';
import '../widgets/app_update_sheet.dart';
import '../widgets/data_usage_card.dart';

/// Pengaturan global aplikasi. Semua opsi terhubung langsung ke controller
/// dan disimpan lewat SharedPreferences.
class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key, required this.settings});

  final AppSettingsController settings;

  String _themeLabel(AppThemeChoice choice) => switch (choice) {
        AppThemeChoice.system => 'Ikuti perangkat',
        AppThemeChoice.dark => 'Gelap',
        AppThemeChoice.amoled => 'AMOLED hitam',
        AppThemeChoice.light => 'Terang',
      };

  IconData _themeIcon(AppThemeChoice choice) => switch (choice) {
        AppThemeChoice.system => Icons.brightness_auto_rounded,
        AppThemeChoice.dark => Icons.dark_mode_rounded,
        AppThemeChoice.amoled => Icons.contrast_rounded,
        AppThemeChoice.light => Icons.light_mode_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primaryContainer.withValues(alpha: 0.88), scheme.surfaceContainerLow, scheme.secondaryContainer.withValues(alpha: 0.38)],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [scheme.primary, scheme.secondary]), borderRadius: BorderRadius.circular(19)),
                      child: Icon(Icons.tune_rounded, size: 29, color: scheme.onPrimary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PUSAT KONTROL', style: TextStyle(color: scheme.primary, fontSize: 9.5, letterSpacing: 1.4, fontWeight: FontWeight.w900)),
                          const SizedBox(height: 5),
                          const Text('Atur MusikKu', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.8)),
                          const SizedBox(height: 5),
                          Text('Semua preferensi dalam satu tempat.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.35)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SettingsPill(icon: Icons.palette_outlined, label: 'Tampilan'),
                    _SettingsPill(icon: Icons.network_check_rounded, label: 'Hemat data'),
                    _SettingsPill(icon: Icons.graphic_eq_rounded, label: 'Pemutar'),
                    _SettingsPill(icon: Icons.shield_outlined, label: 'Kontrol lokal'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SectionLabel(icon: Icons.palette_outlined, title: 'Tampilan'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: ValueListenableBuilder<AppThemeChoice>(
                valueListenable: settings.theme,
                builder: (context, selected, _) => RadioGroup<AppThemeChoice>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) unawaited(settings.setTheme(value));
                  },
                  child: Column(
                    children: [
                      for (final choice in AppThemeChoice.values)
                        RadioListTile<AppThemeChoice>(
                          value: choice,
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            _themeIcon(choice),
                            color: selected == choice
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          title: Text(
                            _themeLabel(choice),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(switch (choice) {
                            AppThemeChoice.system => 'Ikuti mode terang/gelap sistem.',
                            AppThemeChoice.dark => 'Tema gelap dengan aksen MusikKu.',
                            AppThemeChoice.amoled => 'Latar hitam untuk layar OLED.',
                            AppThemeChoice.light => 'Latar terang untuk ruangan cerah.',
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          _SectionLabel(icon: Icons.network_check_rounded, title: 'Data dan jaringan'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ValueListenableBuilder<DataSaverMode>(
                valueListenable: settings.dataSaverMode,
                builder: (context, mode, _) => RadioGroup<DataSaverMode>(
                  groupValue: mode,
                  onChanged: (value) {
                    if (value != null) unawaited(settings.setDataSaverMode(value));
                  },
                  child: Column(
                    children: [
                      for (final choice in DataSaverMode.values)
                        RadioListTile<DataSaverMode>(
                          value: choice,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                          title: Text(
                            choice.label,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(choice.description),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: settings.prefetchWifiOnly,
                  builder: (context, value, _) => SwitchListTile(
                    secondary: const Icon(Icons.wifi_rounded),
                    title: const Text('Prefetch hanya saat Wi-Fi', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Batasi pemuatan data tambahan melalui jaringan seluler.'),
                    value: value,
                    onChanged: (next) => unawaited(settings.setPrefetchWifiOnly(next)),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ValueListenableBuilder<int>(
                  valueListenable: settings.bufferAlertSeconds,
                  builder: (context, seconds, _) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.hourglass_bottom_rounded),
                            const SizedBox(width: 10),
                            const Expanded(child: Text('Peringatan buffer rendah', style: TextStyle(fontWeight: FontWeight.w700))),
                            Text('$seconds dtk', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w900)),
                          ],
                        ),
                        Slider(
                          value: seconds.toDouble(),
                          min: 3,
                          max: 30,
                          divisions: 9,
                          label: '$seconds detik',
                          onChanged: (value) => unawaited(settings.setBufferAlertSeconds(value.round())),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionLabel(icon: Icons.data_usage_rounded, title: 'Konsumsi data'),
          const SizedBox(height: 8),
          const DataUsageCard(),
          const SizedBox(height: 12),
          _SectionLabel(icon: Icons.tune_rounded, title: 'Pemutar musik & tampilan'),
          const SizedBox(height: 8),
          Card(
            child: ValueListenableBuilder<bool>(
              valueListenable: settings.cropVideoBranding,
              builder: (context, value, _) => SwitchListTile(
                secondary: const Icon(Icons.crop_rounded),
                title: const Text('Potong tepi video', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Perbesar video sedikit; sebagian tepi dapat terpotong.'),
                value: value,
                onChanged: (next) => unawaited(settings.setCropVideoBranding(next)),
              ),
            ),
          ),
          const SizedBox(height: 26),
          _SectionLabel(icon: Icons.health_and_safety_outlined, title: 'Diagnostik & pemulihan'),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.monitor_heart_outlined),
              title: const Text('Diagnostik aplikasi', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Lihat error pemutaran, salin laporan, atau hapus log lokal.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AppHealthPage()),
              ),
            ),
          ),
          const SizedBox(height: 26),
          _SectionLabel(icon: Icons.system_update_alt_rounded, title: 'Pembaruan aplikasi'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: settings.autoUpdateEnabled,
                  builder: (context, enabled, _) => SwitchListTile(
                    secondary: const Icon(Icons.update_rounded),
                    title: const Text('Periksa pembaruan otomatis', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Periksa versi baru saat MusikKu dibuka dan beri tahu jika tersedia.'),
                    value: enabled,
                    onChanged: (next) => unawaited(settings.setAutoUpdateEnabled(next)),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: settings.autoUpdateEnabled,
                  builder: (context, autoUpdateEnabled, _) =>
                      ValueListenableBuilder<bool>(
                    valueListenable: settings.autoInstallUpdates,
                    builder: (context, enabled, _) => SwitchListTile(
                      secondary: const Icon(Icons.downloading_rounded),
                      title: const Text('Unduh & buka installer otomatis', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Jika update ditemukan, unduh APK terverifikasi dan buka installer Android. Perlu konfirmasi pemasangan dari Android.'),
                      value: enabled,
                      onChanged: autoUpdateEnabled
                          ? (next) => unawaited(settings.setAutoInstallUpdates(next))
                          : null,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, size: 17, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Pemasangan senyap dan melewati Google Play Protect tidak didukung. Android tetap mengatur izin, pemeriksaan keamanan, dan konfirmasi instalasi.',
                          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          _SectionLabel(icon: Icons.info_outline_rounded, title: 'Tentang aplikasi'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: scheme.primaryContainer,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 30),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(appName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            Text('Versi $appVersion • Build $appBuildNumber', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('MusikKu • Musik, koleksi, radio, lirik, dan pemutar audio dalam satu aplikasi.'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(AppUpdateSheet.show(context)),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('Periksa pembaruan'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _SettingsPill extends StatelessWidget {
  const _SettingsPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.70),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: scheme.primary),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 19, color: scheme.primary),
        const SizedBox(width: 9),
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: scheme.onSurface)),
      ],
    );
  }
}
