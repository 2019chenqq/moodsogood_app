import 'package:flutter/material.dart';
import '../models/post.dart';
import '../providers/room_feed_provider.dart';
import 'community_style.dart';

class EmpathyBar extends StatefulWidget {
  final Post post;
  final void Function(ReactType type, bool wasReacted) onReact;

  const EmpathyBar({
    super.key,
    required this.post,
    required this.onReact,
  });

  @override
  State<EmpathyBar> createState() => _EmpathyBarState();
}

class _EmpathyBarState extends State<EmpathyBar> {
  void _toggleReaction(String type, ReactType reactType) {
    final wasReacted = widget.post.hasReacted(type);
    
    setState(() {
      // 只更新反應狀態，計數交給父級處理
      widget.post.toggleReaction(type);
    });
    
    // 通知父級：讓它決定是加還是減
    widget.onReact(reactType, wasReacted);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _reactionChip(
          context,
          '🫂',
          post.hug,
          'hug',
          ReactType.hug,
          post.hasReacted('hug'),
        ),
        _reactionChip(
          context,
          '👂',
          post.listen,
          'listen',
          ReactType.listen,
          post.hasReacted('listen'),
        ),
        _reactionChip(
          context,
          '🌱',
          post.hope,
          'hope',
          ReactType.hope,
          post.hasReacted('hope'),
        ),
        _reactionChip(
          context,
          '💙',
          post.heart,
          'heart',
          ReactType.heart,
          post.hasReacted('heart'),
        ),
      ],
    );
  }

  Widget _reactionChip(
    BuildContext context,
    String emoji,
    int count,
    String type,
    ReactType reactType,
    bool isPressed,
  ) {
    final backgroundColor = isPressed
        ? CommunityStyle.accent.withOpacity(0.2)
        : CommunityStyle.surface;
    final borderColor =
        isPressed ? CommunityStyle.accent : CommunityStyle.outline;
    final textColor =
        isPressed ? CommunityStyle.accent : CommunityStyle.text;

    return InkWell(
      onTap: () => _toggleReaction(type, reactType),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor, width: isPressed ? 1.5 : 1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: textColor,
                    fontWeight: isPressed ? FontWeight.bold : FontWeight.normal,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

