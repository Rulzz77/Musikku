import 'package:flutter/material.dart';

/// Shared editorial canvas for every MusikKu destination.
/// Kept intentionally quiet so artwork and page content become the focus.
class MusicBackdrop extends StatelessWidget {
  const MusicBackdrop({super.key, required this.child, this.intensity = 1});

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wash = (0.035 * intensity).clamp(0.0, 0.07).toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(theme.scaffoldBackgroundColor, scheme.primary, wash)!,
                theme.scaffoldBackgroundColor,
                theme.scaffoldBackgroundColor,
              ],
              stops: const [0, 0.28, 1],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 3,
          child: ColoredBox(color: scheme.primary.withValues(alpha: 0.76)),
        ),
        child,
      ],
    );
  }
}

/// Solid editorial surface. The legacy name remains to keep existing screens
/// source-compatible; no blur is applied anymore.
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
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border(
          left: BorderSide(color: tint, width: 3),
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.42 : 0.75)),
          right: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.42 : 0.75)),
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: dark ? 0.42 : 0.75)),
        ),
      ),
      child: child,
    );
  }
}

/// Compact editorial title block for secondary pages.
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
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: scheme.onPrimary, size: 23),
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
                    letterSpacing: 1.45,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 23, height: 1.02, fontWeight: FontWeight.w900, letterSpacing: -0.85),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: scheme.onSurfaceVariant),
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
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 29, color: scheme.onPrimary),
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
