import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../innera_ai_message.dart';

class AiContextSourcesSheet extends StatelessWidget {
  const AiContextSourcesSheet({super.key, required this.sources});

  final List<AiContextSource> sources;

  static void show(BuildContext context, List<AiContextSource> sources) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AiContextSourcesSheet(sources: sources),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.42,
      minChildSize: 0.25,
      maxChildSize: 0.72,
      builder: (context, controller) {
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: HealingDesignSystem.adaptiveCardBorder(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '這次回答參考了：',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            if (sources.isEmpty)
              Text('這次沒有使用個人紀錄。', style: Theme.of(context).textTheme.bodyMedium)
            else
              ...sources.map(
                (source) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('• '),
                      Expanded(
                        child: Text(
                          '${source.label}（${source.dateRange}，${source.count} 筆）',
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.copyWith(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
