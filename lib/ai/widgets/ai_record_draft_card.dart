import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../innera_ai_record_draft.dart';

class AiRecordDraftCard extends StatelessWidget {
  const AiRecordDraftCard({
    super.key,
    required this.draft,
    required this.onPreview,
  });

  final InneraAiRecordDraft draft;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summary = <String>[];
    if (draft.emotions.isNotEmpty) {
      summary.add(
        draft.emotions
            .map(
              (item) => item.source == AiDraftSource.defaultPendingConfirmation
                  ? '${item.name} 暫定 ${item.score} / 5'
                  : '${item.name} ${item.score} / 5',
            )
            .join('、'),
      );
    }
    if (draft.symptoms.isNotEmpty) {
      summary.add('症狀：${draft.symptoms.join('、')}');
    }
    if (draft.sleep.hasData) {
      summary.add('睡眠：已補充');
    }
    if (draft.diaryText.isNotEmpty || draft.rawUserEntries.isNotEmpty) {
      summary.add('日記：已整理 ${draft.diaryText.length} 字');
    }
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: HealingDesignSystem.adaptiveSurface(context),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18),
                const SizedBox(width: 8),
                Text('目前已整理', style: textTheme.titleSmall),
                const Spacer(),
                TextButton(onPressed: onPreview, child: const Text('查看完整草稿')),
              ],
            ),
            const SizedBox(height: 6),
            if (summary.isEmpty)
              const Text('還沒有足夠內容，直接描述今天的狀態即可。')
            else
              ...summary.take(4).map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(item,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
            if (draft.missingFields.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('仍可補充：${draft.missingFields.take(2).join('、')}',
                  style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
