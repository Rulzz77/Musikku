import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'app_info.dart';
import 'pages/startup_page.dart';
import 'services/app_settings.dart';
import 'theme/app_colors.dart';
import 'services/app_health_monitor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Avoid writing playback identifiers, request URLs, or API error details to
  // production logcat through the many debugPrint diagnostics in the app.
  if (!kDebugMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
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
    final surface = isDark ? (amoled ? Colors.black : appPanel) : appLightPanel;

    final base = ColorScheme.fromSeed(
      seedColor: appGoldStrong,
      brightness: brightness,
      surface: surface,
    );

    final scheme = base.copyWith(
      // Music-first graphite surfaces with a YouTube-Music-inspired red accent.
      primary: isDark ? const Color(0xFFFF416C) : const Color(0xFFD51F4E),
      onPrimary: Colors.white,
      primaryContainer: isDark ? const Color(0xFF3B1828) : const Color(0xFFFFE3EA),
      onPrimaryContainer: isDark ? const Color(0xFFFFD6E0) : const Color(0xFF6E1230),
      secondary: appSecondary,
      onSecondary: Colors.white,
      secondaryContainer: isDark ? const Color(0xFF3B202D) : const Color(0xFFFFE9EF),
      onSecondaryContainer: isDark ? const Color(0xFFFFE1E9) : const Color(0xFF63172F),
      surface: surface,
      surfaceContainerLowest: isDark ? const Color(0xFF09090A) : Colors.white,
      surfaceContainerLow: isDark ? const Color(0xFF121214) : const Color(0xFFFCFBFC),
      surfaceContainer: isDark ? const Color(0xFF1B1B1F) : const Color(0xFFF3F1F2),
      surfaceContainerHigh: isDark ? const Color(0xFF222226) : const Color(0xFFECE9EB),
      surfaceContainerHighest: isDark ? const Color(0xFF2B2B30) : const Color(0xFFE4E0E3),
      onSurface: isDark ? const Color(0xFFF8F6F7) : const Color(0xFF161316),
      onSurfaceVariant: isDark ? const Color(0xFFB8B0B4) : const Color(0xFF696166),
      outline: isDark ? const Color(0xFF4B4448) : const Color(0xFFD0C9CD),
      outlineVariant: isDark ? const Color(0xFF343136) : const Color(0xFFE3DEE1),
      error: const Color(0xFFD94A5C),
    );

    final baseTextTheme = ThemeData(
      brightness: brightness,
      useMaterial3: true,
    ).textTheme;

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
      textTheme: baseTextTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ).copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -1.3,
          height: 1.02,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.9,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.7,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.45,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.35,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(height: 1.35),
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
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
          letterSpacing: -0.45,
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
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 21,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.45,
        ),
        contentTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? appPanelElevated : const Color(0xFF30272E),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
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
        subtitleTextStyle: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        minVerticalPadding: 8,
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
