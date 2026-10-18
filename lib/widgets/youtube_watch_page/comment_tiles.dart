import 'package:flutter/material.dart';

import '../../services/youtube_video_service.dart';
import '../../utils/time_formatters.dart';

/// Standalone rendering for a single YouTube comment reply.
class YoutubeCommentReplyTile extends StatelessWidget {
  const YoutubeCommentReplyTile({super.key, required this.reply});

  final YoutubeCommentReply reply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 34),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundImage: reply.authorAvatarUrl.isNotEmpty
                ? NetworkImage(reply.authorAvatarUrl)
                : null,
            child: reply.authorAvatarUrl.isEmpty
                ? const Icon(Icons.person_outline_rounded, size: 14)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(reply.author, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 3),
                Text(reply.text, style: const TextStyle(height: 1.3, fontSize: 12.5)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${reply.likeCount} suka', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5)),
                    if (reply.publishedAt != null)
                      Text(
                        formatRelativeTime(reply.publishedAt),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10.5),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stateless comment presentation. Reply fetching and expanded-state remain in the page.
class YoutubeCommentTile extends StatelessWidget {
  const YoutubeCommentTile({
    super.key,
    required this.comment,
    required this.expanded,
    required this.loadingReplies,
    required this.replies,
    required this.onToggleReplies,
  });

  final YoutubeComment comment;
  final bool expanded;
  final bool loadingReplies;
  final List<YoutubeCommentReply> replies;
  final VoidCallback onToggleReplies;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundImage: comment.authorAvatarUrl.isNotEmpty
                ? NetworkImage(comment.authorAvatarUrl)
                : null,
            child: comment.authorAvatarUrl.isEmpty
                ? const Icon(Icons.person_outline_rounded, size: 18)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(comment.author, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                const SizedBox(height: 4),
                Text(comment.text, style: const TextStyle(height: 1.35)),
                const SizedBox(height: 7),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${comment.likeCount} suka', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                    if (comment.publishedAt != null) ...[
                      const SizedBox(width: 12),
                      Text(formatRelativeTime(comment.publishedAt), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                    ],
                    if (comment.replyCount > 0) ...[
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: onToggleReplies,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          expanded ? 'Sembunyikan balasan' : 'Lihat ${comment.replyCount} balasan',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ],
                ),
                if (expanded) ...[
                  if (loadingReplies)
                    const Padding(
                      padding: EdgeInsets.only(left: 34, top: 8),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    ...replies.map((reply) => YoutubeCommentReplyTile(reply: reply)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
