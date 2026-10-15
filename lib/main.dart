import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

import 'app_info.dart';
import 'pages/startup_page.dart';
import 'services/app_settings.dart';
import 'theme/app_colors.dart';
import 'services/app_health_monitor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final health = AppHealthMonitor.instance;

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(health.record(
      kind: 'FlutterError',
      error: details.exception,
      stack: details.stack,
    ));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(health.record(kind: 'Unhandled', error: error, stack: stack));
    return true;
  };

  await runZonedGuarded(() async {
    final settings = AppSettingsController.instance;
    await settings.load();

    runApp(MusikKuApp(settings: settings));
  }, (error, stack) async {
    await health.record(kind: 'ZoneError', error: error, stack: stack);
  });
}

class MusikKuApp extends StatelessWidget {
  const MusikKuApp({super.key, required this.settings});

  final AppSettingsController settings;

  ThemeData _buildTheme(Brightness brightness, {required bool amoled}) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? (amoled ? Colors.black : appInk) : appLightBackground;
    final surface = isDark ? appPanel : appLightPanel;

    final base = ColorScheme.fromSeed(
      seedColor: appGoldStrong,
      brightness: brightness,
      surface: surface,
    );

    final scheme = base.copyWith(
      // Midnight Flow palette: mint primary, cool navy surfaces.
      primary: isDark ? const Color(0xFF66E3C4) : const Color(0xFF087F71),
      onPrimary: isDark ? const Color(0xFF07130F) : Colors.white,
      primaryContainer: isDark ? const Color(0xFF173A34) : const Color(0xFFD8F7EF),
      onPrimaryContainer: isDark ? const Color(0xFFBDF8E9) : const Color(0xFF073D34),
      secondary: appSecondary,
      onSecondary: Colors.white,
      secondaryContainer: isDark ? const Color(0xFF29263F) : const Color(0xFFECE8FF),
      onSecondaryContainer: isDark ? const Color(0xFFE7E0FF) : const Color(0xFF30245D),
      surface: surface,
      surfaceContainerLowest: isDark ? const Color(0xFF0A0F13) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF111A20) : const Color(0xFFF8FBFB),
      surfaceContainer: isDark ? const Color(0xFF18232B) : const Color(0xFFF0F5F4),
      surfaceContainerHigh: isDark ? const Color(0xFF1B2933) : const Color(0xFFE8F0EF),
      surfaceContainerHighest: isDark ? const Color(0xFF253642) : const Color(0xFFDFE9E7),
      onSurface: isDark ? const Color(0xFFF0F7F6) : const Color(0xFF0B1716),
      onSurfaceVariant: isDark ? const Color(0xFFA4B5BB) : const Color(0xFF5C6D6D),
      outline: isDark ? const Color(0xFF40535D) : const Color(0xFFC6D4D1),
      outlineVariant: isDark ? const Color(0xFF263942) : const Color(0xFFDCE6E4),
      error: const Color(0xFFD94A5C),
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      // Pastikan emoji/judul YouTube punya fallback font emoji di Android.
      // Roboto tidak mencakup semua glyph emoji, sehingga tanpa fallback
      // beberapa emoji dapat berubah menjadi kotak/karakter tidak terbaca.
      fontFamilyFallback: const [
        'Noto Color Emoji',
        'Noto Emoji',
      ],
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.36 : 0.68),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.05,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.75), width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.42 : 0.70),
        space: 1,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        // Keep the app-wide theme in sync with YoutubeHub's existing 66px bar.
        height: 66,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer.withValues(alpha: 0.92),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            size: 23,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            letterSpacing: 0.05,
            color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          );
        }),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? appPanelElevated : const Color(0xFF222733),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outlineVariant.withValues(alpha: 0.35),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.outlineVariant.withValues(alpha: 0.55),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.10),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurface),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        subtitleTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeChoice>(
      valueListenable: settings.theme,
      builder: (context, choice, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: appName,
          theme: _buildTheme(Brightness.light, amoled: false),
          darkTheme: _buildTheme(
            Brightness.dark,
            amoled: choice == AppThemeChoice.amoled,
          ),
          themeMode: settings.themeMode,
          home: StartupPage(settings: settings),
        );
      },
    );
  }
}
