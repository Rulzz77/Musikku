import 'package:flutter/material.dart';

/// Editorial feature header used throughout MusikKu. The new system avoids
/// copying a standard streaming-app card: titles sit directly on the canvas,
/// with one small asymmetric identity mark and a restrained citrus accent.
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
    final titleSize = compact ? 22.0 : 30.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(2, compact ? 4 : 10, 2, compact ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 29 : 34,
                height: compact ? 29 : 34,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    topRight: Radius.circular(11),
                    bottomRight: Radius.circular(11),
                    bottomLeft: Radius.circular(3),
                  ),
                ),
                child: Icon(icon, size: compact ? 16 : 19, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  (eyebrow ?? 'MUSIKKU').toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.8,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          SizedBox(height: compact ? 10 : 15),
          Text(
            title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: titleSize,
              height: 0.99,
              fontWeight: FontWeight.w900,
              letterSpacing: compact ? -0.8 : -1.25,
            ),
          ),
          SizedBox(height: compact ? 6 : 9),
          Text(
            subtitle,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: compact ? 11 : 12.5,
              height: 1.42,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: compact ? 10 : 14),
          Container(
            width: compact ? 40 : 58,
            height: 3,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section labels have a consistent editorial hierarchy across every screen.
class FlowSectionHeader extends StatelessWidget {
  const FlowSectionHeader({super.key, required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: 22,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: scheme.primary, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.35,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}
