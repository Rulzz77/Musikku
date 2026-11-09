import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' hide appBuildNumber;
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import '../services/storage_service.dart';
import 'app_health_page.dart';
import '../services/app_settings.dart';
import '../services/floating_lyrics_bridge.dart';
import '../widgets/app_update_sheet.dart';
import '../widgets/data_usage_card.dart';
import '../widgets/music_design.dart';
import '../widgets/flow_components.dart';

Future<void> _exportMusikKuBackup(BuildContext context) async {
  try {
    final raw = await StorageService().exportBackupJson();
    final documents = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final file = File('${documents.path}/MusikKu_Backup_$stamp.json');
    await file.writeAsString(raw, flush: true);
    var copiedToClipboard = false;
    // Clipboard implementations on mobile may reject very large JSON files.
    // The backup file is already saved, so this optional convenience must not
    // turn a successful export into a reported failure.
    try {
      await Clipboard.setData(ClipboardData(text: raw));
      copiedToClipboard = true;
    } catch (_) {}
    if (!context.mounted) return;
    final message = copiedToClipboard
        ? 'Backup disimpan dan JSON disalin ke clipboard.'
        : 'Backup disimpan. Clipboard tidak menerima JSON ini; gunakan file: ${file.path}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 7)),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup gagal: $error')));
  }
}

Future<void> _restoreMusikKuBackup(BuildContext context) async {
  final clipboard = await Clipboard.getData('text/plain');
  if (!context.mounted) return;
  final controller = TextEditingController(text: clipboard?.text ?? '');
  final raw = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Pulihkan backup'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: controller,
          autofocus: true,
          minLines: 5,
          maxLines: 10,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'Tempel JSON backup MusikKu di sini',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Pulihkan')),
      ],
    ),
  );
  controller.dispose();
  if (raw == null || raw.trim().isEmpty || !context.mounted) return;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Ganti data lokal?'),
      content: const Text('Data favorit, playlist, antrean, riwayat, dan statistik yang cocok di backup akan ditimpa. Pastikan kamu sudah membuat backup terbaru.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Lanjutkan')),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  try {
    await StorageService().restoreBackupJson(raw);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backup dipulihkan. Tutup lalu buka kembali MusikKu agar semua data dimuat ulang.')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup tidak dapat dipulihkan: $error')));
  }
}

