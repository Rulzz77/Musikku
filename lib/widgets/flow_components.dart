import 'package:flutter/material.dart';

/// Reusable editorial hero for secondary MusikKu pages.
class FlowPageHero extends StatelessWidget {
  const FlowPageHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.trailing,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? eyebrow;
  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(compact ? 14 : 18, compact ? 14 : 18, compact ? 12 : 16, compact ? 14 : 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: dark ? 0.72 : 0.92),
            scheme.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(compact ? 18 : 23),
        border: Border.all(color: scheme.primary.withValues(alpha: dark ? 0.22 : 0.16)),
        boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 42 : 52,
            height: compact ? 42 : 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [scheme.primary, scheme.tertiary]),
              borderRadius: BorderRadius.circular(compact ? 13 : 16),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.20), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: Icon(icon, size: compact ? 22 : 26, color: scheme.onPrimary),
          ),
          SizedBox(width: compact ? 11 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((eyebrow ?? '').isNotEmpty) ...[
                  Text(eyebrow!.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.primary, fontSize: 9, letterSpacing: 1.35, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                ],
                Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 17 : 22, height: 1.04, letterSpacing: -0.8, fontWeight: FontWeight.w900, color: scheme.onSurface)),
                const SizedBox(height: 6),
                Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 11 : 12, height: 1.38, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class FlowSectionHeader extends StatelessWidget {
  const FlowSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 4,
          height: 23,
          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.25),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
