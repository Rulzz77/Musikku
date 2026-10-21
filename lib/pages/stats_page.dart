import 'package:flutter/material.dart';

import '../models/listening_stat.dart';
import '../services/storage_service.dart';
import '../widgets/flow_components.dart';
import '../theme/app_colors.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.storage});

  final StorageService storage;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<List<ListeningStat>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ListeningStat>> _load() async {
    await widget.storage.flushPendingWrites();
    return widget.storage.loadListeningStats();
  }

  String _formatMinutes(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes menit';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours jam' : '$hours jam ${rest}m';
  }

  String _formatDay(DateTime? date) {
    if (date == null) return 'Belum pernah';
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays == 0) return 'Hari ini';
    if (difference.inDays == 1) return 'Kemarin';
    if (difference.inDays < 7) return '${difference.inDays} hari lalu';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistik'),
      ),
      body: FutureBuilder<List<ListeningStat>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CenteredMessage(
              icon: Icons.error_outline_rounded,
              message: 'Statistik gagal dimuat.',
            );
          }

          final stats = snapshot.data ?? const <ListeningStat>[];
          final byListen = [...stats]
            ..sort((a, b) => b.listenedSeconds.compareTo(a.listenedSeconds));
          final bySkip = [...stats]
            ..sort((a, b) => b.skipCount.compareTo(a.skipCount));

          final totalSeconds = stats.fold<double>(
            0,
            (sum, item) => sum + item.listenedSeconds,
          );
          final totalPlays = stats.fold<int>(
            0,
            (sum, item) => sum + item.playCount,
          );
          final totalSkips = stats.fold<int>(
            0,
            (sum, item) => sum + item.skipCount,
          );

          final artistCounts = <String, int>{};
          final artistSeconds = <String, double>{};
          for (final stat in stats) {
            artistCounts[stat.artist] =
                (artistCounts[stat.artist] ?? 0) + stat.playCount;
            artistSeconds[stat.artist] =
                (artistSeconds[stat.artist] ?? 0) + stat.listenedSeconds;
          }
          final topArtists = artistCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final topArtist = topArtists.isEmpty ? null : topArtists.first;
          final topArtistMinutes = topArtist == null
              ? 0.0
              : artistSeconds[topArtist.key] ?? 0.0;

          return RefreshIndicator(
            onRefresh: () async {
              setState(() => _future = _load());
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 44),
              children: [
                _StatsHero(
                  totalSeconds: totalSeconds,
                  totalPlays: totalPlays,
                  topArtist: topArtist?.key,
                  topArtistMinutes: topArtistMinutes,
                  formatMinutes: _formatMinutes,
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 560;
                    final cardWidth = compact
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 20) / 3;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MetricCard(
                          width: cardWidth,
                          icon: Icons.headphones_rounded,
                          label: 'Waktu dengar',
                          value: _formatMinutes(totalSeconds),
                        ),
                        _MetricCard(
                          width: cardWidth,
                          icon: Icons.play_circle_filled_rounded,
                          label: 'Total putar',
                          value: '$totalPlays',
                        ),
                        _MetricCard(
                          width: cardWidth,
                          icon: Icons.skip_next_rounded,
                          label: 'Dilewati',
                          value: '$totalSkips',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: 'Artis paling sering diputar',
                  icon: Icons.mic_external_on_outlined,
                ),
                const SizedBox(height: 10),
                if (topArtists.isEmpty)
                  const _EmptyState(
                    message: 'Belum ada data artis. Putar beberapa lagu dulu.',
                  )
                else
                  ...topArtists.take(5).toList().asMap().entries.map(
                    (entry) {
                      final rank = entry.key + 1;
                      final item = entry.value;
                      return _RankTile(
                        rank: rank,
                        title: item.key,
                        subtitle: '${item.value}× diputar',
                        trailing: _formatMinutes(artistSeconds[item.key] ?? 0),
                      );
                    },
                  ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: 'Paling sering didengar',
                  icon: Icons.local_fire_department_outlined,
                ),
                const SizedBox(height: 10),
                if (byListen.isEmpty)
                  const _EmptyState(
                    message: 'Belum ada statistik. Putar beberapa lagu dulu.',
                  )
                else
                  ...byListen.take(10).toList().asMap().entries.map(
                    (entry) {
                      return _StatSongTile(
                        stat: entry.value,
                        rank: entry.key + 1,
                        formatMinutes: _formatMinutes,
                        formatDay: _formatDay,
                      );
                    },
                  ),
                if (bySkip.any((stat) => stat.skipCount > 0)) ...[
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: 'Sering dilewati',
                    icon: Icons.swipe_right_alt_outlined,
                  ),
                  const SizedBox(height: 10),
                  ...bySkip.where((stat) => stat.skipCount > 0).take(8).map(
                    (stat) => _SkipTile(stat: stat),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Statistik dirangkum dari pemutaran, durasi dengar, like, dan skip di perangkat ini.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatsHero extends StatelessWidget {
  const _StatsHero({
    required this.totalSeconds,
    required this.totalPlays,
    required this.topArtist,
    required this.topArtistMinutes,
    required this.formatMinutes,
  });

  final double totalSeconds;
  final int totalPlays;
  final String? topArtist;
  final double topArtistMinutes;
  final String Function(double) formatMinutes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.22),
            scheme.secondary.withValues(alpha: 0.10),
            scheme.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
        boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.07), blurRadius: 26, offset: const Offset(0, 10))],
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 12,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: appGoldStrong.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(19),
            ),
            child: Icon(Icons.insights_rounded, color: scheme.primary, size: 27),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RINGKASAN PERSONAL',
                  style: TextStyle(fontSize: 10, letterSpacing: 1.05, fontWeight: FontWeight.w900, color: scheme.secondary),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatMinutes(totalSeconds)} • $totalPlays play',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
                if (topArtist != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Teratas: $topArtist • ${formatMinutes(topArtistMinutes)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appGoldStrong,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: appGoldStrong.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: appGoldStrong, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 20,
                          letterSpacing: -0.4,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => FlowSectionHeader(icon: icon, title: title);
}

class _RankTile extends StatelessWidget {
  const _RankTile({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final int rank;
  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: appGoldStrong.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_outline_rounded, color: appGoldStrong, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            maxLines: 1,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StatSongTile extends StatelessWidget {
  const _StatSongTile({
    required this.stat,
    required this.rank,
    required this.formatMinutes,
    required this.formatDay,
  });

  final ListeningStat stat;
  final int rank;
  final String Function(double) formatMinutes;
  final String Function(DateTime?) formatDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbUrl = stat.thumbnailUrl.isEmpty
        ? 'https://i.ytimg.com/vi/${stat.videoId}/hqdefault.jpg'
        : stat.thumbnailUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              thumbUrl,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              cacheWidth: 156,
              errorBuilder: (_, _, _) => Container(
                width: 52,
                height: 52,
                color: scheme.surfaceContainerHighest,
                child: const Icon(Icons.music_note_rounded),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${stat.artist} • ${stat.playCount}× • ${formatMinutes(stat.listenedSeconds)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDay(stat.lastPlayedAt),
                  maxLines: 1,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkipTile extends StatelessWidget {
  const _SkipTile({required this.stat});

  final ListeningStat stat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.skip_next_rounded, color: appGoldStrong, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stat.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  stat.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            '${stat.skipCount}×',
            style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_outlined, color: appGoldStrong),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: scheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
