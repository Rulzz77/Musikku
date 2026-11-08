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

  ThemeData _buildTheme(
    Brightness brightness, {
    required bool amoled,
    required Color accent,
  }) {
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? (amoled ? Colors.black : const Color(0xFF111419))
        : const Color(0xFFF4F6F8);
    final surface = isDark
        ? (amoled ? const Color(0xFF050505) : const Color(0xFF191E25))
        : const Color(0xFFFFFFFF);

    final base = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      surface: surface,
    );
    final primaryContainer = Color.lerp(
      surface,
      accent,
      isDark ? 0.30 : 0.15,
    )!;
    final scheme = base.copyWith(
      primary: accent,
      onPrimary: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? Colors.white
          : const Color(0xFF101318),
      primaryContainer: primaryContainer,
      onPrimaryContainer: isDark ? Colors.white : const Color(0xFF17202B),
      surface: surface,
      surfaceContainerLowest: isDark ? const Color(0xFF0D1015) : const Color(0xFFFFFFFF),
      surfaceContainerLow: isDark ? const Color(0xFF171C23) : const Color(0xFFF8F9FB),
      surfaceContainer: isDark ? const Color(0xFF1D242D) : const Color(0xFFF0F2F5),
      surfaceContainerHigh: isDark ? const Color(0xFF252D38) : const Color(0xFFE9EDF2),
      surfaceContainerHighest: isDark ? const Color(0xFF303A47) : const Color(0xFFDFE5EC),
      onSurface: isDark ? const Color(0xFFF1F4F8) : const Color(0xFF1B222B),
      onSurfaceVariant: isDark ? const Color(0xFFADB7C4) : const Color(0xFF687482),
      outline: isDark ? const Color(0xFF566271) : const Color(0xFFB6C0CB),
      outlineVariant: isDark ? const Color(0xFF39434F) : const Color(0xFFDCE2E9),
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
        fontFamily: 'Roboto',
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ).copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.15,
          height: 1.02,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.75,
        ),
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.55,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
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
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.40 : 0.78),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: scheme.onPrimary,
          backgroundColor: scheme.primary,
          minimumSize: const Size(0, 46),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.05),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected) ? scheme.onPrimaryContainer : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected) ? scheme.primaryContainer : scheme.surfaceContainerHighest),
        trackOutlineColor: WidgetStateProperty.all(scheme.outlineVariant),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: scheme.outline),
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : null),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? appPanelElevated : appInk,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 500),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        indicatorColor: scheme.primary,
        dividerColor: scheme.outlineVariant.withValues(alpha: 0.55),
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
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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
        backgroundColor: isDark ? appPanelElevated : appInk,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        clipBehavior: Clip.antiAlias,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        textColor: scheme.onSurface,
        subtitleTextStyle: TextStyle(color: scheme.onSurfaceVariant, height: 1.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        minVerticalPadding: 7,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings.theme, settings.accentColor, settings.motion]),
      builder: (context, _) {
        final choice = settings.theme.value;
        final accent = settings.accentColor.value.color;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: appName,
          theme: _buildTheme(Brightness.light, amoled: false, accent: accent),
          darkTheme: _buildTheme(
            Brightness.dark,
            amoled: choice == AppThemeChoice.amoled,
            accent: accent,
          ),
          themeMode: settings.themeMode,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final reduceMotion = settings.motion.value == AppMotionChoice.reduced;
            return MediaQuery(
              data: media.copyWith(disableAnimations: media.disableAnimations || reduceMotion),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: StartupPage(settings: settings),
        );
      },
    );
  }
}
