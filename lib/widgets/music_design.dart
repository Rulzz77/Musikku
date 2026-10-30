import 'package:flutter/material.dart';

/// Shared midnight canvas used by secondary pages and overlays.
/// It relies on solid, high-contrast surfaces rather than glass blur.
class MusicBackdrop extends StatelessWidget {
  const MusicBackdrop({super.key, required this.child, this.intensity = 1});

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final glow = (0.075 * intensity).clamp(0.0, 0.12).toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(theme.scaffoldBackgroundColor, scheme.primary, glow)!,
                theme.scaffoldBackgroundColor,
                Color.lerp(theme.scaffoldBackgroundColor, scheme.secondary, glow * 0.25)!,
              ],
              stops: const [0, 0.48, 1],
            ),
          ),
        ),
        Positioned(
          top: -105,
          right: -92,
          child: IgnorePointer(
            child: Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [scheme.primary.withValues(alpha: dark ? 0.12 : 0.09), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -140,
          left: -100,
          child: IgnorePointer(
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [scheme.secondary.withValues(alpha: dark ? 0.075 : 0.055), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Distinct solid surface shared across feature pages.
class MusicGlassPanel extends StatelessWidget {
  const MusicGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = accent ?? scheme.primary;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.14 : 0.035),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
          BoxShadow(color: tint.withValues(alpha: 0.035), blurRadius: 26, spreadRadius: -9),
        ],
      ),
      child: child,
    );
  }
}

/// Bold title block used by secondary destinations.
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, scheme.tertiary],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.24), blurRadius: 16, offset: const Offset(0, 7))],
            ),
            child: Icon(icon, color: scheme.onPrimary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, letterSpacing: 1.65, fontWeight: FontWeight.w900, color: scheme.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 25, height: 1.0, fontWeight: FontWeight.w900, letterSpacing: -0.9),
                ),
                const SizedBox(height: 6),
                Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, height: 1.38, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Animated-friendly empty state with a clear accent and readable message.
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
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.primary.withValues(alpha: 0.18), width: 1.5),
            ),
            child: Icon(icon, size: 30, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 15),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, height: 1.45)),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 17),
            FilledButton.icon(onPressed: onAction, icon: const Icon(Icons.arrow_forward_rounded, size: 18), label: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}


/// A restrained entrance transition used by feature pages and full-screen tools.
/// Keeps the existing scrollable child and all of its callbacks untouched.
class MusicPageEntrance extends StatelessWidget {
  const MusicPageEntrance({super.key, required this.child, this.duration = const Duration(milliseconds: 420)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, progress, child) {
        final value = progress.clamp(0.0, 1.0).toDouble();
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - value)),
            child: Transform.scale(scale: 0.985 + (0.015 * value), child: child),
          ),
        );
      },
      child: child,
    );
  }
}

/// Compact visual heading for sheets and modal feature panels.
class MusicSheetHeading extends StatelessWidget {
  const MusicSheetHeading({super.key, required this.icon, required this.title, required this.subtitle, this.accent});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? scheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, scheme.tertiary]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.20), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: Icon(icon, color: scheme.onPrimary, size: 24),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.55)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 11.5, height: 1.35, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
