import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/follow_up_ai_summary.dart';

void main() {
  FollowUpSummaryRecord record({
    String notes = '最近完成一件開心的事',
    List<String> shared = const [],
  }) =>
      FollowUpSummaryRecord(
        id: 'private-id',
        createdAt: DateTime.utc(2026, 8, 5),
        updatedAt: DateTime.utc(2026, 8, 5),
        confirmedAt: DateTime.utc(2026, 8, 5),
        appointmentDate: DateTime.utc(2026, 8, 10),
        periodStart: DateTime.utc(2026, 7, 1),
        periodEnd: DateTime.utc(2026, 8, 5),
        validRecordDays: 12,
        selectedTopics: const [
          {'type': 'sleep', 'label': '睡眠品質'}
        ],
        discussionDetails: '最近工作壓力想請教',
        additionalNotes: notes,
        aiOutput: FollowUpAiOutput(
          keyChanges: const [
            '頭痛出現 3 天',
            '平均睡眠 7 小時。',
            '情緒較平穩',
          ],
          timelineRelations: const [],
          discussionPriorities: const ['最近工作壓力想請教。'],
          userSharedNotes: shared,
          dataLimitations: const ['有效紀錄 12 天。'],
          generatedAt: DateTime.utc(2026, 8, 5, 8),
        ),
        sleepSummary: const {
          'durationHours': {
            'recordedDays': 2,
            'average': 7,
            'minimum': 6,
            'maximum': 8,
          }
        },
        sleepTrend: const [
          {'date': '2026-08-04', 'value': 6},
          {'date': '2026-08-05', 'value': 8},
        ],
        medicationTimeline: const [],
      );

  test('preserves user-entered life updates even when text looks like Q/A', () {
    final display = FollowUpSummaryDisplayModel.fromRecord(
      record(notes: '問題：最近換了新工作\n回答：還在適應中'),
    );

    expect(display.userSharedNotes, [
      '問題：最近換了新工作。',
      '回答：還在適應中。',
    ]);
  });
}
