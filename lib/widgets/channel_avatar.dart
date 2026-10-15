import 'package:flutter/material.dart';

import '../services/channel_avatar_service.dart';

/// Foto profil channel. Selama foto belum ada (atau gagal dimuat) tampil
/// huruf pertama nama channel.
class ChannelAvatar extends StatefulWidget {
  final String channelId;

  /// Dipakai mencari channel bila [channelId] kosong (data lama/cache).
  final String videoId;
  final String name;
  final double radius;
  final VoidCallback? onTap;

  const ChannelAvatar({
    super.key,
    required this.channelId,
    this.videoId = '',
    required this.name,
    this.radius = 18,
    this.onTap,
  });

  @override
  State<ChannelAvatar> createState() => _ChannelAvatarState();
}

class _ChannelAvatarState extends State<ChannelAvatar> {
  @override
  void initState() {
    super.initState();
    ChannelAvatarService.instance.request(widget.channelId, videoId: widget.videoId);
  }

  @override
  void didUpdateWidget(ChannelAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId ||
        oldWidget.videoId != widget.videoId) {
      ChannelAvatarService.instance.request(widget.channelId, videoId: widget.videoId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.name.trim();
    final size = widget.radius * 2;

    final avatar = ListenableBuilder(
      listenable: ChannelAvatarService.instance,
      builder: (context, _) {
        final url = ChannelAvatarService.instance
            .urlFor(widget.channelId, videoId: widget.videoId);
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircleAvatar(
                radius: widget.radius,
                backgroundColor: scheme.secondaryContainer,
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: widget.radius * 0.78,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (url != null)
                ClipOval(
                  child: Image.network(
                    url,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    cacheWidth: (size * 3).round(),
                    filterQuality: FilterQuality.medium,
                    // Gagal dimuat: huruf di bawahnya tetap terlihat.
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (widget.onTap == null) return avatar;
    return InkResponse(
      onTap: widget.onTap,
      customBorder: const CircleBorder(),
      radius: widget.radius + 6,
      child: avatar,
    );
  }
}
