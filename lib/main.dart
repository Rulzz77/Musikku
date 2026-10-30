import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'app_info.dart';
import 'pages/startup_page.dart';
import 'services/app_settings.dart';
import 'theme/app_colors.dart';
import 'services/app_health_monitor.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  // This singleton has no binding-dependent constructor side effects, so it
  // is safe to prepare the error recorder before entering the guarded zone.
  final health = AppHealthMonitor.instance;

  await runZonedGuarded(() async {
    // IMPORTANT: initialize Flutter and call runApp in the same Zone. Keeping
    // ensureInitialized outside runZonedGuarded triggers Flutter's
    // "Zone mismatch" diagnostic during startup.
    WidgetsFlutterBinding.ensureInitialized();

    // Avoid writing playback identifiers, request URLs, or API error details
    // to production logcat through the many debugPrint diagnostics in the app.
    if (!kDebugMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }

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

    await _clearLegacyYouTubeAccountData();
    final settings = AppSettingsController.instance;
    await settings.load();

    // Keep runApp in this same guarded zone as ensureInitialized above.
    runApp(MusikKuApp(settings: settings));
  }, (error, stack) async {
    await health.record(kind: 'ZoneError', error: error, stack: stack);
  });
}


/// Remove legacy account login/cache keys from older app versions at startup.
/// The music player no longer stores or uses a Google/YouTube account session.
Future<void> _clearLegacyYouTubeAccountData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    const exactKeys = <String>{
      'youtube_session_ok',
      'youtube_user_explicitly_signed_out',
      'youtube_last_account_email',
      'youtube_last_account_name',
    };
    for (final key in exactKeys) {
      await prefs.remove(key);
    }
    const legacyPrefixes = <String>[
      'youtube_hub_cache_v1_',
      'account_cache_',
      'youtube_account_',
      // DiskCache namespaces used only by the previous signed-in library.
      'cache_index_yt_upload_pages_v1',
      'cache_yt_upload_pages_v1_',
      'cache_index_yt_enriched_video_batches_v1',
      'cache_yt_enriched_video_batches_v1_',
    ];
    for (final key in prefs.getKeys().toList(growable: false)) {
      if (legacyPrefixes.any((prefix) => key.startsWith(prefix))) {
        await prefs.remove(key);
      }
    }
  } catch (_) {
    // Legacy cleanup must never block playback startup.
  }
}

class MusikKuApp extends StatelessWidget {
  const MusikKuApp({super.key, required this.settings});

  final AppSettingsController settings;

  ThemeData _buildTheme(Brightness brightness, {required bool amoled, bool pink = false}) {
    final isDark = brightness == Brightness.dark;
    final background = pink ? const Color(0xFFFFF5F8) : (isDark ? (amoled ? Colors.black : appInk) : appLightBackground);
    final surface = pink ? const Color(0xFFFFFBFC) : (isDark ? (amoled ? Colors.black : appPanel) : appLightPanel);

    final base = ColorScheme.fromSeed(
      seedColor: pink ? const Color(0xFFE879A6) : const Color(0xFF38BFD0),
      brightness: brightness,
      surface: surface,
    );

    final scheme = pink
        ? base.copyWith(
            primary: const Color(0xFFCE5C8B),
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFFFDCE9),
            onPrimaryContainer: const Color(0xFF6D2443),
            secondary: const Color(0xFFB86B8D),
            onSecondary: Colors.white,
            secondaryContainer: const Color(0xFFFFE8F0),
            onSecondaryContainer: const Color(0xFF71334E),
            tertiary: const Color(0xFFB77B9D),
            tertiaryContainer: const Color(0xFFF8DFEA),
            onTertiary: Colors.white,
            onTertiaryContainer: const Color(0xFF593348),
            surface: surface,
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFFFF8FA),
            surfaceContainer: const Color(0xFFFFEEF4),
            surfaceContainerHigh: const Color(0xFFFBE4ED),
            surfaceContainerHighest: const Color(0xFFF4D7E2),
            onSurface: const Color(0xFF35242C),
            onSurfaceVariant: const Color(0xFF806773),
            outline: const Color(0xFFD9B8C7),
            outlineVariant: const Color(0xFFEEDCE4),
            error: const Color(0xFFD94A5C),
          )
        : base.copyWith(
            // MusikKu identity: midnight blue, electric cyan and warm coral.
            primary: isDark ? const Color(0xFF65E3F0) : const Color(0xFF087F91),
            onPrimary: isDark ? const Color(0xFF04151D) : Colors.white,
            primaryContainer: isDark ? const Color(0xFF123A48) : const Color(0xFFD8F4F6),
            onPrimaryContainer: isDark ? const Color(0xFFC6F8FC) : const Color(0xFF064B57),
            secondary: isDark ? const Color(0xFFFF8A78) : const Color(0xFFD65C4C),
            onSecondary: isDark ? const Color(0xFF28100F) : Colors.white,
            secondaryContainer: isDark ? const Color(0xFF492522) : const Color(0xFFFFE2DC),
            onSecondaryContainer: isDark ? const Color(0xFFFFD8D0) : const Color(0xFF713127),
            tertiary: isDark ? const Color(0xFFFFD078) : const Color(0xFFB77A16),
            tertiaryContainer: isDark ? const Color(0xFF46351B) : const Color(0xFFFFEEC8),
            onTertiary: isDark ? const Color(0xFF211607) : Colors.white,
            onTertiaryContainer: isDark ? const Color(0xFFFFE9BC) : const Color(0xFF62400D),
            surface: surface,
            surfaceContainerLowest: isDark ? const Color(0xFF080E18) : Colors.white,
            surfaceContainerLow: isDark ? const Color(0xFF121E2E) : const Color(0xFFFAFCFE),
            surfaceContainer: isDark ? const Color(0xFF18263A) : const Color(0xFFEAF0F5),
            surfaceContainerHigh: isDark ? const Color(0xFF203149) : const Color(0xFFE0E9F0),
            surfaceContainerHighest: isDark ? const Color(0xFF2A3C55) : const Color(0xFFD3E0E9),
            onSurface: isDark ? const Color(0xFFF0F6FB) : const Color(0xFF142438),
            onSurfaceVariant: isDark ? const Color(0xFF9FB0C2) : const Color(0xFF5D7083),
            outline: isDark ? const Color(0xFF40536B) : const Color(0xFFB8C7D4),
            outlineVariant: isDark ? const Color(0xFF293A50) : const Color(0xFFDCE5EC),
            error: const Color(0xFFE45B66),
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
          letterSpacing: -0.55,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.40 : 0.78),
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
          borderRadius: BorderRadius.circular(14),
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
          theme: _buildTheme(Brightness.light, amoled: false, pink: choice == AppThemeChoice.pink),
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
