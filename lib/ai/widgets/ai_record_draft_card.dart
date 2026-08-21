import 'package:flutter/material.dart';

import '../../constants/healing_design_system.dart';
import '../../daily/daily_state_dimensions.dart';
import '../../daily/body_measurement_input.dart';
import '../../models/daily_record.dart';
import '../innera_ai_record_draft.dart';

class AiRecordDraftCard extends StatelessWidget {
  const AiRecordDraftCard({
    super.key,
    required this.draft,
    required this.onPreview,
    required this.onExtractDiary,
    this.isExtractingDiary = false,
  });

  final InneraAiRecordDraft draft;
  final VoidCallback onPreview;
  final VoidCallback onExtractDiary;
  final bool isExtractingDiary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summary = <String>[];
    if (draft.eventDrafts.isNotEmpty) {
      summary.add('將建立 ${draft.eventDrafts.length} 筆事件紀錄');
      for (final event in draft.eventDrafts.take(2)) {
        final content =
            event.symptoms.isEmpty ? event.note : event.symptoms.join('、');
        summary.add('${event.timeLabel}：$content');
      }
    }
    if (draft.emotions.isNotEmpty) {
      final item = draft.emotions.first;
      final label = item.normalizedDimensionName ?? item.rawText;
      summary.add(item.score == null ? label : '$label ${item.score}/5');
    }
    if (draft.symptoms.isNotEmpty) {
      summary.add(draft.symptoms.first);
    }
    if (draft.stateChanges.isNotEmpty) {
      final entry = draft.stateChanges.entries.first;
      final dimension = kDailyStateDimensionsById[entry.key];
      if (dimension != null) {
        summary.add(
          '${dimension.displayName}：${dailyStateValueLabel(dimension, entry.value)}',
        );
      }
    }
    final timeContext = draft.emotions
        .map((item) => item.timeContext?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (timeContext != null) summary.add('$timeContext發生');
    if (summary.length < 4 && draft.bodyMeasurement?.hasData == true) {
      final measurement = draft.bodyMeasurement!;
      final values = <String>[
        if (measurement.weightKg != null)
          '體重 ${formatBodyMeasurementNumber(measurement.weightKg)} kg',
        if (measurement.bodyFatPercent != null)
          '體脂 ${formatBodyMeasurementNumber(measurement.bodyFatPercent)}%',
        if (measurement.waistCm != null)
          '腰圍 ${formatBodyMeasurementNumber(measurement.waistCm)} cm',
        if (measurement.measurementTiming != null)
          measurement.measurementTimeDisplay ??
              measurement.measurementTiming!.displayName,
      ];
      summary.add(values.join('、'));
    }
    if (summary.length < 4 && draft.sleep.hasData) {
      summary.add('睡眠：已補充');
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
                Expanded(
                  child: Text('可以整理成紀錄', style: textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (summary.isEmpty)
              const Text('還沒有足夠內容，直接描述今天的狀態即可。')
            else
              ...summary.take(4).map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        item,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
            if (draft.missingFields.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '還可以補充：${draft.missingFields.take(2).join('、')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: HealingDesignSystem.adaptiveSecondaryText(context),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isExtractingDiary
                    ? null
                    : draft.eventDrafts.isNotEmpty && !draft.confirmed
                        ? onPreview
                        : onExtractDiary,
                icon: isExtractingDiary
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        draft.confirmed
                            ? Icons.playlist_add_rounded
                            : Icons.auto_awesome_rounded,
                        size: 18,
                      ),
                label: Text(
                  isExtractingDiary
                      ? '正在整理…'
                      : draft.eventDrafts.isNotEmpty && !draft.confirmed
                          ? '查看並確認 ${draft.eventDrafts.length} 筆紀錄'
                          : draft.confirmed
                              ? '新增另一筆紀錄'
                              : '查看並確認',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
