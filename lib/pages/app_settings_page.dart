import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import 'app_health_page.dart';
import '../services/app_settings.dart';
import '../widgets/app_update_sheet.dart';
import '../widgets/data_usage_card.dart';

/// Pengaturan global aplikasi. Semua opsi terhubung langsung ke controller
/// dan disimpan lewat SharedPreferences.
///
/// Tampilan: bersih dan lega. Tiap bagian punya judul kecil di atas, lalu satu
/// blok lembut berisi baris-baris pengaturan yang dipisah garis tipis. Tidak
/// ada kartu hero, gradien, atau lencana dekoratif.
class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key, required this.settings, this.onOpenAudioSettings});

  final AppSettingsController settings;
  final VoidCallback? onOpenAudioSettings;

  String _themeLabel(AppThemeChoice choice) => switch (choice) {
        AppThemeChoice.system => 'Ikuti perangkat',
        AppThemeChoice.dark => 'Gelap',
        AppThemeChoice.amoled => 'AMOLED hitam',
        AppThemeChoice.light => 'Terang',
        AppThemeChoice.pink => 'Pink pastel aesthetic',
      };

  IconData _themeIcon(AppThemeChoice choice) => switch (choice) {
        AppThemeChoice.system => Icons.brightness_auto_rounded,
        AppThemeChoice.dark => Icons.dark_mode_rounded,
        AppThemeChoice.amoled => Icons.contrast_rounded,
        AppThemeChoice.light => Icons.light_mode_rounded,
        AppThemeChoice.pink => Icons.favorite_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          // ---------------------------------------------------------------
          // TAMPILAN
          // ---------------------------------------------------------------
          const _SectionLabel(icon: Icons.palette_outlined, title: 'Tampilan'),
          _Group(
            children: [
              ValueListenableBuilder<AppThemeChoice>(
                valueListenable: settings.theme,
                builder: (context, selected, _) => RadioGroup<AppThemeChoice>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) unawaited(settings.setTheme(value));
                  },
                  child: Column(
                    children: [
                      for (var i = 0; i < AppThemeChoice.values.length; i++) ...[
                        if (i > 0) const _InsetDivider(),
                        RadioListTile<AppThemeChoice>(
                          value: AppThemeChoice.values[i],
                          secondary: Icon(
                            _themeIcon(AppThemeChoice.values[i]),
                            color: selected == AppThemeChoice.values[i]
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                          title: Text(
                            _themeLabel(AppThemeChoice.values[i]),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(switch (AppThemeChoice.values[i]) {
                            AppThemeChoice.system => 'Ikuti mode terang/gelap sistem.',
                            AppThemeChoice.dark => 'Tema gelap dengan aksen MusikKu.',
                            AppThemeChoice.amoled => 'Latar hitam untuk layar OLED.',
                            AppThemeChoice.light => 'Latar terang untuk ruangan cerah.',
                            AppThemeChoice.pink => 'Pink lembut, rose, dan glass. Pilih Mode Gelap atau Terang untuk kembali ke tampilan normal.',
                          }),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ---------------------------------------------------------------
          // DATA DAN JARINGAN
          // ---------------------------------------------------------------
          const _SectionLabel(icon: Icons.network_check_rounded, title: 'Data dan jaringan'),
          _Group(
            children: [
              ValueListenableBuilder<DataSaverMode>(
                valueListenable: settings.dataSaverMode,
                builder: (context, mode, _) => RadioGroup<DataSaverMode>(
                  groupValue: mode,
                  onChanged: (value) {
                    if (value != null) unawaited(settings.setDataSaverMode(value));
                  },
                  child: Column(
                    children: [
                      for (var i = 0; i < DataSaverMode.values.length; i++) ...[
                        if (i > 0) const _InsetDivider(),
                        RadioListTile<DataSaverMode>(
                          value: DataSaverMode.values[i],
                          title: Text(
                            DataSaverMode.values[i].label,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(DataSaverMode.values[i].description),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Group(
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
              ValueListenableBuilder<int>(
                valueListenable: settings.bufferAlertSeconds,
                builder: (context, seconds, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.hourglass_bottom_rounded, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text('Peringatan buffer rendah', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
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

          // ---------------------------------------------------------------
          // KONSUMSI DATA
          // ---------------------------------------------------------------
          const _SectionLabel(icon: Icons.data_usage_rounded, title: 'Konsumsi data'),
          const DataUsageCard(),

          // ---------------------------------------------------------------
          // PEMUTAR MUSIK & TAMPILAN
          // ---------------------------------------------------------------
          const _SectionLabel(icon: Icons.tune_rounded, title: 'Pemutar musik & tampilan'),
          _Group(
            children: [
              if (onOpenAudioSettings != null)
                ListTile(
                  leading: const Icon(Icons.graphic_eq_rounded),
                  title: const Text('Efek audio', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Preset equalizer, volume, dan transisi antar lagu.'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: onOpenAudioSettings,
                ),
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

          // ---------------------------------------------------------------
          // DIAGNOSTIK & PEMULIHAN
          // ---------------------------------------------------------------
          const _SectionLabel(icon: Icons.health_and_safety_outlined, title: 'Diagnostik & pemulihan'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('Diagnostik aplikasi', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Lihat error pemutaran, salin laporan, atau hapus log lokal.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AppHealthPage()),
                ),
              ),
            ],
          ),

          // ---------------------------------------------------------------
          // PEMBARUAN APLIKASI
          // ---------------------------------------------------------------
          const _SectionLabel(icon: Icons.system_update_alt_rounded, title: 'Pembaruan aplikasi'),
          _Group(
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
              ValueListenableBuilder<bool>(
                valueListenable: settings.autoUpdateEnabled,
                builder: (context, autoUpdateEnabled, _) => ValueListenableBuilder<bool>(
                  valueListenable: settings.backgroundDownloadUpdates,
                  builder: (context, enabled, _) => SwitchListTile(
                    secondary: const Icon(Icons.downloading_rounded),
                    title: const Text('Unduh pembaruan di latar belakang', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Saat MusikKu dibuka, unduh APK terverifikasi diam-diam jika versi baru tersedia. Memakai kuota internet; unduhan dapat berhenti jika Android menutup aplikasi, dan pemasangan tetap perlu konfirmasi Android.'),
                    value: enabled,
                    onChanged: autoUpdateEnabled
                        ? (next) => unawaited(settings.setBackgroundDownloadUpdates(next))
                        : null,
                  ),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: settings.autoUpdateEnabled,
                builder: (context, autoUpdateEnabled, _) => ValueListenableBuilder<bool>(
                  valueListenable: settings.autoInstallUpdates,
                  builder: (context, enabled, _) => SwitchListTile(
                    secondary: const Icon(Icons.install_mobile_rounded),
                    title: const Text('Unduh & buka installer otomatis', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Jika update ditemukan, unduh APK terverifikasi dan buka installer Android. Perlu konfirmasi pemasangan dari Android.'),
                    value: enabled,
                    onChanged: autoUpdateEnabled
                        ? (next) => unawaited(settings.setAutoInstallUpdates(next))
                        : null,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, size: 15, color: scheme.onSurfaceVariant),
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

          // ---------------------------------------------------------------
          // TENTANG APLIKASI (tanpa kartu, rata tengah)
          // ---------------------------------------------------------------
          const SizedBox(height: 36),
          Center(
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(19),
                color: scheme.primaryContainer,
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset(
                'assets/icon/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(appName, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
          ),
          const SizedBox(height: 3),
          Center(
            child: Text(
              'Versi $appVersion • Build $appBuildNumber',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'MusikKu • Musik, koleksi, radio, lirik, dan pemutar audio dalam satu aplikasi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton.icon(
              onPressed: () => unawaited(AppUpdateSheet.show(context)),
              icon: const Icon(Icons.system_update_alt_rounded, size: 19),
              label: const Text('Periksa pembaruan'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Judul bagian: huruf kapital kecil dengan jarak antar-huruf, di atas blok.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 28, 6, 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu blok lembut tanpa garis tepi; baris di dalamnya dipisah garis tipis.
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const _InsetDivider(),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _InsetDivider extends StatelessWidget {
  const _InsetDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }
}