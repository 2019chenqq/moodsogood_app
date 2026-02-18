import 'package:flutter/material.dart';
import 'community_style.dart';

class SafetyBanner extends StatelessWidget {
  final bool show;

  const SafetyBanner({super.key, this.show = true});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    return Card(
      color: CommunityStyle.surface,
      shape: CommunityStyle.cardShape,
      elevation: 0.4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: CommunityStyle.accentDark),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '如果你正在經歷強烈痛苦或有自傷/自殺念頭，請優先尋求即時協助：'
                '可聯絡身邊信任的人、就近急診或撥打在地求助專線。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: CommunityStyle.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}