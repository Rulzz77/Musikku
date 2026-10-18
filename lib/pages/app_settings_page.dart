import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_settings.dart';
import '../widgets/app_update_sheet.dart';

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
        title: const Text('Pengaturan MusikKu'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
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
          const SizedBox(height: 22),
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
          const SizedBox(height: 22),
          _SectionLabel(icon: Icons.tune_rounded, title: 'Pemutar musik & tampilan'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: settings.showDataUsageOnPlayer,
                  builder: (context, value, _) => SwitchListTile(
                    secondary: const Icon(Icons.data_usage_rounded),
                    title: const Text('Tampilkan penggunaan data', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Tampilkan ringkasan penggunaan data di layar pemutar.'),
                    value: value,
                    onChanged: (next) => unawaited(settings.setShowDataUsageOnPlayer(next)),
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ValueListenableBuilder<bool>(
                  valueListenable: settings.cropVideoBranding,
                  builder: (context, value, _) => SwitchListTile(
                    secondary: const Icon(Icons.crop_rounded),
                    title: const Text('Potong tepi video', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Perbesar video sedikit; sebagian tepi dapat terpotong.'),
                    value: value,
                    onChanged: (next) => unawaited(settings.setCropVideoBranding(next)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
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
