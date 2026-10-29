import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Decorative, non-interactive ambient backdrop shared by MusikKu screens.
/// The content itself remains in charge of scrolling, gestures, and playback.
class MusicBackdrop extends StatelessWidget {
  const MusicBackdrop({super.key, required this.child, this.intensity = 1});

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = (0.075 * intensity).clamp(0.0, 0.14).toDouble();
    final b = (0.045 * intensity).clamp(0.0, 0.10).toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          top: -125,
          right: -115,
          child: IgnorePointer(
            child: _GlowOrb(size: 300, color: scheme.primary.withValues(alpha: a)),
          ),
        ),
        Positioned(
          bottom: -135,
          left: -120,
          child: IgnorePointer(
            child: _GlowOrb(size: 330, color: scheme.secondary.withValues(alpha: b)),
          ),
        ),
        child,
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
              stops: const [0, 1],
            ),
          ),
        ),
      );
}

/// Soft blurred surface for dialogs, cards, and compact controls. Uses the
/// current theme so dark, light, and AMOLED modes stay visually coherent.
class MusicGlassPanel extends StatelessWidget {
  const MusicGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.accent,
    this.blur = 14,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? accent;
  final double blur;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = accent ?? scheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint.withValues(alpha: dark ? 0.11 : 0.075),
                  scheme.surfaceContainerLow.withValues(alpha: dark ? 0.68 : 0.88),
                ],
              ),
              borderRadius: borderRadius,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: dark ? 0.48 : 0.72),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Page-specific header that feels like a streaming catalogue rather than a
/// generic settings screen. Intended for secondary pages only.
class MusicPageHeader extends StatelessWidget {
  const MusicPageHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.eyebrow = 'MUSIKKU',
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MusicGlassPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      radius: 23,
      accent: scheme.primary,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.secondary],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: scheme.onPrimary, size: 25),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20, height: 1.05, fontWeight: FontWeight.w900, letterSpacing: -0.65),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.3, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// A consistent empty state for catalogue sections, search, and local media.
class MusicEmptyState extends StatelessWidget {
  const MusicEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MusicGlassPanel(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary.withValues(alpha: 0.18), scheme.secondary.withValues(alpha: 0.12)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, size: 31, color: scheme.primary),
          ),
          const SizedBox(height: 13),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.25)),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.4)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.arrow_forward_rounded, size: 18), label: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
