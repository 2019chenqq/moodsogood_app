import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moodsogood_app/models/follow_up_ai_summary.dart';
import 'package:moodsogood_app/services/follow_up_ai_service.dart';
import 'package:moodsogood_app/widgets/follow_up_sleep_trend_card.dart';

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
  "dataLimitations":[]
}
```
請確認。''';

    final output = FollowUpAiService.parseSummaryReplyForTesting(reply);
    expect(output, isNotNull);
    expect(output!.keyChanges, hasLength(3));
    expect(output.timelineRelations, isEmpty);
    expect(output.userReportedConcerns, isEmpty);
    expect(output.usedFallback, isFalse);
  });

  test('fallback never copies malformed model text into key changes', () {
    final output = FollowUpAiService.fallbackSummaryForTesting(_input());

    expect(output.usedFallback, isTrue);
    expect(output.keyChanges, hasLength(greaterThanOrEqualTo(3)));
    expect(
      output.keyChanges.join(),
      isNot(contains('AI 暫時無法完成')),
    );
  });

  group('follow-up medication question validation', () {
    test('research text alone does not authorize painkiller questions', () {
      final questions = FollowUpAiService.filterMedicationQuestionsForTesting(
        const ['目前服用的止痛藥效果如何？', '最近是否有新的身體不適？'],
        _medicationInput(discussionDetails: '研究止痛藥與情緒相關的關鍵字。'),
      );
      expect(questions, ['最近是否有新的身體不適？']);
    });

    test('current medication authorizes effect and side-effect questions', () {
      final questions = FollowUpAiService.filterMedicationQuestionsForTesting(
        const ['目前服用的止痛藥效果或副作用如何？'],
        _medicationInput(currentMedications: const [
          {'name': '止痛藥', 'dose': 1, 'unit': '顆'}
        ]),
      );
      expect(questions, hasLength(1));
    });

    test('added medication timeline authorizes change questions', () {
      final questions = FollowUpAiService.filterMedicationQuestionsForTesting(
        const ['新增止痛藥後有什麼變化？'],
        _medicationInput(medicationTimeline: const [
          {
            'medicationName': '止痛藥',
            'type': 'added',
            'date': '2026-08-01',
          }
        ]),
      );
      expect(questions, hasLength(1));
    });

    test('structured medication data wins over contradictory free text', () {
      final questions = FollowUpAiService.filterMedicationQuestionsForTesting(
        const [
          '目前服用的止痛藥效果如何？',
          '目前服用的情緒穩定劑是否有副作用？',
        ],
        _medicationInput(
          discussionDetails: '目前有服用止痛藥。',
          currentMedications: const [
            {'name': '情緒穩定劑', 'dose': 1, 'unit': '顆'}
          ],
        ),
      );
      expect(questions, ['目前服用的情緒穩定劑是否有副作用？']);
    });
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

  testWidgets('sleep card renders dynamically recorded conditions',
      (tester) async {
    final input = _input(sleep: const {
      'durationHours': {
        'recordedDays': 1,
        'average': 8,
        'minimum': 8,
        'maximum': 8,
        'dailyTrend': [
          {'date': '2026-08-05', 'value': 8}
        ],
      },
      'quality': {'recordedDays': 1, 'average': 3},
      'conditions': [
        {'code': 'dreams', 'label': '多夢', 'occurrenceDays': 1}
      ],
      'naps': {'days': 0, 'count': 0},
    });
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: FollowUpSleepTrendCard(input: input))),
    );

    expect(find.text('多夢'), findsOneWidget);
    expect(find.text('1 天'), findsWidgets);
    expect(find.text('入睡困難'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

FollowUpAiV1Input _input({Map<String, dynamic>? sleep}) {
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
    sleep: sleep ??
        const {
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

FollowUpAiV1Input _medicationInput({
  String discussionDetails = '',
  List<Map<String, dynamic>> currentMedications = const [],
  List<Map<String, dynamic>> medicationTimeline = const [],
}) {
  final base = _input();
  return FollowUpAiV1Input(
    schemaVersion: base.schemaVersion,
    statistics: base.statistics,
    discussionTopics: base.discussionTopics,
    discussionDetails: discussionDetails,
    additionalNotes: base.additionalNotes,
    wellbeingTrends: base.wellbeingTrends,
    sleep: base.sleep,
    highFrequencySymptoms: base.highFrequencySymptoms,
    bodyMeasurements: base.bodyMeasurements,
    currentMedications: currentMedications,
    medicationTimeline: medicationTimeline,
    dataLimitations: base.dataLimitations,
  );
}
