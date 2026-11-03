import 'package:flutter/material.dart';

/// A quiet, graphic backdrop shared by every MusikKu destination.
/// It uses broad color fields rather than glass blur or heavy gradients.
class MusicBackdrop extends StatelessWidget {
  const MusicBackdrop({super.key, required this.child, this.intensity = 1});

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final strength = (0.035 * intensity).clamp(0.0, 0.07).toDouble();
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: theme.scaffoldBackgroundColor),
        Positioned(
          top: -110,
          right: -115,
          child: IgnorePointer(
            child: Container(
              width: 270,
              height: 270,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: strength * (dark ? 1.0 : 0.75)),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -170,
          left: -125,
          child: IgnorePointer(
            child: Container(
              width: 310,
              height: 310,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.secondary.withValues(alpha: strength * (dark ? 0.55 : 0.42)),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Solid, tactile surface shared across feature pages. The legacy class name
/// remains so all existing screens receive the new design without changing logic.
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.62)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.brightness == Brightness.dark ? 0.10 : 0.025),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          if (accent != null)
            BoxShadow(color: accent!.withValues(alpha: 0.035), blurRadius: 14, spreadRadius: -9),
        ],
      ),
      child: child,
    );
  }
}

/// Editorial title block used by secondary destinations.
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
      padding: const EdgeInsets.fromLTRB(2, 5, 2, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(13),
                topRight: Radius.circular(13),
                bottomRight: Radius.circular(13),
                bottomLeft: Radius.circular(3),
              ),
            ),
            child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
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
                  style: TextStyle(fontSize: 9, letterSpacing: 1.65, fontWeight: FontWeight.w900, color: scheme.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 29, height: 0.99, fontWeight: FontWeight.w900, letterSpacing: -1.1),
                ),
                const SizedBox(height: 6),
                Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Animated-friendly empty state with a clear action.
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
      radius: 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, size: 29, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 15),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.25)),
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
          child: Transform.translate(offset: Offset(0, 13 * (1 - value)), child: child),
        );
      },
      child: child,
    );
  }
}

/// Compact heading for sheets and modal feature panels.
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(15)),
          child: Icon(icon, color: color, size: 23),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(fontSize: 11.5, height: 1.35, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}
