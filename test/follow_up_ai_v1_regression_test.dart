import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/follow_up/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/follow_up/services/follow_up_ai_service.dart';
import 'package:moodsogood_app/follow_up/widgets/follow_up_sleep_trend_card.dart';

void main() {
  test('scheduleChanged uses times and never renders a dose arrow', () {
    final text = FollowUpAiService.formatMedicationTimelineEvent({
      'date': '2026-07-31',
      'medicationName': '測試藥物',
      'type': 'scheduleChanged',
      'beforeDose': 0.0,
      'afterDose': 0.0,
      'beforeTimes': ['早上'],
      'afterTimes': ['睡前'],
    });

    expect(text, '2026-07-31 測試藥物：服藥時間：早上 → 睡前');
    expect(text, isNot(contains('0.0 → 0.0')));
  });

  test('summary parser accepts fenced JSON and fills optional concerns', () {
    const reply = '''以下是整理結果：
```json
{
  "keyChanges":["變化一","變化二","變化三"],
  "discussionPriorities":["睡眠"],
  "timelineRelations":[],
  "dataLimitations":[]
}
```
請確認。''';

    final output = FollowUpAiService.parseSummaryReplyForTesting(reply);
    expect(output, isNotNull);
    expect(output!.keyChanges, hasLength(3));
    expect(output.userReportedConcerns, isEmpty);
    expect(output.usedFallback, isFalse);
  });

  test(
    'summary parser tolerates non-array medicationSubjectiveSummaries '
    'instead of forcing a fallback',
    () {
      const reply = '''```json\n{
  "keyChanges":["變化一","變化二","變化三"],
  "discussionPriorities":["睡眠"],
  "timelineRelations":[],
  "userSharedNotes":[],
  "dataLimitations":[],
  "medicationSubjectiveSummaries":{"date":"2026-08-01","note":"wrong type"}
}\n```''';

      final output = FollowUpAiService.parseSummaryReplyForTesting(reply);
      expect(output, isNotNull);
      expect(output!.keyChanges, hasLength(3));
      expect(output.usedFallback, isFalse);
      // The malformed optional field should degrade to an empty list, not
      // collapse the whole summary into null.
      expect(
        output.timelineRelations.where(
          (item) => item.startsWith('__med_subjective__:'),
        ),
        isEmpty,
      );
    },
  );

  test('fallback never copies malformed model text into key changes', () {
    final output = FollowUpAiService.fallbackSummaryForTesting(_input());

    expect(output.usedFallback, isTrue);
    expect(output.keyChanges, hasLength(greaterThanOrEqualTo(3)));
    expect(
      output.keyChanges.join(),
      isNot(contains('AI 暫時無法完成')),
    );
  });

  testWidgets('sleep card renders a safe empty state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowUpSleepTrendCard(input: _input()),
        ),
      ),
    );

    expect(find.text('睡眠趨勢'), findsOneWidget);
    expect(find.text('統計期間內沒有可用的睡眠時數紀錄'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

FollowUpAiV1Input _input() {
  const emptyTrend = MetricTrendInput(dailyValues: []);
  return FollowUpAiV1Input(
    statistics: FollowUpStatistics(
      periodStart: DateTime(2026, 7, 31),
      periodEnd: DateTime(2026, 8, 5),
      validRecordDays: 0,
    ),
    discussionTopics: const [
      FollowUpDiscussionTopicInput(
        type: 'sleep',
        label: '睡眠品質',
        selected: true,
      ),
    ],
    discussionDetails: '想討論睡眠',
    additionalNotes: '近期生活事件',
    wellbeingTrends: const WellbeingTrendsInput(
      mood: emptyTrend,
      anxiety: emptyTrend,
      energy: emptyTrend,
      appetite: emptyTrend,
      activity: emptyTrend,
    ),
    sleep: const {
      'durationHours': {
        'recordedDays': 0,
        'average': null,
        'minimum': null,
        'maximum': null,
        'dailyTrend': [],
      },
      'quality': {'recordedDays': 0, 'average': null},
      'sleepOnsetDifficulty': {'occurrenceDays': 0},
      'earlyAwakening': {'occurrenceDays': 0},
      'nightInterruption': {'occurrenceDays': 0},
      'naps': {'days': 0, 'count': 0},
    },
    highFrequencySymptoms: const [],
    bodyMeasurements: const [],
    currentMedications: const [],
    medicationTimeline: const [],
    dataLimitations: const ['睡眠資料不足'],
  );
}
