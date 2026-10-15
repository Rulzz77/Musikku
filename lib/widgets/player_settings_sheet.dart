import 'dart:async';

import 'package:flutter/material.dart';

/// Mode subtitle dibuat eksplisit agar "track langsung" dan "terjemahan
/// otomatis" tidak tercampur seperti versi sebelumnya.
const List<({String value, String label, String description})> youtubeCaptionOptions = [
  (
    value: 'id',
    label: 'Indonesia',
    description: 'Pakai track Indonesia langsung bila tersedia.',
  ),
  (
    value: 'en',
    label: 'Inggris',
    description: 'Pakai track Inggris langsung bila tersedia.',
  ),
  (
    value: 'original',
    label: 'Bahasa asli',
    description: 'Pakai track asli pertama yang tersedia.',
  ),
  (
    value: 'auto:id',
    label: 'Terjemahan otomatis Indonesia',
    description: 'Terjemahkan track yang tersedia ke Indonesia.',
  ),
  (
    value: 'auto:en',
    label: 'Terjemahan otomatis Inggris',
    description: 'Terjemahkan track yang tersedia ke Inggris.',
  ),
];

String youtubeCaptionLabel(String value) {
  for (final option in youtubeCaptionOptions) {
    if (option.value == value) return option.label;
  }
  return value;
}

/// Sheet pengaturan pemutar.
Future<void> showYoutubePlayerSettingsSheet({
  required BuildContext context,
  required bool repeat,
  required bool captionsEnabled,
  required String captionLanguage,
  required VoidCallback onToggleRepeat,
  required Future<void> Function(bool enabled) onSetCaptions,
  required Future<void> Function(String language) onSetCaptionLanguage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) {
      var repeatValue = repeat;
      var captionsValue = captionsEnabled;
      var captionLanguageValue = captionLanguage;

      return StatefulBuilder(
        builder: (context, setSheetState) {
          final scheme = Theme.of(context).colorScheme;

          Future<void> chooseCaption(String value) async {
            setSheetState(() => captionLanguageValue = value);
            try {
              await onSetCaptionLanguage(value);
            } catch (_) {
              // Error sudah ditampilkan pemanggil.
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pengaturan video',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    Icons.repeat_rounded,
                    color: repeatValue ? scheme.primary : null,
                  ),
                  title: const Text('Ulangi video'),
                  value: repeatValue,
                  onChanged: (_) {
                    onToggleRepeat();
                    setSheetState(() => repeatValue = !repeatValue);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    Icons.translate_rounded,
                    color: captionsValue ? scheme.primary : null,
                  ),
                  title: const Text('Subtitle'),
                  subtitle: Text(
                    captionsValue
                        ? 'Aktif • ${youtubeCaptionLabel(captionLanguageValue)}'
                        : 'Mati • ${youtubeCaptionLabel(captionLanguageValue)}',
                  ),
                  value: captionsValue,
                  onChanged: (value) {
                    setSheetState(() => captionsValue = value);
                    unawaited(onSetCaptions(value));
                  },
                ),
                const SizedBox(height: 4),
                const Text(
                  'Bahasa subtitle',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: youtubeCaptionOptions.any((o) => o.value == captionLanguageValue)
                      ? captionLanguageValue
                      : youtubeCaptionOptions.first.value,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    prefixIcon: const Icon(Icons.translate_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  menuMaxHeight: 320,
                  items: [
                    for (final option in youtubeCaptionOptions)
                      DropdownMenuItem<String>(
                        value: option.value,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) unawaited(chooseCaption(value));
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  youtubeCaptionOptions
                          .where((option) => option.value == captionLanguageValue)
                          .map((option) => option.description)
                          .firstOrNull ??
                      '',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.high_quality_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Resolusi video',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gunakan ikon setelan (⚙️) bawaan YouTube pada pemutar untuk melihat pilihan kualitas yang tersedia. YouTube bisa tetap memilih kualitas otomatis sesuai video, koneksi, dan ukuran pemutar.',
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
