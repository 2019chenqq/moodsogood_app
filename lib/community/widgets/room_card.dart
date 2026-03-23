import 'package:flutter/material.dart';
import '../models/room.dart';
import 'community_style.dart';

class RoomCard extends StatelessWidget {
  final Room room;
  final VoidCallback onTap;

  const RoomCard({super.key, required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: CommunityStyle.surface,
      shape: CommunityStyle.cardShape,
      elevation: 0.5,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(room.icon, size: 26, color: CommunityStyle.accentDark),
              const SizedBox(height: 10),
              Text(
                room.name,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: CommunityStyle.text,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                room.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: CommunityStyle.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}