/// Pengaturan global aplikasi. Semua opsi terhubung langsung ke controller
/// dan disimpan lewat SharedPreferences.
///
/// Tampilan: bersih dan lega. Tiap bagian punya judul kecil di atas, lalu satu
/// blok lembut berisi baris-baris pengaturan yang dipisah garis tipis. Tidak
/// ada kartu hero, gradien, atau lencana dekoratif.
class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({
    super.key,
    required this.settings,
    this.onOpenAudioSettings,
  });

  final AppSettingsController settings;
  final VoidCallback? onOpenAudioSettings;

  String _themeLabel(AppThemeChoice choice) => switch (choice) {
        AppThemeChoice.system => 'Otomatis',
        AppThemeChoice.dark => 'Gelap',
        AppThemeChoice.amoled => 'AMOLED',
        AppThemeChoice.light => 'Terang',
        AppThemeChoice.pink => 'Otomatis',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan'),
      ),
      body: MusicBackdrop(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: MusicPageEntrance(
              child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
        children: [
          const FlowPageHero(
            icon: Icons.tune_rounded,
            eyebrow: 'PENGATURAN APLIKASI',
            title: 'Atur MusikKu.',
            subtitle: 'Atur tampilan, penggunaan data, dan cara pemutar musik bekerja.',
            trailing: Icon(Icons.auto_awesome_rounded),
          ),
          const SizedBox(height: 12),
          // ---------------------------------------------------------------
          // TAMPILAN
          // ---------------------------------------------------------------
          const _SectionLabel(icon: Icons.palette_outlined, title: 'Tampilan'),
          _Group(
            children: [
              ValueListenableBuilder<AppThemeChoice>(
                valueListenable: settings.theme,
                builder: (context, selected, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('Tema aplikasi', style: TextStyle(color: scheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900))),
                          Text(_themeLabel(selected), style: TextStyle(color: scheme.primary, fontSize: 10, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Pilih tema terang, gelap, AMOLED, atau ikuti perangkat. Perubahan diterapkan langsung ke seluruh aplikasi.',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, height: 1.4),
                      ),
                      const SizedBox(height: 13),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 620 ? 4 : 2;
                          final itemWidth = (constraints.maxWidth - ((columns - 1) * 8)) / columns;
                          return Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: [
                              for (final choice in const <AppThemeChoice>[AppThemeChoice.system, AppThemeChoice.dark, AppThemeChoice.amoled, AppThemeChoice.light])
                                SizedBox(
                                  width: itemWidth,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(13),
                                    onTap: () => unawaited(settings.setTheme(choice)),
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
                                          width: double.infinity,
                                          height: 58,
                                          decoration: BoxDecoration(
                                            color: switch (choice) {
                                              AppThemeChoice.system => scheme.surfaceContainerHighest,
                                              AppThemeChoice.dark => const Color(0xFF151F30),
                                              AppThemeChoice.amoled => Colors.black,
                                              AppThemeChoice.light => const Color(0xFFF3F0E6),
                                              AppThemeChoice.pink => scheme.surfaceContainerHighest,
                                            },
                                            borderRadius: BorderRadius.circular(11),
                                            border: Border.all(color: selected == choice ? scheme.primary : scheme.outlineVariant, width: selected == choice ? 2 : 1),
                                          ),
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                left: 8,
                                                top: 8,
                                                child: Container(
                                                  width: 21,
                                                  height: 21,
                                                  decoration: BoxDecoration(
                                                    color: switch (choice) {
                                                      AppThemeChoice.light => const Color(0xFF3985E8),
                                                      _ => scheme.primary,
                                                    },
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              ),
                                              if (selected == choice)
                                                Positioned(
                                                  right: 6,
                                                  bottom: 5,
                                                  child: Container(
                                                    width: 19,
                                                    height: 19,
                                                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                                                    child: Icon(Icons.check_rounded, size: 13, color: scheme.onPrimary),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(_themeLabel(choice), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: selected == choice ? scheme.primary : scheme.onSurfaceVariant, fontSize: 11, fontWeight: selected == choice ? FontWeight.w900 : FontWeight.w700)),
                                      ],
                                    ),
                                  ),
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
          ),
          const SizedBox(height: 10),
          const _SectionLabel(icon: Icons.color_lens_outlined, title: 'Warna aksen'),
          _Group(
            children: [
              ValueListenableBuilder<AccentColorChoice>(
                valueListenable: settings.accentColor,
                builder: (context, selected, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(child: Text('Warna utama aplikasi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                          Text(selected.label, style: TextStyle(color: scheme.primary, fontSize: 11, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      const SizedBox(height: 13),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 760 ? 7 : constraints.maxWidth >= 520 ? 5 : 4;
                          final itemWidth = (constraints.maxWidth - ((columns - 1) * 9)) / columns;
                          return Wrap(
                            spacing: 9,
                            runSpacing: 12,
                            children: [
                              for (final color in AccentColorChoice.values)
                                SizedBox(
                                  width: itemWidth,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: () => unawaited(settings.setAccentColor(color)),
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
                                          width: 38,
                                          height: 38,
                                          decoration: BoxDecoration(
                                            color: color.color,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: selected == color ? scheme.onSurface : Colors.transparent, width: 2.5),
                                            boxShadow: selected == color ? [BoxShadow(color: color.color.withValues(alpha: 0.28), blurRadius: 10, spreadRadius: 1)] : null,
                                          ),
                                          child: selected == color ? const Icon(Icons.check_rounded, color: Colors.white, size: 19) : null,
                                        ),
                                        const SizedBox(height: 5),
                                        Text(color.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10.5, fontWeight: selected == color ? FontWeight.w900 : FontWeight.w600, color: selected == color ? scheme.primary : scheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text('Warna ini mengubah tombol, indikator aktif, slider, dan highlight. Artwork album tetap memakai warna aslinya.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, height: 1.4)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Group(
            children: [
              ValueListenableBuilder<AppMotionChoice>(
                valueListenable: settings.motion,
                builder: (context, motion, _) => SwitchListTile(
                  secondary: const Icon(Icons.motion_photos_on_outlined),
                  title: const Text('Kurangi animasi', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Gunakan transisi lebih singkat dan minim efek gerak.'),
                  value: motion == AppMotionChoice.reduced,
                  onChanged: (reduced) => unawaited(settings.setMotionChoice(
                    reduced ? AppMotionChoice.reduced : AppMotionChoice.premium,
                  )),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const _SectionLabel(icon: Icons.apps_rounded, title: 'Ikon home screen'),
          _Group(
            children: [
              ValueListenableBuilder<AppIconChoice>(
                valueListenable: settings.appIcon,
                builder: (context, selected, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pilih warna ikon MusikKu', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 5),
                      Text('Bentuk dan simbol ikon tetap sama. Hanya palet warnanya yang berubah.', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11, height: 1.4)),
                      const SizedBox(height: 13),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          const columns = 4;
                          final itemWidth = (constraints.maxWidth - ((columns - 1) * 10)) / columns;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 12,
                            children: [
                              for (final iconChoice in AppIconChoice.values)
                                SizedBox(
                                  width: itemWidth,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(13),
                                    onTap: () async {
                                      final applied = await settings.setAppIcon(iconChoice);
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(applied
                                              ? 'Ikon home screen diubah ke ${iconChoice.label}.'
                                              : 'Penggantian ikon belum didukung di perangkat ini.'),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 180),
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(17),
                                            border: Border.all(color: selected == iconChoice ? scheme.primary : scheme.outlineVariant, width: selected == iconChoice ? 2 : 1),
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(13),
                                            child: Image.asset(
                                              iconChoice.assetPath,
                                              width: 48,
                                              height: 48,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => Container(width: 48, height: 48, color: iconChoice.color, child: const Icon(Icons.music_note_rounded, color: Colors.white, size: 28)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            if (selected == iconChoice) Icon(Icons.check_circle_rounded, color: scheme.primary, size: 11),
                                            if (selected == iconChoice) const SizedBox(width: 3),
                                            Flexible(child: Text(iconChoice.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, fontWeight: selected == iconChoice ? FontWeight.w900 : FontWeight.w600, color: selected == iconChoice ? scheme.primary : scheme.onSurfaceVariant))),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
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
          ),

          // ---------------------------------------------------------------
          // BACKUP DAN PEMULIHAN
          // ---------------------------------------------------------------
          const _SectionLabel(icon: Icons.backup_rounded, title: 'Backup dan pemulihan'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('Buat backup lokal', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Simpan koleksi, antrean, riwayat, statistik, pengaturan, dan cover custom ke JSON.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(_exportMusikKuBackup(context)),
              ),
              const _InsetDivider(),
              ListTile(
                leading: const Icon(Icons.restore_rounded),
                title: const Text('Pulihkan dari JSON', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Tempel isi backup yang pernah disalin dari perangkat lain.'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(_restoreMusikKuBackup(context)),
              ),
            ],
          ),
          const SizedBox(height: 10),

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
                valueListenable: settings.bluetoothAutoResume,
                builder: (context, value, _) => SwitchListTile(
                  secondary: const Icon(Icons.bluetooth_connected_rounded),
                  title: const Text(
                    'Lanjutkan otomatis via Bluetooth',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Lanjutkan lagu ketika headset Bluetooth tersambung kembali setelah terputus saat musik diputar. Khusus Android.',
                  ),
                  value: value,
                  onChanged: (next) =>
                      unawaited(settings.setBluetoothAutoResume(next)),
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: settings.loudnessNormalization,
                builder: (context, value, _) => SwitchListTile(
                  secondary: const Icon(Icons.equalizer_rounded),
                  title: const Text('Penyeimbang volume adaptif (Beta)', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Leveler K-weighted sekitar 400 ms dengan pembatas puncak pada audio native Media3. Bukan LUFS terintegrasi/ReplayGain; fallback iframe YouTube tidak terpengaruh.'),
                  value: value,
                  onChanged: (next) => unawaited(settings.setLoudnessNormalization(next)),
                ),
              ),
              const _InsetDivider(),
              const _FloatingLyricsSettingsTile(),
              const _InsetDivider(),
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
            ),
          ),
        ),
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
      padding: const EdgeInsets.fromLTRB(1, 25, 1, 9),
      child: Row(
        children: [
          Container(width: 4, height: 20, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 10),
          Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurface, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: -0.2))),
          Icon(icon, size: 17, color: scheme.primary),
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
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.58)),
      ),
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

class _FloatingLyricsSettingsTile extends StatefulWidget {
  const _FloatingLyricsSettingsTile();

  @override
  State<_FloatingLyricsSettingsTile> createState() => _FloatingLyricsSettingsTileState();
}

class _FloatingLyricsSettingsTileState extends State<_FloatingLyricsSettingsTile> {
  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await FloatingLyricsBridge.initialize();
    if (!mounted) return;
    setState(() {
      _enabled = FloatingLyricsBridge.enabled;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool next) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await FloatingLyricsBridge.setEnabled(next);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _enabled = next;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Izinkan MusikKu tampil di atas aplikasi lain, lalu aktifkan sakelar ini lagi.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.lyrics_rounded),
      title: const Text('Floating Lyrics', style: TextStyle(fontWeight: FontWeight.w700)),
      subtitle: const Text('Tampilkan baris lirik tersinkron di atas aplikasi lain. Membutuhkan izin overlay Android.'),
      value: _enabled,
      onChanged: _loading || _busy || !Platform.isAndroid ? null : _setEnabled,
    );
  }
}
