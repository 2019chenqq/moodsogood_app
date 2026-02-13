import 'package:flutter/material.dart';
import '../models/post.dart';
import '../providers/room_feed_provider.dart';
import 'empathy_bar.dart';

class PostListItem extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  final void Function(ReactType type) onReact;

  const PostListItem({
    super.key,
    required this.post,
    required this.onTap,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) {
    final time = _friendlyTime(post.createdAt);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('匿名者 ${post.authorAnonId}',
                      style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  Text(time, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                post.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              EmpathyBar(
                hug: post.hug,
                listen: post.listen,
                hope: post.hope,
                heart: post.heart,
                onReact: onReact,
              ),
              const SizedBox(height: 8),
              Text('回覆 ${post.replyCount}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  String _friendlyTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分鐘前';
    if (diff.inHours < 24) return '${diff.inHours} 小時前';
    return '${diff.inDays} 天前';
  }
}