import 'dart:async';

import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_settings.dart';
import 'home_page.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({super.key, required this.settings});

  final AppSettingsController settings;

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
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
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => HomePage(settings: widget.settings),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.scaffoldBackgroundColor,
                  Color.lerp(theme.scaffoldBackgroundColor, scheme.primary, 0.08)!,
                  theme.scaffoldBackgroundColor,
                ],
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, height: 4, child: ColoredBox(color: scheme.primary)),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.94, end: 1.0),
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
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(25)),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, _, _) => Icon(Icons.graphic_eq_rounded, size: 48, color: scheme.onPrimary),
                        ),
                      ),
                      const SizedBox(height: 27),
                      Text(appName, style: TextStyle(fontSize: 42, height: 0.98, letterSpacing: -1.8, fontWeight: FontWeight.w900, color: scheme.onSurface)),
                      const SizedBox(height: 9),
                      Text('MUSIK. SUASANA. MOMENMU.', style: TextStyle(color: scheme.primary, fontSize: 10, letterSpacing: 1.65, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 34),
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
                      Text('v$appVersion  ·  build $appBuildNumber', style: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.78), fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
