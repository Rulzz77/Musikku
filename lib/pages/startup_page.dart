import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_settings.dart';
import '../widgets/music_design.dart';
import 'home_page.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({super.key, required this.settings});

  final AppSettingsController settings;

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage>
    with SingleTickerProviderStateMixin {
  bool _opened = false;
  late final AnimationController _recordSpin;

  @override
  void initState() {
    super.initState();
    _recordSpin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    // Berikan waktu singkat untuk splash, lalu buka beranda tanpa mewajibkan login.
    await Future<void>.delayed(const Duration(milliseconds: 650));
    _openHome();
  }

  void _openHome() {
    if (!mounted || _opened) return;
    _opened = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => HomePage(settings: widget.settings),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.018),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recordSpin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: MusicBackdrop(
        intensity: 1.45,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 76,
              right: -52,
              child: IgnorePointer(
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.08),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 42,
              left: -72,
              child: IgnorePointer(
                child: Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.tertiary.withValues(alpha: 0.075),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1.0),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) => Opacity(
                  opacity: scale.clamp(0.0, 1.0).toDouble(),
                  child: Transform.scale(scale: scale, child: child),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: SizedBox(
                            width: 186,
                            height: 186,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                RotationTransition(
                                  turns: _recordSpin,
                                  child: Container(
                                    width: 182,
                                    height: 182,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          scheme.surfaceContainerHighest,
                                          scheme.surfaceContainerLow,
                                          theme.scaffoldBackgroundColor,
                                        ],
                                        stops: const [0.0, 0.72, 1.0],
                                      ),
                                      border: Border.all(
                                        color: scheme.primary.withValues(alpha: 0.24),
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: scheme.primary.withValues(alpha: 0.15),
                                          blurRadius: 28,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 126,
                                        height: 126,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: scheme.onSurface.withValues(alpha: 0.10),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 104,
                                  height: 104,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [scheme.primary, scheme.tertiary],
                                    ),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: scheme.surface.withValues(alpha: 0.55),
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: scheme.primary.withValues(alpha: 0.30),
                                        blurRadius: 23,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    'assets/icon/app_icon.png',
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    errorBuilder: (_, _, _) => Icon(
                                      Icons.graphic_eq_rounded,
                                      size: 48,
                                      color: scheme.onPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 27),
                        Center(
                          child: Text(
                            appName,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 42,
                              height: 0.98,
                              letterSpacing: -1.8,
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Text(
                            'MUSIK. SUASANA. MOMENMU.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 10,
                              letterSpacing: 1.65,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(height: 39),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  minHeight: 3,
                                  backgroundColor: scheme.outlineVariant.withValues(alpha: 0.55),
                                  valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.graphic_eq_rounded, size: 18, color: scheme.primary),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Center(
                          child: Text(
                            'v$appVersion  ·  build $appBuildNumber',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.78),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
