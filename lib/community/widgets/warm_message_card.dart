import 'package:flutter/material.dart';
import 'community_style.dart';

class WarmMessageCard extends StatelessWidget {
  const WarmMessageCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: CommunityStyle.surface,
      shape: CommunityStyle.cardShape,
      elevation: 0.4,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.favorite_border, color: CommunityStyle.accentDark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '你已經很努力了。今天也先照顧好你自己。',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: CommunityStyle.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
