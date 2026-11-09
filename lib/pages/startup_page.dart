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
  late final AnimationController _loadingPulse;

  @override
  void initState() {
    super.initState();
    _loadingPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
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
    _loadingPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: MusicBackdrop(
        intensity: 0.8,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(15),
                          topRight: Radius.circular(15),
                          bottomRight: Radius.circular(15),
                          bottomLeft: Radius.circular(4),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/icon/app_icon.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(Icons.graphic_eq_rounded, color: scheme.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MUSIKKU', style: TextStyle(color: scheme.primary, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
                        Text('PERSONAL SOUND SPACE', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'Dengar.\nRasakan.\nUlangi.',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 48,
                    height: 0.94,
                    letterSpacing: -2.0,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                Container(width: 54, height: 5, decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 13),
                Text(
                  'Satu ruang untuk musik yang menemani setiap suasana.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 38),
                AnimatedBuilder(
                  animation: _loadingPulse,
                  builder: (context, _) {
                    final progress = 0.28 + (_loadingPulse.value * 0.62);
                    return Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              minHeight: 4,
                              value: progress,
                              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.55),
                              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 20),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'v$appVersion  ·  build $appBuildNumber',
                  style: TextStyle(color: scheme.onSurfaceVariant.withValues(alpha: 0.78), fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
