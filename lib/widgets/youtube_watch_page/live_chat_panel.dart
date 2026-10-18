import 'package:flutter/material.dart';

import '../../services/youtube_live_chat_service.dart';
import '../../utils/time_formatters.dart';

/// Presentational live-chat list. Polling/replay timing remains in YoutubeWatchPage.
class YoutubeLiveChatPanel extends StatelessWidget {
  const YoutubeLiveChatPanel({
    super.key,
    required this.messages,
    required this.controller,
    required this.loading,
    required this.ended,
    required this.failures,
    required this.isReplay,
  });

  final List<LiveChatMessage> messages;
  final ScrollController controller;
  final bool loading;
  final bool ended;
  final int failures;
  final bool isReplay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (messages.isEmpty) {
      final String message;
      if (ended) {
        message = 'Siaran berakhir atau chat ditutup.';
      } else if (failures >= 3) {
        message = 'Chat gagal dimuat, mencoba lagi…';
      } else if (isReplay) {
        message = 'Belum ada chat di bagian video ini.';
      } else {
        message = 'Menunggu pesan baru…';
      }
      return Center(
        child: loading
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Text(message, textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
      );
    }

    final showFooter = ended && !isReplay;
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      itemCount: messages.length + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Siaran berakhir atau chat ditutup.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          );
        }
        return _LiveChatMessageTile(message: messages[index], isReplay: isReplay);
      },
    );
  }
}

class _LiveChatMessageTile extends StatelessWidget {
  const _LiveChatMessageTile({required this.message, required this.isReplay});

  final LiveChatMessage message;
  final bool isReplay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nameColor = message.isOwner
        ? scheme.primary
        : message.isModerator
            ? Colors.lightBlueAccent
            : scheme.onSurfaceVariant;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: scheme.surfaceContainerHighest,
          backgroundImage: message.avatarUrl.isNotEmpty ? NetworkImage(message.avatarUrl) : null,
          child: message.avatarUrl.isEmpty ? const Icon(Icons.person_outline_rounded, size: 13) : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: message.author, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: nameColor)),
                if (message.isOwner || message.isModerator)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Icon(message.isOwner ? Icons.verified_rounded : Icons.build_circle_rounded, size: 13, color: nameColor),
                    ),
                  ),
                if (message.sentAt != null && !isReplay)
                  TextSpan(text: '  ${formatClockTime(message.sentAt)}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                if (isReplay && message.offsetMs > 0)
                  TextSpan(text: '  ${formatVideoOffset(message.offsetMs)}', style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500)),
                const TextSpan(text: '  '),
                TextSpan(text: message.text, style: const TextStyle(fontSize: 13, height: 1.3)),
              ],
            ),
          ),
        ),
      ],
    );
    if (message.amount.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: row);
    }
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message.amount, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: scheme.onTertiaryContainer)),
          const SizedBox(height: 4),
          row,
        ],
      ),
    );
  }
}
